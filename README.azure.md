# Setup Cluster with Azure

> WARNING: This is a work in progress.

## Requirements

* Install the [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest).

## Configure the Azure CLI

Login into Azure:

```bash
az login
```

Create a Resource Group:

```bash
export GROUP="Kubernetes"

az group create --name $GROUP --location "East US"
```

## DNS Configuration

Create a DNS Zone:

```bash
export GROUP="Kubernetes"
export DOMAIN="azure.agalue.net"

az network dns zone create -g $GROUP -n $DOMAIN
```

> **WARNING**: Make sure to add a `NS` record on your registrar pointing to the Domain Servers returned from the above command.

## Cluster Creation

> **WARNING**: Make sure you have enough quota on your Azure to create all the resources. Be aware that trial accounts cannot request quota changes. A reduced version is available in order to test the deployment.

With enough quota:

```bash
export GROUP="Kubernetes"

az aks create --name opennms \
  --resource-group $GROUP \
  --dns-name-prefix opennms \
  --enable-rbac \
  --kubernetes-version 1.14.8 \
  --location "East US" \
  --node-count 4 \
  --node-vm-size Standard_DS3_v2 \
  --nodepool-name onms-pool \
  --generate-ssh-keys \
  --tags "Department=Support Environment=Test"
```

> **WARNING**: This operation takes about an hour, so be patient.

To validate the cluster:

```bash
export GROUP="Kubernetes"

az aks show --resource-group $GROUP --name opennms
```

To configure `kubectl`:

```bash
export GROUP="Kubernetes"

az aks get-credentials --resource-group $GROUP --name opennms
```

## Install the NGinx Ingress Controller

This add-on is required in order to avoid having a LoadBalancer per external service.

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/mandatory.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/provider/cloud-generic.yaml
```

## Install the CertManager

```bash
kubectl create namespace cert-manager
kubectl apply --validate=false -f https://github.com/jetstack/cert-manager/releases/download/v0.12.0/cert-manager.yaml
```

## Install Jaeger Tracing

```bash
kubectl create namespace observability
kubectl create -f https://raw.githubusercontent.com/jaegertracing/jaeger-operator/master/deploy/crds/jaegertracing.io_jaegers_crd.yaml
kubectl create -f https://raw.githubusercontent.com/jaegertracing/jaeger-operator/master/deploy/service_account.yaml
kubectl create -f https://raw.githubusercontent.com/jaegertracing/jaeger-operator/master/deploy/role.yaml
kubectl create -f https://raw.githubusercontent.com/jaegertracing/jaeger-operator/master/deploy/role_binding.yaml
kubectl create -f https://raw.githubusercontent.com/jaegertracing/jaeger-operator/master/deploy/operator.yaml
```

## Configure DNS Entry for the Ingress Controller and Kafka

With Kops and EKS, the External DNS controller takes care of the DNS entries. Here, we're going to use a different approach.

Find out the external IP of the Ingress Controller (wait for it, in case it is not there):

```bash
kubectl get svc ingress-nginx -n ingress-nginx
```

The output should be something like this:

```text
NAME            TYPE           CLUSTER-IP    EXTERNAL-IP      PORT(S)                      AGE
ingress-nginx   LoadBalancer   10.0.83.198   40.117.237.217   80:30664/TCP,443:30213/TCP   9m58s
```

Something similar can be done for Kafka:

```bash
kubectl get svc ext-kafka -n opennms
```

Create a wildcard DNS entry on your DNS Zone to point to the `EXTERNAL-IP`; and create an A record for `kafka`. For example:

```bash
export GROUP="Kubernetes"
export DOMAIN="azure.agalue.net"
export NGINX_EXTERNAL_IP=$(kubectl get svc ingress-nginx -n ingress-nginx -o json | jq -r '.status.loadBalancer.ingress[0].ip')
export KAFKA_EXTERNAL_IP=$(kubectl get svc ext-kafka -n opennms -o json | jq -r '.status.loadBalancer.ingress[0].ip')

az network dns record-set a add-record -g $GROUP -z $DOMAIN -n '*' -a $NGINX_EXTERNAL_IP
az network dns record-set a add-record -g $GROUP -z $DOMAIN -n 'kafka' -a $KAFKA_EXTERNAL_IP
```

## Manifets

To apply all the manifests:

```bash
kubectl apply -k aks
```

> **NOTE**: The amount of resources has been reduced to avoid quota issues.

## Security Groups

When configuring Kafka, the `hostPort` is used in order to configure the `advertised.listeners` using the EC2 public FQDN. For this reason the external port (i.e. `9094`) should be opened. Fortunately, AKS does that auto-magically for you, so there is no need for changes.

## Cleanup

Remove the A Records from the DNS Zone:

```bash
export GROUP="Kubernetes"
export DOMAIN="azure.agalue.net"
export NGINX_EXTERNAL_IP=$(kubectl get svc ingress-nginx -n ingress-nginx -o json | jq -r '.status.loadBalancer.ingress[0].ip')
export KAFKA_EXTERNAL_IP=$(kubectl get svc ext-kafka -n opennms -o json | jq -r '.status.loadBalancer.ingress[0].ip')

az network dns record-set a remove-record -g $GROUP -z $DOMAIN -n '*' -a $NGINX_EXTERNAL_IP
az network dns record-set a remove-record -g $GROUP -z $DOMAIN -n 'kafka' -a $KAFKA_EXTERNAL_IP
```

Delete the cluster:

```bash
export GROUP="Kubernetes"

az aks delete --name opennms --resource-group $GROUP
```

> **WARNING**: Deleting the cluster can take a long time.
