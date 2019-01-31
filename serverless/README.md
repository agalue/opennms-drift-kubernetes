
# Introduction to Serverless

This is a very simple serverless function to retrieve an alarm from OpenNMS through Kafka (assuming that the OpenNMS server is using the Kafka Producer feature), and send it to a Slack channel as a message.

## Installation

### Deploy the Kafka Converter Application

The Kafka Producer feature of OpenNMS publishes events, alarms, metrics and nodes to topics using Google Protobuf as the payload format.

Unfortunately, serverless controllers like Fission or Kubeless expect plain text, or to be more presice JSON as the payload. For this reason we need to convert the GPB messages to JSON messgages.

There is an application for that:

https://github.com/agalue/OpenNMS-Kafka-Converter

The repository explains all the details to to generate a Docker image for the application, and has an example YAML file to deploy the converter to Kubernetes.

```shell
kubectl apply -f https://raw.githubusercontent.com/agalue/OpenNMS-Kafka-Converter/master/k8s-converter.yaml
```

> NOTE: Make sure the `INSTANCE_ID` has not been changed on your OpenNMS Pod, as the above yaml assumes it should be `OpenNMS`.

### Create a Slack WebHook

Follow the Slack API [documentation](https://api.slack.com/incoming-webhooks) to create a Webhook to send messages to a given channel.

### Deploy the Function

* Using [Fission](README.fission.md)
* Using [Kubeless](README.kubeless.md)

## Test

From now on, when an alarm is generated in OpenNMS, the Kafka Producer will forward it to Kafka. From there, the converter will put the JSON version of the GPB alarm to another topic. From there, the Fission Message Queue Listener will grab it and call the function. Finally, the function will post the alarm on Slack.
