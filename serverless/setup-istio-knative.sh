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

serving_version="v0.10.0"
eventing_version="v0.10.0"
istio_version="1.3.3"
kafka_server="kafka.opennms.svc.cluster.local:9092"

function header_text {
  echo "$header$*$reset"
}

header_text "Starting Knative on minikube..."

header_text "Using Knative Serving Version:  ${serving_version}"
header_text "Using Knative Eventing Version: ${eventing_version}"
header_text "Using Istio Version:            ${istio_version}"
header_test "Using Kafka Server:             ${kafka_server}"

header_text "Labeling default namespace w/ istio-injection=enabled"
kubectl label namespace default istio-injection=enabled

header_text "Setting up Istio"
kubectl apply -f "https://raw.githubusercontent.com/knative/serving/${serving_version}/third_party/istio-${istio_version}/istio-crds.yaml"
kubectl apply -f "https://raw.githubusercontent.com/knative/serving/${serving_version}/third_party/istio-${istio_version}/istio-lean.yaml"

header_text "Waiting for istio to become ready"
sleep 10; while echo && kubectl get pods -n istio-system | grep -v -E "(Running|Completed|STATUS)"; do sleep 10; done

header_text "Setting up Knative Serving"
kubectl apply -f "https://github.com/knative/serving/releases/download/${serving_version}/serving.yaml"

header_text "Waiting for Knative Serving to become ready"
sleep 10; while echo && kubectl get pods -n knative-serving | grep -v -E "(Running|Completed|STATUS)"; do sleep 10; done

header_text "Setting up Knative Eventing"
kubectl apply -f "https://github.com/knative/eventing/releases/download/${eventing_version}/release.yaml"
kubectl apply -f "https://github.com/knative/eventing-contrib/releases/download/${eventing_version}/kafka-source.yaml"

header_text "Waiting for Knative Eventing to become ready"
sleep 5; while echo && kubectl get pods -n knative-eventing | grep -v -E "(Running|Completed|STATUS)"; do sleep 5; done
sleep 5; while echo && kubectl get pods -n knative-sources | grep -v -E "(Running|Completed|STATUS)"; do sleep 5; done

header_text "Launching Slack Forwarder Service"
kubectl apply -f knative-service.yaml

header_text "Launching Kafka Event Source"
kubectl apply -f knative-kafka-source.yaml
