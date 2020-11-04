# OpenNMS-Kafka-Converter

> **DEPRECATED**: This tool is not used anymore as the current solution is based on the [Producer Enhancer](https://github.com/agalue/producer-enhancer).

A simple Kafka Consumer application to convert GPB payload from Topic A to JSON into Topic B

This solution requires using the OpenNMS Kafka Producer. This feature can export events, alarms, metrics, nodes and edges from the OpenNMS database to Kafka. All the payloads are stored using Google Protobuf.

Unfortunately, for certain solution like Serverless, JSON (or to be more precise, plain text) is required in order to use Kafka as a trigger once a new message arrive to a given Topic. This is why this tool has been implemented.

This repository also contains a Dockerfile to compile and build an image with the tool, which can be fully customized through environment variables, so the solution can be used with Kubernetes (the sample YAML file is also available).

## Requirements

* `BOOTSTRAP_SERVERS` environment variable with Kafka Bootstrap Server (i.e. `kafka01:9092`)
* `SOURCE_TOPIC` environment variable with the source Kafka Topic with GPB Payload
* `DEST_TOPIC` environment variable with the destination Kafka Topic with JSON Payload
* `GROUP_ID` \[Optional\] environment variable with the Consumer Group ID (defaults to `opennms`)
* `MESSAGE_KIND` \[Optional\] environment variable with the payload type. Valid values are: alarm, event, node, metric, edge (defaults to `alarm`).
* To pass producer settings, add an environment variable with the prefix `PRODUCER_`, for example: `PROCUCER_MAX_REQUEST_SIZE`.
* To pass consumer settings, add an environment variable with the prefix `CONSUMER_`, for example: `CONSUMER_AUTO_OFFSET_RESET`.

For producer/consumer settings, the character "_" will be replaced with "." and converted to lowercase. For example, `CONSUMER_AUTO_OFFSET_RESET` will be configured as `auto.offset.reset`.

## Build

In order to build the application:

```bash
docker build -t agalue/kafka-converter-go:latest .
docker push agalue/kafka-converter-go:latest
```

> *NOTE*: Please use your own Docker Hub account or use the image provided on my account.

To build the controller locally for testing:

```bash
export GO111MODULE="on"

go build
./kafka-converter
```
