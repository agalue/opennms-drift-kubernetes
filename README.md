# OpenNMS Drift in Kubernetes

OpenNMS Drift deployment in [Kubernetes](https://kubernetes.io/) through [Kops](https://github.com/kubernetes/kops) and [AWS](https://aws.amazon.com/).

This is basically the `Kubernetes` version of my work done [here](https://github.com/OpenNMS/opennms-drift-aws/tree/release/horizon-23). For learning purposes, I'm avodiong `Helm` charts and `operators` for this solution. Maybe I'll write one re-using existing solutions in the future.

Instead of using discrete EC2 instances, this repository explains how to deploy basically the same solution with `Kubernetes`.

`Kafka` uses the `hostPort` feature to expose the advertise external listeners on port 9094, so applications outside `Kubernetes` like `Minion` can access it. For this reason, `Kafka` can be scaled up to the number of worker nodes on the `Kubernetes` cluster.

## Requirements

* Install [kops](https://github.com/kubernetes/kops/blob/master/docs/install.md) (this environment has been tested with version `1.10.0`, but I can't find a reason why it would't work with `1.9.x`)
* Install [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)
* Install the [AWS CLI](https://aws.amazon.com/cli/)
* Install [terraform](https://www.terraform.io)
* Have your AWS account configured on your system (`~/.aws/credentials`)

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
  --zones us-east-2a \
  --master-size t2.medium \
  --master-count 1 \
  --node-size t2.2xlarge \
  --node-count 5 \
  --yes
```

> **IMPORTANT: Remember to change the settings to reflect your desired environment.**

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

## Deployment

Creation Order:

* Namespace
* ConfigMaps
* Storage Classes
* Volumes (if apply)
* Security Groups
* Services
* Deployments and StatefulSets

### Namespace

From the directory on which this repository has been checked out:

```shell
kubectl apply -f ./namespace
```

### Configuration Maps

From the directory on which this repository has been checked out:

```shell
kubectl create configmap opennms-core-overlay --from-file=config/opennms-core/ --namespace opennms
kubectl create configmap opennms-sentinel-overlay --from-file=config/opennms-sentinel/ --namespace opennms
kubectl create configmap opennms-ui-overlay --from-file=config/opennms-ui/ --namespace opennms
kubectl create configmap grafana --from-file=config/grafana/ --namespace opennms
```

### Storage Classes

From the directory on which this repository has been checked out:

```shell
kubectl apply -f ./storage
```

Volumes for `StatefulSets` are going to be automatically created.

### Security Groups

When configuring Kafka, the `hostPort` is used in order to configure the `advertised.listeners` using the EC2 public FQDN. For this reason the external port (i.e. `9094`) should be opened on the security group called `nodes.k8s.opennms.org`. Certainly, this can be done manually, but a [Terraform](https://www.terraform.io) recipe has been used for this purpose (`update-security-groups.tf).

Make sure you have it installed on your system, and then execute the following:

```shell
terraform init
terraform apply -auto-approve
```

> NOTE: it is possible to pass additional security groups when creating the cluster, but that requires to pre-create a VPC. An example for this might be added in the future.

### Services, Deployments and StatefulSets

The applications will wait for their respective dependencies to be ready prior start, so there is no need to start them on a specific order.

From the directory on which this repository has been checked out:

```shell
kubectl apply -f ./manifests
```

After a while, you should be able to see this:

```text
➜  kubectl get all --namespace opennms
NAME                                 READY     STATUS    RESTARTS   AGE
pod/cassandra-0                      1/1       Running   0          6m
pod/cassandra-1                      1/1       Running   0          6m
pod/cassandra-2                      1/1       Running   0          4m
pod/esdata-0                         1/1       Running   0          6m
pod/esdata-1                         1/1       Running   0          5m
pod/esdata-2                         1/1       Running   0          4m
pod/esmaster-0                       1/1       Running   0          6m
pod/esmaster-1                       1/1       Running   0          6m
pod/esmaster-2                       1/1       Running   0          6m
pod/grafana-5875cd6cb4-75h2j         1/1       Running   0          6m
pod/grafana-5875cd6cb4-ntthk         1/1       Running   0          6m
pod/kafka-0                          1/1       Running   0          6m
pod/kafka-1                          1/1       Running   0          5m
pod/kafka-2                          1/1       Running   0          4m
pod/kafka-manager-86c876b86d-x7bgw   1/1       Running   0          6m
pod/kibana-58cc68bdb6-xlh58          1/1       Running   0          6m
pod/onms-0                           1/1       Running   0          6m
pod/onms-ui-7c56f74975-2mjq7         0/1       Running   0          6m
pod/onms-ui-7c56f74975-jtzvx         1/1       Running   0          6m
pod/postgres-0                       1/1       Running   0          6m
pod/sentinel-5fbf86857d-ds6nj        1/1       Running   0          6m
pod/sentinel-5fbf86857d-f5lwl        1/1       Running   0          6m
pod/zk-0                             1/1       Running   0          6m
pod/zk-1                             1/1       Running   0          6m
pod/zk-2                             1/1       Running   0          6m

NAME                        TYPE           CLUSTER-IP       EXTERNAL-IP                                                               PORT(S)                      AGE
service/cassandra           ClusterIP      None             <none>                                                                    9042/TCP                     6m
service/esdata              ClusterIP      None             <none>                                                                    9200/TCP                     6m
service/esmaster            ClusterIP      None             <none>                                                                    9200/TCP                     6m
service/ext-grafana         LoadBalancer   100.69.214.165   aa988ea8f99ae11e8a0690240989dcf9-1502556027.us-east-2.elb.amazonaws.com   80:31375/TCP                 6m
service/ext-kafka           LoadBalancer   100.68.235.20    aa9bf858199ae11e8a0690240989dcf9-20371613.us-east-2.elb.amazonaws.com     9094:30844/TCP               6m
service/ext-kafka-manager   LoadBalancer   100.69.134.149   aa9a0282b99ae11e8a0690240989dcf9-734450708.us-east-2.elb.amazonaws.com    80:32134/TCP                 6m
service/ext-kibana          LoadBalancer   100.69.158.228   aa9e03cc599ae11e8a0690240989dcf9-13927087.us-east-2.elb.amazonaws.com     80:30315/TCP                 6m
service/ext-onms            LoadBalancer   100.67.218.34    aaa003ad099ae11e8a0690240989dcf9-351868183.us-east-2.elb.amazonaws.com    80:32252/TCP,22:31879/TCP    6m
service/ext-onms-ui         LoadBalancer   100.69.102.50    aaa2afbc099ae11e8a0690240989dcf9-972434993.us-east-2.elb.amazonaws.com    80:31742/TCP                 6m
service/grafana             ClusterIP      None             <none>                                                                    3000/TCP                     6m
service/kafka               ClusterIP      None             <none>                                                                    9092/TCP,9999/TCP            6m
service/kibana              ClusterIP      None             <none>                                                                    5601/TCP                     6m
service/opennms-core        ClusterIP      None             <none>                                                                    8980/TCP,8101/TCP            6m
service/opennms-ui          ClusterIP      None             <none>                                                                    8980/TCP,8101/TCP            6m
service/postgresql          ClusterIP      None             <none>                                                                    5432/TCP                     6m
service/zookeeper           ClusterIP      None             <none>                                                                    2888/TCP,3888/TCP,2181/TCP   6m

NAME                            DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/grafana         2         2         2            2           6m
deployment.apps/kafka-manager   1         1         1            1           6m
deployment.apps/kibana          1         1         1            1           6m
deployment.apps/onms-ui         2         2         2            1           6m
deployment.apps/sentinel        2         2         2            2           6m

NAME                                       DESIRED   CURRENT   READY     AGE
replicaset.apps/grafana-5875cd6cb4         2         2         2         6m
replicaset.apps/kafka-manager-86c876b86d   1         1         1         6m
replicaset.apps/kibana-58cc68bdb6          1         1         1         6m
replicaset.apps/onms-ui-7c56f74975         2         2         1         6m
replicaset.apps/sentinel-5fbf86857d        2         2         2         6m

NAME                         DESIRED   CURRENT   AGE
statefulset.apps/cassandra   3         3         6m
statefulset.apps/esdata      3         3         6m
statefulset.apps/esmaster    3         3         6m
statefulset.apps/kafka       3         3         6m
statefulset.apps/onms        1         1         6m
statefulset.apps/postgres    1         1         6m
statefulset.apps/zk          3         3         6m

NAME                  DESIRED   SUCCESSFUL   AGE
job.batch/helm-init   1         1            6m
```

## Minion

Your Minions should use the following resources in order to connect to OpenNMS and the dependept applications:

* OpenNMS Core: `http://onms.k8s.opennms.org/opennms`
* Kafka: `kafka.k8s.opennms.org:9094`

For example:

```shell
[root@onms-minion ~]# cat /opt/minion/etc/org.opennms.minion.controller.cfg 
location=Vagrant
id=onms-minion.local
http-url=http://onms.k8s.opennms.org/opennms

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

> NOTE: Make sure to use your own Domain ;)

## Users

* OpenNMS UI: `http://onmsui.k8s.opennms.org/opennms`
* Grafana: `http://grafana.k8s.opennms.org/`
* Kibana: `http://kibana.k8s.opennms.org/`
* Kafka Manager: `http://kaffa-manager.k8s.opennms.org/`

> NOTE: Make sure to use your own Domain ;)

## Optional Kubernetes Addons

To install the  Dashboard:

```shell
kubectl apply -f https://raw.githubusercontent.com/kubernetes/kops/master/addons/kubernetes-dashboard/v1.8.3.yaml
```

To install the standalone Heapster monitoring (required for the `kubectl top` command):

```shell
kubectl apply -f https://raw.githubusercontent.com/kubernetes/kops/master/addons/monitoring-standalone/v1.7.0.yaml
```

To install Prometheus Operator for monitoring:

```
kubectl apply -f https://raw.githubusercontent.com/kubernetes/kops/master/addons/prometheus-operator/v0.19.0.yaml
```

At least the first 2 are recommended to have a basic insight about how the kubernetes cluster behaves.

Click [here](https://github.com/kubernetes/kops/blob/1.10.0-beta.1/docs/addons.md) for more information.

## Cleanup

To remove the Kubernetes cluster, do the following:

```shell
kubectl delete all --all --namespace opennms
kubectl delete pvc --all
kubectl delete pv --all
kops delete cluster --name k8s.opennms.org --state s3://k8s.opennms.org --yes
```

## Future Enhancements

* Use `ConfigMaps` to centralize the configuration of the applications.
* Use `Secrets` for the applications passwords.
* Design a solution to handle scale down of Cassandra and decommission of nodes.
* Design a solution to manage OpenNMS Configuration files (the `/opt/opennms/etc` directory), or use an existing one like [ksync](https://vapor-ware.github.io/ksync/).
* Add support for `HorizontalPodAutoscaler` for the data clusters like Cassandra, Kafka and Elasticsearch. Make sure `heapster` is running.
* Add support for Cluster Autoscaler. Check what `kops` offers on this regard.
* Add support for monioring. Initially through the basic metrics provided via [kubelet](https://kubernetes.io/docs/reference/command-line-tools-reference/kubelet/); then, through [Prometheus](https://prometheus.io) using [Prometheus Operator](https://coreos.com/operators/prometheus/docs/latest/). As a bonus, create a Dashboard for the cluster metrics in Grafana.
* Explore [Helm](https://helm.sh), and potentially add support for it.
* Explore a `PostgreSQL` solution like [Spilo/Patroni](https://patroni.readthedocs.io/en/latest/) using the [Postgres Operator](https://postgres-operator.readthedocs.io/en/latest/), to understand how to build a HA Postgres.
* Build a VPC with the additional security groups using Terraform. Then, use `--vpc` and `--node-security-groups` when calling `kops create cluster`, as explained [here](https://github.com/kubernetes/kops/blob/master/docs/run_in_existing_vpc.md).
