# OpenNMS Drift in Kubernetes

OpenNMS Drift deployment in [Kubernetes](https://kubernetes.io/) through [Kops](https://github.com/kubernetes/kops) and [AWS](https://aws.amazon.com/).

This is basically the `Kubernetes` version of my work done [here](https://github.com/OpenNMS/opennms-drift-aws/tree/release/horizon-23). For learning purposes, I'm avodiong `Helm` charts and `operators` for this solution. Maybe I'll write one re-using existing solutions in the future.

Instead of using discrete EC2 instances, this repository explains how to deploy basically the same solution with `Kubernetes`.

`Kafka` uses the `hostPort` feature to expose the advertise external listeners on port 9094, so applications outside `Kubernetes` like `Minion` can access it. For this reason, `Kafka` can be scaled up to the number of worker nodes on the `Kubernetes` cluster.

## Requirements

* Have your AWS account configured on your system (`~/.aws/credentials`)
* Install the [kops](https://github.com/kubernetes/kops/blob/master/docs/install.md) binary
* Install the [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/) binary
* Install the [AWS CLI](https://aws.amazon.com/cli/)
* Install the [terraform](https://www.terraform.io) binary [Optional. See security groups]

## Cluster Configuration

Create DNS sub-domain on [Route 53](https://console.aws.amazon.com/route53/home), and make sure it works prior start the cluster; for example:

```shell
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

```shell
aws s3api create-bucket \
  --bucket k8s.opennms.org \
  --create-bucket-configuration LocationConstraint=us-east-2

aws s3api put-bucket-versioning \
  --bucket k8s.opennms.org \
  --versioning-configuration Status=Enabled
```

Create the Kubernetes cluster using `kops`. The following example creates a cluster with 1 master node and 5 worker nodes on a single Availability Zone using the Hosted Zone `k8s.opennms.org`:

```shell
kops create cluster \
  --name k8s.opennms.org \
  --state s3://k8s.opennms.org \
  --dns-zone k8s.opennms.org \
  --master-size t2.medium \
  --master-count 1 \
  --master-zones us-east-2a \
  --node-size t2.2xlarge \
  --node-count 5 \
  --zones us-east-2a \
  --cloud-labels Environment=Test,Department=Support \
  --kubernetes-version 1.11.7 \
  --networking calico
```

> **IMPORTANT: Remember to change the settings to reflect your desired environment.**

Then, you should edit the cluster configuration to enable creating Route 53 entries for Ingress hosts:

```shell
kops edit cluster k8s.opennms.org --state s3://k8s.opennms.org
```

Then, add:

```yaml
spec:
  externalDns:
    watchIngress: true
```

While you're on edit mode, if you're interested on using `CoreDNS` instead, you can add:

```yaml
spec:
  kubeDNS:
    provider: CoreDNS
```

Finally, apply the changes to create the cluster:

```shell
kops update cluster k8s.opennms.org --state s3://k8s.opennms.org --yes
```

It takes a few minutes to have the cluster ready. Verify the cluster statue using `kubectl` and `kops`:

```shell
kops validate cluster --name k8s.opennms.org --state s3://k8s.opennms.org
```

The output should be:

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

```shell
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

Make sure you have it installed on your system, and then execute the following:

```shell
terraform init
terraform apply -auto-approve
```

> NOTE: it is possible to pass additional security groups when creating the cluster through `kops`, but that requires to pre-create the securigy group.

## Deployment

As a side note, instead of providing the namespace for all the kubectl commands every single time, you can make the `opennms` namespace as the default one, by running the following command:

```shell
kubectl config set-context $(kubectl config current-context) --namespace=opennms
```

### Plugins/Controllers

#### Install the NGinx Ingress Controller

This add-on is required in order to avoid having a LoadBalancer per external service.

```shell
kubectl apply -f https://raw.githubusercontent.com/kubernetes/kops/master/addons/ingress-nginx/v1.6.0.yaml
```

#### Install the CertManager

This add-on is required in order to provide HTTP/TLS support through LetsEncrypt to the HTTP services managed by the ingress controller.

```shell
kubectl create namespace cert-manager
kubectl label namespace cert-manager certmanager.k8s.io/disable-validation=true
kubectl apply -f https://raw.githubusercontent.com/jetstack/cert-manager/release-0.6/deploy/manifests/00-crds.yaml
kubectl apply -f https://raw.githubusercontent.com/jetstack/cert-manager/release-0.6/deploy/manifests/cert-manager.yaml --validate=false
```

> NOTE: For troubleshooting, check the [installation guide](http://docs.cert-manager.io/en/latest/getting-started/install.html).

### Namespace

From the directory on which this repository has been checked out:

```shell
kubectl apply -f ./namespace
```

This will additionally add some complementary RBAC permissions, in case there is a need of adding operators and/or administrators to the OpenNMS namespace.

### ConfigMaps/Secrets

#### ConfigMaps

From the directory on which this repository has been checked out:

```shell
kubectl create configmap opennms-config --from-file=config/ --namespace opennms --dry-run -o yaml | kubectl apply -f -
```

#### Secrets

Create a secret object for the passwords:

```shell
kubectl create secret generic onms-passwords \
 --from-literal POSTGRES=postgres \
 --from-literal OPENNMS_DB=opennms \
 --from-literal OPENNMS_UI_ADMIN=admin \
 --from-literal GRAFANA_UI_ADMIN=opennms \
 --from-literal ELASTICSEARCH=elastic \
 --from-literal KAFKA_MANAGER_APPLICATION_SECRET=opennms \
 --from-literal HASURA_GRAPHQL_ACCESS_KEY=0p3nNMS \
 --namespace opennms --dry-run -o yaml | kubectl apply -f -
```

Feel free to change them.

### Storage Classes

From the directory on which this repository has been checked out:

```shell
kubectl apply -f ./storage
```

Volumes for `StatefulSets` are going to be automatically created.

### Services, Deployments and StatefulSets

The applications will wait for their respective dependencies to be ready prior start (a feature implemented through `initContainers`), so there is no need to start them on a specific order.

From the directory on which this repository has been checked out:

```shell
kubectl apply -f ./manifests
```

Use the following to check whether or not all the resources have been created:

```shell
kubectl get all --namespace opennms
```

## Minion

This deployment already contains Minions inside the opennms namespace for monitoring devices within the cluster. In order to have Minions outside the Kubernetes cluster, they should use the following resources in order to connect to OpenNMS and the dependent applications:

* OpenNMS Core: `https://onms.k8s.opennms.org/opennms`
* Kafka: `kafka.k8s.opennms.org:9094`

For example, here is the minimum configuration (without flow listeners):

```shell
[root@onms-minion ~]# cat /opt/minion/etc/org.opennms.minion.controller.cfg
location=Apex
id=onms-minion.local
http-url=https://onms.k8s.opennms.org/opennms

[root@onms-minion ~]# cat /opt/minion/etc/org.opennms.core.ipc.sink.kafka.cfg
bootstrap.servers=kafka.k8s.opennms.org:9094
acks=1

[root@onms-minion ~]# cat /opt/minion/etc/org.opennms.core.ipc.rpc.kafka.cfg
bootstrap.servers=kafka.k8s.opennms.org:9094
acks=1

[root@onms-minion ~]# cat /opt/minion/etc/featuresBoot.d/kafka.boot
!opennms-core-ipc-sink-camel
!opennms-core-ipc-rpc-jms
opennms-core-ipc-sink-kafka
opennms-core-ipc-rpc-kafka
```

With Docker:

```shell
docker run -it --name minion \
 -e MINION_ID=docker-minion-1 \
 -e MINION_LOCATION=Docker \
 -e OPENNMS_HTTP_URL=https://onms.k8s.opennms.org/opennms \
 -e OPENNMS_HTTP_USER=admin \
 -e OPENNMS_HTTP_PASS=admin \
 -e KAFKA_RPC_ACKS=1 \
 -e KAFKA_RPC_BOOTSTRAP_SERVERS=kafka.k8s.opennms.org:9094 \
 -e KAFKA_SINK_BOOTSTRAP_SERVERS=kafka.k8s.opennms.org:9094 \
 -p 8201:8201 \
 -p 1514:1514 \
 -p 1162:1162 \
 --sysctl "net.ipv4.ping_group_range=0 429496729" \
 agalue/minion:23.0.2-oracle-jdk8u201 -c
```

> IMPORTANT: Make sure to use the same version as OpenNMS. If the `INSTANCE_ID` inside the OpenNMS YAML file or the Minion YAML file is different than the default (i.e. OpenNMS), the above won't work unless the property `org.opennms.instance.id` is added to the `system.properties` file.

> NOTE: Make sure to use your own Domain, and use the same version tag as OpenNMS.

> NOTE: The above samples are not including information about the Flow listeners. Check the [Minion's config](config/onms-minion-init.sh) for more details.

## Users

* OpenNMS Core: `https://onms.k8s.opennms.org/opennms` (for administrative tasks)
* OpenNMS UI: `https://onmsui.k8s.opennms.org/opennms` (for users/operators)
* Grafana: `https://grafana.k8s.opennms.org/`
* Kibana: `https://kibana.k8s.opennms.org/` (remember to enable monitoring)
* Kafka Manager: `https://kaffa-manager.k8s.opennms.org/` (make sure to register the cluster using `zookeeper.opennms.svc.cluster.local:2181/kafka` for the "Cluster Zookeeper Hosts")
* Hasura GraphQL API: `https://hasura.k8s.opennms.org/v1alpha1/graphql`
* Hasura GraphQL Console: `https://hasura.k8s.opennms.org/console`

> NOTE: Make sure to use your own Domain ;)

## Optional Kubernetes Addons

Click [here](https://github.com/kubernetes/kops/blob/master/docs/addons.md) for more information.

### Dashboard

To install the dashboard:

```shell
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

```shell
kops get secrets kube --type secret -oplaintext --state s3://k8s.opennms.org
```

Or,

```shell
kubectl config view --minify
```

### Heapster

To install the standalone Heapster monitoring (required for the `kubectl top` command):

```shell
kubectl apply -f https://raw.githubusercontent.com/kubernetes/kops/master/addons/monitoring-standalone/v1.11.0.yaml
```

### Prometheus

To install Prometheus Operator for monitoring:

```shell
kubectl apply -f https://raw.githubusercontent.com/kubernetes/kops/master/addons/prometheus-operator/v0.26.0.yaml
```

Click [here](https://github.com/coreos/prometheus-operator/blob/master/contrib/kube-prometheus/README.md) for more information.

## Cleanup

To remove the Kubernetes cluster, do the following:

```shell
kubectl delete ingress ingress-rules --namespace opennms
kubectl delete service  ext-kafka --namespace opennms
kops delete cluster --name k8s.opennms.org --state s3://k8s.opennms.org --yes
```

The first 2 will trigger the removal of the Route 53 CNAMEs associated with the ingresses and the Kafka ELB. The last will take care of the rest (including the PVCs).

## Future Enhancements

* Add SSL encryption with SASL Authentication for external Kafka (for Minions outside K8S/AWS). The challenge here is which FQDN will be taken in consideration for the certificates.
* Add [Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/) to control the communication between components (for example, only OpenNMS needs access to PostgreSQL and Cassandra; other component should not access those resources). A network manager like [Calico](https://www.projectcalico.org) is required.
* Design a solution to manage OpenNMS Configuration files (the `/opt/opennms/etc` directory), or use an existing one like [ksync](https://vapor-ware.github.io/ksync/).
* Investigate how to provide support for `HorizontalPodAutoscaler` for the data clusters like Cassandra, Kafka and Elasticsearch. Check [here](https://github.com/kubernetes/kops/blob/master/docs/horizontal_pod_autoscaling.md) for more information. Although, using operators seems more feasible in this regard, due to the complexities when expanding/shrinking these kind of applications.
* Add support for Cluster Autoscaler. Check what `kops` offers on this regard.
* Add support for monitoring through [Prometheus](https://prometheus.io) using [Prometheus Operator](https://coreos.com/operators/prometheus/docs/latest/). Expose the UI (including Grafana) through the Ingress controller.
* Expose the Kubernetes Dashboard through the Ingress controller.
* Design a solution to handle scale down of Cassandra and decommission of nodes; or investigate the existing operators.
* Explore a `PostgreSQL` solution like [Spilo/Patroni](https://patroni.readthedocs.io/en/latest/) using their [Postgres Operator](https://postgres-operator.readthedocs.io/en/latest/), to understand how to build a HA Postgres within K8s. Alternatively, we might consider the [Crunchy Data Operator](https://crunchydata.github.io/postgres-operator/stable/)
* Add a sidecar container on PostgreSQL using [hasura](https://hasura.io) to expose the DB schema through GraphQL. If a Postgres Operator is used, Hasura can be managed through a deployment instead.
* Explore a `Kafka` solution like [Strimzi](https://strimzi.io/), an operator that supports encryption and authentication.
* Build a VPC with the additional security groups using Terraform. Then, use `--vpc` and `--node-security-groups` when calling `kops create cluster`, as explained [here](https://github.com/kubernetes/kops/blob/master/docs/run_in_existing_vpc.md).
* Explore [Helm](https://helm.sh), and potentially add support for it.
