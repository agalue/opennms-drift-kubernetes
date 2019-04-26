# OpenNMS Drift in Kubernetes

OpenNMS Drift deployment in [Kubernetes](https://kubernetes.io/).

This is basically the `Kubernetes` version of the work done [here](https://github.com/OpenNMS/opennms-drift-aws/) for OpenNMS Horizon 24. For learning purposes, `Helm` charts and `operators` are avoided for this solution on the main components, with the exceptions of the Ingress Controller and Cert-Manager. In the future, that might change to take advantage of these technologies.

Instead of using discrete EC2 instances, this repository explains how to deploy basically the same solution with `Kubernetes`.

Of course, there are more features in this particular solution compared with the original one, like dealing with additional features like [Hasura](https://hasura.io/), [Cassandra Reaper](http://cassandra-reaper.io/) and [Kafka Manager](https://github.com/yahoo/kafka-manager) is easier when using containers.

## Limitations

`Kafka` uses the `hostPort` feature to expose the advertise external listeners on port 9094, so applications outside `Kubernetes` like `Minion` can access it. For this reason, `Kafka` can be scaled up to the number of worker nodes on the `Kubernetes` cluster.

## Cluster Configuration

Proceed with the preferred cluster technology:

* Using [Kops](README.kops.md)
* Using [EKS](README.eks.md)
* Using [GCE](README.gce.md)

## Deployment

### Namespace

From the directory on which this repository has been checked out:

```bash
kubectl apply -f ./namespace
```

This will additionally add some complementary RBAC permissions, in case there is a need of adding operators and/or administrators to the OpenNMS namespace.

As a side note, instead of providing the namespace for all the kubectl commands every single time, you can make the `opennms` namespace as the default one, by running the following command:

```bash
kubectl config set-context $(kubectl config current-context) --namespace=opennms
```

### ConfigMaps/Secrets

#### ConfigMaps

From the directory on which this repository has been checked out, execute the following to build a config-map based on the files inside the `config` directory:

```bash
kubectl create configmap opennms-config --from-file=config/ --namespace opennms --dry-run -o yaml | kubectl apply -f -
```

Then, create the common settings shared across multiple services, to have then on a central place.

```bash
kubectl create configmap common-settings \
 --from-literal TIMEZONE=America/New_York \
 --from-literal OPENNMS_INSTANCE_ID=OpenNMS \
 --from-literal MINION_LOCATION=Kubernetes \
 --from-literal CASSANDRA_DC=Main \
 --from-literal CASSANDRA_CLUSTER_NAME=OpenNMS \
 --from-literal CASSANDRA_REPLICATION_FACTOR=2 \
 --from-literal KAFKA_NUM_PARTITIONS=6 \
 --namespace opennms --dry-run -o yaml | kubectl apply -f -
```

#### Secrets

From the directory on which this repository has been checked out, create a secret object for all the custom secrets that are going to be used with this solution:

```bash
kubectl create secret generic onms-passwords \
 --from-literal POSTGRES_PASSWORD=postgres \
 --from-literal OPENNMS_DB_PASSWORD=opennms \
 --from-literal OPENNMS_UI_ADMIN_PASSWORD=admin \
 --from-literal GRAFANA_UI_ADMIN_PASSWORD=opennms \
 --from-literal GRAFANA_DB_USERNAME=grafana \
 --from-literal GRAFANA_DB_PASSWORD=grafana \
 --from-literal ELASTICSEARCH_PASSWORD=elastic \
 --from-literal KAFKA_MANAGER_APPLICATION_SECRET=0p3nNMS \
 --from-literal KAFKA_MANAGER_USERNAME=opennms \
 --from-literal KAFKA_MANAGER_PASSWORD=0p3nNMS \
 --from-literal HASURA_GRAPHQL_ACCESS_KEY=0p3nNMS \
 --namespace opennms --dry-run -o yaml | kubectl apply -f -
```

Feel free to change them.

### Storage Classes

From the directory on which this repository has been checked out:

```bash
kubectl apply -f ./storage
```

Volumes for `StatefulSets` are going to be automatically created.

### Services, Deployments and StatefulSets

The applications will wait for their respective dependencies to be ready prior start (a feature implemented through `initContainers`), so there is no need to start them on a specific order.

From the directory on which this repository has been checked out:

```bash
kubectl apply -f ./manifests
```

Use the following to check whether or not all the resources have been created:

```bash
kubectl get all --namespace opennms
```

## Minion

This deployment already contains Minions inside the opennms namespace for monitoring devices within the cluster. In order to have Minions outside the Kubernetes cluster, they should use the following resources in order to connect to OpenNMS and the dependent applications:

* OpenNMS Core: `https://onms.k8s.opennms.org/opennms`
* Kafka: `kafka.k8s.opennms.org:9094`

For example, here is the minimum configuration (without flow listeners):

```bash
[root@onms-minion ~]# cat /opt/minion/etc/org.opennms.minion.controller.cfg
location=Apex
id=onms-minion.local
http-url=https://onms.k8s.opennms.org/opennms

[root@onms-minion ~]# cat /opt/minion/etc/org.opennms.core.ipc.sink.kafka.cfg
bootstrap.servers=kafka.k8s.opennms.org:9094

[root@onms-minion ~]# cat /opt/minion/etc/org.opennms.core.ipc.rpc.kafka.cfg
bootstrap.servers=kafka.k8s.opennms.org:9094
acks=1

[root@onms-minion ~]# cat /opt/minion/etc/featuresBoot.d/kafka.boot
!minion-jms
!opennms-core-ipc-sink-camel
!opennms-core-ipc-rpc-jms
opennms-core-ipc-sink-kafka
opennms-core-ipc-rpc-kafka
```

With Docker:

```bash
docker run -it --name minion \
 -e MINION_ID=docker-minion-1 \
 -e MINION_LOCATION=Apex \
 -e OPENNMS_HTTP_URL=https://onms.k8s.opennms.org/opennms \
 -e OPENNMS_HTTP_USER=admin \
 -e OPENNMS_HTTP_PASS=admin \
 -e KAFKA_RPC_ACKS=1 \
 -e KAFKA_RPC_BOOTSTRAP_SERVERS=kafka.k8s.opennms.org:9094 \
 -e KAFKA_SINK_BOOTSTRAP_SERVERS=kafka.k8s.opennms.org:9094 \
 -p 8201:8201 \
 -p 1514:1514 \
 -p 1162:1162 \
 opennms/minion:24.0.0-rc -c
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

> NOTE: Make sure to use your own Domain.

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
