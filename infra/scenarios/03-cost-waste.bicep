// ─── Scenario 3: Cost Waste ──────────────────────────────────────
// An unattached managed disk + an oversized App Service Plan that
// hosts zero apps. Meter Reader's classic findings. SRE Agent +
// Azure Advisor should both surface these.

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

// ── Idle App Service Plan ──
resource idlePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: '${prefix}-cost-idle-plan'
  location: location
  tags: {
    scenario: scenarioTag
    'support-owner': 'demo-team@ogedemos.com'
    'expected-finding': 'idle-app-service-plan'
    'simulates': 'leftover-from-decommissioned-project'
  }
  sku: {
    name: 'P0v3'
    tier: 'Premium0V3'
    capacity: 1
  }
  kind: 'linux'
  properties: { reserved: true }
}

output orphanDiskId string = orphanDisk.id
output idlePlanId string = idlePlan.id
output expectedFinding string = '1 TB Premium SSD unattached for >30 days (~$135/mo) + P0v3 plan hosting 0 apps (~$60/mo).'
