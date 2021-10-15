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

## Service Principal

Create a service principal account, and extract the service principal ID (or `appId`) and the client secret (or `password`):

```bash
export SERVICE_PRINCIPAL_NAME=$USER-k8s-opennms
export SERVICE_PRINCIPAL_FILE=~/.azure/$SERVICE_PRINCIPAL_NAME.json

az ad sp create-for-rbac --skip-assignment --name $SERVICE_PRINCIPAL_NAME > $SERVICE_PRINCIPAL_FILE

export SERVICE_PRINCIPAL=$(jq -r .appId $SERVICE_PRINCIPAL_FILE)
export CLIENT_SECRET=$(jq -r .password $SERVICE_PRINCIPAL_FILE)
```

> **WARNING**: The `az ad sp create-for-rbac` command should be executed once. If the principal already exists, either extract the information as mentioned or delete it and recreate it before proceed.

The reason for pre-creating the service principal is due to a [known issue](https://github.com/Azure/azure-cli/issues/9585) that prevents the `az aks create` command to do it for you. For more information about service principals, follow [this](https://docs.microsoft.com/en-us/azure/aks/kubernetes-service-principal) link.

> **INFO**: When the resource group to use for the AKS cluster is new, you might omit to create the service principal account, as it will ve created for you (if your account has enough privileges).

As explained [here](https://docs.microsoft.com/en-us/azure/aks/kubernetes-service-principal?tabs=azure-cli) the SP must have the Contributor role for the chosen resource group so AKS can create resources on your behalf like Load Balancers, Volumes, and so on.

However, you must have enough privileges to assign the roles, like the following:

```bash
GROUP_ID=$(az group show -g "$GROUP" | jq -r .id)
az role assignment create --assignee $SERVICE_PRINCIPAL --scope $GROUP_ID --role Contributor
```

If not, please get in touch with your Azure Administrator so they can create the SP with the appropriate role for you. Remember that you need the `appId` and `password` as mentioned above to create the AKS cluster.

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
VERSION=$(az aks get-versions \
    --location "$LOCATION" \
    --query 'orchestrators[?!isPreview] | [-1].orchestratorVersion' \
    --output tsv)

az aks create --name "$USER-opennms" \
  --resource-group "$GROUP" \
  --service-principal "$SERVICE_PRINCIPAL" \
  --client-secret "$CLIENT_SECRET" \
  --dns-name-prefix "$USER-opennms" \
  --kubernetes-version "$VERSION" \
  --location "$LOCATION" \
  --node-count $AKS_NODE_COUNT \
  --node-vm-size $AKS_VM_SIZE \
  --nodepool-name "$USER" \
  --nodepool-tags "Owner=$USER" \
  --network-plugin azure \
  --network-policy azure \
  --ssh-key-value ~/.ssh/id_rsa.pub \
  --admin-username "$USER" \
  --tags "Owner=$USER" \
  --output table
```

Note the usage of `$USER` across multiple fields. The purpose of this is to make sure the names are unique, to avoid conflicts when using shared resource groups, meaning the above would work only on Linux or macOS systems.

> **WARNING**: Unfortunately, due to [this](https://github.com/Azure/AKS/issues/1200) known issue, the above command will fail if your subscription has a Tag Policy in place (a policy that enforced having tags on every resource on a given resource group).

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
CMVER=$(curl -s https://api.github.com/repos/jetstack/cert-manager/releases/latest | grep tag_name | cut -d '"' -f 4)
kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/$CMVER/cert-manager.yaml
```

## Install Jaeger CRDs

```bash
kubectl apply -f https://raw.githubusercontent.com/jaegertracing/jaeger-operator/master/deploy/crds/jaegertracing.io_jaegers_crd.yaml
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

## Install Jaeger Tracing

This installs the Jaeger operator in the `opennms` namespace for tracing purposes.

```bash
kubectl apply -n opennms -f https://raw.githubusercontent.com/jaegertracing/jaeger-operator/master/deploy/service_account.yaml
kubectl apply -n opennms -f https://raw.githubusercontent.com/jaegertracing/jaeger-operator/master/deploy/role.yaml
kubectl apply -n opennms -f https://raw.githubusercontent.com/jaegertracing/jaeger-operator/master/deploy/role_binding.yaml
kubectl apply -n opennms -f https://raw.githubusercontent.com/jaegertracing/jaeger-operator/master/deploy/operator.yaml
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
export NGINX_EXTERNAL_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o json | jq -r '.status.loadBalancer.ingress[0].ip')

az network dns record-set a add-record -g "$GROUP" -z "$DOMAIN" -n "*" -a $NGINX_EXTERNAL_IP
```

> **IMPORTANT**: The above assumes that Azure DNS was configured within the same Resource Group as the AKS cluster. Change it if necessary.

## Cleanup

To remove the A Records from the DNS Zone:

```bash
az network dns record-set a remove-record -g "$GROUP" -z "$DOMAIN" -n "*" -a $NGINX_EXTERNAL_IP
```

To delete the Kubernetes cluster, do the following:

```bash
az aks delete --name "$USER-opennms" --resource-group "$GROUP"
```

> **WARNING**: Deleting the cluster may take several minutes to complete.
