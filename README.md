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

* Permissions
* ConfigMaps
* Storage Classes
* Volumes (if apply)
* Services
* Deployments and StatefulSets

### Permissions

On the AWS Console, go to IAM, then Roles, then click on the IAM Role called `nodes.k8s.opennms.org`, expand the Policy named `nodes.k8s.opennms.org`, and add the following permissions:

```json
{
  "Effect": "Allow",
  "Action": [
    "route53:GetHostedZone",
    "route53:ListHostedZonesByName",
    "route53:ListHostedZones",
    "route53:ListResourceRecordSets",
    "route53:CreateHostedZone",
    "route53:DeleteHostedZone",
    "route53:ChangeResourceRecordSets",
    "route53:CreateHealthCheck",
    "route53:GetHealthCheck",
    "route53:DeleteHealthCheck",
    "route53:UpdateHealthCheck",
    "ec2:DescribeVpcs",
    "ec2:DescribeRegions",
    "servicediscovery:*"
  ],
  "Resource": [
    "*"
  ]
}
```

### Configuration Maps

```shell
kubectl create configmap opennms-core-overlay --from-file=config/opennms-core/
kubectl create configmap opennms-ui-overlay --from-file=config/opennms-ui/
kubectl create configmap grafana --from-file=config/grafana/
```

### Storage Classes

```shell
kubectl apply -f aws-storage.yaml
```

Volumes for `StatefulSets` are going to be automatically created.

### Applications

It is recommended to follow the same order. The applications will wait for their respective dependencies to be ready prior start.

```shell
kubectl apply -f external-dns.yaml
kubectl apply -f postgresql.yaml
kubectl apply -f activemq.yaml
kubectl apply -f cassandra.yaml
kubectl apply -f elasticsearch.yaml
kubectl apply -f zookeper.yaml
kubectl apply -f kafka.yaml
kubectl apply -f opennms.core.yaml
kubectl apply -f opennms.ui.yaml
kubectl apply -f grafana.yaml
kubectl apply -f kibana.yaml
```

After a while, you should be able to see this:

```text
➜  ~ kubectl get all -l deployment=drift -o wide
NAME                          READY     STATUS    RESTARTS   AGE       IP            NODE
pod/amq-0                     1/1       Running   0          53m       100.96.3.2    ip-172-20-52-27.us-east-2.compute.internal
pod/cassandra-0               1/1       Running   0          53m       100.96.1.4    ip-172-20-57-36.us-east-2.compute.internal
pod/cassandra-1               0/1       Running   3          52m       100.96.4.8    ip-172-20-36-206.us-east-2.compute.internal
pod/cassandra-2               1/1       Running   0          51m       100.96.3.6    ip-172-20-52-27.us-east-2.compute.internal
pod/elasticsearch-0           1/1       Running   0          53m       100.96.2.3    ip-172-20-59-100.us-east-2.compute.internal
pod/elasticsearch-1           1/1       Running   0          51m       100.96.1.8    ip-172-20-57-36.us-east-2.compute.internal
pod/elasticsearch-2           1/1       Running   1          50m       100.96.4.9    ip-172-20-36-206.us-east-2.compute.internal
pod/grafana-946b9b667-4fm6g   1/1       Running   1          52m       100.96.4.7    ip-172-20-36-206.us-east-2.compute.internal
pod/grafana-946b9b667-6jbzw   1/1       Running   0          52m       100.96.1.6    ip-172-20-57-36.us-east-2.compute.internal
pod/kafka-0                   1/1       Running   0          26m       100.96.2.6    ip-172-20-59-100.us-east-2.compute.internal
pod/kafka-1                   1/1       Running   0          26m       100.96.1.9    ip-172-20-57-36.us-east-2.compute.internal
pod/kafka-2                   1/1       Running   0          25m       100.96.3.7    ip-172-20-52-27.us-east-2.compute.internal
pod/kibana-7fffd7b66c-zpxqs   1/1       Running   0          52m       100.96.1.7    ip-172-20-57-36.us-east-2.compute.internal
pod/onms-0                    1/1       Running   1          14m       100.96.3.9    ip-172-20-52-27.us-east-2.compute.internal
pod/onms-ui-0                 1/1       Running   0          1m        100.96.2.9    ip-172-20-59-100.us-east-2.compute.internal
pod/onms-ui-1                 1/1       Running   0          8m        100.96.1.10   ip-172-20-57-36.us-east-2.compute.internal
pod/postgres-0                1/1       Running   1          53m       100.96.4.11   ip-172-20-36-206.us-east-2.compute.internal
pod/zk-0                      1/1       Running   1          53m       100.96.4.10   ip-172-20-36-206.us-east-2.compute.internal
pod/zk-1                      1/1       Running   0          53m       100.96.3.4    ip-172-20-52-27.us-east-2.compute.internal
pod/zk-2                      1/1       Running   0          53m       100.96.1.5    ip-172-20-57-36.us-east-2.compute.internal

NAME                    TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)                      AGE       SELECTOR
service/activemq        ClusterIP   None         <none>        61616/TCP                    53m       app=amq
service/cassandra       ClusterIP   None         <none>        9042/TCP                     53m       app=cassandra
service/elasticsearch   ClusterIP   None         <none>        9200/TCP                     53m       app=elasticsearch
service/grafana         ClusterIP   None         <none>        3000/TCP                     52m       app=grafana
service/kafka           ClusterIP   None         <none>        9092/TCP                     53m       app=kafka
service/kibana          ClusterIP   None         <none>        5601/TCP                     52m       app=kibana
service/opennms-core    ClusterIP   None         <none>        8980/TCP,8101/TCP            53m       app=onms
service/opennms-ui      ClusterIP   None         <none>        8980/TCP,8101/TCP            53m       app=onms-ui
service/postgresql      ClusterIP   None         <none>        5432/TCP                     54m       app=postgres
service/zookeeper       ClusterIP   None         <none>        2888/TCP,3888/TCP,2181/TCP   53m       app=zk

NAME                            DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE       CONTAINERS   IMAGES                                  SELECTOR
deployment.extensions/grafana   2         2         2            2           52m       grafana      grafana/grafana:5.2.1                   app=grafana
deployment.extensions/kibana    1         1         1            1           52m       kibana       docker.elastic.co/kibana/kibana:6.2.4   app=kibana

NAME                                      DESIRED   CURRENT   READY     AGE       CONTAINERS   IMAGES                                  SELECTOR
replicaset.extensions/grafana-946b9b667   2         2         2         52m       grafana      grafana/grafana:5.2.1                   app=grafana,pod-template-hash=502656223
replicaset.extensions/kibana-7fffd7b66c   1         1         1         52m       kibana       docker.elastic.co/kibana/kibana:6.2.4   app=kibana,pod-template-hash=3999836227

NAME                      DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE       CONTAINERS   IMAGES                                  SELECTOR
deployment.apps/grafana   2         2         2            2           52m       grafana      grafana/grafana:5.2.1                   app=grafana
deployment.apps/kibana    1         1         1            1           52m       kibana       docker.elastic.co/kibana/kibana:6.2.4   app=kibana

NAME                                DESIRED   CURRENT   READY     AGE       CONTAINERS   IMAGES                                  SELECTOR
replicaset.apps/grafana-946b9b667   2         2         2         52m       grafana      grafana/grafana:5.2.1                   app=grafana,pod-template-hash=502656223
replicaset.apps/kibana-7fffd7b66c   1         1         1         52m       kibana       docker.elastic.co/kibana/kibana:6.2.4   app=kibana,pod-template-hash=3999836227

NAME                             DESIRED   CURRENT   AGE       CONTAINERS      IMAGES
statefulset.apps/amq             1         1         53m       amq             webcenter/activemq:5.14.3
statefulset.apps/cassandra       3         3         53m       cassandra       cassandra:3.11.2
statefulset.apps/elasticsearch   3         3         53m       elasticsearch   docker.elastic.co/elasticsearch/elasticsearch-oss:6.2.4
statefulset.apps/kafka           3         3         26m       kafka           wurstmeister/kafka:2.11-1.1.0
statefulset.apps/onms            1         1         14m       onms            opennms/horizon-core-web:22.0.1-1
statefulset.apps/onms-ui         2         2         8m        onms-ui         opennms/horizon-core-web:22.0.1-1
statefulset.apps/postgres        1         1         53m       postgres        postgres:10.4
statefulset.apps/zk              3         3         53m       zk              zookeeper:3.4.10
```

## Minion

Your Minion should use the following resources:

* ActiveMQ: `failover:(tcp://activemq.k8s.opennms.org:61616)?randomize=false`
* Kafka: `kafka-0.k8s.opennms.org:9092,kafka-1.k8s.opennms.org:9092,kafka-2.k8s.opennms.org:9092`
* OpenNMS Core: `http://onms.k8s.opennms.org:8980/opennms`

Make sure to use your own Domain ;)

## Users

* OpenNMS UI: `http://onmsui.k8s.opennms.org:8980/opennms`
* Grafana: `http://grafana.k8s.opennms.org:3000/`
* Kibana: `http://kibana.k8s.opennms.org:5601/`

Make sure to use your own Domain ;)

## Future Enhancements

* Service created for Kafka.
* Use `ConfigMaps` to centralize configuration.
* Use `Secrets` for the passwords.
* Improve IAM Role handling for the external-dns.
