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
KubeDNS is running at https://api.k8s.opennms.org/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy

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
kubectl apply -f https://raw.githubusercontent.com/jetstack/cert-manager/release-0.6/deploy/manifests/cert-manager.yaml
```

> NOTE: For troubleshooting, check the [installation guide](https://cert-manager.readthedocs.io/en/latest/getting-started/2-installing.html#with-static-manifests).

### Namespace

From the directory on which this repository has been checked out:

```shell
kubectl apply -f ./namespace
```

### ConfigMaps/Secrets

#### ConfigMaps

From the directory on which this repository has been checked out:

```shell
kubectl create configmap opennms-config --from-file=config/ --namespace opennms
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
 --from-literal KAFKA_MANAGER_USERNAME=admin \
 --from-literal KAFKA_MANAGER_PASSWORD=opennms \
 --namespace opennms
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

After a while, you should be able to see this:

```shell
➜  kubectl get all --namespace opennms
NAME                                 READY   STATUS      RESTARTS   AGE
pod/cassandra-0                      1/1     Running     0          7m
pod/cassandra-1                      1/1     Running     0          6m
pod/cassandra-2                      1/1     Running     0          4m
pod/esdata-0                         1/1     Running     0          7m
pod/esdata-1                         1/1     Running     0          5m
pod/esdata-2                         1/1     Running     0          4m
pod/esmaster-0                       1/1     Running     0          7m
pod/esmaster-1                       1/1     Running     0          7m
pod/esmaster-2                       1/1     Running     0          7m
pod/grafana-77dccf7559-drqnz         1/1     Running     0          7m
pod/grafana-77dccf7559-lxb8l         1/1     Running     0          7m
pod/helm-init-qlzb7                  0/1     Completed   0          7m
pod/kafka-0                          1/1     Running     0          7m
pod/kafka-1                          1/1     Running     0          5m
pod/kafka-2                          1/1     Running     0          4m
pod/kafka-manager-68d7b4d664-g4dpv   1/1     Running     0          7m
pod/kibana-6b495f6c9b-h7jqt          1/1     Running     0          7m
pod/minion-0                         1/1     Running     0          1m
pod/minion-1                         1/1     Running     0          1m
pod/onms-0                           1/1     Running     0          7m
pod/onms-ui-7648fd4fdb-vnq2b         1/1     Running     0          7m
pod/onms-ui-7648fd4fdb-z47br         1/1     Running     0          7m
pod/postgres-0                       1/1     Running     0          7m
pod/sentinel-684c6959b4-qtwk8        1/1     Running     0          7m
pod/sentinel-684c6959b4-sv6gj        1/1     Running     0          7m
pod/zk-0                             1/1     Running     0          7m
pod/zk-1                             1/1     Running     0          7m
pod/zk-2                             1/1     Running     0          7m

NAME                   TYPE           CLUSTER-IP       EXTERNAL-IP                                                              PORT(S)                               AGE
service/cassandra      ClusterIP      None             <none>                                                                   7000/TCP,7001/TCP,7199/TCP,9042/TCP   7m
service/esdata         ClusterIP      None             <none>                                                                   9200/TCP,9300/TCP                     7m
service/esmaster       ClusterIP      None             <none>                                                                   9200/TCP,9300/TCP                     7m
service/ext-kafka      LoadBalancer   100.66.151.114   a99afef5b14f211e99200024245e3dd7-837167553.us-east-2.elb.amazonaws.com   9094:31403/TCP                        7m
service/grafana        ClusterIP      None             <none>                                                                   3000/TCP                              7m
service/kafka          ClusterIP      None             <none>                                                                   9092/TCP,9094/TCP,9999/TCP            7m
service/kafka-manager  ClusterIP      None             <none>                                                                   9000/TCP                              7m
service/kibana         ClusterIP      None             <none>                                                                   5601/TCP                              7m
service/minion         ClusterIP      None             <none>                                                                   8201/TCP                              2m
service/opennms-core   ClusterIP      None             <none>                                                                   8980/TCP,8101/TCP                     7m
service/opennms-ui     ClusterIP      None             <none>                                                                   8980/TCP,8101/TCP                     7m
service/postgresql     ClusterIP      None             <none>                                                                   5432/TCP                              7m
service/zookeeper      ClusterIP      None             <none>                                                                   2888/TCP,3888/TCP,2181/TCP,9998/TCP   7m

NAME                            DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/grafana         2         2         2            2           7m
deployment.apps/kafka-manager   1         1         1            1           7m
deployment.apps/kibana          1         1         1            1           7m
deployment.apps/onms-ui         2         2         2            2           7m
deployment.apps/sentinel        2         2         2            2           7m

NAME                                       DESIRED   CURRENT   READY   AGE
replicaset.apps/grafana-77dccf7559         2         2         2       7m
replicaset.apps/kafka-manager-68d7b4d664   1         1         1       7m
replicaset.apps/kibana-6b495f6c9b          1         1         1       7m
replicaset.apps/onms-ui-7648fd4fdb         2         2         2       7m
replicaset.apps/sentinel-684c6959b4        2         2         2       7m

NAME                         DESIRED   CURRENT   AGE
statefulset.apps/cassandra   3         3         7m
statefulset.apps/esdata      3         3         7m
statefulset.apps/esmaster    3         3         7m
statefulset.apps/kafka       3         3         7m
statefulset.apps/minion      2         2         2m
statefulset.apps/onms        1         1         7m
statefulset.apps/postgres    1         1         7m
statefulset.apps/zk          3         3         7m

NAME                  DESIRED   SUCCESSFUL   AGE
job.batch/helm-init   1         1            7m
```

Ingress are not shown, but you could do:

```bash
➜  kubectl get ingress -n opennms
NAME            HOSTS                                                                                      ADDRESS                                                                   PORTS     AGE
ingress-rules   grafana.k8s.opennms.org,kafka-manager.k8s.opennms.org,kibana.k8s.opennms.org + 2 more...   a580a93fdc35211e8a26702c5612cb12-1869830019.us-east-2.elb.amazonaws.com   80        12m
```

## Minion

This deployment already contains Minions inside the opennms namespace for monitoring devices within the cluster. In order to have Minions outside the Kubernetes cluster, they should use the following resources in order to connect to OpenNMS and the dependent applications:

* OpenNMS Core: `https://onms.k8s.opennms.org/opennms`
* Kafka: `kafka.k8s.opennms.org:9094`

For example:

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

Here is a more detailed example using Docker:

```shell
docker run -it --name minion \
 -e MINION_ID=minion01 \
 -e MINION_LOCATION=Docker \
 -e OPENNMS_HTTP_URL=https://onms.k8s.opennms.org/opennms \
 -e OPENNMS_HTTP_USER=admin \
 -e OPENNMS_HTTP_PASS=admin \
 -e KAFKA_RPC_ACKS=1 \
 -e KAFKA_RPC_BOOTSTRAP_SERVERS=kafka.k8s.opennms.org:9094 \
 -e KAFKA_SINK_BOOTSTRAP_SERVERS=kafka.k8s.opennms.org:9094 \
 -p 8201:8201 \
 --sysctl "net.ipv4.ping_group_range=0 429496729" \
 opennms/minion:bleeding -f
```

> NOTE: Make sure to use your own Domain ;)

## Users

* OpenNMS UI: `https://onmsui.k8s.opennms.org/opennms`
* Grafana: `https://grafana.k8s.opennms.org/`
* Kibana: `https://kibana.k8s.opennms.org/`
* Kafka Manager: `https://kaffa-manager.k8s.opennms.org/`

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
kubectl delete all --all --namespace opennms --force --grace-period 0
kubectl delete pvc --all --namespace opennms
kubectl delete pv --all
kops delete cluster --name k8s.opennms.org --state s3://k8s.opennms.org --yes
```

If you're using add-ons, you might also need to manually remove those resources too, to guarantee that nothing left at AWS; for example:

```shell
kubectl delete all --all --namespace kube-ingress --force --grace-period 0
kubectl delete all --all --namespace monitoring --force --grace-period 0
```

## Future Enhancements

* Add SSL encryption with SASL Authentication for external Kafka (for Minions outside K8S/AWS)
* Add Network Policies to control the communication between components (for example, only OpenNMS needs access to PostgreSQL and Cassandra; other component should not access those resources). A network manager like Calico is required.
* Design a solution to handle scale down of Cassandra and decommission of nodes.
* Design a solution to manage OpenNMS Configuration files (the `/opt/opennms/etc` directory), or use an existing one like [ksync](https://vapor-ware.github.io/ksync/).
* Add support for `HorizontalPodAutoscaler` for the data clusters like Cassandra, Kafka and Elasticsearch. Make sure `heapster` is running.
* Add support for Cluster Autoscaler. Check what `kops` offers on this regard.
* Add support for monitoring through [Prometheus](https://prometheus.io) using [Prometheus Operator](https://coreos.com/operators/prometheus/docs/latest/). Expose the UI (including Grafana) through the Ingress controller.
* Expose the Kubernetes Dashboard through the Ingress controller.
* Explore a `PostgreSQL` solution like [Spilo/Patroni](https://patroni.readthedocs.io/en/latest/) using the [Postgres Operator](https://postgres-operator.readthedocs.io/en/latest/), to understand how to build a HA Postgres.
* Explore [Strimzi](https://strimzi.io/) an operator for Kafka that supports encryption and authentication.
* Explore [Kubeless](https://kubeless.io), or [Fission](https://fission.io), and use Kafka for trigger `serverless` apps based on alarms or events. Hint: I've found Fission more feature reach and works with modern versions of Kafka. On both cases, it is important to create a Kafka Stream application to convert from GPB to JSON the required data.
* Build a VPC with the additional security groups using Terraform. Then, use `--vpc` and `--node-security-groups` when calling `kops create cluster`, as explained [here](https://github.com/kubernetes/kops/blob/master/docs/run_in_existing_vpc.md).
* Explore [Helm](https://helm.sh), and potentially add support for it.
