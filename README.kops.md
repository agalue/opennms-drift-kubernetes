# Setup Cluster with kOps

## Requirements

* Install the [AWS CLI](https://aws.amazon.com/cli/).
* Have your AWS account (IAM Credentials) configured on your system (`~/.aws/credentials`).
* Install the [kOps](https://github.com/kubernetes/kops/blob/master/docs/install.md) binary; version 1.20.x or newer recommended.

> **WARNING:** Please note that all the manifests were verified for Kubernetes 1.21 or newer. If you're going to use and older version, please adjust the API versions of the manifests for `CronJobs` in [elasticsearch.curator.yaml](manifests/elasticsearch.curator.yaml), `PodDisruptionBudget` in [zookeeper.yaml](manifests/zookeeper.yaml), and `Ingress` in [external-access.yaml](manifests/external-access.yaml).

## DNS Configuration

Create DNS sub-domain on [Route 53](https://console.aws.amazon.com/route53/home), register it as an `NS` entry on your registrar matching the name servers from the sub-domain, and make sure it works before starting the cluster; for example:

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

This is required so the Ingress Controller and CertManager can use custom FQDNs for all the different services.

## Cluster Creation

Create an S3 bucket to hold the `kOps` configuration; for example:

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

Create the Kubernetes cluster using `kOps`. The following example creates a cluster with 1 master node and 5 worker nodes on a single Availability Zone using the Hosted Zone `aws.agalue.net`, and the S3 bucked created above:

```bash
export KOPS_CLUSTER_NAME="aws.agalue.net"
export KOPS_STATE_STORE="s3://$KOPS_CLUSTER_NAME"

kops create cluster \
  --cloud aws \
  --cloud-labels Environment=Test,Department=Support,Owner=$USER \
  --dns-zone $KOPS_CLUSTER_NAME \
  --master-size t2.large \
  --master-count 1 \
  --master-zones us-east-2a \
  --node-size t2.2xlarge \
  --node-count 5 \
  --zones us-east-2a \
  --networking calico
```

> **IMPORTANT:** Remember to change the settings to reflect your desired environment.

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

While on edit mode, optionally, enable `CoreDNS` instead of `KubeDNS` (the default) by adding:

```yaml
spec:
  kubeDNS:
    provider: CoreDNS
```

Optionally, if there is a need for having `metrics-server` running, add the following under the `kubelet` section:

```yaml
spec:
...
  kubelet:
    anonymousAuth: false
    authorizationMode: Webhook
    authenticationTokenWebhook: true
```

Finally, apply the changes to create the cluster:

```bash
kops update cluster --yes
```

The creation process takes between 10 to 15 minutes to complete. You can verify the status using `kubectl` and `kops`:

```bash
kops validate cluster --wait 10m
```

The output should be something like this (when it is ready):

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

If you have issues, execute the following and then try again:

```
kops export kubecfg --admin
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

This add-on is required to avoid having a Load Balancer per external service.

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/static/provider/aws/deploy.yaml
```

## Install the CertManager

The [cert-manager](https://cert-manager.readthedocs.io/en/latest/) add-on is required to provide HTTPS/TLS support through [LetsEncrypt](https://letsencrypt.org) to the web-based services managed by the ingress controller.

```bash
CMVER=$(curl -s https://api.github.com/repos/jetstack/cert-manager/releases/latest | grep tag_name | cut -d '"' -f 4)
kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/$CMVER/cert-manager.yaml
```

> NOTE: For more details, check the [installation guide](http://docs.cert-manager.io/en/latest/getting-started/install.html).

## Install Jaeger Tracing CRDs.

```bash
kubectl apply -f https://raw.githubusercontent.com/jaegertracing/jaeger-operator/master/deploy/crds/jaegertracing.io_jaegers_crd.yaml
```

## Manifets

Make sure all the operators are up and running. Then, to apply all the manifests:

```bash
kubectl apply -k manifests
```

> The main [README](README.md) offers a way to initialize an external Minion that points to this solution for testing purposes.

## Install Jaeger Tracing

This installs the Jaeger operator in the `opennms` namespace for tracing purposes.

```bash
kubectl apply -n opennms -f https://raw.githubusercontent.com/jaegertracing/jaeger-operator/master/deploy/service_account.yaml
kubectl apply -n opennms -f https://raw.githubusercontent.com/jaegertracing/jaeger-operator/master/deploy/role.yaml
kubectl apply -n opennms -f https://raw.githubusercontent.com/jaegertracing/jaeger-operator/master/deploy/role_binding.yaml
kubectl apply -n opennms -f https://raw.githubusercontent.com/jaegertracing/jaeger-operator/master/deploy/operator.yaml
```

# [Optional] Install Metrics Server

```bash
curl https://raw.githubusercontent.com/kubernetes/kops/master/addons/metrics-server/v1.8.x.yaml 2>/dev/null | sed 's|extensions/v1beta1|apps/v1|' | kubectl apply -f -
```

> With recent Kubernetes versions, deployments must use `apps/v1` (hence the patch).

## Cleanup

To delete the Kubernetes cluster, do the following:

```bash
export KOPS_CLUSTER_NAME="aws.agalue.net"
export KOPS_STATE_STORE="s3://$KOPS_CLUSTER_NAME"

kubectl delete ingress grpc-ingress --namespace opennms
kubectl delete ingress onms-ingress --namespace opennms
sleep 10
kops delete cluster --yes
```

The first 2 commands will trigger the removal of the Route 53 entries associated with the ingresses. The last will take care of the kubernetes resources (including the PVCs).
