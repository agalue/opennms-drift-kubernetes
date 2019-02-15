# Fission

> WARNING: Since version 1.0.0 was released, the solution doesn't work. Still investigating about it ...

## Install Fission

Make sure to install the fission CLI on your own computer, as explained on the [documentation](https://docs.fission.io/installation/).

For the manifets, it is enough to have the core functionality, with the Kafka Listener implemented. As Helm is not used here, this can easily be done by executing the following commands:

```shell
kubectl config set-context $(kubectl config current-context) --namespace=default
kubectl apply -f https://github.com/fission/fission/releases/download/1.0.0/fission-core-1.0.0.yaml
kubectl apply -f fission-mqtrigger-kafka.yaml
```

The above will publish the Pods on the default namespace. It is required to change the above YAMLs to use a different keyspace, as the solution is intended to be installed through Helm.

The second YAML contains the Kafka mqtrigger which is not included/enabled by default with Fission.

It has been done this way because it doesn't look possible to use `fission-core` with `mqtrigger-kafka` through Helm, as the Kafka feature is part of `fission-all`, which contains features not required here.


## Create the secret for Slack URL

Once you have the WebHook URL, add it to a `secret`; for example:

```shell
kubectl -n default create secret generic serverless-config \
 --from-literal=SLACK_URL="https://hooks.slack.com/services/xxx/yyy/zzzz" \
 --dry-run -o yaml | kubectl apply -f -
```

## Create the NodeJS Environment

```shell
fission environment create --name nodejs --image fission/node-env:1.0.0 --builder fission/node-builder:1.0.0
```

## Create a ZIP with the NodeJS app and its dependencies

The `slack-forwarder` directory contains the NodeJS application and the dependencies file.

```shell
zip alarm2slack.zip ./slack-forwarder/package.json ./slack-forwarder/alarm2slack.js
```

## Create the function

```shell
fission function create --name alarm2slack --src alarm2slack.zip --env nodejs --secret serverless-config --entrypoint "alarm2slack.fission"
```

## Create the function trigger based on a Kafka Topic

```shell
fission mqt create --name alarm2slack --function alarm2slack --mqtype kafka --topic opennms_alarms_json
```

The name of the topic relies on the Kafka Converter YAML file.

## Testing

```shell
fission function test --name alarm2slack --body '{"uei":"uei.jigsaw/test", "id":666, "logMessage":"I want to play a game", "description":"<p>Hope to hear from your soon!</p>"}'
```
