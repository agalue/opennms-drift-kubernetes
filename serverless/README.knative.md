# Knative

In this tutorial, a very simple and simplified installation of [Istio](https://istio.io) and [Knative](https://knative.dev/) will be performed. All tracing/logging/observability features won/t be used to simplify the deployment.

The following outlines the installation steps, but all of them have been placed on the script [setup-istio-knative.sh](./setup-istio-knative.sh)

> **IMPORTANT**: This requires Kubernetes 1.15 or newer.

## Declare versions to use

In order to use the simplified version of Istio, the chosen version of it depends on what's available at the [third-party](https://github.com/knative/serving/tree/master/third_party) folder for the chosen version of Knative Service.

```bash
export serving_version="v0.14.0"
export eventing_version="v0.14.0"
export istio_version="1.5.1"
```

## Install Istio

Labeling default namespace with `istio-injection=enabled`:

```bash
kubectl label namespace default istio-injection=enabled --overwrite=true
```

The above is for convenience, to facilitate the injection of the sidecars for the knative related pods.

Install a simplified Istio from Knative source:

```bash
kubectl apply -f "https://raw.githubusercontent.com/knative/serving/${serving_version}/third_party/istio-${istio_version}/istio-crds.yaml"
kubectl apply -f "https://raw.githubusercontent.com/knative/serving/${serving_version}/third_party/istio-${istio_version}/istio-minimal.yaml"
```

> **NOTE**: [Here](https://knative.dev/docs/install/installing-istio/#installing-istio-without-sidecar-injection) you can see how to build your own `istio-minimal.yaml` from the Istio GIT repository.

## Install Knative Serving

```bash
kubectl apply -f "https://github.com/knative/serving/releases/download/${serving_version}/serving-crds.yaml"
kubectl apply -f "https://github.com/knative/serving/releases/download/${serving_version}/serving-core.yaml"
```

> **NOTE**: The monitoring manifets are not installed as they are not required for this solution; although, if your Kubernetes cluster has enough resources, you can give that a try.

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
  $DOMAIN: ""
EOF
```

> **WARNING**: do not forget to use your own domain.

## Install Knative Eventing

```bash
kubectl apply -f "https://github.com/knative/eventing/releases/download/${eventing_version}/eventing-crds.yaml"
kubectl apply -f "https://github.com/knative/eventing/releases/download/${eventing_version}/eventing-core.yaml"
kubectl apply -f "https://github.com/knative/eventing-contrib/releases/download/${eventing_version}/kafka-source.yaml"
```

## Create the secret with configuration

Once you have the Slack WebHook URL, add it to a `secret`, as well as the OpenNMS WebUI URL; for example:

```bash
SLACK_URL="https://hooks.slack.com/services/xxx/yyy/zzzz"
ONMS_URL="https://onmsui.aws.agalue.net/opennms"

kubectl create secret generic serverless-config \
 --namespace default \
 --from-literal=SLACK_URL="$SLACK_URL" \
 --from-literal=ONMS_URL="$ONMS_URL" \
 --dry-run=client -o yaml | kubectl apply -f -
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
