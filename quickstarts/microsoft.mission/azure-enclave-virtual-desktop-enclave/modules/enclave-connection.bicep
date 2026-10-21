@description('The resource ID of the community endpoint to which the enclave will connect.')
param communityEndpointResourceId string

@description('The resource ID of the community.')
param communityResourceId string

@description('The location for the enclave connection.')
param location string

@description('The source CIDR block from which traffic will originate for the enclave connection.')
param sourceCidr string

@description('The metadata to be applied to the enclave connection resource.')
param tags object = {}

@description('The resource ID of the virtual enclave.')
param virtualEnclaveResourceId string

resource enclaveConnection 'Microsoft.Mission/enclaveConnections@2026-03-01-preview' = {
  name: 'ec-${split(virtualEnclaveResourceId, '/')[8]}-to-${split(communityEndpointResourceId, '/')[8]}'
  location: location
  tags: tags[?'Microsoft.Mission/enclaveConnections'] ?? {}
  properties: {
    communityResourceId: communityResourceId
    destinationEndpointId: communityEndpointResourceId
    sourceCidr: sourceCidr
    sourceResourceId: virtualEnclaveResourceId
  }
}
