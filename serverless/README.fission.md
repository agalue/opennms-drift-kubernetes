# Fission

## Install Fission

Make sure to install the fission CLI on your own computer, as explained on the [documentation](https://docs.fission.io/installation/).

For the manifets, it is enough to have the core functionality, with the Kafka Listener implemented. As Helm is not used here, this can easily be done by executing the following commands:

```shell
kubectl apply -f https://github.com/fission/fission/releases/download/1.0-rc2/fission-core-1.0-rc2.yaml
kubectl apply -f fission-mqtrigger-kafka.yaml
```

The above will publish the Pods on the default namespace. It is required to change the above YAMLs to use a different keyspace, as the solution is intended to be installed through Helm. The second YAML contains the Kafka mqtrigger which is not included/enabled by default with Fission.

## Create the secret for Slack URL

Once you have the WebHook URL, add it to a `secret`; for example:

```shell
kubectl -n default create secret generic serverless-config \
 --from-literal=SLACK_URL="https://hooks.slack.com/services/xxx/yyy/zzzz" \
 --dry-run -o yaml | kubectl apply -f -
```

## Create the NodeJS Environment

```shell
fission environment create --name nodejs --image fission/node-env:latest --builder fission/node-builder:latest
```

## Create a ZIP with the NodeJS app and its dependencies

The `slack-forwarder` directory contains the NodeJS application and the dependencies file.

```shell
zip alarm2slack.zip ./slack-forwarder/package.json ./slack-forwarder/alarm2slack.js
```

## Create the function

```shell
fission function create --name alarm2slack --src alarm2slack.zip --env nodejs --secret serverless-config --entrypoint alarm2slack.fission
```

## Create the function trigger based on a Kafka Topic

```shell
fission mqt create --name alarm2slack --function alarm2slack --mqtype kafka --topic opennms_alarms_json
```

The name of the topic relies on the Kafka Converter YAML file.

## Optional Testing

Create an HTTP triger and use curl to emulate an alarm:

```shell
fission route create --name alarm2slack --method POST --url /alarm2slack --host fission.k8s.opennms.org --createingress
```

Then,

```shell
curl -X POST -v -d '{"uei":"uei.jigsaw/test", "id":666, "logMessage":"I want to play a game", "description":"<p>Hope to hear from your soon!</p>"}' http://fission.k8s.opennms.org/alarm2slack
```
