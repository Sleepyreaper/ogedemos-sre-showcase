// ─── Scenario 1: Storm / Reliability ─────────────────────────────
// A VM Scale Set with NO autoscale rules — when "load" spikes,
// it can't grow, and DTE customer-portal traffic during a storm
// would degrade. SRE Agent should flag the absent autoscale policy.

@description('Prefix for scenario resources.')
param prefix string = 'ogedemo'

@description('Location for resources.')
param location string = resourceGroup().location

@description('Tag applied to every scenario resource so the triage agent can correlate.')
param scenarioTag string = 'storm-no-autoscale'

var vnetName = '${prefix}-storm-vnet'
var subnetName = 'snet-storm'
var vmssName = '${prefix}-storm-vmss'

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: vnetName
  location: location
  tags: {
    scenario: scenarioTag
    'support-owner': 'demo-team@ogedemos.com'
    'expected-finding': 'autoscale-missing'
  }
  properties: {
    addressSpace: { addressPrefixes: ['10.50.0.0/24'] }
    subnets: [
      {
        name: subnetName
        properties: { addressPrefix: '10.50.0.0/27' }
      }
    ]
  }
}

resource vmss 'Microsoft.Compute/virtualMachineScaleSets@2023-09-01' = {
  name: vmssName
  location: location
  tags: {
    scenario: scenarioTag
    'support-owner': 'demo-team@ogedemos.com'
    'expected-finding': 'autoscale-missing'
    'simulates': 'dte-customer-portal-tier'
  }
  sku: {
    name: 'Standard_B1s'
    capacity: 1
    tier: 'Standard'
  }
  properties: {
    upgradePolicy: { mode: 'Manual' }
    virtualMachineProfile: {
      osProfile: {
        computerNamePrefix: 'stormvm'
        adminUsername: 'demoadmin'
        adminPassword: '${uniqueString(resourceGroup().id, deployment().name)}P!'
        linuxConfiguration: { disablePasswordAuthentication: false }
      }
      storageProfile: {
        imageReference: {
          publisher: 'Canonical'
          offer: '0001-com-ubuntu-server-jammy'
          sku: '22_04-lts-gen2'
          version: 'latest'
        }
        osDisk: {
          createOption: 'FromImage'
          managedDisk: { storageAccountType: 'Standard_LRS' }
        }
      }
      networkProfile: {
        networkInterfaceConfigurations: [
          {
            name: 'nic-config'
            properties: {
              primary: true
              ipConfigurations: [
                {
                  name: 'ipconfig'
                  properties: {
                    subnet: { id: '${vnet.id}/subnets/${subnetName}' }
                  }
                }
              ]
            }
          }
        ]
      }
    }
  }
}

// Intentionally: NO autoscale settings deployed. SRE Agent + Arc Flash
// should both flag this as a reliability gap for a customer-portal-tier
// resource.

output vmssId string = vmss.id
output expectedFinding string = 'No autoscale settings on a customer-facing VMSS — storm load can\'t scale out.'
