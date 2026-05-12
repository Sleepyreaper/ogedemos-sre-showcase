#!/usr/bin/env bash
# =============================================================================
# setup-github.sh — Wire a GitHub PAT into ogeagenticops as a data connector
#
# This is the PAT-based alternative to configuring the OAuth GitHub connector
# in the SRE Agent portal. Use this script if you can't or don't want to do
# the browser-based OAuth flow.
#
# Requirements:
#   GITHUB_PAT env var. Either:
#     - Classic PAT with `repo` scope, OR
#     - Fine-grained PAT scoped to Sleepyreaper/ogedemos-sre-showcase with
#       Contents: Read, Issues: Read+Write, Metadata: Read
#
# Usage:
#   export GITHUB_PAT=ghp_xxxxxxxxxxxxxxxxxxxx
#   bash scripts/setup-github.sh
# =============================================================================
set -uo pipefail

RG="${RG:-OGEDemos_RG}"
AGENT_NAME="${AGENT_NAME:-ogeagenticops}"
API_VERSION="2025-05-01-preview"
GITHUB_REPO="${GITHUB_REPO:-Sleepyreaper/ogedemos-sre-showcase}"

if [ -z "${GITHUB_PAT:-}" ]; then
  cat <<EOF
✗ GITHUB_PAT environment variable is not set.

Generate a fine-grained PAT at https://github.com/settings/personal-access-tokens/new
with the following scopes for $GITHUB_REPO:
  • Contents:    Read
  • Issues:      Read and Write
  • Metadata:    Read

Or a classic PAT with 'repo' scope: https://github.com/settings/tokens/new

Then:
  export GITHUB_PAT=ghp_xxxxxxxxxxxxxxxxxxxx
  bash scripts/setup-github.sh
EOF
  exit 1
fi

AGENT_ENDPOINT=$(az resource show \
  --resource-type "Microsoft.App/agents" \
  --name "$AGENT_NAME" -g "$RG" \
  --api-version "$API_VERSION" \
  --query "properties.agentEndpoint" -o tsv 2>&1)

if [ -z "$AGENT_ENDPOINT" ] || [[ "$AGENT_ENDPOINT" == *"ERROR"* ]]; then
  echo "✗ Could not get agent endpoint. Verify $AGENT_NAME exists in $RG."
  exit 1
fi

echo "→ Agent endpoint: $AGENT_ENDPOINT"
echo "→ Target repo: $GITHUB_REPO"
echo

DATA_TOKEN=$(az account get-access-token --resource https://azuresre.dev --query accessToken -o tsv)

# Apply the GitHub data connector with the PAT.
# The data plane API path for connectors is /api/v1/Connectors.
# Schema: { name, type, dataSource, credentials: { patToken } }
echo "→ Registering GitHub PAT connector via data plane..."
RESP=$(curl -sS -X PUT "${AGENT_ENDPOINT}/api/v1/Connectors/github" \
  -H "Authorization: Bearer ${DATA_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"github\",
    \"type\": \"GitHub\",
    \"dataSource\": \"github-pat\",
    \"credentials\": {
      \"patToken\": \"${GITHUB_PAT}\"
    },
    \"defaultRepository\": \"${GITHUB_REPO}\"
  }")

if echo "$RESP" | grep -qi "error\|fail"; then
  echo "✗ Data-plane PUT failed. Response:"
  echo "$RESP" | head -10
  echo
  echo "If this endpoint isn't supported, configure GitHub via the portal:"
  echo "  1. Open https://sre.azure.com"
  echo "  2. Select agent: $AGENT_NAME"
  echo "  3. Builder → Connectors → Add GitHub (OAuth flow)"
  exit 1
fi

echo "✓ GitHub connector configured."
echo
echo "─── Next steps ──────────────────────────────────────────────"
echo "1. Re-run apply-sre-config.sh so subagents pick up the connector:"
echo "   bash scripts/apply-sre-config.sh --agents-only"
echo
echo "2. Test in the SRE Agent chat UI:"
echo "   /agent issue-triager"
echo "   Ask: 'Triage any open issues on $GITHUB_REPO with [Customer Issue] in the title'"
