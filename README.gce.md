# Setup Cluster with GCE

> WARNING: This is a work in progress.

## Requirements

* Install the [Google Cloud CLI](https://cloud.google.com/sdk/).
* Have your AWS account (IAM Credentials) configured on your system (`~/.aws/credentials`).
* Install the [helm](https://helm.sh) binary.

## Configure the Google Cloud CLI

To simplify further commands, configure your default project and zone:

```bash
export PROJECT_ID="alejandro-playground"
export ZONE="us-central1-a"

gcloud auth login
gcloud config set project $PROJECT_ID
gcloud config set compute/zone $ZONE
```

> **WARNING**: Make sure to use your project and your zone.

## DNS Configuration

Make sure you have a Cloud DNS Zone configured on your Registrar.

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

```
; <<>> DiG 9.10.6 <<>> gce.agalue.net.
;; global options: +cmd
;; Got answer:
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 38953
;; flags: qr rd ra; QUERY: 1, ANSWER: 0, AUTHORITY: 1, ADDITIONAL: 1

;; OPT PSEUDOSECTION:
; EDNS: version: 0, flags:; udp: 4096
;; QUESTION SECTION:
;gce.agalue.net.			IN	A

;; AUTHORITY SECTION:
gce.agalue.net.		300	IN	SOA	ns-cloud-a1.googledomains.com. cloud-dns-hostmaster.google.com. 1 21600 3600 259200 300

;; Query time: 89 msec
;; SERVER: 172.20.1.9#53(172.20.1.9)
;; WHEN: Mon Apr 29 16:41:06 EDT 2019
;; MSG SIZE  rcvd: 136
```

> **WARNING**: Please use your own Domain, meaning that every time the domain `aws.agalue.net` is used, replace it with yours.

## Cluster Creation

Create the Kubernetes Cluster

```bash
gcloud container clusters create opennms \
  --num-nodes=5 \
  --cluster-version=1.12.7-gke.10 \
  --machine-type=n1-standard-8
```

Once the cluster is running, configure `kubectl` from your own machine or through Google Shell:

```bash
gcloud container clusters get-credentials opennms
```

## Helm

Install Helm, if it is not installed on your machine or Google Shell:

```bash
curl -o get_helm.sh https://raw.githubusercontent.com/kubernetes/helm/master/scripts/get
chmod +x get_helm.sh
./get_helm.sh
```

Initialize it with RBAC:

```bash
kubectl create serviceaccount --namespace kube-system tiller
kubectl create clusterrolebinding tiller-cluster-rule --clusterrole=cluster-admin --serviceaccount=kube-system:tiller
helm init --service-account tiller
```

## Install the NGinx Ingress Controller

This add-on is required in order to avoid having a LoadBalancer per external service.

```bash
helm install --name nginx-ingress stable/nginx-ingress --set rbac.create=true
```

## Install the CertManager

```bash
kubectl apply -f https://raw.githubusercontent.com/jetstack/cert-manager/release-0.7/deploy/manifests/00-crds.yaml
kubectl create namespace cert-manager
kubectl label namespace cert-manager certmanager.k8s.io/disable-validation=true
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install --name cert-manager --namespace cert-manager --version v0.7.1 jetstack/cert-manager
```

## Configure DNS Entry for the Ingress Controller

Wait until the Ingress Controller is active and have aan external IP:

```bash
kubectl get service nginx-ingress-controller
NAME                       TYPE           CLUSTER-IP      EXTERNAL-IP    PORT(S)                      AGE
nginx-ingress-controller   LoadBalancer   10.23.246.178   35.239.78.96   80:30658/TCP,443:32196/TCP   6m8s
```

Create a wildcard DNS entry on your Cloud DNS Zone to point to the `EXTERNAL-IP`, for example:

```bash
EXTERNAL_IP=$(kubectl get service nginx-ingress-controller -o json | jq -r .status.loadBalancer.ingress[0].ip)
DOMAIN="gce.agalue.net"
ZONE="gce"

cat <<EOF > /tmp/ingress.yaml
kind: dns#resourceRecordSet
name: '*.${DOMAIN}.'
rrdatas:
- ${EXTERNAL_IP}
ttl: 300
type: A
EOF

gcloud dns record-sets import /tmp/ingress.yaml --zone $ZONE
```

## Manifets

To apply all the manifests:

```bash
kubectl apply -k manifests
```

If you're not running `kubectl` version 1.14, the following is an alternative:

```bash
kustomize build manifests | kubectl apply -f
```

## Cleanup

```bash
gcloud container clusters delete opennms
```

Also, remember to remove the A Record from the Cloud DNS Zone, as this won't happen automatically.