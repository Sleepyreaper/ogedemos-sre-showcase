# Demo Script — Thursday, 10-minute slot, ~2000 attendees

> **Live URLs to keep open in browser tabs:**
> 1. **Reliability view**: https://dteops.ogedemos.com (loads on Reliability tab)
> 2. **Cloud Weather Ops chat**: https://dteops.ogedemos.com (click "Cloud Weather Operations" tab)
> 3. **SRE Agent portal**: https://sre.azure.com (have `ogeagenticops` already open)
> 4. **GitHub issues**: https://github.com/Sleepyreaper/ogedemos-sre-showcase/issues
> 5. **Backup**: pre-recorded video (`~/demo-backup.mp4` — record day-before)

> **Before going live (T-30 min):**
> 1. Visit https://dteops.ogedemos.com → wait for first page load (cold-start ~6s)
> 2. Run a single-agent /api/ask to warm Foundry
> 3. Verify `ogeagenticops` shows Running (not BuildingKnowledgeGraph)
> 4. Verify GitHub Issue #3 + PR #2 are still open (or pre-stage new ones)
> 5. Close all unrelated tabs; presenter mode in browser
> 6. **Disable browser notifications** (Slack, Teams, etc.) — embarrassment-prevention

---

## Slide-by-slide flow

### [0:00 – 0:30] Open with the problem

**Slide:** "A large investor-owned utility — millions of customers, billions of meter reads"

**Say:**
> "When severe weather hits a utility's service territory, the systems that keep the lights on are running on Azure. SCADA, AMI metering at scale, the outage management system, the customer portal. These aren't optional. When the portal goes down during a storm, a family who lost power can't even check restoration estimates.
>
> Today I'm going to show you how we're using **Azure AI Foundry** and the **Azure SRE Agent** to keep that platform running — not by having more engineers, but by giving the engineers we have an agentic team that argues, investigates, and proposes fixes for them."

### [0:30 – 1:30] Reliability view — set the stage

**Click:** Open https://dteops.ogedemos.com (Reliability tab loads by default)

**Say:**
> "This is what an SRE on a utility cloud-ops team sees first thing on Monday morning. It's an executive reliability dashboard — score out of 100, four pillars: Security, Governance, Resilience, Cost. All of it backed by **real Azure Resource Graph** and **Service Health** queries — no canned data."

**Click:** Briefly hover the score ring and pillar bars

**Say:**
> "These numbers update every 60 seconds from Resource Graph, which is free. So this is always-on real-time intelligence at zero token cost. The AI agents only fire when someone asks a question or when a problem is detected — that's where the cost lives, and that's where the value lives."

### [1:30 – 2:30] Switch to Cloud Weather Ops — introduce the crew

**Click:** Top nav → "Cloud Weather Operations" tab

**Say:**
> "Now meet the team. Six AI agents, each named after a power-grid concept. They run on Azure AI Foundry — `gpt-5.4` for the synthesis agents, `o4-mini` reasoning models for the analytical work."

**Point at each card:**
> "**Grid Dispatch** is the coordinator. **Meter Reader** counts every dollar — pushes for savings. **The Lineman** is the grizzled veteran — pushes back on cost cuts that risk reliability. The tension between Meter Reader and The Lineman is a *feature*, not a bug. **Blackout** does root-cause analysis. **Arc Flash** is the early warning. **The Regulator** handles compliance."

### [2:30 – 5:00] The debate — main act

**Type into the chat:**
> `VM SCADA-batch-vm01 is oversized at D16. A storm is forecast for tonight. Cost vs reliability — what do we do?`

**Engage agents:** Meter Reader, The Lineman, Arc Flash (3 agents = ~30s)

**Say while it streams:**
> "Watch this. The agents stream in one at a time. **Arc Flash** is the alerting layer — short, terse, severity-tagged. **Meter Reader** is going to show his math. **The Lineman** is going to push back."

**When agents finish Round 1, point out:**
> "Look at the conflict. Meter Reader: $204/month savings. The Lineman: 'Not safe to touch blind with a storm coming.'"

**When Round 2 (rebuttals) fires:**
> "Now they're reacting to each other — Arc Flash is taking The Lineman's side. Meter Reader concedes the point and asks for data first."

**When synthesis lands:**
> "And **Grid Dispatch** synthesizes — perspectives, where they agreed, where they clashed, and a recommendation that names the tradeoff. This isn't a single AI giving an answer. It's a team of specialists with conflicting incentives, and the disagreement makes the recommendation *more trustworthy*, not less."

### [5:00 – 6:00] Pivot to the SRE Agent

**Say:**
> "But what about when humans aren't there to ask? That's where **Microsoft's Azure SRE Agent** comes in."

**Click:** Switch to https://sre.azure.com tab with `ogeagenticops` open

**Say:**
> "This is a managed Microsoft product — the same agentic operations runtime they use internally at Microsoft. We've pointed it at a resource group called `OGEDemos_RG`. It builds its own knowledge graph of every resource. We've uploaded **seven runbooks** to its memory, and connected it to **our GitHub repo** so it can read our infrastructure-as-code."

**Click:** Open the chat side of the SRE Agent

**Show / pre-prepare:** A prior conversation history (Issue #3 generation thread)

**Say:**
> "Here's a conversation from earlier this week. I asked it to investigate a security drift on a network security group in our demo environment. Watch what it did."

**Scroll through the messages briefly, highlighting:**
- Read the security-drift-runbook from memory
- Ran `az network nsg show` against live Azure
- Grep'd the GitHub repo for the resource name
- Found the Bicep source defining the bad rules
- Detected IaC↔live drift in *either* direction
- Filed a GitHub issue with a complete fix proposal

### [6:00 – 8:00] The output — closed-loop on GitHub

**Click:** Switch to https://github.com/Sleepyreaper/ogedemos-sre-showcase/issues/3

**Say:**
> "This is the issue the agent filed. Look at the structure — Summary, Impact, Timeline, Evidence with **specific ARM resource IDs**. Root cause classified as one of five categories. A complete Bicep patch that fixes the problem. Risk callout. Verification steps. *This is what a senior engineer would write.*"

**Click:** Switch to PR #2

**Say:**
> "And here's the draft PR. A second agent — our **custom Foundry triage agent** running in GitHub Actions — picked up that issue, generated this fix proposal, opened the PR. Now a human reviews. CODEOWNERS approves. Merge. And the deploy workflow redeploys the fix to the resource group automatically."

**Trace the architecture on screen:**
> "Detection → Issue → Custom agent → Draft PR → Human approval → Auto-deploy. Closed loop. Nothing touches Azure without a human signing the PR."

### [8:00 – 9:30] The point

**Pull up architecture slide (or backup screenshot):**

**Say:**
> "What we just saw — two complementary patterns, both running on the same Azure AI Foundry:
>
> 1. **Cloud Weather Operations** — six specialist agents that debate. We built it on the OpenAI SDK and Managed Identity. About 500 lines of Python. No framework.
>
> 2. **Azure SRE Agent** — Microsoft's managed product. Drop-in, custom subagents in YAML, knowledge base in Markdown, native GitHub integration.
>
> Both are governed by the same Foundry account. Both are observed in the same Application Insights. Both gate every change behind human PR approval. And both can be reused for any utility-style customer."

### [9:30 – 10:00] Close

**Say:**
> "The pattern works for any operationally-complex Azure customer. Anyone who's got a resource group full of moving parts, a small SRE team, and a roadmap of work they wish they had time for. That's the pitch.
>
> Repos and docs are at github.com/Sleepyreaper/ogedemos-sre-showcase. Live demo stays up at dteops.ogedemos.com. Questions?"

---

## Fallback plan — if something breaks live

### Cloud Weather Ops app slow / errors:
1. **Cut to the pre-recorded backup video** (~3 min of the chat working)
> "Live cloud demos in front of a packed room, what can possibly go wrong"
3. Recover with: "Here's the same flow we just ran, recorded earlier"

### SRE Agent shows "Building knowledge graph":
1. **Skip live invocation**, go straight to **GitHub Issue #3**
2. Narrate the agent's work from the issue body — same content
3. "This was filed autonomously by the agent earlier this week"

### GitHub Actions workflow fails / hangs:
1. **Show PR #2** which is already open from a prior run
2. "This PR was generated the same way — fix proposal, human review gate, ready to merge"

### Live Foundry rate-limit:
1. Switch Cloud Weather Ops to **Demo mode** (Demo Data toggle in top nav)
2. Pre-baked debate scenarios — no model calls at all
3. Same content, no risk

### Total catastrophic failure:
1. **Backup screen recording** — full 10 minutes pre-recorded
2. Pull up the recording, narrate over it
3. "The cloud gods are angry today, but the recording shows the working demo"

---

## Pre-flight checklist (T-30 min)

- [ ] Cloud Weather Ops loads in <3s (warm)
- [ ] Single-agent `/api/ask` returns in <12s
- [ ] `ogeagenticops` agent shows `Running` (not BuildingKnowledgeGraph)
- [ ] Issue #3 still open on showcase repo
- [ ] PR #2 still open and showing the right content
- [ ] Architecture backup slide loaded in adjacent tab
- [ ] Pre-recorded backup video loaded and tested locally
- [ ] Browser notifications: OFF
- [ ] All other tabs: closed
- [ ] Presenter / clicker tested
- [ ] Audio level checked
- [ ] Water on stage 💧

---

## Talking-point cheat sheet

**The hook:**
> "Millions of customers. Storm coming. Six AI specialists arguing about whether to downsize a SCADA VM. Live."

**The differentiator (vs single-agent demos):**
> "Single agent gives you confident answers. A team of agents that disagree gives you *transparent reasoning*. The disagreement is the proof of work."

**The trust statement:**
> "Every change ships as a PR. Every PR has CODEOWNERS. No agent touches Azure without a human signature on the diff. Agentic ops doesn't mean autonomous ops."

**The scale story:**
> "The utility's SRE team is small. The agents aren't bigger headcount — they're more *expertise* per engineer. One person + six agents has the throughput of a small team."

**The technology layer:**
> "Built on Azure AI Foundry. Models live in our account. Telemetry flows to our Application Insights. Governed by our Azure Policy. Same security posture as everything else they run in Azure."

**The numbers (cite if asked):**
- Cloud Weather Ops: ~$0.06-0.12 per crew query · ~$0.15-0.75/day total
- Microsoft SRE Agent internal: 1,300+ agents · 35,000+ incidents mitigated · 20,000+ engineering hours saved
- Microsoft App Service time-to-mitigate: 40.5 hours → 3 minutes (per the post-GA blog)
