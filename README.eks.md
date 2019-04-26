# Setup Cluster with EKS

> WARNING: This is a work in progress.

## Requirements

* Install the [AWS CLI](https://aws.amazon.com/cli/)
* Have your AWS account configured on your system (`~/.aws/credentials`)
* Install the [eksctl](https://eksctl.io/) binary
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

Create the Kubernetes cluster using `eksctl`. The following example creates a cluster with 1 master node and 5 worker nodes:

```bash
eksctl create cluster \
  --version 1.12 \
  --name opennms \
  --nodegroup-name opennms-fleet \
  --tags Environment=Test,Department=Support \
  --region us-east-2 \
  --node-type t2.2xlarge \
  --nodes 5 \
  --ssh-access \
  --external-dns-access \
  --alb-ingress-access \
  --auto-kubeconfig
```

Grab a cup of coffee, as this will take a while. The command will finish when the cluster is ready.

To check if the cluster is active:

```bash
eksctl get cluster opennms
```

The output should be something like this:

```text
NAME	VERSION	STATUS	CREATED			VPC			SUBNETS															SECURITYGROUPS
opennms	1.12	ACTIVE	2019-04-22T19:25:46Z	vpc-0410e512a21e4d8a2	subnet-070d4349396f1a05d,subnet-07480443483b51317,subnet-07848cf0983b1b86d,subnet-08a0417d7b0595cd7,subnet-09cd415e82652db14,subnet-0b9e3781fbb60f1cf	sg-06f9565eac82f1fba
```

Make the `kubeconfig` active:

```bash
eksctl utils write-kubeconfig opennms
```

Then,

```bash
kubectl cluster-info
```

The output should be something like this:

```text
Kubernetes master is running at https://06A5F9A6D38587A5B43F6B93DF2515C1.yl4.us-east-2.eks.amazonaws.com
CoreDNS is running at https://06A5F9A6D38587A5B43F6B93DF2515C1.yl4.us-east-2.eks.amazonaws.com/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy

To further debug and diagnose cluster problems, use 'kubectl cluster-info dump'.
```

## Security Groups

When configuring Kafka, the `hostPort` is used in order to configure the `advertised.listeners` using the EC2 public FQDN. For this reason the external port (i.e. `9094`) should be opened on the security group called `eksctl-opennms-cluster/ClusterSharedNodeSecurityGroup`. Certainly, this can be done manually, but a `Terraform` recipe has been used for this purpose (check `update-security-groups.tf` for more details).

Make sure `terraform` it installed on your system, and then execute the following:

```bash
terraform init
terraform apply -auto-approve
```

> NOTE: it is possible to pass additional security groups when creating the cluster through `kops`, but that requires to pre-create those security group.

## ALB Ingress Controller

This add-on is required in order to avoid having a LoadBalancer per external service.

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/aws-alb-ingress-controller/v1.1.0/docs/examples/rbac-role.yaml
curl https://raw.githubusercontent.com/kubernetes-sigs/aws-alb-ingress-controller/v1.1.0/docs/examples/alb-ingress-controller.yaml 2>/dev/null | sed 's/devCluster/opennms/' | kubectl apply -f -
```

For Route53 mapping:

```bash
DOMAIN=k8s.opennms.org
OWNER=agalue
curl https://raw.githubusercontent.com/kubernetes-sigs/aws-alb-ingress-controller/v1.1.0/docs/examples/external-dns.yaml 2>/dev/null | sed "s/--domain-filter=.*/--domain-filter=$DOMAIN" | sed "s/--txt-owner-id=.*/--txt-owner-id=$OWNER/" | kubectl apply -f -
```

## Cert-Manager

```bash
kubectl create namespace cert-manager
kubectl label namespace cert-manager certmanager.k8s.io/disable-validation=true
kubectl apply --validate=false -f https://raw.githubusercontent.com/jetstack/cert-manager/release-0.7/deploy/manifests/cert-manager.yaml
```

## Manifets

A change is required on `manifests/external-access.yaml`, in order to use the `ALB Ingress`:

```diff
diff --git a/manifests/external-access.yaml b/manifests/external-access.yaml
index 53eb9da..287bb2d 100644
--- a/manifests/external-access.yaml
+++ b/manifests/external-access.yaml
@@ -30,10 +30,10 @@ metadata:
   labels:
     deployment: drift
   annotations:
-    kubernetes.io/ingress.class: nginx
+    kubernetes.io/ingress.class: alb
     certmanager.k8s.io/cluster-issuer: letsencrypt-prod
     certmanager.k8s.io/acme-http01-edit-in-place: 'true'
-    nginx.ingress.kubernetes.io/ssl-redirect: 'true'
+    alb.ingress.kubernetes.io/scheme: internet-facing
 spec:
   tls:
     - secretName: k8s-opennms-org-ingress
@@ -111,7 +111,7 @@ metadata:
     app: kafka
     deployment: drift
   annotations:
-    dns.alpha.kubernetes.io/external: kafka.k8s.opennms.org.
+    external-dns.alpha.kubernetes.io/hostname: kafka.k8s.opennms.org.
 spec:
   type: LoadBalancer
   ports:
```

A patch file with the above content was create at [eks-patch.diff](eks-patch.diff).

Go back to the main [README](README.md) and follow the steps to configure OpenNMS and the dependencies.

Go back to the main `README` and follow the steps to configure OpenNMS and the dependencies.

## Cleanup

To remove the Kubernetes cluster, do the following:

```bash
kubectl delete ingress ingress-rules --namespace opennms
kubectl delete service ext-kafka --namespace opennms
eksctl delete cluster --name opennms --region us-east-2 --wait
```

The first 2 will trigger the removal of the Route 53 CNAMEs associated with the ingresses and the Kafka ELB. The last will take care of the rest (including the PVCs).

Grab another cup of coffee, as this will also take a while. The command will finish when the cluster is completely removed. If wait is not feasible, remove `--wait` from the command.

## TODO

* Verify that everything works, including the Ingress Controller with Cert-Manager.