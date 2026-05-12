```diff
--- infra/scenarios/02-security-open-nsg.bicep
+++ infra/scenarios/02-security-open-nsg.bicep
@@ resource nsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
       securityRules: [
         {
           name: 'allow-ssh-from-anywhere'
           properties: {
             priority: 100
             direction: 'Inbound'
             access: 'Allow'
             protocol: 'Tcp'
-            sourceAddressPrefix: '*'
+            sourceAddressPrefix: '10.0.0.0/8' // TODO: replace with your corporate VPN CIDR
             sourcePortRange: '*'
             destinationAddressPrefix: '*'
             destinationPortRange: '22'
@@ resource nsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
         {
           name: 'allow-rdp-from-anywhere'
           properties: {
             priority: 110
             direction: 'Inbound'
             access: 'Allow'
             protocol: 'Tcp'
-            sourceAddressPrefix: '*'
+            sourceAddressPrefix: '10.0.0.0/8' // TODO: replace with your corporate VPN CIDR
             sourcePortRange: '*'
             destinationAddressPrefix: '*'
             destinationPortRange: '3389'
```