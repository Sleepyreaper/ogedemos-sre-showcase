// ─── Scenario 3: Cost Waste ──────────────────────────────────────
// An unattached managed disk + an unattached public IP. Meter Reader's
// classic findings. SRE Agent + Azure Advisor should both surface these.

@description('Prefix for scenario resources.')
param prefix string = 'ogedemo'

@description('Location for resources.')
param location string = resourceGroup().location

@description('Tag applied to every scenario resource so the triage agent can correlate.')
param scenarioTag string = 'cost-orphaned-resources'

// ── Orphaned managed disk (1 TB Premium SSD, attached to nothing) ──
resource orphanDisk 'Microsoft.Compute/disks@2023-10-02' = {
  name: '${prefix}-cost-orphan-disk'
  location: location
  tags: {
    scenario: scenarioTag
    'support-owner': 'demo-team@ogedemos.com'
    'expected-finding': 'orphaned-disk'
    'simulates': 'forgotten-test-vm-cleanup'
  }
  sku: { name: 'Premium_LRS' }
  properties: {
    creationData: { createOption: 'Empty' }
    diskSizeGB: 1024
  }
}

// ── Orphaned public IP (Standard SKU static, no attachment) ──
resource orphanIp 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: '${prefix}-cost-orphan-pip'
  location: location
  tags: {
    scenario: scenarioTag
    'support-owner': 'demo-team@ogedemos.com'
    'expected-finding': 'unassociated-public-ip'
    'simulates': 'leftover-after-decommission'
  }
  sku: { name: 'Standard' }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
    idleTimeoutInMinutes: 4
  }
}

output orphanDiskId string = orphanDisk.id
output orphanIpId string = orphanIp.id
output expectedFinding string = '1 TB Premium SSD unattached (~$135/mo) + Standard static public IP with no association (~$3.65/mo).'
