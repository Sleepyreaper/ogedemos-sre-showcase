@description('CIDR range for management workstation subnets')
param managementIpCidr string = '203.0.113.0/24'  // TODO: replace with your approved range

resource nsg 'Microsoft.Network/networkSecurityGroups@2021-08-01' existing = {
  name: 'ogedemo-security-nsg'
}

// Update SSH rule to restrict source
resource sshRule 'Microsoft.Network/networkSecurityGroups/securityRules@2021-08-01' = {
  parent: nsg
  name: 'Allow-SSH'
  properties: {
    priority: 1001
    direction: 'Inbound'
    access: 'Allow'
    protocol: 'Tcp'
    sourcePortRange: '*'
    destinationPortRange: '22'
    sourceAddressPrefix: managementIpCidr
    destinationAddressPrefix: '*'
    description: 'Restrict SSH access to management IP range'
  }
}

// Update RDP rule to restrict source
resource rdpRule 'Microsoft.Network/networkSecurityGroups/securityRules@2021-08-01' = {
  parent: nsg
  name: 'Allow-RDP'
  properties: {
    priority: 1002
    direction: 'Inbound'
    access: 'Allow'
    protocol: 'Tcp'
    sourcePortRange: '*'
    destinationPortRange: '3389'
    sourceAddressPrefix: managementIpCidr
    destinationAddressPrefix: '*'
    description: 'Restrict RDP access to management IP range'
  }
}