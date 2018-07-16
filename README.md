# OpenNMS Drift in Kubernetes

OpenNMS Drift deployment in Kubernetes through Kops and AWS for testing purposes

## Cluster Configuration

Create DNS sub-domain, and make sure it works prior start the cluster:

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

```shell
kubectl apply -f postgresql.yaml
kubectl apply -f activemq.yaml
kubectl apply -f cassandra.yaml
kubectl apply -f elasticsearch.yaml
kubectl apply -f zookeper.yaml
kubectl apply -f kafka.yaml
kubectl apply -f opennms.core.yaml
```

WARNING:

* Order is important.
* Make sure to wait until each `StatefulSet` has been fully deployed.

## Future Enhancements

* Include `initContainers` to validate dependencies.
* Expose services to use them outside Kubernetes/AWS, in order to use Minion.
