targetScope = 'subscription'

param deploymentNameSuffix string
// param locations object // This is only needed for Recovery Services which has been disabled for now.
param tags object
param virtualNetworkResourceId string

var cloudSuffix = replace(replace(environment().resourceManager, 'https://management.azure.', ''), '/', '')
var privateDnsZoneNames = [
  'privatelink.azure-automation.${privateDnsZoneSuffixes.azureAutomation[?environment().name] ?? cloudSuffix}' // Azure Automation
  // privateDnsZoneNames_Backup // Azure Backup
  'privatelink.blob.${environment().suffixes.storage}' // Azure Blob Storage
  'privatelink.file.${environment().suffixes.storage}' // Azure Files
  'privatelink${replace(environment().suffixes.keyvaultDns, 'vault', 'vaultcore')}' // Azure Key Vault
  'privatelink.agentsvc.azure-automation.${privateDnsZoneSuffixes.azureAutomation[?environment().name] ?? 'opinsights.azure.${cloudSuffix}'}' // Azure Monitor
  'privatelink.monitor.azure.${privateDnsZoneSuffixes.azureMonitor[?environment().name] ?? cloudSuffix}' // Azure Monitor
  'privatelink.ods.opinsights.azure.${privateDnsZoneSuffixes.azureMonitor[?environment().name] ?? cloudSuffix}' // Azure Monitor
  'privatelink.oms.opinsights.azure.${privateDnsZoneSuffixes.azureMonitor[?environment().name] ?? cloudSuffix}' // Azure Monitor
  'privatelink.queue.${environment().suffixes.storage}' // Azure Queues
  'privatelink${environment().suffixes.sqlServerHostname}' // Azure SQL Servers
  'privatelink.table.${environment().suffixes.storage}' // Azure Tables
  'privatelink.wvd.${privateDnsZoneSuffixes.azureVirtualDesktop[?environment().name] ?? cloudSuffix}' // Azure Virtual Desktop
  'privatelink-global.wvd.${privateDnsZoneSuffixes.azureVirtualDesktop[?environment().name] ?? cloudSuffix}' // Azure Virtual Desktop
  'privatelink.${privateDnsZoneSuffixes.azureWebSites[?environment().name] ?? 'appservice.${cloudSuffix}'}' // Azure Web Apps
]

// The following variable is only needed for Recovery Services which has been disabled for now.
//var privateDnsZoneNames_Backup = [for location in items(locations): 'privatelink.${location.value.recoveryServicesGeo}.backup.windowsazure.${privateDnsZoneSuffixes.azureBackup[environment().name] ?? cloudSuffix}']

var privateDnsZoneSuffixes = {
  azureAutomation: {
    AzureCloud: 'net'
    AzureUSGovernment: 'us'
  }
  azureBackup: {
    AzureCloud: 'com'
    AzureUSGovernment: 'us'
  }
  azureMonitor: {
    AzureCloud: 'com'
    AzureUSGovernment: 'us'
  }
  azureVirtualDesktop: {
    AzureCloud: 'microsoft.com'
    AzureUSGovernment: 'azure.us'
  }
  azureWebSites: {
    AzureCloud: 'azurewebsites.net'
    AzureUSGovernment: 'azurewebsites.us'
  }
}

module privateDnsZones 'private-dns-zone.bicep' = [for (name, i) in privateDnsZoneNames: {
  name: 'deploy-pvt-dns-zone-${i}-${deploymentNameSuffix}'
  scope: resourceGroup(split(virtualNetworkResourceId, '/')[2], split(virtualNetworkResourceId, '/')[4])
  params: {
    name: name
    tags: tags[?'Microsoft.Network/privateDnsZones'] ?? {}
  }
}]

module virtualNetworkLinks 'virtual-network-link.bicep' = {
  name: 'deploy-vnet-links--${deploymentNameSuffix}'
  scope: resourceGroup(split(virtualNetworkResourceId, '/')[2], split(virtualNetworkResourceId, '/')[4])
  params: {
    privateDnsZoneNames: privateDnsZoneNames
    virtualNetworkName: split(virtualNetworkResourceId, '/')[8]
    virtualNetworkResourceGroupName: split(virtualNetworkResourceId, '/')[4]
    virtualNetworkSubscriptionId: split(virtualNetworkResourceId, '/')[2]
  }
  dependsOn: [
    privateDnsZones
  ]
}

output resourceIds array = [for (name, i) in privateDnsZoneNames: privateDnsZones[i].outputs.resourceId]
