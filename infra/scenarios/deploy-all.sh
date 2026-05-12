#!/usr/bin/env bash
# Deploys all four broken-on-purpose scenarios to OGEDemos_RG.
#
# Usage: bash deploy-all.sh [resource-group] [location]
set -euo pipefail

RG="${1:-OGEDemos_RG}"
LOC="${2:-eastus2}"
PREFIX="${3:-ogedemo}"

if ! az group show -n "$RG" >/dev/null 2>&1; then
  echo "Creating resource group $RG in $LOC..."
  az group create -n "$RG" -l "$LOC" >/dev/null
fi

echo "→ [1/4] Storm scenario (VMSS with no autoscale)..."
az deployment group create -g "$RG" \
  --name "scenario-01-storm-$(date +%s)" \
  --template-file "$(dirname "$0")/01-storm-no-autoscale.bicep" \
  --parameters prefix="$PREFIX" \
  --query "properties.provisioningState" -o tsv

echo "→ [2/4] Security scenario (NSG open to 0.0.0.0/0)..."
az deployment group create -g "$RG" \
  --name "scenario-02-security-$(date +%s)" \
  --template-file "$(dirname "$0")/02-security-open-nsg.bicep" \
  --parameters prefix="$PREFIX" \
  --query "properties.provisioningState" -o tsv

echo "→ [3/4] Cost scenario (orphan disk + idle plan)..."
az deployment group create -g "$RG" \
  --name "scenario-03-cost-$(date +%s)" \
  --template-file "$(dirname "$0")/03-cost-waste.bicep" \
  --parameters prefix="$PREFIX" \
  --query "properties.provisioningState" -o tsv

echo "→ [4/4] Reliability scenario (Key Vault for near-expiry cert)..."
ADMIN_OID="$(az ad signed-in-user show --query id -o tsv 2>/dev/null || echo "")"
az deployment group create -g "$RG" \
  --name "scenario-04-reliability-$(date +%s)" \
  --template-file "$(dirname "$0")/04-reliability-cert.bicep" \
  --parameters prefix="$PREFIX" adminPrincipalId="$ADMIN_OID" \
  --query "properties.provisioningState" -o tsv

echo ""
echo "✓ All four scenarios deployed."
echo "  Next: bash scripts/seed-expiring-cert.sh to inject the near-expiry cert into Key Vault."
