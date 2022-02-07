# Setup Cluster with EKS

## Requirements

* Install the [AWS CLI](https://aws.amazon.com/cli/).
* Have your AWS account (IAM Credentials) configured on your system (`~/.aws/credentials`).
* Install the [eksctl](https://eksctl.io/) binary.

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

Create the Kubernetes cluster using `eksctl`. The following example creates a cluster with 1 master node and 6 worker nodes:

```bash
eksctl create cluster \
  --version 1.21 \
  --name opennms \
  --region us-east-2 \
  --nodegroup-name onms-fleet \
  --node-type t2.2xlarge \
  --nodes 5 \
  --tags Environment=Test,Department=Support,Owner=$USER \
  --ssh-access \
  --external-dns-access \
  --alb-ingress-access
```

> **WARNING**: Ensure you have enough quota on your AWS account to create all the resources. Be aware that trial accounts cannot request quota changes. If you need further limitations, use any of the `reduced` folder as inspiration, and create a copy of it with your desired settings. The minimal version is what `minikube` would use.

The creation process takes between 15 to 20 minutes to complete. The above command will finish when the cluster is ready.

To check if the cluster is active:

```bash
eksctl get cluster opennms
```

The output should be something like this:

```text
NAME	VERSION	STATUS	CREATED			VPC			SUBNETS											SECURITYGROUPS
opennms	1.21	ACTIVE	2021-04-09T14:37:49Z	vpc-05d7ebb8980713546	subnet-03a49abe804f21824,subnet-061e35b67b4145175,subnet-09a51b0ac396718b2,subnet-0c03c7719d44f4965,subnet-0d6ff4b413595c583,subnet-0e1d1a5389d459b1c	sg-063005b91330b51c1
```

Then,

```bash
kubectl cluster-info
```

The output should be something like this:

```text
Kubernetes control plane is running at https://B2C36A1FCD670EE2477BCB54C7F118F2.yl4.us-east-2.eks.amazonaws.com
CoreDNS is running at https://B2C36A1FCD670EE2477BCB54C7F118F2.yl4.us-east-2.eks.amazonaws.com/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy

To further debug and diagnose cluster problems, use 'kubectl cluster-info dump'.
```

## Install the Ingress Controller

This add-on is required to avoid having a Load Balancer per external service.

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/static/provider/aws/deploy.yaml
```

For Route53 mapping:

 ```bash
export DOMAIN=aws.agalue.net
export OWNER=agalue

curl https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/examples/external-dns.yaml 2>/dev/null | sed "s/--domain-filter=.*/--domain-filter=$DOMAIN/" | sed "s/--txt-owner-id=.*/--txt-owner-id=$OWNER/" | kubectl apply -f -
```

> **WARNING**: Please use your own domain.

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

To apply all the manifests:

```bash
kubectl apply -k manifests
```

## Cleanup

To delete the Kubernetes cluster, do the following:

```bash
kubectl delete ingress grpc-ingress --namespace opennms
kubectl delete ingress onms-ingress --namespace opennms
sleep 10
eksctl delete cluster --name opennms --region us-east-2 --wait
```

The first 2 commands will trigger the removal of the Route 53 entries associated with the ingresses. The last will take care of the rest.

However, EBS volumes associated with PVCs might not be removed. In tha case you could do:

```bash
volumes=($(aws ec2 describe-volumes --filters 'Name=tag:Name,Values=kubernetes-dynamic*'  --query 'Volumes[*].VolumeId' --output text))

for v in ${volumes[@]}; do aws ec2 delete-volume --volume-id $v --output text; done
```

This process could take on average between 10 to 15 minutes to complete. If waiting is not feasible, remove `--wait` from the last command.
