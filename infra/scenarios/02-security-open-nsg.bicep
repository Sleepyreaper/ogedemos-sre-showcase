@@ -4,6 +4,9 @@
 param prefix string = 'ogedemo'
 @description('Location for resources.')
 param location string = resourceGroup().location
+@description('Approved management CIDR range for SSH/RDP access.')
+param managementCidr string = '10.0.0.0/24'
+
 resource nsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
   name: '${prefix}-security-nsg'
@@ -33,7 +36,7 @@
         direction: 'Inbound'
         access: 'Allow'
         protocol: 'Tcp'
-        sourceAddressPrefix: '*'
+        sourceAddressPrefix: managementCidr
         sourcePortRange: '*'
         destinationAddressPrefix: '*'
         destinationPortRange: '22'
@@ -46,7 +49,7 @@
         direction: 'Inbound'
         access: 'Allow'
         protocol: 'Tcp'
-        sourceAddressPrefix: '*'
+        sourceAddressPrefix: managementCidr
         sourcePortRange: '*'
         destinationAddressPrefix: '*'
         destinationPortRange: '3389'