# Setup Cluster with Azure

## Requirements

* Install the [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest) command.

> **WARNING:** Please note that all the manifests were verified for Kubernetes 1.21 or newer. If you're going to use and older version, please adjust the API versions of the manifests for `CronJobs` in [elasticsearch.curator.yaml](manifests/elasticsearch.curator.yaml), `PodDisruptionBudget` in [zookeeper.yaml](manifests/zookeeper.yaml), and `Ingress` in [external-access.yaml](manifests/external-access.yaml).

## Configure the Azure CLI

Login into Azure:

```bash
az login
```

## Create common environment variables:

```bash
export GROUP="Kubernetes"
export LOCATION="eastus"
export DOMAIN="azure.agalue.net"
export IDENTITY="opennms"
```

> Those variables will be used by all the commands used below. Make sure to use your own domain.

## Create a Resource Group:

```bash
az group create --name "$GROUP" --location "$LOCATION"
```

The above is not strictly necessary. You can use an existing group if you want. If you do, make sure to update the `GROUP` environment variable so all subsequent commands will use the correct one (same for the region or location).

## DNS Configuration

Create a DNS Zone:

```bash
az network dns zone create -g "$GROUP" -n "$DOMAIN"
```

> **WARNING**: Make sure to add an `NS` record on your registrar pointing to the Domain Servers returned from the above command. The resource group can be different than the group used for the AKS cluster.

This is required so the Ingress Controller and CertManager can use custom FQDNs for all the different services.

## Managed Identities vs Service Principal

You could either use a Managed Identity or a Service Principal when deploying an AKS cluster. However, the preferred method is using a Managed Identity to avoid sharing credentials with broad permissions (as it would require having a Contributor role at the Subscription level assigned to it).

By default, unless specified, AKS will create a system-assigned managed identity.

Besides avoiding sharing credentials, another advantage of using Managed Identities is allowing access to other resources like Azure Container Registries.

To create a user-assigned managed identity and use it when creating your cluster:

```bash
az identity create  -g "$GROUP" -n "$IDENTITY"
```

At runtime, even if your Azure Account doesn't have privileges to assign roles, AKS will associate a contributor role to the provided managed identity for the resource group it creates (the one prefixed with `MC_`).

## Cluster Creation

> **WARNING**: Make sure you have enough quota on your Azure to create all the resources. Be aware that trial accounts cannot request quota changes. A reduced version is available in order to test the deployment, based on the `Visual Studio Enterprise` Subscription (which has a limitation of 20 vCPUs). If you need further limitations, use the `aks-reduced` folder as inspiration, and create a copy of it with your desired settings. The minimal version is what `minikube` would use.

With enough quota:

```bash
export AKS_NODE_COUNT=5
export AKS_VM_SIZE=Standard_DS4_v2
```

With reduced quota:

```bash
export AKS_NODE_COUNT=4
export AKS_VM_SIZE=Standard_DS3_v2
```

> **WARNING**: Please keep in mind that node size cannot be changed after the cluster is created (i.e., `--node-vm-size`); although you can change the number of nodes in the scale set (i.e., `--node-count`).

Then,

```bash
VERSION=$(az aks get-versions --location "$LOCATION" --output tsv \
  --query 'orchestrators[?!isPreview] | [-1].orchestratorVersion')

az aks create --name "$USER-opennms" \
  --resource-group "$GROUP" \
  --dns-name-prefix "$USER-opennms" \
  --kubernetes-version "$VERSION" \
  --location "$LOCATION" \
  --node-count $AKS_NODE_COUNT \
  --node-vm-size $AKS_VM_SIZE \
  --ssh-key-value ~/.ssh/id_rsa.pub \
  --admin-username "$USER" \
  --nodepool-tags "Owner=$USER" \
  --tags "Owner=$USER" \
  --output table
```

Note the usage of `$USER` across multiple fields. The purpose of this is to make sure the names are unique, to avoid conflicts when using shared resource groups, meaning the above would work only on Linux or macOS systems.

The above creates a cluster based on Kubenet (basic networking) using a system-assigned managed identity.

To use an existing user-assigned managed identity, add the following to the above command:

```bash
--assign-identity "$IDENTITY"
```

You can instruct Azure to assign the AKS cluster to a specifc subnet of an existing VNET, regardless if you're using Kubenet or Azure CNI. For instance, before issuing `az aks create`, do the follwing:

```bash
az network vnet create -g "$GROUP" \
  --name "$USER-k8s-vnet" \
  --address-prefix "13.0.0.0/16" \
  --subnet-name "main" \
  --subnet-prefix "13.0.0.0/16" \
  --tags Owner=$USER \
  --output table

SUBNET_ID=$(az network vnet subnet show -g "$GROUP" \
    --vnet-name "$USER-k8s-vnet" \
    --name "main" | jq -r .id)
```

Then, to use the above subnet ID, add the following to the `az aks create` command:

```bash
--vnet-subnet-id=$SUBNET_ID
```

If you want to use Azure CNI instead of Kubenet, make sure you plan the subnet range accordingly.

With Azure CNI, each worker node from the node pool will pre-reserve `--max-pods` (defaults to 30) IP addresses from the subnet to use them for Pods, meaning Pods will use an IP from the subnet (think of them as sub-interfaces of the nodes that Pods would use at runtime).

With Kubenet, there is a concept of Pod Network (Pod CIDR), and AKS creates a routing table to allow Pod-to-Pod communication. The Pod Network concept doesn't exist in Azure CNI, as all Pods will use an IP from the provided subnet (and there is no need for a routing table).

To use Azure CNI, add the following to the `az aks create` command:

```bash
--network-plugin=azure
```

If you're interested in Network Policies, you can use Calico with both, Kubenet or Azure CNI, but with the latter, you can also use Azure, for instance:

```bash
--network-policy=azure
```

> **IMPORTANT**: According to the [documentation](https://docs.microsoft.com/en-us/azure/aks/configure-azure-cni), when using Azure CNI, each pod will get an IP from that subnet and requires more planning.

> **WARNING**: Due to [this](https://github.com/Azure/AKS/issues/1200) known issue, the above command will fail if your subscription has a Tag Policy in place (a policy that enforced having tags on every resource on a given resource group).

To validate the cluster:

```bash
az aks show --resource-group "$GROUP" --name "$USER-opennms"
```

To configure `kubectl`:

```bash
az aks get-credentials --resource-group "$GROUP" --name "$USER-opennms"
```

## Install the NGinx Ingress Controller

This add-on is required to avoid having a Load Balancer per external service.

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/static/provider/cloud/deploy.yaml
```

## Install the CertManager

The [cert-manager](https://cert-manager.readthedocs.io/en/latest/) add-on is required to provide HTTPS/TLS support through [LetsEncrypt](https://letsencrypt.org) to the web-based services managed by the ingress controller.

```bash
CMVER=$(curl -s https://api.github.com/repositories/92313258/releases/latest | grep tag_name | cut -d '"' -f 4)
kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/$CMVER/cert-manager.yaml
```

## Install Jaeger Operator

```bash
JAEGERVER=$(curl -s https://api.github.com/repos/jaegertracing/jaeger-operator/releases/latest | grep tag_name | cut -d '"' -f 4)
kubectl create ns observability
kubectl apply -n observability \
  -f https://github.com/jaegertracing/jaeger-operator/releases/download/$JAEGERVER/jaeger-operator.yaml
```

## Manifets

To apply all the manifests with enough quota:

```bash
kubectl apply -k aks
```

With reduced quota:

```bash
kubectl apply -k aks-reduced
```

## Configure DNS Entry for the Ingress Controller

With Kops and EKS, the External DNS controller takes care of the DNS entries. Here, we're going to use a different approach.

Find out the external IP of the Ingress Controller (wait for it, in case it is not there):

```bash
kubectl get svc ingress-nginx-controller -n ingress-nginx
```

The output should be something like this:

```text
NAME                       TYPE           CLUSTER-IP    EXTERNAL-IP      PORT(S)                      AGE
ingress-nginx-controller   LoadBalancer   10.0.83.198   40.117.237.217   80:30664/TCP,443:30213/TCP   9m58s
```

Create a wildcard DNS entry on your DNS Zone to point to the `EXTERNAL-IP`; for example:

```bash
export NGINX_EXTERNAL_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

az network dns record-set a add-record -g "$GROUP" -z "$DOMAIN" -n "*" -a $NGINX_EXTERNAL_IP
```

> **IMPORTANT**: The above assumes that Azure DNS was configured within the same Resource Group as the AKS cluster. Change it if necessary.

## Cleanup

To remove the A Records from the DNS Zone (using `NGINX_EXTERNAL_IP` from the above section):

```bash
az network dns record-set a remove-record -g "$GROUP" -z "$DOMAIN" -n "*" -a $NGINX_EXTERNAL_IP
```

To delete the Kubernetes cluster, do the following:

```bash
az aks delete --name "$USER-opennms" --resource-group "$GROUP"
```

> **WARNING**: Deleting the cluster may take several minutes to complete.
