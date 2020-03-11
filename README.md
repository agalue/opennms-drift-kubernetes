# OpenNMS Drift in Kubernetes

OpenNMS Drift deployment in [Kubernetes](https://kubernetes.io/).

This is basically the `Kubernetes` version of the work done [here](https://github.com/OpenNMS/opennms-drift-aws/) for OpenNMS Horizon 24. For learning purposes, `Helm` charts and `operators` are avoided for this solution on the main components, with the exceptions of the Ingress Controller and Cert-Manager. In the future, that might change to take advantage of these technologies.

Instead of using discrete EC2 instances, this repository explains how to deploy basically the same solution with `Kubernetes`.

In this case, there are some additional features available in this particular solution compared with the original one, like [Hasura](https://hasura.io/), [Cassandra Reaper](http://cassandra-reaper.io/) and [Kafka Manager](https://github.com/yahoo/kafka-manager).

## Limitations

`Kafka` uses the `hostPort` feature to expose the advertise external listeners on port 9094, so applications outside `Kubernetes` like `Minion` can access it. For this reason, `Kafka` can be scaled up to the number of worker nodes on the `Kubernetes` cluster.

## Minimum Requirements

* Install the [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/) binary. Make sure to have version 1.14 to use the `kustomize` integration.
* Install the [kustomize](https://kustomize.io/) binary on your machine [Optional, but good to have for troubleshooting]

> **NOTE**: Depending on the chosen platform, additional requirements might be needed. Check the respective `README` files for more information.

## Cluster Configuration

Proceed with the preferred cluster technology:

* Using [Kops](README.kops.md) on AWS.
* Using [EKS](README.eks.md) on AWS.
* Using [Google Compute Platform](README.gce.md).
* Using [Microsoft Azure](README.azure.md).
* Using [Minikube](README.minikube.md) on your machine (with restrictions).

## Deployment

To facilicate the process, everything is done through `kustomize`.

To update the default settings, find the `common-settings` under `configMapGenerator` inside [kustomization.yaml](manifests/kustomization.yaml).

To update the default passwords, find the `onms-passwords` under `secretGenerator` inside [kustomization.yaml](manifests/kustomization.yaml).

Each cluster technology explains how to deploy the manifests.

As part of the deployment, some complementary RBAC permissions will be added, in case there is a need for adding operators and/or administrators to the OpenNMS namespace. Check [namespace.yaml](manifests/namespace.yaml) for more details.

Use the following to check whether or not all the resources have been created:

```bash
kubectl get all --namespace opennms
```

## Minion

This deployment already contains Minions inside the opennms namespace for monitoring devices within the cluster. In order to have Minions outside the Kubernetes cluster, they should use the following resources in order to connect to OpenNMS and the dependent applications.

For `AWS` using the domain `aws.agalue.net`, the resources should be:

* OpenNMS Core: `https://onms.aws.agalue.net/opennms`
* Kafka: `kafka.aws.agalue.net:9094`

For example:

```bash
export DOMAIN="aws.agalue.net"
export LOCATION="Apex"
export INSTANCE_ID="K8S" # Must match kustomization.yaml

docker pull opennms/minion:bleeding

docker run -it --rm --entrypoint cat opennms/minion:bleeding -- etc/system.properties > system.properties
echo "org.opennms.instance.id=${INSTANCE_ID}" >> system.properties
cat <<EOF > features.boot
!minion-jms
!opennms-core-ipc-rpc-jms
!opennms-core-ipc-sink-camel
opennms-core-ipc-grpc-client
EOF

cat <<EOF > grpc-client.cfg
host=grpc.$DOMAIN
port=8990
EOF

docker run -it --name minion \
 -e MINION_ID=$LOCATION-minion-1 \
 -e MINION_LOCATION=$LOCATION \
 -e OPENNMS_HTTP_URL=https://onms.$DOMAIN/opennms \
 -e OPENNMS_HTTP_USER=admin \
 -e OPENNMS_HTTP_PASS=admin \
 -p 8201:8201 \
 -p 1514:1514/udp \
 -p 1162:1162/udp \
 -v $(pwd)/system.properties:/opt/minion-etc-overlay/system.properties \
 -v $(pwd)/grpc-client.cfg:/opt/minion-etc-overlay/org.opennms.core.ipc.grpc.client.cfg \
 -v $(pwd)/features.boot:/opt/minion-etc-overlay/featuresBoot.d/features.boot \
 opennms/minion:bleeding -f
```

> **IMPORTANT**: Make sure to use the same version as OpenNMS. The above contemplates using a custom content for the `INSTANCE_ID`. Make sure it matches the content of [kustomization.yaml](manifests/kustomization.yaml).

> **WARNING**: Make sure to use your own Domain and Location, and use the same version tag as the OpenNMS manifests.

## Users Resources

* OpenNMS Core: `https://onms.aws.agalue.net/opennms/` (for administrative tasks)
* OpenNMS UI: `https://onmsui.aws.agalue.net/opennms/` (for users/operators)
* Grafana: `https://grafana.aws.agalue.net/`
* Kibana: `https://kibana.aws.agalue.net/` (remember to enable monitoring)
* Kafka Manager: `https://kafka-manager.aws.agalue.net/` (make sure to register the cluster using `zookeeper.opennms.svc.cluster.local:2181/kafka` for the `Cluster Zookeeper Hosts`)
* Hasura GraphQL API: `https://hasura.aws.agalue.net/v1alpha1/graphql`
* Hasura GraphQL Console: `https://hasura.aws.agalue.net/console`
* Jaeger UI: `https://tracing.aws.agalue.net/`
* Cassandra Reaper: `https://cassandra-reaper.aws.agalue.net/webui/`

> **WARNING**: Make sure to use your own Domain.

## Future Enhancements

* Add [Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/) to control the communication between components (for example, only OpenNMS needs access to PostgreSQL and Cassandra; other component should not access those resources). A network manager like [Calico](https://www.projectcalico.org) is required.
* Design a solution to manage OpenNMS Configuration files (the `/opt/opennms/etc` directory), or use an existing one like [ksync](https://vapor-ware.github.io/ksync/).
* Investigate how to provide support for `HorizontalPodAutoscaler` for the data clusters like Cassandra, Kafka and Elasticsearch. Check [here](https://github.com/kubernetes/kops/blob/master/docs/horizontal_pod_autoscaling.md) for more information. Although, using operators seems more feasible in this regard, due to the complexities when expanding/shrinking these kind of applications.
* Add support for Cluster Autoscaler. Check what `kops` offers on this regard.
* Add support for monitoring through [Prometheus](https://prometheus.io) using [Prometheus Operator](https://coreos.com/operators/prometheus/docs/latest/). Expose the UI (including Grafana) through the Ingress controller.
* Expose the Kubernetes Dashboard through the Ingress controller.
* Design a solution to handle scale down of Cassandra and decommission of nodes; or investigate the existing operators.
* Explore a `PostgreSQL` solution like [Spilo/Patroni](https://patroni.readthedocs.io/en/latest/) using their [Postgres Operator](https://postgres-operator.readthedocs.io/en/latest/), to understand how to build a HA Postgres within K8s. Alternatively, we might consider the [Crunchy Data Operator](https://crunchydata.github.io/postgres-operator/stable/)
* Explore a `Kafka` solution like [Strimzi](https://strimzi.io/), an operator that supports encryption and authentication.
* Build a VPC with the additional security groups using Terraform. Then, use `--vpc` and `--node-security-groups` when calling `kops create cluster`, as explained [here](https://github.com/kubernetes/kops/blob/master/docs/run_in_existing_vpc.md).
* Explore [Helm](https://helm.sh), and potentially add support for it.
