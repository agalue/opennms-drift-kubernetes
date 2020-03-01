# Setup Cluster with KOPS

## Requirements

* Install the [AWS CLI](https://aws.amazon.com/cli/).
* Have your AWS account (IAM Credentials) configured on your system (`~/.aws/credentials`).
* Install the [kops](https://github.com/kubernetes/kops/blob/master/docs/install.md) binary. Tested with version 1.16.x.

## DNS Configuration

Create DNS sub-domain on [Route 53](https://console.aws.amazon.com/route53/home), register it as an `NS` entry on your registrar matching the name servers from the sub-domain, and make sure it works prior start the cluster; for example:

```bash
dig ns aws.agalue.net
```

The output should look like this:

```text
; <<>> DiG 9.10.6 <<>> ns aws.agalue.net
;; global options: +cmd
;; Got answer:
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 46163
;; flags: qr rd ra; QUERY: 1, ANSWER: 4, AUTHORITY: 0, ADDITIONAL: 1

;; OPT PSEUDOSECTION:
; EDNS: version: 0, flags:; udp: 4096
;; QUESTION SECTION:
;aws.agalue.net.      IN  NS

;; ANSWER SECTION:
aws.agalue.net.   172800  IN  NS  ns-1821.awsdns-35.co.uk.
aws.agalue.net.   172800  IN  NS  ns-718.awsdns-25.net.
aws.agalue.net.   172800  IN  NS  ns-1512.awsdns-61.org.
aws.agalue.net.   172800  IN  NS  ns-144.awsdns-18.com.

;; Query time: 85 msec
;; SERVER: 172.20.1.9#53(172.20.1.9)
;; WHEN: Mon Apr 29 14:16:37 EDT 2019
;; MSG SIZE  rcvd: 180
```

> **WARNING**: Please use your own Domain, meaning that every time the domain `aws.agalue.net` is mentioned or used, replace it with your own.

## Cluster Creation

Create an S3 bucket to hold the `kops` configuration; for example:

```bash
export KOPS_CLUSTER_NAME="aws.agalue.net"
export AWS_REGION=us-east-2

aws s3api create-bucket \
  --bucket $KOPS_CLUSTER_NAME \
  --create-bucket-configuration LocationConstraint=$AWS_REGION

aws s3api put-bucket-versioning \
  --bucket $KOPS_CLUSTER_NAME \
  --versioning-configuration Status=Enabled
```

Create the Kubernetes cluster using `kops`. The following example creates a cluster with 1 master node and 5 worker nodes on a single Availability Zone using the Hosted Zone `aws.agalue.net`, and the S3 bucked created above:

```bash
export KOPS_CLUSTER_NAME="aws.agalue.net"
export KOPS_STATE_STORE="s3://$KOPS_CLUSTER_NAME"

kops create cluster \
  --cloud aws \
  --cloud-labels Environment=Test,Department=Support \
  --dns-zone $KOPS_CLUSTER_NAME \
  --master-size t2.large \
  --master-count 1 \
  --master-zones us-east-2a \
  --node-size t2.2xlarge \
  --node-count 5 \
  --zones us-east-2a \
  --kubernetes-version 1.16.7 \
  --networking calico
```

> **IMPORTANT:** Remember to change the settings to reflect your desired environment.

> **WARNING:** There are problem with K8s 1.14.7 and ELB creation (fixed on 1.14.8 as of [#82923](https://github.com/kubernetes/kubernetes/issues/82923)). This leads to not having services with type LoadBalancer affecting the Ingress Controller and cert-manager.

Edit the cluster configuration to enable creating Route 53 entries for Ingress hosts:

```bash
kops edit cluster
```

Then, add:

```yaml
spec:
  externalDns:
    watchIngress: true
```

The above is to avoid setting up `external-dns`, but if you're familiar with that controller, you're welcome to use it.

While on edit mode, optionally, enable `CoreDNS` instead of `KubeDNS` (the default), by adding:

```yaml
spec:
  kubeDNS:
    provider: CoreDNS
```

Finally, apply the changes to create the cluster:

```bash
kops update cluster --yes
```

It takes a few minutes to have the cluster ready. Verify the cluster statue using `kubectl` and `kops`:

```bash
kops validate cluster
```

The output should be something like this:

```text
Validating cluster aws.agalue.net

INSTANCE GROUPS
NAME                ROLE      MACHINETYPE    MIN    MAX    SUBNETS
master-us-east-2a   Master    t2.large       1      1      us-east-2a
nodes               Node      t2.2xlarge     5      5      us-east-2a

NODE STATUS
NAME                                         ROLE   READY
ip-172-20-34-142.us-east-2.compute.internal  node   True
ip-172-20-40-103.us-east-2.compute.internal  master True
ip-172-20-41-96.us-east-2.compute.internal   node   True
ip-172-20-43-40.us-east-2.compute.internal   node   True
ip-172-20-44-179.us-east-2.compute.internal  node   True
ip-172-20-62-60.us-east-2.compute.internal   node   True

Your cluster aws.agalue.net is ready
```

Or,

```bash
kubectl cluster-info
```

The output should be:

```text
Kubernetes master is running at https://api.aws.agalue.net
CoreDNS is running at https://api.aws.agalue.net/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy

To further debug and diagnose cluster problems, use 'kubectl cluster-info dump'.
```

## Install the Ingress Controller

This add-on is required in order to avoid having a LoadBalancer per external service.

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/nginx-0.30.0/deploy/static/mandatory.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/nginx-0.30.0/deploy/static/provider/aws/service-l4.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/nginx-0.30.0/deploy/static/provider/aws/patch-configmap-l4.yaml
```

## Install the CertManager

The [cert-manager](https://cert-manager.readthedocs.io/en/latest/) add-on is required in order to provide HTTP/TLS support through [LetsEncrypt](https://letsencrypt.org) to the HTTP services managed by the ingress controller.

```bash
kubectl create namespace cert-manager
kubectl apply --validate=false -f https://github.com/jetstack/cert-manager/releases/download/v0.13.1/cert-manager.yaml
```

> NOTE: For more details, check the [installation guide](http://docs.cert-manager.io/en/latest/getting-started/install.html).

## Install Jaeger Tracing CRDs.

```bash
kubectl apply -f https://raw.githubusercontent.com/jaegertracing/jaeger-operator/master/deploy/crds/jaegertracing.io_jaegers_crd.yaml
```

## Security Groups

When configuring Kafka, the `hostPort` is used in order to configure the `advertised.listeners` using the EC2 public FQDN. For this reason the external port (i.e. `9094`) should be opened on the security group called `nodes.aws.agalue.net`. Certainly, this can be done manually, but a `Terraform` recipe has been used for this purpose (check `update-security-groups.tf` for more details).

Make sure `terraform` it installed on your system, and then execute the following:

```bash
export DOMAIN_NAME="aws.agalue.net"
export AWS_REGION="us-east-2"

pushd kops
terraform init
terraform apply -var "region=$AWS_REGION" -var "domain=$DOMAIN_NAME" -auto-approve
popd
```

> NOTE: it is possible to pass additional security groups when creating the cluster through `kops`, but that requires to pre-create those security group.

## Manifets

To apply all the manifests:

```bash
kubectl apply -k manifests
```

If you're not running `kubectl` version 1.14, the following is an alternative:

```bash
kustomize build manifests | kubectl apply -f
```

> The main [README](README.md) offers a way to initialize an external Minion that points to this solution for testing purposes.

## Install Jaeger Tracing

```bash
kubectl apply -n opennms -f https://raw.githubusercontent.com/jaegertracing/jaeger-operator/master/deploy/service_account.yaml
kubectl apply -n opennms -f https://raw.githubusercontent.com/jaegertracing/jaeger-operator/master/deploy/role.yaml
kubectl apply -n opennms -f https://raw.githubusercontent.com/jaegertracing/jaeger-operator/master/deploy/role_binding.yaml
kubectl apply -n opennms -f https://raw.githubusercontent.com/jaegertracing/jaeger-operator/master/deploy/operator.yaml
```

## Cleanup

To remove the Kubernetes cluster, do the following:

```bash
export KOPS_CLUSTER_NAME="aws.agalue.net"
export KOPS_STATE_STORE="s3://$KOPS_CLUSTER_NAME"

kubectl delete ingress ingress-rules --namespace opennms
kubectl delete service ext-kafka --namespace opennms
sleep 10
kops delete cluster --yes
```

The first 2 commands will trigger the removal of the Route 53 entries associated with the ingresses and the Kafka ELB. The last will take care of the rest (including the PVCs).
