# Kubeless

## Install Kubeless

Make sure to install the kubeless CLI on your own computer, as explained on the [documentation](https://kubeless.io/docs/quick-start/).

For the manifets, with the Kafka Listener, this can easily be done by executing the following commands:

```bash
export RELEASE=$(curl -s https://api.github.com/repos/kubeless/kubeless/releases/latest | grep tag_name | cut -d '"' -f 4)
kubectl create ns kubeless
kubectl apply -f https://github.com/kubeless/kubeless/releases/download/$RELEASE/kubeless-$RELEASE.yaml
kubectl apply -f kubeless-mqtrigger-kafka.yaml
```

## Create the secret with configuration

Once you have the WebHook URL, add it to a `secret`, as well as the OpenNMS WebUI URL; for example:

```bash
kubectl -n opennms create secret generic serverless-config \
 --from-literal=SLACK_URL="https://hooks.slack.com/services/xxx/yyy/zzzz" \
 --from-literal=ONMS_URL="https://onmsui.aws.agalue.net/opennms" \
 --dry-run -o yaml | kubectl apply -f -
```

## Create the function

```bash
kubeless function deploy alarm2slack \
--namespace opennms \
--runtime nodejs8 \
--dependencies ./slack-forwarder/package.json \
--from-file ./slack-forwarder/alarm2slack.js \
--handler alarm2slack.kubeless \
--secrets serverless-config
```

## Create the function trigger based on a Kafka Topic

```bash
kubeless trigger kafka create alarm2slack \
 --namespace opennms \
 --function-selector created-by=kubeless,function=alarm2slack \
 --trigger-topic opennms_alarms_json
```

The name of the topic relies on the Kafka Converter YAML file.

Use `kubeless function list` to check whether the function is ready to use.

## Testing

```bash
kubeless function call alarm2slack \
 -n opennms \
 --data '{
  "id": 666,
  "uei": "uei.jigsaw/test",
  "severity": "WARNING",
  "lastEventTime": 1560438592000,
  "logMessage": "I want to play a game",
  "description": "<p>Hope to hear from your soon!</p>"
 }'
```
