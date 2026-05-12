// ─── Scenario 4: Reliability — Self-Signed Cert + Failed Deployment ──
// A Key Vault containing a self-signed certificate that's already
// "near-expiry" by setting a short validity, plus a failed deployment
// stub that the Activity Log captures.

@description('Prefix for scenario resources.')
param prefix string = 'ogedemo'

@description('Location for resources.')
param location string = resourceGroup().location

@description('Tag applied to every scenario resource so the triage agent can correlate.')
param scenarioTag string = 'reliability-cert-expiry'

@description('Object ID of the principal that should be Key Vault Administrator on this KV (e.g., your user objectId).')
param adminPrincipalId string = ''

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: '${prefix}-reli-kv-${uniqueString(resourceGroup().id)}'
  location: location
  tags: {
    scenario: scenarioTag
    'support-owner': 'demo-team@ogedemos.com'
    'expected-finding': 'cert-near-expiry'
    'simulates': 'forgotten-cert-rotation'
  }
  properties: {
    tenantId: subscription().tenantId
    sku: { family: 'A', name: 'standard' }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enablePurgeProtection: null
  }
}

resource kvAdminRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(adminPrincipalId)) {
  scope: kv
  name: guid(kv.id, adminPrincipalId, 'kv-admin')
  properties: {
    // Key Vault Administrator
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '00482a5a-887f-4fb3-b363-3b7fe8e74483')
    principalId: adminPrincipalId
    principalType: 'User'
  }
}

// Note: the actual near-expiry self-signed cert is created out-of-band
// via scripts/seed-expiring-cert.sh — Bicep can't natively create a
// pre-aged certificate. The cert is named "near-expiry-cert" and is
// configured with 30-day validity so it surfaces as near-expiry quickly.

output keyVaultName string = kv.name
output expectedFinding string = 'Certificate "near-expiry-cert" in Key Vault expires in <30 days, no rotation policy.'
