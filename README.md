# OpenNMS Drift in Kubernetes

OpenNMS Drift deployment in Kubernetes through [Kops](https://github.com/kubernetes/kops) and [AWS](https://aws.amazon.com/) for testing purposes

## Requirements

* Install `kops`
* Install `kubectl`
* Intall the AWS CLI
* Have your AWS account configured on your system

## Cluster Configuration

Create DNS sub-domain, and make sure it works prior start the cluster; for example:

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

Create an S3 bucket to hold the Kops configuration:

```shell
aws s3api create-bucket \
  --bucket k8s.opennms.org \
  --create-bucket-configuration LocationConstraint=us-east-2

aws s3api put-bucket-versioning \
  --bucket k8s.opennms.org \
  --versioning-configuration Status=Enabled
```

Create the Kubernetes cluster using `kops`:

```shell
kops create cluster \
  --name k8s.opennms.org \
  --state s3://k8s.opennms.org \
  --dns-zone k8s.opennms.org \
  --zones us-east-2a \
  --master-size t2.medium \
  --node-size t2.2xlarge \
  --node-count 4 \
  --yes
```

Remember to change the settings to reflect your environment.

After a few minutes, verify the state of the cluster using either `kubectl` or `kops`:

```shell
kops validate cluster --name k8s.opennms.org --state s3://k8s.opennms.org
```

The output should be:

```text
Validating cluster k8s.opennms.org

INSTANCE GROUPS
NAME			ROLE	MACHINETYPE	MIN	MAX	SUBNETS
master-us-east-2a	Master	t2.medium	1	1	us-east-2a
nodes			Node	t2.2xlarge	4	4	us-east-2a

NODE STATUS
NAME						ROLE	READY
ip-172-20-32-202.us-east-2.compute.internal	node	True
ip-172-20-33-61.us-east-2.compute.internal	node	True
ip-172-20-40-131.us-east-2.compute.internal	master	True
ip-172-20-55-47.us-east-2.compute.internal	node	True
ip-172-20-57-252.us-east-2.compute.internal	node	True

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
* Services
* Deployments and StatefulSets

### Configuration Maps

```shell
kubectl create configmap opennms-core-overlay --from-file=config/opennms-core/etc/
```

### Storage Classes

```shell
kubectl apply -f aws-storage.yaml
```

Volumes for `StatefulSets` are going to be automatically created.

### Applications

WARNING:

* Order is important.
* Make sure to wait until each `StatefulSet` has been fully deployed.

```shell
kubectl apply -f postgresql.yaml
kubectl apply -f activemq.yaml
kubectl apply -f cassandra.yaml
kubectl apply -f elasticsearch.yaml
kubectl apply -f zookeper.yaml
kubectl apply -f kafka.yaml
kubectl apply -f opennms.core.yaml
```

After a while, you should be able to see this:

```text
➜  ~ kubectl get all
NAME                  READY     STATUS    RESTARTS   AGE
pod/amq-0             1/1       Running   0          5h
pod/cassandra-0       1/1       Running   0          5h
pod/cassandra-1       1/1       Running   0          5h
pod/cassandra-2       1/1       Running   0          5h
pod/elasticsearch-0   1/1       Running   0          5h
pod/elasticsearch-1   1/1       Running   0          5h
pod/elasticsearch-2   1/1       Running   0          5h
pod/kafka-0           1/1       Running   0          1h
pod/kafka-1           1/1       Running   0          1h
pod/kafka-2           1/1       Running   0          1h
pod/onms-0            1/1       Running   0          1h
pod/postgres-0        1/1       Running   0          4h
pod/zk-0              1/1       Running   0          2h
pod/zk-1              1/1       Running   0          2h
pod/zk-2              1/1       Running   0          2h

NAME                    TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)                      AGE
service/activemq        ClusterIP   None         <none>        61616/TCP                    5h
service/cassandra       ClusterIP   None         <none>        9042/TCP                     5h
service/elasticsearch   ClusterIP   None         <none>        9200/TCP                     5h
service/kafka           ClusterIP   None         <none>        9092/TCP                     1h
service/kubernetes      ClusterIP   100.64.0.1   <none>        443/TCP                      5h
service/opennms-core    ClusterIP   None         <none>        8980/TCP,8101/TCP            1h
service/postgresql      ClusterIP   None         <none>        5432/TCP                     4h
service/zookeeper       ClusterIP   None         <none>        2888/TCP,3888/TCP,2181/TCP   2h

NAME                             DESIRED   CURRENT   AGE
statefulset.apps/amq             1         1         5h
statefulset.apps/cassandra       3         3         5h
statefulset.apps/elasticsearch   3         3         5h
statefulset.apps/kafka           3         3         1h
statefulset.apps/onms            1         1         1h
statefulset.apps/postgres        1         1         4h
statefulset.apps/zk              3         3         2h
```

## Future Enhancements

* Include `initContainers` to validate and wait for dependencies.
* Expose services to use them outside Kubernetes/AWS, in order to use Minion.
* Use `ConfigMaps` to centralize configuration.
