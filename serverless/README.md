
# Introduction to Serverless

This is a very simple serverless function to retrieve an alarm from OpenNMS and send it to a Slack channel as a message.

## Installation

### Deploy the Kafka Converter Application

The Kafka Producer feature of OpenNMS publishes events, alarms, metrics and nodes to topics using Google Protobuf as the payload format. Unfortunately, serverless controllers like Fission expect plain text, or to be more presice JSON as the payload. For this reason we need to convert the GPB messages to JSON messgages.

There is an application for that:

https://github.com/agalue/OpenNMS-Kafka-Converter

The repository explains how to generate a Docker image for the application, and has a YAML file to deploy the converter to Kubernetes, on the same keyspace where OpenNMS is running.

```shell
kubectl apply -f https://raw.githubusercontent.com/agalue/OpenNMS-Kafka-Converter/master/deployment/k8s-converter.yaml
```

### Create a Slack WebHook

Follow the Slack API [documentation](https://api.slack.com/incoming-webhooks) to create a Webhook to send messages to a given channel.

Once you have the URL, add it to a config-map; for example:

```shell
kubectl -n default create configmap alarms2kafka-config --from-literal=SLACK_URL="https://hooks.slack.com/services/xxx/yyy/zzzz"
```

### Install Fission

Make sure to install the fission CLI on your own computer, as explained on the [documentation](https://docs.fission.io/installation/).

For the manifets, it is enough to have the core functionality, with the Kafka Listener implemented. As Helm is not used here, this can easily be done by executing the following commands:

```shell
kubectl apply -f https://github.com/fission/fission/releases/download/1.0-rc2/fission-core-1.0-rc2.yaml
kubectl apply -f fission-mqtrigger-kafka.yaml
```

The above will publish the Pods on the default namespace. It is required to change the above YAMLs to use a different keyspace, as the solution is intended to be installed through Helm. The YAML for the Kafka mqtrigger is provided on this repository.

### Create the NodeJS Environment

```shell
fission environment create --name nodejs --image fission/node-env:latest --builder fission/node-builder:latest
```

### Create a ZIP with the NodeJS app and its dependencies

The `slack-forwarder` directory contains the NodeJS application and the dependencies file.

```shell
zip alarm2slack.zip ./slack-forwarder/package.json ./slack-forwarder/alarm2slack.js
```

### Create the function

```shell
fission function create --name alarm2slack --src alarm2slack.zip --env nodejs --configmap alarms2kafka-config
```

### Create the function trigger based on a Kafka Topic

```shell
fission mqt create --name alarm2slack --function alarm2slack --mqtype kafka --topic opennms_alarms_json
```

The name of the topic relies on the Kafka Converter YAML file.

## Test

From now on, when an alarm is generated in OpenNMS, the Kafka Producer will forward it to Kafka. From there, the converter will put the JSON version of the GPB alarm to another topic. From there, the Fission Message Queue Listener will grab it and call the function. Finally, the function will post the alarm on Slack.

Another way to test is create an HTTP triger and use curl to emulate an alarm:

```shell
fission route create --name alarm2slack --url /alarm2slack --host fission.k8s.opennms.org --createingress
```

Then,

```shell
curl -X POST -v -d '{"uei":"uei.jigsaw/test", "id":666, "logMessage":"I want to play a game"}' http://fission.k8s.opennms.org/alarm2slack
```
