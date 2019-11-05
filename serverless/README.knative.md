# Knative

In this tutorial, a very simple and simplified installation of [Istio](https://istio.io) and [Knative](https://knative.dev/) will be performed. All tracing/logging/observability features won/t be used to simplify the deployment.

The following outlines the installation steps, but all of them have been placed on the script [setup-istio-knative.sh](./setup-istio-knative.sh)

## Install Istio

Labeling default namespace w/ istio-injection=enabled

```bash
kubectl label namespace default istio-injection=enabled
```

Install a simplified Istio from Knative source:

```bash
serving_version="v0.10.0"
istio_version="1.3.3"

kubectl apply -f "https://raw.githubusercontent.com/knative/serving/${serving_version}/third_party/istio-${istio_version}/istio-crds.yaml"
kubectl apply -f "https://raw.githubusercontent.com/knative/serving/${serving_version}/third_party/istio-${istio_version}/istio-lean.yaml"

echo "Waiting for istio to become ready"
sleep 10; while echo && kubectl get pods -n istio-system | grep -v -E "(Running|Completed|STATUS)"; do sleep 10; done
```

## Install Knative Serving

```bash
serving_version="v0.10.0"

kubectl apply -f "https://github.com/knative/serving/releases/download/${serving_version}/serving.yaml"

echo "Waiting for Knative Serving to become ready"
sleep 10; while echo && kubectl get pods -n knative-serving | grep -v -E "(Running|Completed|STATUS)"; do sleep 10; done
```

## Install Knative Eventing

```bash
eventing_version="v0.10.0"

kubectl apply -f "https://github.com/knative/eventing/releases/download/${eventing_version}/release.yaml"
kubectl apply -f "https://github.com/knative/eventing-contrib/releases/download/${eventing_version}/kafka-source.yaml"

echo "Waiting for Knative Eventing to become ready"
sleep 5; while echo && kubectl get pods -n knative-eventing | grep -v -E "(Running|Completed|STATUS)"; do sleep 5; done
sleep 5; while echo && kubectl get pods -n knative-sources | grep -v -E "(Running|Completed|STATUS)"; do sleep 5; done
```

## Fix the Domain Configuration

```bash
DOMAIN="aws.agalue.net"

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: config-domain
  namespace: knative-serving
data:
  $DOMAIN: |
    $DOMAIN: ""
EOF
```

> **WARNING**: do not forget to use your own domain.

## Create the secret with configuration

Once you have the Slack WebHook URL, add it to a `secret`, as well as the OpenNMS WebUI URL; for example:

```bash
kubectl create secret generic serverless-config \
 --from-literal=SLACK_URL="https://hooks.slack.com/services/xxx/yyy/zzzz" \
 --from-literal=ONMS_URL="https://onmsui.aws.agalue.net/opennms" \
 --dry-run -o yaml | kubectl apply -f -
```

> **WARNING**: do not forget to fix the Slack URL.

## Install the Knative Service

This service represents the `function` or the code that will be executed every time a message has been sent to a specific in kafka.

```bash
kubectl apply -f knative-service.yaml
```

> **WARNING**: make sure that the image from [slack-forwarder-go](./slack-forwarder-go) has been created and uploaded to Docker Hub. If a different account is used, make sure to adjust the YAML file.

## Install and Kafka Source controller

This will trigger the desired Knative service when a message is received from a given Kafka topic.

```bash
kubectl apply -f knative-kafka-source.yaml
```

Note that we specify the kafka Consumer Grup, the Kafka Cluster Bootstrap Server, the Kafka Topic and the `ksvc` that will be triggered when a new messages is received from the topic.

> **IMPORTANT**: Make sure to use the topic maintained by `agalue/kafka-converter-go`, as it is expected to receive a JSON payload.
