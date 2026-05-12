#!/usr/bin/env bash
# Provisions Azure SRE Agent (preview) against OGEDemos_RG.
#
# The Azure SRE Agent is a Microsoft preview product under the
# Microsoft.App provider. Feature flags must be registered first.
# This script:
#   1. Registers SREAgentPreview + regional preview features
#   2. Waits for registration to propagate
#   3. Creates the SRE Agent resource scoped to OGEDemos_RG
#   4. Configures the agent to file findings as GitHub Issues in this repo
#
# Re-run safe. If features are already registered it skips ahead.
set -euo pipefail

RG="${1:-OGEDemos_RG}"
LOC="${2:-eastus2}"
REPO="${3:-Sleepyreaper/ogedemos-sre-showcase}"

echo "→ Checking SRE Agent preview registration..."
STATE_GLOBAL=$(az feature show --namespace Microsoft.App --name SREAgentPreview --query "properties.state" -o tsv 2>/dev/null || echo "NotRegistered")
STATE_REGIONAL=$(az feature show --namespace Microsoft.App --name "SREAgentPreview.${LOC}" --query "properties.state" -o tsv 2>/dev/null || echo "NotRegistered")
echo "   Global preview: $STATE_GLOBAL"
echo "   $LOC preview:    $STATE_REGIONAL"

if [ "$STATE_GLOBAL" != "Registered" ] || [ "$STATE_REGIONAL" != "Registered" ]; then
  echo "→ Registering preview features (this can take 15+ minutes to propagate)..."
  az feature register --namespace Microsoft.App --name SREAgentPreview >/dev/null
  az feature register --namespace Microsoft.App --name "SREAgentPreview.${LOC}" >/dev/null
  echo "   Waiting for Registered state..."
  for i in {1..60}; do
    s1=$(az feature show --namespace Microsoft.App --name SREAgentPreview --query "properties.state" -o tsv)
    s2=$(az feature show --namespace Microsoft.App --name "SREAgentPreview.${LOC}" --query "properties.state" -o tsv)
    if [ "$s1" = "Registered" ] && [ "$s2" = "Registered" ]; then
      echo "   ✓ Both features Registered."
      break
    fi
    echo "   ($i/60) global=$s1 regional=$s2 — waiting 30s..."
    sleep 30
  done
fi

echo "→ Re-registering Microsoft.App provider to propagate feature flags..."
az provider register --namespace Microsoft.App --wait

echo "→ Creating SRE Agent resource..."
# NOTE: The exact resource type + API version may shift during preview.
# As of this writing the resource type is Microsoft.App/sreAgents.
# If the schema has changed, see https://learn.microsoft.com/azure/sre-agent/
AGENT_NAME="ogedemos-sre-agent"

cat > /tmp/sre-agent.json <<EOF
{
  "location": "$LOC",
  "properties": {
    "scope": "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RG",
    "findingDestinations": {
      "github": {
        "repository": "$REPO",
        "labels": ["sre-finding", "needs-triage"]
      }
    }
  }
}
EOF

if az resource show --resource-type "Microsoft.App/sreAgents" --name "$AGENT_NAME" -g "$RG" >/dev/null 2>&1; then
  echo "   SRE Agent $AGENT_NAME already exists. Updating..."
  az resource update --resource-type "Microsoft.App/sreAgents" \
    --name "$AGENT_NAME" -g "$RG" \
    --properties "$(cat /tmp/sre-agent.json | jq '.properties')" || true
else
  az resource create --resource-type "Microsoft.App/sreAgents" \
    --api-version "2025-02-02-preview" \
    --name "$AGENT_NAME" -g "$RG" \
    --properties "$(cat /tmp/sre-agent.json | jq '.properties')" \
    --location "$LOC" || {
      echo ""
      echo "⚠️  Could not auto-create the SRE Agent resource."
      echo "    The preview API may have changed shape, or the feature may still be propagating."
      echo "    Provision via the Azure portal instead:"
      echo "      https://portal.azure.com/#blade/HubsExtension/BrowseResource/resourceType/Microsoft.App%2FsreAgents"
      echo "    Configure findings to file as GitHub Issues to: $REPO"
      echo "    Labels: sre-finding, needs-triage"
      exit 1
    }
fi

echo ""
echo "✓ Azure SRE Agent provisioned at /subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RG/providers/Microsoft.App/sreAgents/$AGENT_NAME"
echo "  Findings will be filed as Issues with label 'sre-finding' on $REPO."
