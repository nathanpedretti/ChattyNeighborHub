# Insurance Member Data Mastering Hub (Headless)

This repository contains Azure Bicep templates for a **headless data mastering hub** based on Azure Event Hubs.

## What gets deployed

- Azure Event Hubs namespace using the **lowest-cost SKU that supports Private Endpoints**: **Standard (1 Throughput Unit)**
- Four event hubs (used as topics):
	- `reference-data-raw`
	- `reference-data-accepted`
	- `preference-data-row`
	- `preference-data-accepted`
- Private Endpoint support
- Private DNS integration (`privatelink.servicebus.windows.net`)

> Note: Azure Event Hubs **Basic** is lower cost but does **not** support Private Endpoints. Standard is the lowest tier that satisfies your private networking requirement.

## Files

- `infra/hub/main.bicep` – deploys the shared hub namespace + event hubs + optional private endpoint.
- `infra/consumer-connection/main.bicep` – deploys consumer-side private endpoint from a separate subscription.

## Prerequisites

- Azure CLI installed and logged in: `az login`
- Permissions:
	- Hub subscription: permission to deploy Event Hubs + networking
	- Consumer subscription: permission to deploy Private Endpoint + DNS
- Existing VNets/subnets prepared for private endpoints (private endpoint network policies disabled on PE subnet)

---

## 1) Deploy the shared data mastering hub (hub subscription)

Run in the hub subscription context:

```bash
az account set --subscription <HUB_SUBSCRIPTION_ID>

az deployment group create \
	--resource-group <HUB_RESOURCE_GROUP> \
	--template-file infra/hub/main.bicep \
	--parameters \
			namespaceName=<globally-unique-namespace-name> \
			skuName=Standard \
			standardThroughputUnits=1 \
			messageRetentionInDays=1 \
			partitionCount=2 \
			disablePublicNetworkAccess=true \
			deployPrivateEndpoint=true \
			privateEndpointSubnetResourceId=<HUB_SUBNET_RESOURCE_ID> \
			createPrivateDnsZone=true \
			privateDnsVnetResourceId=<HUB_VNET_RESOURCE_ID>
```

If you do **not** want a private endpoint in the hub subscription, set `deployPrivateEndpoint=false`.

---

## 2) Connect an app from a separate subscription (consumer subscription)

Deploy a **consumer-side private endpoint** targeting the shared Event Hubs namespace.

Run in the consumer subscription context:

```bash
az account set --subscription <CONSUMER_SUBSCRIPTION_ID>

az deployment group create \
	--resource-group <CONSUMER_RESOURCE_GROUP> \
	--template-file infra/consumer-connection/main.bicep \
	--parameters \
			hubSubscriptionId=<HUB_SUBSCRIPTION_ID> \
			hubResourceGroupName=<HUB_RESOURCE_GROUP> \
			hubNamespaceName=<HUB_NAMESPACE_NAME> \
			privateEndpointSubnetResourceId=<CONSUMER_SUBNET_RESOURCE_ID> \
			createPrivateDnsZone=true \
			consumerPrivateDnsVnetResourceId=<CONSUMER_VNET_RESOURCE_ID>
```

### Private endpoint approval

- If auto-approval does not occur, a hub-side owner must approve the private endpoint connection:
	1. Open Event Hubs namespace in Azure Portal
	2. Networking → Private endpoint connections
	3. Approve pending request

### DNS validation from consumer app host

From a VM/container in the consumer VNet, validate:

```bash
nslookup <HUB_NAMESPACE_NAME>.servicebus.windows.net
```

It should resolve to a private IP.

---

## 3) Authorize the consumer application

Prefer Microsoft Entra ID (managed identity/service principal) over shared keys.

Assign roles on the Event Hubs namespace (hub subscription):

- `Azure Event Hubs Data Sender`
- `Azure Event Hubs Data Receiver`

Example:

```bash
az role assignment create \
	--assignee-object-id <APP_MI_OR_SP_OBJECT_ID> \
	--assignee-principal-type ServicePrincipal \
	--role "Azure Event Hubs Data Sender" \
	--scope /subscriptions/<HUB_SUBSCRIPTION_ID>/resourceGroups/<HUB_RESOURCE_GROUP>/providers/Microsoft.EventHub/namespaces/<HUB_NAMESPACE_NAME>

az role assignment create \
	--assignee-object-id <APP_MI_OR_SP_OBJECT_ID> \
	--assignee-principal-type ServicePrincipal \
	--role "Azure Event Hubs Data Receiver" \
	--scope /subscriptions/<HUB_SUBSCRIPTION_ID>/resourceGroups/<HUB_RESOURCE_GROUP>/providers/Microsoft.EventHub/namespaces/<HUB_NAMESPACE_NAME>
```

---

## 4) Application connection settings

Use namespace FQDN from private DNS:

- AMQP endpoint host: `<HUB_NAMESPACE_NAME>.servicebus.windows.net`
- Kafka bootstrap (if using Kafka API): `<HUB_NAMESPACE_NAME>.servicebus.windows.net:9093`

Target event hub names:

- `reference-data-raw`
- `reference-data-accepted`
- `preference-data-row`
- `preference-data-accepted`

---

## Cost notes

- This template defaults to:
	- Standard tier
	- 1 throughput unit
	- 1 day retention
- Private Endpoint and Private DNS incur additional networking costs.
