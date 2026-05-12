# OGE Demos — Azure SRE Agent + DTE Agentic Ops Showcase

> **End-to-end agentic IT-ops on Azure.** Microsoft's official **Azure SRE Agent** (`ogeagenticops`) watches `OGEDemos_RG`, uses custom subagents and a curated knowledge base, files GitHub issues with proposed fixes, and gates every change behind human PR review.

## Live URLs

| What | Where |
|---|---|
| 🤖 **SRE Agent** (managed portal) | https://sre.azure.com |
| 🌐 **DTE Cloud Weather Ops** (custom Foundry app) | https://dteops.ogedemos.com |
| 📦 **This repo** | https://github.com/Sleepyreaper/ogedemos-sre-showcase |
| 🔍 **Agent endpoint** | https://ogeagenticops--698f97bb.de5105f9.eastus2.azuresre.ai |

## Architecture (Microsoft-native pattern)

```
   ┌────────────────────────────────────────────────────────────────────┐
   │                       OGEDemos_RG (Azure)                           │
   │                                                                      │
   │  Storm scenario  Security scenario  Cost scenario  Reliab. scn       │
   │  (autoscale)     (open NSG)         (orphan disk)  (expired cert)    │
   │                                                                      │
   │                              ▲                                       │
   │                              │ knowledge graph + telemetry           │
   │      ┌───────────────────────┴────────────────────────────┐          │
   │      │  Azure SRE Agent — ogeagenticops                   │          │
   │      │  Microsoft.App/agents · Anthropic model · review   │          │
   │      │                                                    │          │
   │      │  Knowledge Base (data-plane upload, this repo):    │          │
   │      │   • ogedemos-architecture.md                       │          │
   │      │   • security-drift-runbook.md                      │          │
   │      │   • cost-waste-runbook.md                          │          │
   │      │   • reliability-runbook.md                         │          │
   │      │   • storm-readiness-runbook.md                     │          │
   │      │   • github-issue-triage.md                         │          │
   │      │   • incident-report-template.md                    │          │
   │      │                                                    │          │
   │      │  Custom subagents (azuresre.ai/v1 YAML):           │          │
   │      │   • security-fixer       (Review mode)             │          │
   │      │   • cost-optimizer       (Review mode)             │          │
   │      │   • reliability-fixer    (Review mode)             │          │
   │      │   • code-analyzer        (Review mode)             │          │
   │      │   • issue-triager        (Autonomous)              │          │
   │      │                                                    │          │
   │      │  Data Connectors:                                  │          │
   │      │   • OGEAgentAppInsight  (agent's own telemetry)    │          │
   │      │   • dteops-appi          (DTE Cloud Weather Ops)   │          │
   │      │   • dteops-log           (DTE Log Analytics)       │          │
   │      │                                                    │          │
   │      │  CodeRepos (cloned + indexed):                     │          │
   │      │   • ogedemos-sre-showcase    DTECloudWeatherOps    │          │
   │      │   • OGEAgenticITOperations   P66-Ops-Council       │          │
   │      │   • PPLAUTO                  ZeroDownTimeDevOps    │          │
   │      └────────────────────────┬───────────────────────────┘          │
   └────────────────────────────────┼─────────────────────────────────────┘
                                    │ files
                                    ▼
   ┌────────────────────────────────────────────────────────────────────┐
   │                          GitHub (this repo)                        │
   │                                                                    │
   │   Issue with proposed fix                                          │
   │        │                                                           │
   │        ▼                                                           │
   │   PR (human review, CODEOWNERS gate)                              │
   │        │                                                           │
   │        ▼                                                           │
   │   Merge → .github/workflows/deploy.yml redeploys to OGEDemos_RG    │
   └────────────────────────────────────────────────────────────────────┘
```

## What's in this repo

| Path | Purpose |
|------|---------|
| `infra/scenarios/` | 4 broken-on-purpose Bicep templates deployed to `OGEDemos_RG` |
| `knowledge-base/` | Markdown runbooks loaded into the SRE Agent's memory |
| `sre-config/agents/` | YAML specs (`azuresre.ai/v1`) for custom subagents |
| `scripts/apply-sre-config.sh` | Uploads KB + creates subagents + registers CodeRepo on `ogeagenticops` |
| `scripts/register-github-repo.sh` | Register an additional GitHub repo as a CodeRepo (modern pattern) |
| `scripts/check-sre-agent.sh` | Read-only verifier of the agent's current state |
| `scripts/simulate-sre-issue.sh` | Files a synthetic issue without waiting for the real agent |
| `scripts/seed-expiring-cert.sh` | Injects the near-expiry cert into the Key Vault scenario |
| `agents/triage/` | **Alternative pattern** — Foundry-direct Python triage agent run in GitHub Actions |
| `.github/workflows/` | issue-triage.yml + deploy.yml |
| `docs/` | runbook, scenarios, agent-design |

## Quick start

```bash
# 1. Deploy the broken scenarios to OGEDemos_RG
cd infra/scenarios && bash deploy-all.sh

# 2. Apply this repo's config to the SRE Agent
bash scripts/apply-sre-config.sh
# Uploads 7 markdown runbooks via data plane.
# Attempts to create 5 subagents via management plane (may be tenant-gated;
# see "Tenant gates" below).

# 3. Wire GitHub to the SRE Agent
#    One-time: sign in to GitHub at https://sre.azure.com (Connectors → GitHub)
#    Then register the repo:
bash scripts/register-github-repo.sh Sleepyreaper/ogedemos-sre-showcase

# 4. Fire a synthetic test (works without the agent)
bash scripts/simulate-sre-issue.sh "Open SSH on mgmt subnet" security
```

## Tenant gates (as of 2026-05-12)

- ✅ **Knowledge Base upload** — works via the data plane API on this tenant
- ⚠️ **Custom subagents** — the SRE Agent API returns `Agent Extensions are not available for this tenant. This feature is restricted to internal tenants only.` Configure subagents via the **SRE Agent portal** (Builder → Agent Canvas) until the feature GAs to your tenant.
- ✅ **GitHub OAuth connector** — works via the portal Builder → Connectors flow

The YAML specs in `sre-config/agents/` are authoritative — paste them into the portal's Agent Canvas to apply manually.

## Two patterns demonstrated

This repo deliberately shows **both** common agentic-ops patterns side-by-side:

| Pattern | Where | When to choose |
|---|---|---|
| **SRE-Agent-native** | `ogeagenticops` + this repo's `knowledge-base/` + `sre-config/` | Use Microsoft's managed agent platform; minimal custom code; leverages built-in tools (Azure CLI, Log Analytics, App Insights, code interpreter); deep GitHub + Teams integration |
| **Foundry-direct** | `agents/triage/` + `.github/workflows/issue-triage.yml` | Use raw Azure OpenAI / Foundry models in your own runtime when you need full control over the orchestration loop, debate dynamics, or non-SRE workloads. This is what powers the DTE Cloud Weather Ops at https://dteops.ogedemos.com |

Both write to the same GitHub repo, both use Azure AI Foundry (`ogeagenticdemos-resource`) for the underlying models, both gate every change behind human PR review.

## Demo scenarios

Each scenario is intentionally broken so the SRE Agent (or the Foundry triage agent) has something realistic to detect, classify, and propose a fix for.

| Scenario | Resource | Expected finding |
|---|---|---|
| Storm | `ogedemo-storm-vmss` | VMSS has no autoscale settings; customer-portal tier can't grow under load |
| Security | `ogedemo-security-nsg` | SSH (22) + RDP (3389) Allow inbound from `0.0.0.0/0` |
| Cost | `ogedemo-cost-orphan-disk` + `ogedemo-cost-orphan-pip` | 1 TB Premium SSD unattached + Standard public IP unassociated (~$138/mo waste) |
| Reliability | `ogekv...` / `near-expiry-cert` | Cert expires in <30 days, no rotation policy |

Full per-scenario detail in [`docs/scenarios.md`](docs/scenarios.md).

## Status

| Component | Status |
|---|---|
| GitHub repo | ✅ |
| Demo scenarios (Bicep) | ✅ deployed to OGEDemos_RG |
| Knowledge base (7 runbooks) | ✅ uploaded + indexed on `ogeagenticops` |
| Custom subagents (YAML) | ⚠️ specs ready in `sre-config/agents/`; apply via portal (tenant-gated for API) |
| GitHub repo registered as CodeRepo on agent | ✅ `ogedemos-sre-showcase` cloneStatus=Ready alongside 5 other repos |
| DTE Cloud Weather Ops connectors (LAW + App Insights) | ✅ `dteops-log` + `dteops-appi` wired to `ogeagenticops`, query-verified live |
| End-to-end SRE Agent investigation → GitHub issue | ✅ Issue [#3](https://github.com/Sleepyreaper/ogedemos-sre-showcase/issues/3) filed autonomously by the agent (read runbook, investigated, grep'd repo, classified drift, proposed Bicep fix) |
| Triage workflow (Foundry-direct alternative) | ✅ end-to-end verified (issue #1 → PR #2) |
| Workload Identity Federation | ✅ |
| DTE Cloud Weather Ops (sibling app) | ✅ live at dteops.ogedemos.com |

## See also

- [`docs/runbook.md`](docs/runbook.md) — full operational runbook
- [`docs/scenarios.md`](docs/scenarios.md) — what each demo scenario does and why
- [`docs/agent-design.md`](docs/agent-design.md) — how the SRE-Agent-native vs Foundry-direct patterns compare
- [`docs/azure-sre-resources.md`](docs/azure-sre-resources.md) — curated references to Microsoft's official SRE Agent docs, labs, and blogs
