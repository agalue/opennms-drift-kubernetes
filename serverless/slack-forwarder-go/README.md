# Knative Eventing Service Implementation

This represents the Knative Service that will be triggered by Kafka with the OpenNMS alarm that should be forwarded to Slack.

To build the `ksvc` container:

```bash
docker build -t agalue/slack-forwarder:latest .
docker push agalue/slack-forwarder:latest
```

> *NOTE*: Please use your own Docker Hub account or use the image provided on my account.
