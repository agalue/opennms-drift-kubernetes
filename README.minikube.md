# Setup Cluster with Minikube

For testing purposes, it would be nice to be able to start a reduced version of this lab through `minikube`.

For this reason, the `kustomize` tool is used to generate a modified version of the templates, in order to be able to use them with `minikube`.

## Requirements

* Install the [minikube](https://kubernetes.io/docs/tasks/tools/install-minikube/) binary on your machine.

## Cluster Configuration

In order to do that, just start minikube, and make sure it has at least 4 Cores and 16GB of RAM:

```bash
minikube config view
- cpus: 4
- ingress: true
- memory: 16384
```

> *NOTE*: The solution was tested with Kubernetes 1.14.8 and 1.15.6. Newer versions of Kubernetes have not been tested yet.

## Install the CertManager

The [cert-manager](https://cert-manager.readthedocs.io/en/latest/) add-on is required in order to provide HTTP/TLS support through [LetsEncrypt](https://letsencrypt.org) to the HTTP services managed by the ingress controller. Although, for `minikube`, a self-signed certificate will be used.

```bash
kubectl create namespace cert-manager
kubectl apply --validate=false -f https://github.com/jetstack/cert-manager/releases/download/v0.13.1/cert-manager.yaml
```

> **NOTE**: For more details, check the [installation guide](http://docs.cert-manager.io/en/latest/getting-started/install.html). For now, this is not used when using minikube.

## Install Jaeger CRDs

```bash
kubectl apply -f https://raw.githubusercontent.com/jaegertracing/jaeger-operator/master/deploy/crds/jaegertracing.io_jaegers_crd.yaml
```

## Manifets

Once `minikube` is running, execute the following to apply a reduced version of the original YAML files located at the [manifests](manifests) directory, that fits the suggested settings.

```bash
kubectl apply -k minikube
```

## Install Jaeger Tracing

```bash
kubectl apply -n opennms -f https://raw.githubusercontent.com/jaegertracing/jaeger-operator/master/deploy/service_account.yaml
kubectl apply -n opennms -f https://raw.githubusercontent.com/jaegertracing/jaeger-operator/master/deploy/role.yaml
kubectl apply -n opennms -f https://raw.githubusercontent.com/jaegertracing/jaeger-operator/master/deploy/role_binding.yaml
kubectl apply -n opennms -f https://raw.githubusercontent.com/jaegertracing/jaeger-operator/master/deploy/operator.yaml
```

## DNS

Update `/etc/hosts` with the FQDN used by the ingresses. For example:

ONMS_INGRESS=$(kubectl get ingress -n opennms onms-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
GRPC_INGRESS=$(kubectl get ingress -n opennms grpc-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
```bash
cat <<EOF | sudo tee -a /etc/hosts
$ONMS_INGRESS onms.minikube.local
$ONMS_INGRESS grafana.minikube.local
$ONMS_INGRESS kafka-manager.minikube.local
$ONMS_INGRESS tracing.minikube.local
$GRPC_INGRESS grpc.minikube.local
EOF
```

> **WARNING**: Keep in mind that the certificates are self-signed.

# Start Minion

```bash
mkdir -p overlay
kubectl get secret opennms-ingress-cert -n opennms -o json | jq -r '.data["tls.crt"]' | base64 --decode > overlay/onms_server.crt
kubectl get secret grpc-ingress-cert -n opennms -o json | jq -r '.data["tls.crt"]' | base64 --decode > overlay/grpc_server.crt
keytool -importcert -alias grpc -file overlay/grpc_server.crt -storepass 0p3nNM5 -keystore overlay/grpc_trust.jks -noprompt
keytool -importcert -alias onms -file overlay/onms_server.crt -storepass 0p3nNM5 -keystore overlay/grpc_trust.jks -noprompt
JAVA_OPTS="-Djavax.net.ssl.trustStore=/opt/minion/etc/grpc_trust.jks -Djavax.net.ssl.trustStorePassword=0p3nNM5"

docker run -it --rm --name minion \
 -e OPENNMS_HTTP_USER=admin \
 -e OPENNMS_HTTP_PASS=admin \
 -e JAVA_OPTS=$JAVA_OPTS \
 -p 8201:8201 \
 -p 1514:1514/udp \
 -p 1162:1162/udp \
 -p 50000:50000/udp \
 -v $(pwd)/overlay:/opt/minion-etc-overlay \
 -v $(pwd)/minikube/minion.yaml:/opt/minion/minion-config.yaml \
 opennms/minion:26.0.0 -f
```
