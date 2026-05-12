# Operational Runbook — OGEDemos SRE + Triage Showcase

This runbook walks operators through both patterns demonstrated in this repo: **SRE-Agent-native** (the Microsoft pattern, primary) and **Foundry-direct** (custom Python triage agent, secondary).

---

## End-to-end happy path — SRE-Agent-native

```
1. Azure SRE Agent (ogeagenticops) builds knowledge graph on OGEDemos_RG
2. Azure Monitor alert OR user chat invocation OR Response Plan match
3. Agent invokes the matching custom subagent (e.g., security-fixer)
4. Subagent searches knowledge base, follows the runbook, gathers evidence
5. Subagent files GitHub issue using incident-report-template
6. issue-triager (Autonomous) labels and comments on the issue
7. Human reviews issue + agent's proposed fix
8. Reviewer accepts → drafts PR with the fix
9. CODEOWNERS approve + merge
10. .github/workflows/deploy.yml redeploys to OGEDemos_RG
11. Workflow closes the linked issue
```

## End-to-end happy path — Foundry-direct

```
1. Human (or SRE Agent / external system) files issue on this repo
2. .github/workflows/issue-triage.yml fires
3. Custom Foundry agent in agents/triage/ runs with o4-mini
4. Agent fetches Azure state via Resource Graph
5. Agent produces structured JSON fix proposal
6. Workflow opens draft PR with proposal.json + patch file
7. Human reviews + approves + merges
8. .github/workflows/deploy.yml redeploys
```

Both write to the same repo and respect the same human-approval gate. The DTE Cloud Weather Ops at https://dteops.ogedemos.com runs on the **Foundry-direct** pattern and demonstrates the 6-agent debate experience.

---

## First-time bootstrap

### 1. Deploy the broken scenarios

```bash
cd infra/scenarios && bash deploy-all.sh
bash ../../scripts/seed-expiring-cert.sh    # injects the near-expiry cert
```

You should end up with these resources in `OGEDemos_RG`:

| Scenario | Resource type | Name |
|---|---|---|
| Storm / reliability | VMSS + VNet | `ogedemo-storm-vmss`, `ogedemo-storm-vnet` |
| Security | NSG (open SSH+RDP) | `ogedemo-security-nsg` |
| Cost | Managed disk + Public IP | `ogedemo-cost-orphan-disk`, `ogedemo-cost-orphan-pip` |
| Reliability | Key Vault + cert | `ogekv...`, `near-expiry-cert` |

### 2. Verify the SRE Agent (`ogeagenticops`)

```bash
bash scripts/check-sre-agent.sh
```

Expected output: agent is `Running` (or `BuildingKnowledgeGraph` on first deploy), scoped to `OGEDemos_RG`, in `review` mode with `Low` access.

### 3. Apply this repo's config to the agent

```bash
bash scripts/apply-sre-config.sh
```

This uploads 7 markdown runbooks into the agent's knowledge base via the data plane. It also attempts to create 5 custom subagents via the management plane — this currently requires the `Agent Extensions` tenant feature flag (Microsoft preview). If your tenant doesn't have it, the script reports "skipped (tenant gate)" and you should apply the YAML specs in `sre-config/agents/` via the portal manually.

### 4. Wire GitHub to the SRE Agent

**Path A — Portal (recommended for first-time setup)**

1. Open https://sre.azure.com → sign in
2. Open agent `ogeagenticops`
3. Connectors → ensure GitHub is signed in at the user level (one-time)
4. Code Repos → "Add" → paste `https://github.com/Sleepyreaper/ogedemos-sre-showcase`

**Path B — Register via data plane (idempotent CLI)**

```bash
bash scripts/register-github-repo.sh Sleepyreaper/ogedemos-sre-showcase
```

This works after you've completed the one-time portal GitHub sign-in. The repo clones onto the agent and the agent can search code + open issues automatically.

> **Note:** The legacy `GitHubOAuth` *connector* type is deprecated — modern SRE Agent doesn't use per-connector tokens. User-level OAuth (signed in at the portal) covers all repos you register.

### 5. Configure Workload Identity Federation (for the Foundry-direct workflow)

WIF lets `.github/workflows/issue-triage.yml` and `deploy.yml` authenticate to Azure with no stored secrets.

```bash
SUB=$(az account show --query id -o tsv)
TENANT=$(az account show --query tenantId -o tsv)
APP_ID=$(az ad app create --display-name "ogedemos-sre-showcase-github" --query appId -o tsv)
SP_ID=$(az ad sp create --id "$APP_ID" --query id -o tsv)

# Federated credential for main branch + PR builds + triage branches
for SUBJECT in \
  "repo:Sleepyreaper/ogedemos-sre-showcase:ref:refs/heads/main" \
  "repo:Sleepyreaper/ogedemos-sre-showcase:pull_request" \
  "repo:Sleepyreaper/ogedemos-sre-showcase:ref:refs/heads/triage/*"; do
  az ad app federated-credential create --id "$APP_ID" --parameters "{
    \"name\": \"$(echo $SUBJECT | tr ':/' '--' | tr '*' 'x' | head -c 64)\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"$SUBJECT\",
    \"audiences\": [\"api://AzureADTokenExchange\"]
  }"
done

# RBAC
RG_ID=$(az group show -n OGEDemos_RG --query id -o tsv)
AOAI_ID=$(az cognitiveservices account show -g OGEDemos_RG -n ogeagenticdemos-resource --query id -o tsv)
az role assignment create --assignee-object-id "$SP_ID" --assignee-principal-type ServicePrincipal \
  --role "Contributor" --scope "$RG_ID"
az role assignment create --assignee-object-id "$SP_ID" --assignee-principal-type ServicePrincipal \
  --role "Cognitive Services OpenAI User" --scope "$AOAI_ID"
az role assignment create --assignee-object-id "$SP_ID" --assignee-principal-type ServicePrincipal \
  --role "Reader" --scope "/subscriptions/$SUB"

# GitHub secrets
APPI=$(az monitor app-insights component show -g DTE_RG -a dteops-appi --query connectionString -o tsv)
gh secret set AZURE_CLIENT_ID --body "$APP_ID"
gh secret set AZURE_TENANT_ID --body "$TENANT"
gh secret set AZURE_SUBSCRIPTION_ID --body "$SUB"
gh secret set AZURE_OPENAI_ENDPOINT --body "https://ogeagenticdemos-resource.cognitiveservices.azure.com/"
gh secret set APPLICATIONINSIGHTS_CONNECTION_STRING --body "$APPI"

# Allow Actions to create PRs (one-time repo setting)
gh api -X PUT /repos/Sleepyreaper/ogedemos-sre-showcase/actions/permissions/workflow \
  -f default_workflow_permissions=write -F can_approve_pull_request_reviews=false
```

---

## Demo flows

### Flow A — SRE-Agent-native (after subagent feature GAs to your tenant)

Once `Agent Extensions` is enabled and subagents are deployed:

```
1. Open https://sre.azure.com → ogeagenticops → chat
2. Type: /agent security-fixer
3. Ask: "Investigate ogedemo-security-nsg"
4. Watch the agent:
   • Search memory for security-drift-runbook
   • Run az network nsg rule list
   • Pull Activity Log for who/when
   • File a GitHub issue with proposed Bicep patch
5. Review the issue → draft PR → merge → deploy.yml redeploys
```

### Flow B — SRE-Agent-native without subagents (KB-only)

Even without the `Agent Extensions` feature, the main SRE Agent uses the uploaded knowledge base. Just chat with the agent normally:

```
"Are there any security risks in OGEDemos_RG?"
```

The agent will SearchMemory for `security-drift-runbook` automatically and follow it.

### Flow C — Foundry-direct (always works)

```bash
# 1. File a synthetic SRE finding
bash scripts/simulate-sre-issue.sh "Security drift — open SSH" security

# 2. Watch the workflow
gh run watch

# 3. Open the draft PR
gh pr list --label agent-proposal

# 4. Approve + merge in the GitHub UI

# 5. Watch deploy.yml redeploy
gh run watch

# 6. Verify the fix
az network nsg show -g OGEDemos_RG -n ogedemo-security-nsg \
  --query "securityRules[].{name:name, src:sourceAddressPrefix, action:access}" -o table
```

---

## Troubleshooting

### "Agent Extensions are not available for this tenant"

You hit this when calling `PUT .../subagents/{name}`. The custom-subagents feature is preview-gated to internal Microsoft tenants as of 2026-05-12. Mitigation:

- Use the SRE Agent portal's Agent Canvas (Builder → Agent Canvas) to create the same subagents manually from the YAML specs in `sre-config/agents/`.
- The knowledge base still works — the main agent uses your runbooks via `SearchMemory`.
- File a request: https://aka.ms/sreagent/region (or the discussions board) for tenant enablement.

### Knowledge base files show `isIndexed: false`

Usually a transient indexing race when many files upload at once. The apply script now waits between uploads. If you still see failures, delete and re-upload one file at a time:

```bash
TOKEN=$(az account get-access-token --resource https://azuresre.dev --query accessToken -o tsv)
ENDPOINT=$(az resource show --resource-type Microsoft.App/agents -g OGEDemos_RG -n ogeagenticops --api-version 2025-05-01-preview --query properties.agentEndpoint -o tsv)
curl -X POST "${ENDPOINT}/api/v1/AgentMemory/upload" \
  -H "Authorization: Bearer ${TOKEN}" \
  -F "triggerIndexing=true" \
  -F "files=@knowledge-base/<file>.md;type=text/markdown"
```

Then wait 30s and check status:

```bash
curl -s "${ENDPOINT}/api/v1/AgentMemory/files" -H "Authorization: Bearer ${TOKEN}" | python3 -m json.tool
```

### Triage workflow fails on `azure/login@v2`

The federated credential subject must EXACTLY match the workflow's OIDC token. Common mismatches:
- Workflow runs on a PR → subject is `pull_request`, not `ref:refs/heads/<branch>`
- Workflow runs from a `triage/issue-N` branch → subject is `ref:refs/heads/triage/*`

Verify and add federated credentials accordingly (see bootstrap step 5).

### Triage workflow's "Open draft PR" step fails with "GitHub Actions is not permitted to create or approve pull requests"

Repo setting. Toggle:
```bash
gh api -X PUT /repos/Sleepyreaper/ogedemos-sre-showcase/actions/permissions/workflow \
  -f default_workflow_permissions=write -F can_approve_pull_request_reviews=false
```

### Subagent rejects temperature parameter

Reasoning models (`o3`, `o3-pro`, `o4-mini`, `gpt-5.4-pro`) only support default temperature. For the Foundry-direct agent in `agents/triage/`, the runner skips temperature for the deployments listed in `reasoning_models`. If you add a new reasoning model, append its deployment name there.

### Bicep deployment hits "InternalSubscriptionIsOverQuotaForSku"

The cost scenario originally used a P0v3 / B1 App Service Plan; both are zero-quota in Brad NonProd. The current Bicep uses an orphan public IP instead — no compute quota required. If you fork and re-introduce compute, request quota at https://portal.azure.com/#blade/Microsoft_Azure_Capacity.

---

## What this proves

This showcase demonstrates **agentic IT-ops in three styles**, all running on the same Azure AI Foundry account (`ogeagenticdemos-resource`):

1. **Microsoft's managed SRE Agent** with curated knowledge base and custom subagents — operational intelligence delivered through `https://sre.azure.com`.
2. **Custom Foundry-direct agent** with bespoke orchestration — full code control, useful for non-SRE patterns like the DTE Cloud Weather Ops debate experience.
3. **GitHub-mediated human-in-the-loop** — every change goes through PR review + CODEOWNERS gate before deployment. No agent writes to Azure directly.

Combining these patterns gives customers a roadmap: start with the managed agent for general operational toil, add custom Foundry agents for domain-specific workflows, and use GitHub as the audit trail and approval surface for both.
