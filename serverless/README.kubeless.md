# Kubeless

## Install Kubeless

Make sure to install the kubeless CLI on your own computer, as explained on the [documentation](https://kubeless.io/docs/quick-start/).

For the manifets, with the Kafka Listener, this can easily be done by executing the following commands:

```shell
export RELEASE=$(curl -s https://api.github.com/repos/kubeless/kubeless/releases/latest | grep tag_name | cut -d '"' -f 4)
kubectl create ns kubeless
kubectl apply -f https://github.com/kubeless/kubeless/releases/download/$RELEASE/kubeless-$RELEASE.yaml
kubectl apply -f kubeless-mqtrigger-kafka.yaml
```

## Create the function

```shell
kubeless function deploy alarm2slack --runtime nodejs8 --dependencies ./slack-forwarder/package.json --from-file ./slack-forwarder/alarm2slack.js --handler alarm2slack.kubeless --secrets serverless-config
```

## Create the function trigger based on a Kafka Topic

```shell
kubeless trigger kafka create alarm2slack --function-selector created-by=kubeless,function=alarm2slack --trigger-topic opennms_alarms_json
```

The name of the topic relies on the Kafka Converter YAML file.

## Optional Testing

```shell
kubeless function call alarm2slack --data '{"uei":"uei.jigsaw/test", "id":666, "logMessage":"I want to play a game", "description":"<p>Hope to hear from your soon!</p>"}'
```