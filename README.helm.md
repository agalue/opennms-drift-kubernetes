The following has been tested with Helm 3, which doesn't require Tiller on your cluster.

helm repo list

If the stable repository is not installed:

helm repo add stable https://kubernetes-charts.storage.googleapis.com/

Install Ingress NGinx:

kubectl create namespace nginx-ingress
helm install nginx-ingress \
  --namespace nginx-ingress \
  stable/nginx-ingress

Install Cert-Manager:

kubectl apply --validate=false -f https://raw.githubusercontent.com/jetstack/cert-manager/release-0.12/deploy/manifests/00-crds.yaml
kubectl create namespace cert-manager
helm repo add jetstack https://charts.jetstack.io
helm install cert-manager \
  --namespace cert-manager \
  --version v0.12.0 \
  jetstack/cert-manager

Install Jaeger Operator:

helm install jaeger-operator stable/jaeger-operator

Install Strimzi Kafka Operator:

helm repo add strimzi https://strimzi.io/charts/
helm install kafka-operator strimzi/strimzi-kafka-operator

Install Zalando PostgreSQL Operator:

git clone https://github.com/zalando/postgres-operator.git
cd postgres-operator
helm install postgres-operator ./charts/postgres-operator -f ./charts/postgres-operator/values-crd.yaml

Although, the easiest way is:

kubectl apply -k github.com/zalando/postgres-operator/manifests

Elasticsearch (no operators):

helm repo add elastic https://helm.elastic.co
helm install elastic elastic/elasticsearch
helm install kibana elastic/kibana

Note: the above are not operators.

Elasticsearch operator:

kubectl apply -f https://download.elastic.co/downloads/eck/1.0.0/all-in-one.yaml

https://www.elastic.co/guide/en/cloud-on-k8s/current/index.html

Cassandra (no operators):

helm repo add bitnami https://charts.bitnami.com/bitnami
helm install cassandra bitnami/cassandra

Note: the above is not based on operators

OpenNMS Helm Charts

- Horizon
  + ALEC as an addition
- Sentinel
  + ALEC as an addition
- Minion
- Helm/Grafana

The idea is define the dependencies externally at the beginning to keep it simple.
Then, configure whatever is necessary depending on the helm parameters.
For example, if broker-rpc=kafka broker-sink=kafka and kafka-url are provided, that will use Kafka for Sink/RPC.
Otherwise, amq-url is required as broker-rpc=amq and broker-sink=amq will be the defaults.

The initContainers are still going to be required, but they should be as generic as possible.
meaning everything will be configured depending on the provided environment variables.

There are going to be mandatory parameters. If the parameters are not provided, helm should not deploy the solution.

For Minion and Sentinel is going to be much easier.

Phase 2

Create operators for OpenNMS based on helm.

Phase 3

Create advanced operators for OpenNMS based on Golang.

