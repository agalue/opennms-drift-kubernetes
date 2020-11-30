# Setup Cluster with Minikube

For testing purposes, it would be nice to be able to start a reduced version of this lab through `minikube`.

For this reason, the `kustomize` tool is used to generate a modified version of the templates, in order to be able to use them with `minikube`.

## Requirements

* Install the [minikube](https://kubernetes.io/docs/tasks/tools/install-minikube/) binary on your machine.

## Cluster Configuration

Start minikube with the following recommended settings:

```bash
minikube start --cpus=8 --memory=32g --disk-size=60g \
  --addons=ingress \
  --addons=ingress-dns \
  --addons=metrics-server \
  --kubernetes-version=v1.18.10
```

> **WARNING**: it could take time to have all the components up and running compared to cloud-based solutions, and I personally had a bad experiencing trying to make it work, which is why I encourage to use a cloud provider or a bare-metal Kubernetes cluster.

## Install the CertManager

The [cert-manager](https://cert-manager.readthedocs.io/en/latest/) add-on is required in order to provide HTTP/TLS support through [LetsEncrypt](https://letsencrypt.org) to the HTTP services managed by the ingress controller. Although, for `minikube`, a self-signed certificate will be used.

```bash
kubectl apply --validate=false -f https://github.com/jetstack/cert-manager/releases/download/v1.1.0/cert-manager.yaml
```

> **NOTE**: For more details, check the [installation guide](http://docs.cert-manager.io/en/latest/getting-started/install.html).

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

Please take a look at the documentation of [ingress-dns](https://github.com/kubernetes/minikube/tree/master/deploy/addons/ingress-dns) for more information about how to use it, to avoid messing with `/etc/hosts`.

> **WARNING**: Keep in mind that the certificates are self-signed.

# Start Minion

```bash
rm -rf overlay && mkdir -p overlay
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
 -p 11019:11019 \
 -v $(pwd)/overlay:/opt/minion-etc-overlay \
 -v $(pwd)/minikube/minion.yaml:/opt/minion/minion-config.yaml \
 opennms/minion:27.0.0 -f
```
