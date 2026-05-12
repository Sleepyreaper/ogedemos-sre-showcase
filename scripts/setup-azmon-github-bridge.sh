#!/usr/bin/env bash
# Wires Azure Monitor → GitHub Issues bridge as a fallback path for the
# closed-loop demo, in case the SRE Agent's gitHubConfiguration isn't set
# (or while you wait for it to be configured in the portal).
#
# What this creates in OGEDemos_RG:
#   1. A Logic App that posts to GitHub Issues when triggered
#   2. An Action Group that calls the Logic App webhook
#   3. An Activity Log Alert that catches AzMonitor incidents from the SRE Agent
#
# Prerequisites:
#   - GitHub PAT with `repo` scope stored as: gh secret list (or pass --pat)
#   - jq installed
set -euo pipefail

RG="${1:-OGEDemos_RG}"
LOC="${2:-eastus2}"
REPO="${3:-Sleepyreaper/ogedemos-sre-showcase}"

LOGIC_APP="ogeagenticops-github-bridge"
ACTION_GROUP="ogeagenticops-ag"

# 1. Pull a GitHub token for the Logic App to authenticate with.
echo "→ Reading GitHub token from gh CLI..."
GH_TOKEN=$(gh auth token 2>/dev/null) || {
  echo "✗ Could not get token from gh CLI. Run 'gh auth login' first."
  exit 1
}

# 2. Build a minimal Logic App definition that:
#    - Accepts an HTTP POST trigger (called by the Action Group)
#    - Extracts incident details from the AzMonitor payload
#    - POSTs to https://api.github.com/repos/$REPO/issues with sre-finding label
cat > /tmp/github-bridge-definition.json <<'EOF'
{
  "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "githubToken": { "type": "SecureString" },
    "githubRepo":  { "type": "String" }
  },
  "triggers": {
    "manual": {
      "type": "Request",
      "kind": "Http",
      "inputs": { "schema": {} }
    }
  },
  "actions": {
    "Compose_Issue_Body": {
      "type": "Compose",
      "inputs": {
        "title": "@{coalesce(triggerBody()?['data']?['essentials']?['alertRule'], 'SRE Agent finding')}",
        "body": "## Azure SRE Agent Finding\n\n**Severity:** @{coalesce(triggerBody()?['data']?['essentials']?['severity'], 'Sev3')}\n**Detected at:** @{coalesce(triggerBody()?['data']?['essentials']?['firedDateTime'], utcNow())}\n**Affected resource:** @{coalesce(join(triggerBody()?['data']?['essentials']?['alertTargetIDs'], ', '), 'unknown')}\n\n### Description\n@{coalesce(triggerBody()?['data']?['essentials']?['description'], 'No description provided')}\n\n### Recommended action from SRE Agent\n@{coalesce(triggerBody()?['data']?['alertContext'], 'See linked Azure Monitor alert for details.')}\n\nARG-QUERY: Resources | where id =~ '@{coalesce(first(triggerBody()?['data']?['essentials']?['alertTargetIDs']), '')}'",
        "labels": ["sre-finding", "needs-triage", "from-azmonitor"]
      }
    },
    "Post_Issue_to_GitHub": {
      "type": "Http",
      "runAfter": { "Compose_Issue_Body": ["Succeeded"] },
      "inputs": {
        "method": "POST",
        "uri": "@{concat('https://api.github.com/repos/', parameters('githubRepo'), '/issues')}",
        "headers": {
          "Authorization": "@{concat('token ', parameters('githubToken'))}",
          "Accept": "application/vnd.github+json",
          "User-Agent": "ogeagenticops-bridge"
        },
        "body": "@outputs('Compose_Issue_Body')"
      }
    }
  },
  "outputs": {}
}
EOF

echo "→ Deploying Logic App $LOGIC_APP..."
az logic workflow create \
  --resource-group "$RG" \
  --name "$LOGIC_APP" \
  --location "$LOC" \
  --definition @/tmp/github-bridge-definition.json \
  --parameters "{\"githubToken\":{\"value\":\"$GH_TOKEN\"},\"githubRepo\":{\"value\":\"$REPO\"}}" \
  >/dev/null

CALLBACK_URL=$(az logic workflow show -g "$RG" -n "$LOGIC_APP" --query "accessEndpoint" -o tsv)
TRIGGER_URL=$(az rest --method POST --url "https://management.azure.com$(az logic workflow show -g $RG -n $LOGIC_APP --query id -o tsv)/triggers/manual/listCallbackUrl?api-version=2019-05-01" --query value -o tsv)

echo "→ Creating Action Group $ACTION_GROUP..."
az monitor action-group create \
  --resource-group "$RG" \
  --name "$ACTION_GROUP" \
  --short-name "ogeagops" \
  --action webhook github-bridge "$TRIGGER_URL" \
  >/dev/null

echo "→ Wiring an Activity Log alert that catches SRE-agent-originated incidents..."
az monitor activity-log alert create \
  --resource-group "$RG" \
  --name "ogeagenticops-incidents-to-github" \
  --scope "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RG" \
  --condition category=Recommendation \
  --action-group "$ACTION_GROUP" \
  >/dev/null

cat <<EOF

✓ Bridge deployed.
  Logic App:    /subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RG/providers/Microsoft.Logic/workflows/$LOGIC_APP
  Action Group: $ACTION_GROUP
  Trigger URL:  $TRIGGER_URL

To test the bridge end-to-end without waiting for a real SRE finding:
  curl -X POST "$TRIGGER_URL" -H "Content-Type: application/json" -d '{
    "data": {
      "essentials": {
        "alertRule": "Test bridge finding",
        "severity": "Sev3",
        "description": "Synthetic test from setup-azmon-github-bridge.sh",
        "alertTargetIDs": ["/subscriptions/.../OGEDemos_RG/providers/Microsoft.Compute/disks/ogedemo-cost-orphan-disk"]
      }
    }
  }'

Then check https://github.com/$REPO/issues for the new issue.

Security note: this Logic App stores the GitHub PAT in its parameters
(encrypted at rest in ARM but visible to anyone with reader+ on the workflow).
For production, swap to a Managed Identity + GitHub App authentication.
EOF
