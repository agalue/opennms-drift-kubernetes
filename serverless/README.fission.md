# Fission

## Install Fission

Make sure to install the fission CLI on your own computer, as explained on the [documentation](https://docs.fission.io/installation/).

For the manifets, it is enough to have the core functionality, with the Kafka Listener implemented. As Helm is not used here, this can easily be done by executing the following commands:

```bash
export RELEASE=$(curl -s https://api.github.com/repos/fission/fission/releases/latest | grep tag_name | cut -d '"' -f 4)
kubectl create namespace fission
kubectl -n fission apply -f https://github.com/fission/fission/releases/download/$RELEASE/fission-core-$RELEASE.yaml
kubectl -n fission apply -f fission-mqtrigger-kafka.yaml
```

The last command applies the YAML that contains the Kafka `mqtrigger` which is not included/enabled by default with Fission.

It has been done this way because it doesn't look possible to use `fission-core` with `mqtrigger-kafka` through Helm, as the Kafka feature is part of `fission-all`, which contains features not required here.

## Create the secret with configuration

Once you have the WebHook URL, add it to a `secret`, as well as the OpenNMS WebUI URL; for example:

```bash
kubectl -n fission create secret generic serverless-config \
 --from-literal=SLACK_URL="https://hooks.slack.com/services/xxx/yyy/zzzz" \
 --from-literal=ONMS_URL="https://onmsui.aws.agalue.net/opennms" \
 --dry-run -o yaml | kubectl apply -f -
```

> **WARNING**: do not forget to fix the Slack URL.

## Create the NodeJS Environment

```bash
fission environment create \
 --name nodejs \
 --image fission/node-env \
 --builder fission/node-builder
```

## Create a ZIP with the NodeJS app and its dependencies

The `slack-forwarder` directory contains the NodeJS application and the dependencies file.

```bash
zip -j alarm2slack.zip slack-forwarder/package.json slack-forwarder/alarm2slack.js
```

> IMPORTANT: all the relevant files should be at the root of the ZIP (hence, the `-j`).

## Create the function

```bash
fission function create \
 --name alarm2slack \
 --src alarm2slack.zip \
 --env nodejs \
 --secret serverless-config \
 --entrypoint "alarm2slack.fission"
```

## Create the function trigger based on a Kafka Topic

```bash
fission mqt create \
 --name alarm2slack \
 --function alarm2slack \
 --mqtype kafka \
 --topic OpenNMS-alarms-json
```

> **IMPORTANT**: The name of the topic relies on the Kafka Converter YAML file.

## Testing

The best way to test is by generating an actual alarm in OpenNMS. This method works.

The following alternative options are valid, but they are not working, probably due to how `fission` has been installed:

[1] Using the test command:

```bash
fission function test --name alarm2slack --body '{
  "id": 666,
  "uei": "uei.jigsaw/test",
  "severity": "WARNING",
  "lastEventTime": 1560438592000,
  "logMessage": "I want to play a game",
  "description": "<p>Hope to hear from your soon!</p>"
 }'
```

[2] Using an HTTP trigger:

```bash
export DOMAIN="aws.agalue.net"

fission route create \
 --name alarm2slack \
 --function alarm2slack \
 --method POST \
 --url /alarm2slack \
 --host fission.$DOMAIN \
 --createingress
```

Then,

```bash
curl -H 'Content-Type: application/json' -v -d '{
  "id": 666,
  "uei": "uei.jigsaw/test",
  "severity": "WARNING",
  "lastEventTime": 1560438592000,
  "logMessage": "I want to play a game",
  "description": "<p>Hope to hear from your soon!</p>"
 }' http://fission.$DOMAIN/alarm2slack
```
