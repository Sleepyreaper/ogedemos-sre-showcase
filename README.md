# OGE Demos — Azure SRE + DTE Agentic Ops Showcase

> **End-to-end agentic IT-ops loop on Azure.** Microsoft's Azure SRE Agent watches the OGEDemos_RG estate, GitHub issues become the work queue, a custom Foundry triage agent proposes fixes, humans approve, GitHub Actions deploy. All governed and evaluated by Azure AI Foundry.

```
   ┌────────────────────────────────────────────────────────────────┐
   │                     OGEDemos_RG (Azure)                         │
   │                                                                  │
   │  Storm scenario  Security scenario  Cost scenario  Reliab. scn   │
   │  (autoscale)     (open NSG)         (orphan disk)  (expired cert)│
   │                                                                  │
   │                          ▲                                       │
   │                          │ monitors / detects                    │
   │                  ┌───────┴────────┐                              │
   │                  │ Azure SRE Agent│ ← Microsoft preview          │
   │                  │  (Microsoft.App)│                              │
   │                  └───────┬────────┘                              │
   └──────────────────────────│───────────────────────────────────────┘
                              │ files
                              ▼
   ┌──────────────────────────────────────────────────────────────────┐
   │                    GitHub (this repo)                             │
   │                                                                   │
   │   Issue opened   ──webhook──▶  GitHub Action ──▶  Foundry agent  │
   │   (incident)                   (issue-triage.yml)  (triage/)     │
   │                                                       │           │
   │                                                       ▼           │
   │                                              Draft PR with fix   │
   │                                                  +  evidence     │
   │                                                       │           │
   │                                                       ▼           │
   │                                              Human review        │
   │                                              (CODEOWNERS gate)   │
   │                                                       │           │
   │                                                       ▼           │
   │                                              Merge → deploy.yml  │
   │                                              redeploys OGEDemos  │
   └──────────────────────────────────────────────────────────────────┘
                              ▲
                              │ traces + evals
   ┌──────────────────────────│───────────────────────────────────────┐
   │            Azure AI Foundry (OGEAgenticDemos)                    │
   │  • Hosts the triage agent (o4-mini / gpt-5.4)                    │
   │  • App Insights tracing on every agent call                      │
   │  • Continuous evaluation: groundedness, relevance, safety         │
   │  • Same governance plane as the DTE Cloud Weather Ops             │
   └──────────────────────────────────────────────────────────────────┘
```

## What's in here

| Path | Purpose |
|------|---------|
| `infra/scenarios/` | Bicep for 4 intentionally-broken resources in `OGEDemos_RG` |
| `agents/triage/` | Custom Foundry agent that triages GitHub issues into proposed fixes |
| `.github/workflows/issue-triage.yml` | Webhook handler: issue opened → invoke triage agent → draft PR |
| `.github/workflows/deploy.yml` | On merge to `main`, redeploys affected scenarios |
| `scripts/` | Bootstrap + maintenance scripts (deploy scenarios, simulate SRE findings) |
| `docs/` | End-to-end runbook, agent prompts, demo script |

## Live demos

- **DTE Cloud Weather Ops** — https://dteops.ogedemos.com (multi-agent debate UI)
- **SRE Agent + GitHub loop** — this repo (issues + workflow runs are the demo surface)

## Quick start

```bash
# 1. Deploy the broken scenarios to OGEDemos_RG
cd infra/scenarios && bash deploy-all.sh

# 2. Provision Azure SRE Agent against OGEDemos_RG (after feature reg propagates)
bash scripts/provision-sre-agent.sh

# 3. Configure GitHub secrets for the triage agent (uses Workload Identity Federation)
gh secret set AZURE_OPENAI_ENDPOINT --body "https://ogeagenticdemos-resource.cognitiveservices.azure.com/"
gh secret set AZURE_CLIENT_ID --body "<workload-identity-client-id>"
gh secret set AZURE_TENANT_ID --body "<tenant>"
gh secret set AZURE_SUBSCRIPTION_ID --body "<sub>"

# 4. Open a synthetic incident issue to test the loop end-to-end
bash scripts/simulate-sre-issue.sh "Orphaned disk drift detected"
```

## See also

- [`docs/runbook.md`](docs/runbook.md) — Full operational runbook
- [`docs/scenarios.md`](docs/scenarios.md) — The four demo scenarios in detail
- [`docs/agent-design.md`](docs/agent-design.md) — How the triage agent is built
- [`agents/triage/`](agents/triage/) — Agent source code

## Status

| Component | Status |
|---|---|
| GitHub repo | ✅ created |
| Demo scenarios (Bicep) | ✅ scaffolded |
| Triage agent | ✅ scaffolded |
| GitHub workflows | ✅ scaffolded |
| Azure SRE Agent provisioning | ⏳ pending feature registration propagation |
| Workload Identity Federation | ⏳ pending (after first end-to-end) |
| Deployed live demo scenarios | ⏳ pending user "go" |
