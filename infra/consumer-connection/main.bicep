targetScope = 'resourceGroup'

@description('Azure region for consumer-side private endpoint resources.')
param location string = resourceGroup().location

@description('Subscription ID that hosts the shared Event Hubs namespace.')
param hubSubscriptionId string

@description('Resource group name that hosts the shared Event Hubs namespace.')
param hubResourceGroupName string

@description('Event Hubs namespace name in the hub subscription.')
param hubNamespaceName string

@description('Subnet resource ID in this (consumer) subscription where the private endpoint will be placed.')
param privateEndpointSubnetResourceId string

@description('Name of the private endpoint in the consumer subscription.')
param privateEndpointName string = '${hubNamespaceName}-consumer-pe'

@description('Set true to create private DNS zone in consumer subscription/resource group.')
param createPrivateDnsZone bool = true

@description('Resource ID of existing private DNS zone to use when createPrivateDnsZone=false.')
param existingPrivateDnsZoneResourceId string = ''

@description('Resource ID of the consumer VNet to link to private DNS zone. Required when createPrivateDnsZone=true.')
param consumerPrivateDnsVnetResourceId string = ''

var privateDnsZoneName = 'privatelink.servicebus.windows.net'

resource hubRg 'Microsoft.Resources/resourceGroups@2022-09-01' existing = {
  scope: subscription(hubSubscriptionId)
  name: hubResourceGroupName
}

resource hubNamespace 'Microsoft.EventHub/namespaces@2024-01-01' existing = {
  scope: hubRg
  name: hubNamespaceName
}

resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = if (createPrivateDnsZone) {
  name: privateDnsZoneName
  location: 'global'
}

resource privateDnsVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = if (createPrivateDnsZone && !empty(consumerPrivateDnsVnetResourceId)) {
  parent: privateDnsZone
  name: '${privateEndpointName}-dns-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: consumerPrivateDnsVnetResourceId
    }
  }
}

resource consumerPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = {
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
          privateLinkServiceId: hubNamespace.id
          groupIds: [
            'namespace'
          ]
          requestMessage: 'Consumer subscription private access to shared Event Hubs namespace'
        }
      }
    ]
  }
}

resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  parent: consumerPrivateEndpoint
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

output requestedHubNamespaceId string = hubNamespace.id
output privateEndpointId string = consumerPrivateEndpoint.id
