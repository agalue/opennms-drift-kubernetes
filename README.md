# OpenNMS Drift in Kubernetes

OpenNMS Drift deployment in Kubernetes through [Kops](https://github.com/kubernetes/kops) and [AWS](https://aws.amazon.com/).

This is basically the Kubernetes version of my work done [here](https://github.com/OpenNMS/opennms-drift-aws).

Instead of using discrete EC2 instances, this repository explains how to deploy basically the same solution with Kubernetes.

## Requirements

* Install [kops](https://github.com/kubernetes/kops/blob/master/docs/install.md) (this environment has been tested with version `1.10.0-alpha.1`)
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

* ConfigMaps
* Storage Classes
* Volumes (if apply)
* Security Groups
* Services
* Deployments and StatefulSets

### Configuration Maps

From the directory on which this repository has been checked out:

```shell
kubectl create configmap opennms-core-overlay --from-file=config/opennms-core/
kubectl create configmap opennms-ui-overlay --from-file=config/opennms-ui/
kubectl create configmap grafana --from-file=config/grafana/
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
terraform apply
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
➜  kubectl get all -l deployment=drift
NAME                                READY     STATUS    RESTARTS   AGE
pod/amq-0                           1/1       Running   0          4m
pod/cassandra-0                     1/1       Running   0          4m
pod/cassandra-1                     1/1       Running   0          4m
pod/cassandra-2                     1/1       Running   0          2m
pod/esdata-0                        1/1       Running   0          4m
pod/esdata-1                        1/1       Running   0          3m
pod/esdata-2                        1/1       Running   0          2m
pod/esmaster-0                      1/1       Running   0          4m
pod/esmaster-1                      1/1       Running   0          3m
pod/esmaster-2                      1/1       Running   0          2m
pod/grafana-784d596db-8b2t8         1/1       Running   0          4m
pod/grafana-784d596db-vf8n4         1/1       Running   0          4m
pod/kafka-0                         1/1       Running   0          4m
pod/kafka-1                         1/1       Running   0          3m
pod/kafka-2                         1/1       Running   0          2m
pod/kafka-manager-85588cfdd-ks4dr   1/1       Running   1          4m
pod/kibana-6d49bd74c-d6vn7          1/1       Running   0          4m
pod/onms-0                          1/1       Running   0          4m
pod/onms-ui-0                       1/1       Running   0          4m
pod/onms-ui-1                       1/1       Running   0          50s
pod/postgres-0                      1/1       Running   0          4m
pod/zk-0                            1/1       Running   0          4m
pod/zk-1                            1/1       Running   0          4m
pod/zk-2                            1/1       Running   0          4m

NAME                        TYPE           CLUSTER-IP       EXTERNAL-IP                                                               PORT(S)                      AGE
service/activemq            ClusterIP      None             <none>                                                                    61616/TCP                    4m
service/cassandra           ClusterIP      None             <none>                                                                    9042/TCP                     4m
service/esdata              ClusterIP      None             <none>                                                                    9200/TCP                     4m
service/esmaster            ClusterIP      None             <none>                                                                    9200/TCP                     4m
service/ext-amq             LoadBalancer   100.71.184.150   a0f53a3508e6e11e895c9020628a7ebf-1853095402.us-east-2.elb.amazonaws.com   61616:30630/TCP              4m
service/ext-grafana         LoadBalancer   100.68.116.191   a0fb99d728e6e11e895c9020628a7ebf-44402179.us-east-2.elb.amazonaws.com     80:30628/TCP                 4m
service/ext-kafka           LoadBalancer   100.65.3.135     a1001e4d28e6e11e895c9020628a7ebf-1768085006.us-east-2.elb.amazonaws.com   9094:30893/TCP               4m
service/ext-kafka-manager   LoadBalancer   100.69.228.85    a0fd5d1a38e6e11e895c9020628a7ebf-667457554.us-east-2.elb.amazonaws.com    80:31726/TCP                 4m
service/ext-kibana          LoadBalancer   100.68.20.233    a10262eb08e6e11e895c9020628a7ebf-753179253.us-east-2.elb.amazonaws.com    80:32228/TCP                 4m
service/ext-onms            LoadBalancer   100.69.111.89    a1049980a8e6e11e895c9020628a7ebf-1303376795.us-east-2.elb.amazonaws.com   80:30636/TCP                 4m
service/ext-onms-ui         LoadBalancer   100.64.249.172   a106e36c38e6e11e895c9020628a7ebf-588826144.us-east-2.elb.amazonaws.com    80:31956/TCP                 4m
service/grafana             ClusterIP      None             <none>                                                                    3000/TCP                     4m
service/kafka               ClusterIP      None             <none>                                                                    9092/TCP,9999/TCP            4m
service/kibana              ClusterIP      None             <none>                                                                    5601/TCP                     4m
service/opennms-core        ClusterIP      None             <none>                                                                    8980/TCP,8101/TCP            4m
service/opennms-ui          ClusterIP      None             <none>                                                                    8980/TCP,8101/TCP            4m
service/postgresql          ClusterIP      None             <none>                                                                    5432/TCP                     4m
service/zookeeper           ClusterIP      None             <none>                                                                    2888/TCP,3888/TCP,2181/TCP   4m

NAME                            DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/grafana         2         2         2            2           4m
deployment.apps/kafka-manager   1         1         1            1           4m
deployment.apps/kibana          1         1         1            1           4m

NAME                                      DESIRED   CURRENT   READY     AGE
replicaset.apps/grafana-784d596db         2         2         2         4m
replicaset.apps/kafka-manager-85588cfdd   1         1         1         4m
replicaset.apps/kibana-6d49bd74c          1         1         1         4m

NAME                         DESIRED   CURRENT   AGE
statefulset.apps/amq         1         1         4m
statefulset.apps/cassandra   3         3         4m
statefulset.apps/esdata      3         3         4m
statefulset.apps/esmaster    3         3         4m
statefulset.apps/kafka       3         3         4m
statefulset.apps/onms        1         1         4m
statefulset.apps/onms-ui     2         2         4m
statefulset.apps/postgres    1         1         4m
statefulset.apps/zk          3         3         4m
```

## Minion

Your Minions should use the following resources in order to connect to OpenNMS and the dependept applications:

* ActiveMQ: `failover:(tcp://activemq.k8s.opennms.org:61616)?randomize=false`
* OpenNMS Core: `http://onms.k8s.opennms.org/opennms`
* Kafka: `kafka.k8s.opennms.org:9094`

For example:

```shell
[root@onms-minion ~]# cat /opt/minion/etc/org.opennms.minion.controller.cfg 
location=Vagrant
id=onms-minion.local
http-url=http://onms.k8s.opennms.org/opennms
broker-url=failover:(tcp://activemq.k8s.opennms.org:61616)?randomize=false

[root@onms-minion ~]# cat /opt/minion/etc/org.opennms.core.ipc.sink.kafka.cfg 
bootstrap.servers=kafka.k8s.opennms.org:9094
acks=1

[root@onms-minion ~]# cat /opt/minion/etc/featuresBoot.d/kafka.boot 
!opennms-core-ipc-sink-camel
opennms-core-ipc-sink-kafka
```

> NOTE: Make sure to use your own Domain ;)

## Users

* OpenNMS UI: `http://onmsui.k8s.opennms.org/opennms`
* Grafana: `http://grafana.k8s.opennms.org/`
* Kibana: `http://kibana.k8s.opennms.org/`
* Kafka Manager: `http://kaffa-manager.k8s.opennms.org/`

> NOTE: Make sure to use your own Domain ;)

## Cleanup

To remove the Kubernetes cluster, do the following:

```shell
kubectl delete all -l deployment=drift
kops delete cluster --name k8s.opennms.org --state s3://k8s.opennms.org --yes
```

## Future Enhancements

* Use `ConfigMaps` to centralize the configuration of the applications.
* Use `Secrets` for the applications passwords.
* Design a better solution to manage OpenNMS Configuration files.
* Explore and add support for Helm.
* Build a VPC with the additional security groups using Terraform. Then, use `--vpc` and `--node-security-groups` when calling `kops create cluster`, as explained [here](https://github.com/kubernetes/kops/blob/master/docs/run_in_existing_vpc.md).
* Build a PostgreSQL cluster based on Spilo/Patroni using the [postgres-operator](https://postgres-operator.readthedocs.io/en/latest/)