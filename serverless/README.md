
# Introduction to Serverless

There are hundreds of possible ways to use Serverless technologies with OpenNMS and Kubernetes. In this particular case, the idea is to have a simple function to react when an alarm from OpenNMS is sent to a Kafka topic, and forward it to a given Slack Channel as a message.

For this, it is required to have the Kafka producer feature enabled on the OpenNMS.

In essence, and in terms of OpenNMS, this can be seen as a scalable custom OpenNMS NBI implementation, or a scalable Notification system based on alarms, or a scalable Scriptd alternative based on alarms.

Of course, the events are also available through Kafka topics, but alarms are often more important in terms of notifying a user when a problem is discovered.

## Installation

### Deploy the Kafka Converter Application

The Kafka Producer feature of OpenNMS publishes events, alarms, metrics and nodes to topics using Google Protobuf as the payload format. The `.proto` files are defined [here](https://github.com/OpenNMS/opennms/tree/develop/features/kafka/producer/src/main/proto).

Unfortunately, serverless controllers like Fission or Kubeless expect plain text or to be more presice, a JSON as the payload. For this reason, it is necessary to convert the GPB messages to JSON messages.

There is an application for that:

https://github.com/agalue/OpenNMS-Kafka-Converter

The avoid repository contains all the details to to generate a Docker image for the application, and also has an example YAML file to deploy the converter to Kubernetes. The example content of the provided YAML file can be used in this environment:

```bash
kubectl apply -f https://raw.githubusercontent.com/agalue/OpenNMS-Kafka-Converter/master/k8s-converter.yaml
```

> NOTE: Make sure the `INSTANCE_ID` has not been changed on your OpenNMS Pod and/or Minion Pod, as the above YAML assumes it should be `OpenNMS`.

### Create a Slack WebHook

Follow the Slack API [documentation](https://api.slack.com/incoming-webhooks) to create a Webhook to send messages to a given channel.

### Deploy the Function

* Using [Fission](README.fission.md)
* Using [Kubeless](README.kubeless.md)

## Test

From now on, when an alarm is generated in OpenNMS, the Kafka Producer will forward it to Kafka. From there, the converter will put the JSON version of the GPB alarm to another topic. From there, the Serverless Message Queue Listener will grab it and call the function. Finally, the function will transform the alarm into a message, and will post it on Slack.
