# Setup Cluster with GCE

> WARNING: This is a work in progress.

## Requirements

* Install the [Google Cloud CLI](https://cloud.google.com/sdk/).

## Create common environment variables:

```bash
export PROJECT_ID="opennms-k8s"
export PROJECT_DESCR="OpenNMS Kubernetes"
export COMPUTE_ZONE="us-central1-a"
export DOMAIN="gce.agalue.net"

```

> Those variables will be used by all the commands used below.

## Configure the Google Cloud CLI

Create a project and make it the default:

```bash
gcloud auth login
gcloud projects create $PROJECT_ID --name="$PROJECT_DESCR"
gcloud config set project $PROJECT_ID
gcloud config set compute/zone $COMPUTE_ZONE
```

> **NOTE**: An existing project can be used. The following commands will use the default one.

## DNS Configuration

Make sure you have a Cloud DNS Zone configured, and it has an `NS` entry your registrar matching the name servers from the zone.

```bash
gcloud dns managed-zones describe gce | grep dnsName
```

The output would be:

```text
dnsName: gce.agalue.net.
```

To validate:

```bash
dig gce.agalue.net.
```

The output would be:

```text
; <<>> DiG 9.10.6 <<>> gce.agalue.net.
;; global options: +cmd
;; Got answer:
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 38953
;; flags: qr rd ra; QUERY: 1, ANSWER: 0, AUTHORITY: 1, ADDITIONAL: 1

;; OPT PSEUDOSECTION:
; EDNS: version: 0, flags:; udp: 4096
;; QUESTION SECTION:
;gce.agalue.net.      IN  A

;; AUTHORITY SECTION:
gce.agalue.net.   300 IN  SOA ns-cloud-a1.googledomains.com. cloud-dns-hostmaster.google.com. 1 21600 3600 259200 300

;; Query time: 89 msec
;; SERVER: 172.20.1.9#53(172.20.1.9)
;; WHEN: Mon Apr 29 16:41:06 EDT 2019
;; MSG SIZE  rcvd: 136
```

> **WARNING**: Please use your own Domain, meaning that every time the domain `gce.agalue.net` is mentioned or used, replace it with your own.

## Cluster Creation

Create the Kubernetes Cluster

> **WARNING**: Make sure you have enough quota on your Google Cloud account to create all the resources. Without alterations, this deployment requires `CPUS_ALL_REGIONS=40`. Be aware that trial accounts cannot request quota changes. A reduced version is available in order to test the deployment.

With enough quota:

```bash
export GCP_NODE_COUNT=5
export GCP_VM_SIZE=n1-standard-8
```

With reduced quota:

```bash
export GCP_NODE_COUNT=3
export GCP_VM_SIZE=n1-standard-2
```

Then,

```bash
gcloud container clusters create opennms \
  --num-nodes=$GCP_NODE_COUNT \
  --cluster-version=1.16.10-gke.8 \
  --machine-type=$GCP_VM_SIZE
```

Then,

```bash
kubectl cluster-info
```

The output should be something like this:

```text
Kubernetes master is running at https://34.66.138.146
GLBCDefaultBackend is running at https://34.66.138.146/api/v1/namespaces/kube-system/services/default-http-backend:http/proxy
Heapster is running at https://34.66.138.146/api/v1/namespaces/kube-system/services/heapster/proxy
KubeDNS is running at https://34.66.138.146/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
Metrics-server is running at https://34.66.138.146/api/v1/namespaces/kube-system/services/https:metrics-server:/proxy

To further debug and diagnose cluster problems, use 'kubectl cluster-info dump'.
```

## Install the NGinx Ingress Controller

This add-on is required in order to avoid having a LoadBalancer per external service.

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/static/provider/cloud/deploy.yaml
```

## Install the CertManager

```bash
kubectl apply --validate=false -f https://github.com/jetstack/cert-manager/releases/download/v1.0.1/cert-manager.yaml
```

## Install Jaeger CRDs

```bash
kubectl apply -f https://raw.githubusercontent.com/jaegertracing/jaeger-operator/master/deploy/crds/jaegertracing.io_jaegers_crd.yaml
```

## Manifets

To apply all the manifests with enough quota:

```bash
kubectl apply -k gce
```

With reduced quota:

```bash
kubectl apply -k gce-reduced
```

> **NOTE**: Depending on the available resources, it is possible to remove some of the restrictions, to have more instances for the clusters, and/or OpenNMS.

## Configure DNS Entry for the Ingress Controller

With Kops and EKS, the External DNS controller takes care of the DNS entries. Here, we're going to use a different approach, as having external-dns working with GCE is challenging.

Find out the external IP of the Ingress Controller (wait for it, in case it is not there):

```bash
kubectl get svc ingress-nginx -n ingress-nginx
```

The output should be something like this:

```text
NAME            TYPE           CLUSTER-IP      EXTERNAL-IP     PORT(S)                      AGE
ingress-nginx   LoadBalancer   10.51.248.125   35.239.225.26   80:31039/TCP,443:31186/TCP   103s
```

Create a wildcard DNS entry on your Cloud DNS Zone to point to the `EXTERNAL-IP`; for example:

```bash
export MANAGED_ZONE="gce"
export NGINX_EXTERNAL_IP=$(kubectl get svc ingress-nginx -n ingress-nginx -o json | jq -r '.status.loadBalancer.ingress[0].ip')

gcloud dns record-sets transaction start --zone $MANAGED_ZONE
gcloud dns record-sets transaction add "$NGINX_EXTERNAL_IP" --zone $MANAGED_ZONE --name "*.$DOMAIN." --ttl 300 --type A
gcloud dns record-sets transaction execute --zone $MANAGED_ZONE
```

## Install Jaeger Tracing

```bash
kubectl apply -n opennms -f https://raw.githubusercontent.com/jaegertracing/jaeger-operator/master/deploy/service_account.yaml
kubectl apply -n opennms -f https://raw.githubusercontent.com/jaegertracing/jaeger-operator/master/deploy/role.yaml
kubectl apply -n opennms -f https://raw.githubusercontent.com/jaegertracing/jaeger-operator/master/deploy/role_binding.yaml
kubectl apply -n opennms -f https://raw.githubusercontent.com/jaegertracing/jaeger-operator/master/deploy/operator.yaml
```

## Cleanup

Remove the A Records from the Cloud DNS Zone:

```bash
gcloud dns record-sets transaction start --zone $MANAGED_ZONE
gcloud dns record-sets transaction remove --zone $MANAGED_ZONE --name "*.$DOMAIN" --ttl 300 --type A "$NGINX_EXTERNAL_IP"
gcloud dns record-sets transaction execute --zone $MANAGED_ZONE
```

Delete the cluster:

```bash
gcloud container clusters delete opennms
```
