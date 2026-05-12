# Operational Runbook — OGEDemos SRE Showcase

This runbook walks an operator through the full end-to-end loop and what to do when something goes sideways.

---

## End-to-end happy path

```
1. Azure SRE Agent watches OGEDemos_RG
2. SRE Agent detects: open NSG / orphan disk / no autoscale / near-expiry cert
3. SRE Agent files a GitHub Issue on this repo with label "sre-finding"
4. Workflow .github/workflows/issue-triage.yml fires
5. Workflow downloads the issue + queries ARG for the affected resource
6. Foundry triage agent (o4-mini) produces a structured fix proposal
7. Workflow opens a DRAFT PR with the proposal + patch file
8. CODEOWNERS reviewer receives a request
9. Reviewer approves + merges
10. .github/workflows/deploy.yml fires on the merge
11. Bicep redeployment lands in OGEDemos_RG, closing the loop
12. Workflow closes the linked issue
```

Every step is observable in GitHub (Actions tab + PR timeline) and in Azure (App Insights traces of the triage agent + ARM deployments in OGEDemos_RG).

---

## First-time bootstrap

### 1. Deploy the broken scenarios

```bash
cd infra/scenarios && bash deploy-all.sh
bash ../../scripts/seed-expiring-cert.sh    # seeds the near-expiry cert
```

You should end up with these resources in `OGEDemos_RG`:

| Scenario | Resource type | Name |
|---|---|---|
| Storm / reliability | VMSS | `ogedemo-storm-vmss` |
| Security | NSG (open SSH+RDP) | `ogedemo-security-nsg` |
| Cost | Managed disk + App Plan | `ogedemo-cost-orphan-disk`, `ogedemo-cost-idle-plan` |
| Reliability | Key Vault + cert | `ogedemo-reli-kv-*`, `near-expiry-cert` |

### 2. Verify the SRE Agent

The Azure SRE Agent `ogeagenticops` is already provisioned in `OGEDemos_RG`. Confirm it's running and see what (if anything) still needs to be configured:

```bash
bash scripts/check-sre-agent.sh
```

Current configuration (as of 2026-05-12):
- **Resource:** `Microsoft.App/agents/ogeagenticops`
- **Endpoint:** `https://ogeagenticops--698f97bb.de5105f9.eastus2.azuresre.ai`
- **Model:** Anthropic Automatic (managed model selection)
- **Scope:** Knowledge graph covers `OGEDemos_RG`
- **Action mode:** `review` with `Low` access — agent proposes, never executes
- **Identity:** System-assigned + user-assigned (`ogeagenticops-etpaql446bpno`)
- **UAMI roles on `OGEDemos_RG`:** Reader, Monitoring Reader, Monitoring Contributor, Log Analytics Reader
- **Incident management:** Azure Monitor (`incidentManagementConfiguration.type = AzMonitor`)
- **GitHub integration:** ⚠️ not yet configured — see "Bridge to GitHub" below

### 2a. Bridge SRE findings → GitHub Issues

Findings from the SRE Agent need to land as GitHub Issues on this repo to trigger the triage workflow. Two supported paths:

**Path A — Configure GitHub in the SRE Agent portal (recommended)**
1. Open the agent in the [Azure portal](https://portal.azure.com/) → search "SRE Agents" → `ogeagenticops`
2. Go to **Integrations → GitHub**
3. Install the SRE Agent GitHub App on `Sleepyreaper/ogedemos-sre-showcase`
4. Configure labels `sre-finding, needs-triage` on filed issues

**Path B — Azure Monitor Action Group + Logic App bridge (fallback)**
```bash
bash scripts/setup-azmon-github-bridge.sh
```
This deploys a Logic App that POSTs to `https://api.github.com/repos/Sleepyreaper/ogedemos-sre-showcase/issues` whenever an SRE finding becomes an Azure Monitor incident. Slightly less direct than Path A but works without portal access to the GitHub App.

**Path C — Manual simulation (already works)**
```bash
bash scripts/simulate-sre-issue.sh "Open SSH on mgmt subnet" security
```
Files a synthetic issue identical in shape to a real SRE Agent finding. Useful for testing the triage workflow without producing real Azure incidents.

### 3. Configure GitHub → Azure auth (Workload Identity Federation)

Workload Identity Federation lets GitHub Actions get short-lived Azure AD tokens without storing secrets. One-time setup:

```bash
SUB=$(az account show --query id -o tsv)
TENANT=$(az account show --query tenantId -o tsv)
APP_NAME="ogedemos-sre-showcase-github"

# Create an App Registration
APP_ID=$(az ad app create --display-name "$APP_NAME" --query appId -o tsv)
SP_ID=$(az ad sp create --id "$APP_ID" --query id -o tsv)

# Federate against GitHub OIDC (this repo + main branch)
az ad app federated-credential create --id "$APP_ID" --parameters '{
  "name": "github-main",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:Sleepyreaper/ogedemos-sre-showcase:ref:refs/heads/main",
  "audiences": ["api://AzureADTokenExchange"]
}'

# Grant Contributor on OGEDemos_RG (scope down later for production)
RG_ID=$(az group show -n OGEDemos_RG --query id -o tsv)
az role assignment create --assignee-object-id "$SP_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Contributor" --scope "$RG_ID"

# Grant Cognitive Services OpenAI User on the Foundry account
AOAI_ID=$(az cognitiveservices account show -g OGEDemos_RG -n ogeagenticdemos-resource --query id -o tsv)
az role assignment create --assignee-object-id "$SP_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Cognitive Services OpenAI User" --scope "$AOAI_ID"

# Push the IDs into GitHub secrets
gh secret set AZURE_CLIENT_ID --body "$APP_ID"
gh secret set AZURE_TENANT_ID --body "$TENANT"
gh secret set AZURE_SUBSCRIPTION_ID --body "$SUB"
gh secret set AZURE_OPENAI_ENDPOINT --body "https://ogeagenticdemos-resource.cognitiveservices.azure.com/"

# App Insights connection string for tracing the triage agent (optional)
APPI=$(az monitor app-insights component show -g DTE_RG -a dteops-appi --query connectionString -o tsv)
gh secret set APPLICATIONINSIGHTS_CONNECTION_STRING --body "$APPI"
```

### 4. Set CODEOWNERS

Edit `.github/CODEOWNERS` so triage PRs get assigned to the right humans:

```
* @Sleepyreaper
```

---

## Demo flow

The shortest path to a believable demo:

```bash
# 1. (Pre-stage) verify scenarios are deployed and the agent is in place
az resource list -g OGEDemos_RG --query "[].name" -o tsv

# 2. File a synthetic SRE finding to kick off the triage loop
bash scripts/simulate-sre-issue.sh "Security drift — open SSH" security

# 3. Watch the workflow run
gh run watch

# 4. Open the resulting draft PR
gh pr list --label agent-proposal

# 5. Approve + merge in the GitHub UI

# 6. Watch deploy.yml redeploy the scenario with the fix
gh run watch

# 7. Verify the fix landed
az network nsg show -g OGEDemos_RG -n ogedemo-security-nsg \
  --query "securityRules[].{name:name, src:sourceAddressPrefix, action:access}" -o table
```

For the real demo, replace step 2 with the actual Azure SRE Agent filing an issue itself.

---

## Troubleshooting

### Triage workflow fails on `azure/login@v2`

The federated credential subject must EXACTLY match the workflow's OIDC token subject. Common mismatches:

- Branch protection — if the workflow runs on a PR, the subject is `pull_request` not `ref:refs/heads/main`. Add a second federated credential:
  ```
  "subject": "repo:Sleepyreaper/ogedemos-sre-showcase:pull_request"
  ```

### Triage agent returns non-JSON

Reasoning models occasionally produce prose despite `response_format`. Check the `out/proposal.json` file's `raw_output` field. If it's persistent, switch `TRIAGE_MODEL` env var to `gpt-5.4` (synthesis tier) — slightly less reasoning, much stricter format adherence.

### SRE Agent provisioning fails with "feature not registered"

If you're creating the SRE Agent from scratch via CLI, run `az feature show --namespace Microsoft.App --name SREAgentPreview --query properties.state`. If it's still `Registering`, wait — Microsoft preview features can take 15-30 minutes to propagate. In our case the agent (`ogeagenticops`) was created via the portal, which handles the feature reg implicitly.

### PR opens but the patch file is empty

Look at the triage agent's `out/proposal.json` — if `fix.patch` is null, the model decided it didn't have enough info. The PR body explains what data it would need. Add details to the issue and re-trigger the workflow by removing and re-adding the `sre-finding` label.

### Deploy workflow fails on Bicep

Bicep deployments use the App Registration's Contributor role on OGEDemos_RG. Confirm:
- The App Registration's principal ID has Contributor on the RG
- The scenario file references only resources in OGEDemos_RG (no cross-RG references)

---

## What this proves

This showcase demonstrates **agentic IT-ops in production-realistic form**:

- **Detection** — Microsoft's managed SRE Agent (not a custom build)
- **Workqueue** — GitHub Issues (audited, addressable, searchable)
- **Reasoning** — Custom Foundry agent (o4-mini) producing structured fixes
- **Governance** — Human approval gate via PR review + CODEOWNERS
- **Safety** — Agent NEVER writes to Azure directly; only proposes changes as PRs
- **Observability** — Every agent call traced in App Insights
- **Repeatability** — Whole loop is IaC + workflow YAML, redeployable per engagement

Pair this with the DTE Cloud Weather Ops (`https://dteops.ogedemos.com`) to show both a **direct chat-based agentic experience** and an **autonomous detection→fix→approve→deploy** loop running on the same Foundry.
