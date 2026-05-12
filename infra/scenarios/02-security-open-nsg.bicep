// ─── Scenario 2: Security Drift ──────────────────────────────────
// An NSG with an inbound rule allowing SSH from 0.0.0.0/0.
// Classic "Do Something Stupid" pattern — equivalent to the chaos
// demo in the DTE Cloud Weather Ops app, but persistent so the SRE
// Agent has a stable finding to discover.

@description('Prefix for scenario resources.')
param prefix string = 'ogedemo'

@description('Location for resources.')
param location string = resourceGroup().location

@description('Tag applied to every scenario resource so the triage agent can correlate.')
param scenarioTag string = 'security-open-ssh'

resource nsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: '${prefix}-security-nsg'
  location: location
  tags: {
    scenario: scenarioTag
    'support-owner': 'demo-team@ogedemos.com'
    'expected-finding': 'open-management-port'
    'simulates': 'mgmt-subnet-misconfig'
  }
  properties: {
    securityRules: [
      {
        // ⚠️ DELIBERATELY INSECURE — demo only.
        name: 'allow-ssh-from-anywhere'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
          description: 'DEMO ONLY — intentionally insecure for SRE Agent showcase'
        }
      }
      {
        name: 'allow-rdp-from-anywhere'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '3389'
          description: 'DEMO ONLY — intentionally insecure for SRE Agent showcase'
        }
      }
    ]
  }
}

output nsgId string = nsg.id
output expectedFinding string = 'NSG allows SSH (22) and RDP (3389) from 0.0.0.0/0 — open management ports.'
