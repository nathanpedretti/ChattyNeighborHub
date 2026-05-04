targetScope = 'resourceGroup'

@description('Azure region for the Event Hubs namespace and related resources.')
param location string = resourceGroup().location

@description('Globally unique Event Hubs namespace name (6-50 chars).')
@minLength(6)
@maxLength(50)
param namespaceName string

@description('Event Hubs SKU. Standard is the lowest-cost SKU that supports Private Endpoints.')
@allowed([
  'Standard'
  'Premium'
])
param skuName string = 'Standard'

@description('Throughput units for Standard SKU (1-20).')
@minValue(1)
@maxValue(20)
param standardThroughputUnits int = 1

@description('Retention in days for each event hub.')
@minValue(1)
@maxValue(7)
param messageRetentionInDays int = 1

@description('Partition count for each event hub.')
@minValue(1)
@maxValue(32)
param partitionCount int = 2

@description('When true, disables public network access so only Private Endpoint access is possible.')
param disablePublicNetworkAccess bool = true

@description('Set true to deploy a private endpoint in this subscription/resource group.')
param deployPrivateEndpoint bool = true

@description('Subnet resource ID where the private endpoint NIC will be created. Required when deployPrivateEndpoint=true.')
param privateEndpointSubnetResourceId string = ''

@description('Name of the private endpoint resource.')
param privateEndpointName string = '${namespaceName}-pe'

@description('Set true to create a private DNS zone in this resource group.')
param createPrivateDnsZone bool = true

@description('Resource ID of an existing private DNS zone for Event Hubs endpoint resolution. Used when createPrivateDnsZone=false.')
param existingPrivateDnsZoneResourceId string = ''

@description('Resource ID of the VNet to link with the private DNS zone. Required when createPrivateDnsZone=true.')
param privateDnsVnetResourceId string = ''

var eventHubNames = [
  'reference-data-raw'
  'reference-data-accepted'
  'preference-data-row'
  'preference-data-accepted'
]

var privateDnsZoneName = 'privatelink.servicebus.windows.net'

resource eventHubNamespace 'Microsoft.EventHub/namespaces@2024-01-01' = {
  name: namespaceName
  location: location
  sku: {
    name: skuName
    tier: skuName
    capacity: skuName == 'Standard' ? standardThroughputUnits : 1
  }
  properties: {
    isAutoInflateEnabled: false
    minimumTlsVersion: '1.2'
    publicNetworkAccess: disablePublicNetworkAccess ? 'Disabled' : 'Enabled'
  }
}

resource eventHubs 'Microsoft.EventHub/namespaces/eventhubs@2024-01-01' = [for hubName in eventHubNames: {
  name: hubName
  parent: eventHubNamespace
  properties: {
    messageRetentionInDays: messageRetentionInDays
    partitionCount: partitionCount
  }
}]

resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = if (deployPrivateEndpoint && createPrivateDnsZone) {
  name: privateDnsZoneName
  location: 'global'
}

resource privateDnsVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = if (deployPrivateEndpoint && createPrivateDnsZone && !empty(privateDnsVnetResourceId)) {
  parent: privateDnsZone
  name: '${namespaceName}-dns-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: privateDnsVnetResourceId
    }
  }
}

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = if (deployPrivateEndpoint) {
  name: privateEndpointName
  location: location
  properties: {
    subnet: {
      id: privateEndpointSubnetResourceId
    }
    privateLinkServiceConnections: [
      {
        name: '${privateEndpointName}-conn'
        properties: {
          privateLinkServiceId: eventHubNamespace.id
          groupIds: [
            'namespace'
          ]
          requestMessage: 'Private access for insurance member data mastering hub'
        }
      }
    ]
  }
}

resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = if (deployPrivateEndpoint) {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'eventhubs-zone-config'
        properties: {
          privateDnsZoneId: createPrivateDnsZone ? privateDnsZone.id : existingPrivateDnsZoneResourceId
        }
      }
    ]
  }
  dependsOn: [
    privateDnsVnetLink
  ]
}

output eventHubNamespaceId string = eventHubNamespace.id
output eventHubBootstrapFqdn string = '${namespaceName}.servicebus.windows.net:9093'
output eventHubAmqpFqdn string = '${namespaceName}.servicebus.windows.net'
output eventHubEntityNames array = eventHubNames
