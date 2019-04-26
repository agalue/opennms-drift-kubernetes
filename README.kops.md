# Setup Cluster with KOPS

## Requirements

* Install the [AWS CLI](https://aws.amazon.com/cli/)
* Have your AWS account configured on your system (`~/.aws/credentials`)
* Install the [kops](https://github.com/kubernetes/kops/blob/master/docs/install.md) binary
* Install the [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/) binary
* Install the [terraform](https://www.terraform.io) binary [Optional. See security groups]

## Cluster Configuration

Create DNS sub-domain on [Route 53](https://console.aws.amazon.com/route53/home), and make sure it works prior start the cluster; for example:

```bash
dig ns k8s.opennms.org
```

The output should look like this:

```text
; <<>> DiG 9.10.6 <<>> ns k8s.opennms.org
;; global options: +cmd
;; Got answer:
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 42795
;; flags: qr rd ra; QUERY: 1, ANSWER: 4, AUTHORITY: 0, ADDITIONAL: 1

;; OPT PSEUDOSECTION:
; EDNS: version: 0, flags:; udp: 4096
;; QUESTION SECTION:
;k8s.opennms.org.		IN	NS

;; ANSWER SECTION:
k8s.opennms.org.	21478	IN	NS	ns-402.awsdns-50.com.
k8s.opennms.org.	21478	IN	NS	ns-927.awsdns-51.net.
k8s.opennms.org.	21478	IN	NS	ns-1146.awsdns-15.org.
k8s.opennms.org.	21478	IN	NS	ns-1922.awsdns-48.co.uk.

;; Query time: 31 msec
;; SERVER: 172.20.1.9#53(172.20.1.9)
;; WHEN: Mon Jul 16 10:29:19 EDT 2018
;; MSG SIZE  rcvd: 181
```

Create an S3 bucket to hold the `kops` configuration; for example:

```bash
aws s3api create-bucket \
  --bucket k8s.opennms.org \
  --create-bucket-configuration LocationConstraint=us-east-2

aws s3api put-bucket-versioning \
  --bucket k8s.opennms.org \
  --versioning-configuration Status=Enabled
```

Create the Kubernetes cluster using `kops`. The following example creates a cluster with 1 master node and 5 worker nodes on a single Availability Zone using the Hosted Zone `k8s.opennms.org`, and the S3 bucked created above:

```bash
export KOPS_CLUSTER_NAME="k8s.opennms.org"
export KOPS_STATE_STORE="s3://$KOPS_CLUSTER_NAME"
kops create cluster \
  --dns-zone $KOPS_CLUSTER_NAME \
  --master-size t2.medium \
  --master-count 1 \
  --master-zones us-east-2a \
  --node-size t2.2xlarge \
  --node-count 5 \
  --zones us-east-2a \
  --cloud-labels Environment=Test,Department=Support \
  --kubernetes-version 1.11.9 \
  --networking calico
```

> **IMPORTANT: Remember to change the settings to reflect your desired environment.**

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

While on edit mode, instruct `kops` to use `CoreDNS` instead, by adding:

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
Validating cluster k8s.opennms.org

INSTANCE GROUPS
NAME			ROLE	MACHINETYPE	MIN	MAX	SUBNETS
master-us-east-2a	Master	t2.medium	1	1	us-east-2a
nodes			Node	t2.2xlarge	5	5	us-east-2a

NODE STATUS
NAME						ROLE	READY
ip-172-20-37-147.us-east-2.compute.internal	node	True
ip-172-20-40-60.us-east-2.compute.internal	node	True
ip-172-20-46-131.us-east-2.compute.internal	node	True
ip-172-20-48-40.us-east-2.compute.internal	node	True
ip-172-20-53-105.us-east-2.compute.internal	master	True
ip-172-20-63-49.us-east-2.compute.internal	node	True

Your cluster k8s.opennms.org is ready
```

Or,

```bash
kubectl cluster-info
```

The output should be:

```text
Kubernetes master is running at https://api.k8s.opennms.org
CoreDNS is running at https://api.k8s.opennms.org/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy

To further debug and diagnose cluster problems, use 'kubectl cluster-info dump'.
```

## Security Groups

When configuring Kafka, the `hostPort` is used in order to configure the `advertised.listeners` using the EC2 public FQDN. For this reason the external port (i.e. `9094`) should be opened on the security group called `nodes.k8s.opennms.org`. Certainly, this can be done manually, but a `Terraform` recipe has been used for this purpose (check `update-security-groups.tf` for more details).

Make sure `terraform` it installed on your system, and then execute the following:

```bash
terraform init
terraform apply -auto-approve
```

> NOTE: it is possible to pass additional security groups when creating the cluster through `kops`, but that requires to pre-create those security group.

## Install the NGinx Ingress Controller

This add-on is required in order to avoid having a LoadBalancer per external service.

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/kops/master/addons/ingress-nginx/v1.6.0.yaml
```

## Install the CertManager

The [cert-manager](https://cert-manager.readthedocs.io/en/latest/) add-on is required in order to provide HTTP/TLS support through [LetsEncrypt](https://letsencrypt.org) to the HTTP services managed by the ingress controller.

```bash
kubectl create namespace cert-manager
kubectl label namespace cert-manager certmanager.k8s.io/disable-validation=true
kubectl apply --validate=false -f https://raw.githubusercontent.com/jetstack/cert-manager/release-0.7/deploy/manifests/cert-manager.yaml
```

> NOTE: For more details, check the [installation guide](http://docs.cert-manager.io/en/latest/getting-started/install.html).

## Manifets

Go back to the main [README](README.md) and follow the steps to configure OpenNMS and the dependencies.

## Optional Kubernetes Addons

Click [here](https://github.com/kubernetes/kops/blob/master/docs/addons.md) for more information.

### Dashboard

To install the dashboard:

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/kops/master/addons/kubernetes-dashboard/v1.10.1.yaml
```

To provide access to the dashboard, apply the following YAML:

```yaml
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: kubernetes-dashboard
  labels:
    k8s-app: kubernetes-dashboard
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: kubernetes-dashboard
  namespace: kube-system
```

To get the password of the `admin` account for the dashboard:

```bash
kops get secrets kube --type secret -oplaintext --state s3://k8s.opennms.org
```

Or,

```bash
kubectl config view --minify
```

### Heapster

To install the standalone Heapster monitoring (required for the `kubectl top` command):

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/kops/master/addons/monitoring-standalone/v1.11.0.yaml
```

### Prometheus

To install Prometheus Operator for monitoring:

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/kops/master/addons/prometheus-operator/v0.26.0.yaml
```

Click [here](https://github.com/coreos/prometheus-operator/blob/master/contrib/kube-prometheus/README.md) for more information.

## Cleanup

To remove the Kubernetes cluster, do the following:

```bash
kubectl delete ingress ingress-rules --namespace opennms
kubectl delete service ext-kafka --namespace opennms
kops delete cluster --name k8s.opennms.org --state s3://k8s.opennms.org --yes
```

The first 2 will trigger the removal of the Route 53 CNAMEs associated with the ingresses and the Kafka ELB. The last will take care of the rest (including the PVCs).
