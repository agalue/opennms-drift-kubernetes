# OpenNMS Drift in Kubernetes

OpenNMS Drift deployment in [Kubernetes](https://kubernetes.io/).

This is basically the `Kubernetes` version of the work done [here](https://github.com/OpenNMS/opennms-drift-aws/) for OpenNMS Horizon 24. For learning purposes, `Helm` charts and `operators` are avoided for this solution on the main components, with the exceptions of the Ingress Controller and Cert-Manager. In the future, that might change to take advantage of these technologies.

Instead of using discrete EC2 instances, this repository explains how to deploy basically the same solution with `Kubernetes`.

Of course, there are more features in this particular solution compared with the original one, like dealing with additional features like [Hasura](https://hasura.io/), [Cassandra Reaper](http://cassandra-reaper.io/) and [Kafka Manager](https://github.com/yahoo/kafka-manager) is easier when using containers.

## Limitations

`Kafka` uses the `hostPort` feature to expose the advertise external listeners on port 9094, so applications outside `Kubernetes` like `Minion` can access it. For this reason, `Kafka` can be scaled up to the number of worker nodes on the `Kubernetes` cluster.

## Requirements

* Install the [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/) binary. Make sure to have version 1.14 to use the `kustomize` integration.
* Install the [kustomize](https://kustomize.io/) binary on your machine [Optional, but good to have for troubleshooting]
* Install the [terraform](https://www.terraform.io) binary [Optional. See security groups]

## Cluster Configuration

Proceed with the preffered cluster technology:

* Using [Kops](README.kops.md)
* Using [EKS](README.eks.md)
* Using [GCE](README.gce.md)

## Deployment

To facilicate the process, everything is done through `kustomize`.

To update the default settings, check [kustomization.yaml](manifests/kustomization.yaml).

To update the passwords, check [_passwords.env](manifests/_passwords.env).

Each cluster technology explains how to deploy the manifets.

This will additionally add some complementary RBAC permissions, in case there is a need of adding operators and/or administrators to the OpenNMS namespace.

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
