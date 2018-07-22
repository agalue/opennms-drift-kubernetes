# OpenNMS Drift in Kubernetes

OpenNMS Drift deployment in Kubernetes through [Kops](https://github.com/kubernetes/kops) and [AWS](https://aws.amazon.com/) for testing purposes

## Requirements

* Install [kops](https://github.com/kubernetes/kops/blob/master/docs/install.md) (this environment has been tested with version `1.10.0-alpha.1`)
* Install [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)
* Intall the AWS CLI
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

Create the Kubernetes cluster using `kops` (1 master node and 5 worker nodes):

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
kubectl apply -f aws-storage.yaml
```

Volumes for `StatefulSets` are going to be automatically created.

### Security Groups

When configuring Kafka, the `hostPort` is used in order to configure the `advertised.listeners` using the EC2 public FQDN. For this reason the external port (i.e. `9094`) should be opened on the security group called `nodes.k8s.opennms.org`. Certainly, this can be done manually, but a [Terraform](https://www.terraform.io) recipe has been used for this purpose (`update-security-groups.tf).

Make sure you have it installed on your system, and then:

```shell
terraform init
terraform plan
terraform apply
```

### Services, Deployments and StatefulSets

It is recommended to follow the same order. The applications will wait for their respective dependencies to be ready prior start.

From the directory on which this repository has been checked out:

```shell
kubectl apply -f postgresql.yaml
kubectl apply -f activemq.yaml
kubectl apply -f cassandra.yaml
kubectl apply -f elasticsearch.master.yaml
kubectl apply -f elasticsearch.data.yaml
kubectl apply -f zookeeper.yaml
kubectl apply -f kafka.yaml
kubectl apply -f opennms.core.yaml
kubectl apply -f opennms.ui.yaml
kubectl apply -f grafana.yaml
kubectl apply -f kibana.yaml
```

After a while, you should be able to see this:

```text
➜  kubectl get all -l deployment=drift -o wide
NAME                          READY     STATUS    RESTARTS   AGE       IP            NODE
pod/amq-0                     1/1       Running   0          1m        100.96.1.9    ip-172-20-51-219.us-east-2.compute.internal
pod/cassandra-0               1/1       Running   0          1m        100.96.1.12   ip-172-20-51-219.us-east-2.compute.internal
pod/cassandra-1               1/1       Running   0          1m        100.96.2.8    ip-172-20-32-237.us-east-2.compute.internal
pod/cassandra-2               1/1       Running   0          1m        100.96.3.10   ip-172-20-53-115.us-east-2.compute.internal
pod/esdata-0                  1/1       Running   0          1m        100.96.2.5    ip-172-20-32-237.us-east-2.compute.internal
pod/esdata-1                  1/1       Running   0          1m        100.96.3.9    ip-172-20-53-115.us-east-2.compute.internal
pod/esdata-2                  1/1       Running   0          1m        100.96.1.11   ip-172-20-51-219.us-east-2.compute.internal
pod/esmaster-0                1/1       Running   0          1m        100.96.4.2    ip-172-20-34-233.us-east-2.compute.internal
pod/esmaster-1                1/1       Running   0          1m        100.96.3.4    ip-172-20-53-115.us-east-2.compute.internal
pod/esmaster-2                1/1       Running   0          1m        100.96.1.14   ip-172-20-51-219.us-east-2.compute.internal
pod/grafana-b45486b7d-6h76p   1/1       Running   0          1m        100.96.2.10   ip-172-20-32-237.us-east-2.compute.internal
pod/grafana-b45486b7d-x96sv   1/1       Running   0          1m        100.96.4.14   ip-172-20-34-233.us-east-2.compute.internal
pod/kafka-0                   1/1       Running   0          1m        100.96.3.8    ip-172-20-53-115.us-east-2.compute.internal
pod/kafka-1                   1/1       Running   0          1m        100.96.4.6    ip-172-20-34-233.us-east-2.compute.internal
pod/kafka-2                   1/1       Running   0          1m        100.96.2.9    ip-172-20-32-237.us-east-2.compute.internal
pod/kibana-6d49bd74c-hvzwf    1/1       Running   0          1m        100.96.3.7    ip-172-20-53-115.us-east-2.compute.internal
pod/onms-0                    1/1       Running   0          1m        100.96.4.13   ip-172-20-34-233.us-east-2.compute.internal
pod/onms-ui-0                 1/1       Running   0          1m        100.96.2.11   ip-172-20-32-237.us-east-2.compute.internal
pod/onms-ui-1                 1/1       Running   0          1m        100.96.1.16   ip-172-20-51-219.us-east-2.compute.internal
pod/postgres-0                1/1       Running   0          1m        100.96.4.12   ip-172-20-34-233.us-east-2.compute.internal
pod/zk-0                      1/1       Running   0          1m        100.96.3.6    ip-172-20-53-115.us-east-2.compute.internal
pod/zk-1                      1/1       Running   0          1m        100.96.1.10   ip-172-20-51-219.us-east-2.compute.internal
pod/zk-2                      1/1       Running   0          1m        100.96.4.4    ip-172-20-34-233.us-east-2.compute.internal

NAME                   TYPE           CLUSTER-IP       EXTERNAL-IP                                                               PORT(S)                      AGE       SELECTOR
service/activemq       ClusterIP      None             <none>                                                                    61616/TCP                    1m        app=amq
service/cassandra      ClusterIP      None             <none>                                                                    9042/TCP                     1m        app=cassandra
service/esdata         ClusterIP      None             <none>                                                                    9200/TCP                     1m        role=esdata
service/esmaster       ClusterIP      None             <none>                                                                    9200/TCP                     1m        role=esmaster
service/ext-amq        LoadBalancer   100.68.195.71    ab498f0a08b6811e8b4660291aea5df5-2002819493.us-east-2.elb.amazonaws.com   61616:31217/TCP              1m        app=amq
service/ext-grafana    LoadBalancer   100.70.146.0     a8f440e008b7211e8b4660291aea5df5-164183470.us-east-2.elb.amazonaws.com    80:32025/TCP                 1m        app=grafana
service/ext-kibana     LoadBalancer   100.65.221.38    ac97e48528b6811e8b4660291aea5df5-455127768.us-east-2.elb.amazonaws.com    80:31220/TCP                 1m        app=kibana
service/ext-onms       LoadBalancer   100.65.220.235   a8c3c0ca08b7211e8b4660291aea5df5-1551460738.us-east-2.elb.amazonaws.com   80:31133/TCP                 1m        app=onms
service/ext-onms-ui    LoadBalancer   100.68.95.40     a930883e08b7211e8b4660291aea5df5-1843539511.us-east-2.elb.amazonaws.com   80:30735/TCP                 1m        app=onms-ui
service/grafana        ClusterIP      None             <none>                                                                    3000/TCP                     1m        app=grafana
service/kafka          ClusterIP      None             <none>                                                                    9092/TCP                     1m        app=kafka
service/kibana         ClusterIP      None             <none>                                                                    5601/TCP                     1m        app=kibana
service/opennms-core   ClusterIP      None             <none>                                                                    8980/TCP,8101/TCP            1m        app=onms
service/opennms-ui     ClusterIP      None             <none>                                                                    8980/TCP,8101/TCP            1m        app=onms-ui
service/postgresql     ClusterIP      None             <none>                                                                    5432/TCP                     1m        app=postgres
service/zookeeper      ClusterIP      None             <none>                                                                    2888/TCP,3888/TCP,2181/TCP   1m        app=zk

NAME                           DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE       CONTAINERS     IMAGES                                                    SELECTOR
deployment.apps/grafana        2         2         2            2           1m        grafana        grafana/grafana:5.2.1                                     app=grafana
deployment.apps/kibana         1         1         1            1           1m        kibana         docker.elastic.co/kibana/kibana:6.2.4                     app=kibana

NAME                                DESIRED   CURRENT   READY     AGE       CONTAINERS   IMAGES                                  SELECTOR
replicaset.apps/grafana-b45486b7d   2         2         2         1m        grafana      grafana/grafana:5.2.1                   app=grafana,pod-template-hash=601042638
replicaset.apps/kibana-6d49bd74c    1         1         1         1m        kibana       docker.elastic.co/kibana/kibana:6.2.4   app=kibana,pod-template-hash=280568307

NAME                         DESIRED   CURRENT   AGE       CONTAINERS   IMAGES
statefulset.apps/amq         1         1         1m        amq          webcenter/activemq:5.14.3
statefulset.apps/cassandra   3         3         1m        cassandra    cassandra:3.11.2
statefulset.apps/esdata      3         3         1m        esdata       docker.elastic.co/elasticsearch/elasticsearch:6.2.4
statefulset.apps/esmaster    3         3         1m        esmaster     docker.elastic.co/elasticsearch/elasticsearch:6.2.4
statefulset.apps/kafka       3         3         1m        kafka        wurstmeister/kafka:2.11-1.1.0
statefulset.apps/onms        1         1         1m        onms         opennms/horizon-core-web:22.0.1-1
statefulset.apps/onms-ui     2         2         1m        onms-ui      opennms/horizon-core-web:22.0.1-1
statefulset.apps/postgres    1         1         1m        postgres     postgres:10.4
statefulset.apps/zk          3         3         1m        zk           zookeeper:3.4.10
```

## Minion

Your Minion should use the following resources:

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

Make sure to use your own Domain ;)

## Users

* OpenNMS UI: `http://onmsui.k8s.opennms.org/opennms`
* Grafana: `http://grafana.k8s.opennms.org/`
* Kibana: `http://kibana.k8s.opennms.org/`
* Kafka Manager: `http://kaffa-manager.k8s.opennms.org/`

Make sure to use your own Domain ;)

## Cleanup

To remove the Kubernetes cluster, do the following:

```shell
kubectl delete all -l deployment=drift
kops delete cluster --name k8s.opennms.org --state s3://k8s.opennms.org --yes
```

## Future Enhancements

* Service created for Kafka.
* Use `ConfigMaps` to centralize configuration.
* Use `Secrets` for the passwords.
* Simplify deployment.
* Design a better solution to manage OpenNMS Configuration files.
* Add support for Helm.