"""Triage Agent — converts SRE-Agent-filed GitHub issues into proposed fixes.

Architecture:
  1. Issue opened on this repo (filed by Azure SRE Agent or manually).
  2. .github/workflows/issue-triage.yml invokes `python -m agents.triage`
     with the issue body as input.
  3. This script:
       a. Loads the issue + any attached telemetry from the body.
       b. Queries Azure for current state of the named resource(s).
       c. Calls the Foundry agent (o4-mini reasoning model) with
          a strict prompt asking for a structured fix proposal.
       d. Writes a Markdown PR body + Bicep/CLI patch to ./out/.
       e. Workflow then creates a draft PR from those artifacts.

Auth: Azure Workload Identity Federation (GitHub OIDC → Azure AD).
No secrets stored in GitHub — the workflow uses azure/login with
the federated MI configured against this repo.
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path, PurePosixPath

from openai import AzureOpenAI
from azure.identity import DefaultAzureCredential, get_bearer_token_provider


# Reasoning-model deployment-name prefixes. These models:
#   - require role="developer" in place of "system"
#   - use max_completion_tokens, not max_tokens
#   - don't accept a non-default temperature
REASONING_MODEL_PREFIXES: tuple[str, ...] = ("o1", "o3", "o4", "gpt-5-pro", "gpt-5.4-pro")

# fix.filename whitelist: only these roots are allowed in the auto-generated PR.
# Prevents the LLM (fed untrusted issue content) from rewriting workflows or
# arbitrary repo files via a crafted relative path.
SAFE_PATCH_ROOTS: tuple[str, ...] = ("infra/", "scripts/")

LOG = logging.getLogger("ogedemos-triage")


SYSTEM_PROMPT = """You are the Triage Agent for the OGEDemos SRE showcase.

You receive a GitHub Issue filed by Azure SRE Agent (or a human) describing
a problem detected in the OGEDemos_RG Azure subscription. Your job:

1. Read the issue title + body. Identify the affected Azure resource(s) and
   the type of finding (security drift, cost waste, reliability gap,
   storm/scale issue, compliance violation).
2. Read the "current state" JSON the workflow has attached — it's the result
   of an Azure Resource Graph query for that resource.
3. Propose a concrete fix as:
   a. A short **executive summary** (2-3 sentences, plain English)
   b. **Root cause** — what's actually wrong
   c. **Proposed fix** — Bicep / CLI / Terraform snippet that resolves it
   d. **Risk** — what could go wrong if applied as-is
   e. **Verification** — how a human reviewer can confirm the fix worked
4. Be conservative. NEVER propose anything that:
   - Deletes data
   - Changes production traffic flow without explicit confirmation
   - Modifies auth/RBAC at scope wider than the affected resource
   When in doubt, propose the smallest reversible change.

Output strictly as JSON matching this schema:

{
  "summary": "string",
  "root_cause": "string",
  "fix": {
    "kind": "bicep" | "cli" | "terraform",
    "filename": "string (relative path inside infra/ or scripts/)",
    "patch": "string (the file content or diff)"
  },
  "risk": "string",
  "verification": "string",
  "human_review_focus": ["string", ...]
}

Reasoning instructions:
- You are running on a reasoning model (o4-mini). Think through the
  classification + remediation carefully internally, but output ONLY
  the JSON object. No prose before or after.
- If the issue doesn't have enough detail to propose a fix, set "fix" to
  null and explain what data you'd need in "summary".
"""


@dataclass
class IssueContext:
    title: str
    body: str
    number: int
    labels: list[str] = field(default_factory=list)
    azure_state: dict | None = None


def _client() -> tuple[AzureOpenAI, str]:
    endpoint = os.environ["AZURE_OPENAI_ENDPOINT"]
    deployment = os.environ.get("TRIAGE_MODEL", "o4-mini")
    cred = DefaultAzureCredential()
    token_provider = get_bearer_token_provider(
        cred, "https://cognitiveservices.azure.com/.default"
    )
    client = AzureOpenAI(
        azure_endpoint=endpoint,
        azure_ad_token_provider=token_provider,
        api_version="2025-01-01-preview",
        max_retries=4,
        timeout=120.0,
    )
    return client, deployment


def _is_reasoning_model(deployment: str) -> bool:
    name = deployment.lower()
    return any(name.startswith(p) for p in REASONING_MODEL_PREFIXES)


def triage(ctx: IssueContext) -> dict:
    client, deployment = _client()

    user_msg = f"""GITHUB ISSUE
============
Title:  {ctx.title}
Number: #{ctx.number}
Labels: {", ".join(ctx.labels) or "(none)"}

Body:
{ctx.body}

CURRENT AZURE STATE (Resource Graph snapshot)
=============================================
{json.dumps(ctx.azure_state, indent=2, default=str) if ctx.azure_state else "(not attached — proceed with caveats)"}

Produce the JSON triage object now."""

    # Reasoning models (o1/o3/o4) require the "developer" role and don't honour
    # `temperature`. Standard chat models use "system".
    system_role = "developer" if _is_reasoning_model(deployment) else "system"
    kwargs: dict = {
        "model": deployment,
        "messages": [
            {"role": system_role, "content": SYSTEM_PROMPT},
            {"role": "user", "content": user_msg},
        ],
        "response_format": {"type": "json_object"},
    }
    if _is_reasoning_model(deployment):
        kwargs["max_completion_tokens"] = 4000
    else:
        kwargs["max_tokens"] = 4000
        kwargs["temperature"] = 0.2

    try:
        response = client.chat.completions.create(**kwargs)
    except Exception as exc:  # noqa: BLE001 — surface every failure to the PR body
        LOG.exception("chat.completions.create failed")
        return {
            "summary": f"Triage agent could not reach the Foundry model: {exc}",
            "fix": None,
        }

    raw = response.choices[0].message.content or "{}"
    try:
        return json.loads(raw)
    except json.JSONDecodeError as e:
        return {
            "summary": f"Triage agent produced non-JSON output: {e}",
            "fix": None,
            "raw_output": raw,
        }


def _gather_azure_state(resource_query_hint: str) -> dict | None:
    """Run a best-effort Resource Graph query based on hints in the issue body."""
    if not resource_query_hint:
        return None
    try:
        from azure.identity import DefaultAzureCredential
        from azure.mgmt.resourcegraph import ResourceGraphClient
        from azure.mgmt.resourcegraph.models import QueryRequest

        sub = os.environ.get("AZURE_SUBSCRIPTION_ID")
        if not sub:
            return None
        cred = DefaultAzureCredential()
        client = ResourceGraphClient(cred)
        req = QueryRequest(
            subscriptions=[sub],
            query=resource_query_hint,
        )
        resp = client.resources(req)
        return {"query": resource_query_hint, "rows": resp.data}
    except Exception as exc:  # noqa: BLE001
        return {"query": resource_query_hint, "error": str(exc)}


def _safe_patch_path(raw: str) -> PurePosixPath:
    """Return a sanitized POSIX-style relative path under one of SAFE_PATCH_ROOTS.

    Raises ValueError if the path escapes those roots or contains '..' segments.
    Defends against LLM-generated fix.filename values that try to overwrite
    workflows or any other repo file outside infra/ or scripts/.
    """
    if not raw or not isinstance(raw, str):
        raise ValueError("fix.filename missing or not a string")
    candidate = raw.replace("\\", "/").lstrip("/")
    p = PurePosixPath(candidate)
    if p.is_absolute():
        raise ValueError(f"absolute paths not allowed: {raw}")
    parts = p.parts
    if any(seg in ("..", "") for seg in parts):
        raise ValueError(f"path contains '..' or empty segment: {raw}")
    flat = str(p)
    if not flat.startswith(SAFE_PATCH_ROOTS):
        raise ValueError(
            f"path must start with one of {SAFE_PATCH_ROOTS!r}: {raw}"
        )
    return p


def _fence_for(content: str) -> str:
    """Pick a fence string long enough to escape any backtick run inside `content`.

    Standard 3-backtick fences break when the patch itself contains ``` (e.g.
    nested markdown blocks). We compute max-backtick-run + 1 so the fence is
    always safe.
    """
    longest = max((len(m.group(0)) for m in re.finditer(r"`+", content)), default=0)
    return "`" * max(3, longest + 1)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--issue-file", required=True, help="Path to JSON file with issue payload")
    parser.add_argument("--out-dir", default="./out", help="Where to write triage artifacts")
    parser.add_argument("--state-query", default="", help="Optional ARG query to attach")
    args = parser.parse_args(argv)

    logging.basicConfig(
        level=os.environ.get("LOG_LEVEL", "INFO"),
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )

    # Initialise the OpenTelemetry distro if App Insights is wired up. The
    # workflow exports APPLICATIONINSIGHTS_CONNECTION_STRING from the matching
    # GitHub secret; if absent (local dev), we no-op.
    if os.environ.get("APPLICATIONINSIGHTS_CONNECTION_STRING"):
        try:
            from azure.monitor.opentelemetry import configure_azure_monitor

            configure_azure_monitor(logger_name=LOG.name)
            LOG.info("Azure Monitor OpenTelemetry distro initialised")
        except Exception:  # noqa: BLE001 — telemetry must never crash the agent
            LOG.exception("OpenTelemetry init failed; continuing without traces")

    issue = json.loads(Path(args.issue_file).read_text())
    ctx = IssueContext(
        title=issue.get("title", ""),
        body=issue.get("body", ""),
        number=int(issue.get("number", 0)),
        labels=[lbl["name"] if isinstance(lbl, dict) else lbl for lbl in issue.get("labels", [])],
        azure_state=_gather_azure_state(args.state_query) if args.state_query else None,
    )

    proposal = triage(ctx)

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    fix = proposal.get("fix") or {}
    if fix.get("patch") and fix.get("filename"):
        try:
            safe_rel = _safe_patch_path(fix["filename"])
        except ValueError as e:
            LOG.warning("Rejecting unsafe patch path %r: %s", fix.get("filename"), e)
            proposal.setdefault("warnings", []).append(
                f"Patch filename rejected by guard: {e}. No patch was staged."
            )
            proposal["fix"] = None
        else:
            # Use sanitized relative path everywhere downstream; write the staged
            # file to a basename-only artifact so the workflow can't be tricked
            # into reading from a path the LLM controls.
            staged = "patch-" + safe_rel.name
            (out_dir / staged).write_text(fix["patch"])
            proposal["fix"]["filename"] = str(safe_rel)
            proposal["fix"]["staged_basename"] = staged

    (out_dir / "proposal.json").write_text(json.dumps(proposal, indent=2))
    md = _render_pr_body(ctx, proposal)
    (out_dir / "pr-body.md").write_text(md)

    print(f"✓ Wrote {out_dir / 'proposal.json'} and {out_dir / 'pr-body.md'}")
    return 0


def _render_pr_body(ctx: IssueContext, proposal: dict) -> str:
    fix = proposal.get("fix") or {}
    patch_text = fix.get("patch") or "(no patch generated)"
    fence = _fence_for(patch_text)
    warnings = proposal.get("warnings") or []
    warnings_md = (
        "\n".join(f"> ⚠️ {w}" for w in warnings) + "\n\n" if warnings else ""
    )
    return f"""## Triage Agent Proposal — closes #{ctx.number}

> Generated by the OGEDemos Triage Agent (o4-mini via OGEAgenticDemos Foundry).
> **Human review required before merge.**

{warnings_md}### Summary

{proposal.get("summary", "(not provided)")}

### Root cause

{proposal.get("root_cause", "(not provided)")}

### Proposed fix ({fix.get("kind", "n/a")})

{fence}{fix.get("kind", "")}
{patch_text}
{fence}

Target file: `{fix.get("filename", "(none)")}`

### Risk

{proposal.get("risk", "(not provided)")}

### Verification

{proposal.get("verification", "(not provided)")}

### What the human reviewer should focus on

{chr(10).join("- " + item for item in proposal.get("human_review_focus", []) or ["(not provided)"])}

---

<sub>This PR was generated automatically. The agent did not deploy anything. Approving + merging this PR triggers `.github/workflows/deploy.yml` against `OGEDemos_RG`.</sub>
"""


if __name__ == "__main__":
    sys.exit(main())
