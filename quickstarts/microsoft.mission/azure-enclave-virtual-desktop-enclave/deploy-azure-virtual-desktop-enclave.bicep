targetScope = 'subscription'

#disable-next-line no-unused-params
param isMsisrTenant bool = false
#disable-next-line no-unused-params
param isPlxTenant bool = false

@allowed([
  'ActiveDirectoryDomainServices'
  'MicrosoftEntraDomainServices'
  'MicrosoftEntraId'
  'MicrosoftEntraIdIntuneEnrollment'
])
@description('The service providing domain services for Azure Virtual Desktop.  This is needed to properly configure the private DNS zones.')
param activeDirectorySolution string = 'MicrosoftEntraId'

@allowed([
  ''
  '17'
  '18'
  '19'
  '20'
  '21'
  '22'
  '23'
  '24'
  '25'
  '26'
  '27'
  '28'
])
@description('The network prefix size for the Azure NetApp Files subnet.')
param anfSubnetPrefixSize string = ''

@allowed([
  '17'
  '18'
  '19'
  '20'
  '21'
  '22'
  '23'
  '24'
  '25'
  '26'
  '27'
  '28'
])
@description('The network prefix size for the AVD management subnet.')
param avdManagementSubnetPrefixSize string = '24'

@allowed([
  '17'
  '18'
  '19'
  '20'
  '21'
  '22'
  '23'
  '24'
  '25'
  '26'
  '27'
  '28'
])
@description('The network prefix size for the AVD session hosts subnet.')
param avdSessionHostsSubnetPrefixSize string = '24'

@description('The resource ID of the existing AE Community.')
param communityEndpointResourceId string

@description('The suffix to use for naming deployments uniquely. It defaults to the Bicep resolution of the "utcNow()" function.')
param deploymentNameSuffix string = utcNow()

@allowed([
  'Both'
  'CommunityOnly'
  'EnclaveOnly'
])
@description('The destination for diagnostic logs and metrics from the enclave virtual network.')
param diagnosticDestination string

@description('Determine whether to enable Azure Bastion in the enclave virtual network.')
param enableBastion bool

@description('Determine whether to enable Zero Trust compliance configurations on the deployed resources.')
param enableZeroTrustCompliance bool = false

@description('The address space / prefix for the enclave virtual network. This value is only necessary if the "enclaveNetworkSize" parameter is set to "custom".')
param enclaveAddressSpace string = ''

@allowed([
  'small' // Small (/23)
  'medium' // Medium (/20)
  'large' // Large (/16)
  'custom' // Custom
])
@description('The size of the network to create for the virtual enclave.  This can be "small", "medium", "large", or "custom".  If "custom" is selected, the "enclaveThirdOctet" parameter must be provided to define the address space.')
param enclaveNetworkSize string = 'small'

@allowed([
  'dev' // Development
  'prod' // Production
  'test' // Test
])
@description('The abbreviation for the target environment.')
param environmentAbbreviation string = 'dev'

@allowed([
  ''
  '17'
  '18'
  '19'
  '20'
  '21'
  '22'
  '23'
  '24'
  '25'
  '26'
  '27'
  '28'
])
@description('The network prefix size for the Azure NetApp Files subnet, if using Azure NetApp Files for FSLogix storage.')
param functionAppSubnetPrefixSize string = ''

@maxLength(3)
@description('The unique identifier to distinguish the unique business unit or project in your tenant.')
param identifier string

@description('The location for the resources deployed in this template.')
param location string = deployment().location

@description('The principals allowed to modify the AE managed resources using maintenance mode.')
param maintenanceModePrincipals array

@description('The metadata to apply to resources deployed in this template.')
param tags object = {}

resource community 'Microsoft.Mission/communities@2026-03-01-preview' existing = {
  scope: resourceGroup(split(communityEndpointResourceId, '/')[2], split(communityEndpointResourceId, '/')[4])
  name: split(communityEndpointResourceId, '/')[8]
}

// Gets the naming convention for the AVD enclave
module naming './modules/naming.bicep' = {
  name: 'naming-convention-avd-enclave-${deploymentNameSuffix}'
  params: {
    delimiter: '-'
    environmentAbbreviation: environmentAbbreviation
    identifier: identifier
    location: location
    workloadShortName: 'avd'
  }
}

// Deploys the virtual enclave for AVD
module virtualEnclave './modules/virtual-enclave.bicep' = {
  name: 'virtual-enclave-avd-${deploymentNameSuffix}'
  scope: resourceGroup(split(communityEndpointResourceId, '/')[2], split(communityEndpointResourceId, '/')[4])
  params: {
    communityResourceId: community.id
    diagnosticDestination: diagnosticDestination
    enableBastion: enableBastion
    enclaveAddressSpace: enclaveAddressSpace
    location: location
    maintenanceModeSetting: 'Advanced'
    maintenanceModeJustification: 'Networking'
    maintenanceModePrincipals: maintenanceModePrincipals
    name: naming.outputs.convention.virtualEnclave
    networkSize: enclaveNetworkSize
    subnetConfigurations: union(
      [
        {
          subnetName: 'AzureVirtualDesktopSessionHostsSubnet'
          networkPrefixSize: int(avdSessionHostsSubnetPrefixSize)
        }
        {
          subnetName: 'AzureVirtualDesktopManagementSubnet'
          networkPrefixSize: int(avdManagementSubnetPrefixSize)
        }
      ],
      empty(functionAppSubnetPrefixSize)
        ? []
        : [
            {
              subnetName: 'FunctionAppSubnet'
              networkPrefixSize: int(functionAppSubnetPrefixSize)
              subnetDelegation: 'Microsoft.Web/serverFarms'
            }
          ],
      empty(anfSubnetPrefixSize)
        ? []
        : [
            {
              subnetName: 'AzureNetAppFilesSubnet'
              networkPrefixSize: int(anfSubnetPrefixSize)
              subnetDelegation: 'Microsoft.Netapp/volumes'
            }
          ]
    )
    tags: tags
  }
}

// Deploys the enclave connection from the AVD enclave to the community endpoint
module enclaveConnection './modules/enclave-connection.bicep' = {
  name: 'enclave-connection-avd-${deploymentNameSuffix}'
  scope: resourceGroup(split(communityEndpointResourceId, '/')[2], split(communityEndpointResourceId, '/')[4])
  params: {
    communityEndpointResourceId: communityEndpointResourceId
    communityResourceId: community.id
    location: location
    sourceCidr: filter(
      virtualEnclave.outputs.properties.enclaveVirtualNetwork.subnetConfigurations,
      (subnet) => subnet.subnetName == 'AzureVirtualDesktopSessionHostsSubnet'
    )[0].addressPrefix
    tags: tags
    virtualEnclaveResourceId: virtualEnclave.outputs.resourceId
  }
}

module privateDnsZones './modules/private-dns-zones.bicep' = if (enableZeroTrustCompliance && startsWith(activeDirectorySolution, 'MicrosoftEntraId')) {
  name: 'private-dns-zones-${deploymentNameSuffix}'
  params: {
    tags: tags
    deploymentNameSuffix: deploymentNameSuffix
    virtualNetworkResourceId: filter(virtualEnclave.outputs.properties.resourceCollection, (id) => contains(id, 'microsoft.network/virtualnetworks'))[0]
  }
}
