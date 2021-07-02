#!/usr/bin/env bash

set -e

NO_COLOR=${NO_COLOR:-""}
if [ -z "$NO_COLOR" ]; then
  header=$'\e[1;33m'
  reset=$'\e[0m'
else
  header=''
  reset=''
fi

if [ "${slack_url}" == "" ]; then
  echo "ERROR: the slack_url environment variable is required"
  exit 1
fi

function header_text {
  echo "$header$*$reset"
}

knative_version="v0.23.0"
kafka_source_version="v0.18.8"

domain="${domain-aws.agalue.net}"
kafka_server="kafka.opennms.svc.cluster.local:9092"
onms_url="${onms_url-https://onmsui.$domain/opennms}"

header_text "Starting Knative..."

header_text "Using Knative Version:      ${knative_version}"
header_text "Using Kafka Source Version: ${kafka_source_version}"
header_text "Using Kafka Server:         ${kafka_server}"
header_text "Using OpenNMS UI Server     ${onms_url}"

header_text "Labeling default namespace w/ istio-injection=enabled"
kubectl label namespace default istio-injection=enabled --overwrite=true

header_text "Setting up Knative Serving"
kubectl apply -f "https://github.com/knative/serving/releases/download/${knative_version}/serving-crds.yaml"
kubectl apply -f "https://github.com/knative/serving/releases/download/${knative_version}/serving-core.yaml"

header_text "Setting up Network Layer - Istio"
kubectl apply -f "https://github.com/knative/net-istio/releases/download/${knative_version}/istio.yaml"
kubectl apply -f "https://github.com/knative/net-istio/releases/download/${knative_version}/net-istio.yaml"

header_text "Waiting for istio to become ready"
sleep 10; while echo && kubectl get pods -n istio-system | grep -v -E "(Running|Completed|STATUS)"; do sleep 10; done

header_text "Configuring custom domain"
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: config-domain
  namespace: knative-serving
data:
  $domain: ""
EOF

header_text "Waiting for Knative Serving to become ready"
sleep 10; while echo && kubectl get pods -n knative-serving | grep -v -E "(Running|Completed|STATUS)"; do sleep 10; done

header_text "Setting up Knative Eventing"
kubectl apply -f "https://github.com/knative/eventing/releases/download/${knative_version}/eventing-crds.yaml"
kubectl apply -f "https://github.com/knative/eventing/releases/download/${knative_version}/eventing-core.yaml"
kubectl apply -f "https://github.com/knative/eventing-contrib/releases/download/${kafka_source_version}/kafka-source.yaml"

header_text "Waiting for Knative Eventing to become ready"
sleep 5; while echo && kubectl get pods -n knative-eventing | grep -v -E "(Running|Completed|STATUS)"; do sleep 5; done
sleep 5; while echo && kubectl get pods -n knative-sources | grep -v -E "(Running|Completed|STATUS)"; do sleep 5; done

header_text "Creating secret with OpenNMS and Slack URLs"
kubectl create secret generic serverless-config \
 --namespace default \
 --from-literal=SLACK_URL="${slack_url}" \
 --from-literal=ONMS_URL="${onms_url}"

header_text "Launching Slack Forwarder Service"
kubectl apply -f knative-service.yaml

header_text "Launching Kafka Event Source"
kubectl apply -f knative-kafka-source.yaml
