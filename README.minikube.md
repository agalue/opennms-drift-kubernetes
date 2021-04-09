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
  --addons=metrics-server
```

> **WARNING**: it could take time to have all the components up and running compared to cloud-based solutions, which is why I encourage to use a cloud provider or a bare-metal Kubernetes cluster.

> **IMPORTANT**: on macOS, it is better to use Hyperkit rather than VirtualBox, as I found it a lot faster to work with. You can enforce it by passing `--driver hyperkit`.

## Install the CertManager

The [cert-manager](https://cert-manager.readthedocs.io/en/latest/) add-on is required in order to provide HTTP/TLS support through [LetsEncrypt](https://letsencrypt.org) to the HTTP services managed by the ingress controller. Although, for `minikube`, a self-signed certificate will be used.

```bash
kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v1.3.0/cert-manager.yaml
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
sed 's/aws.agalue.net/test/' minion.yaml > minion-minikube.yaml

docker run --name minion \
 -e OPENNMS_HTTP_USER=admin \
 -e OPENNMS_HTTP_PASS=admin \
 -e JAVA_OPTS=$JAVA_OPTS \
 -p 8201:8201 \
 -p 1514:1514/udp \
 -p 1162:1162/udp \
 -p 8877:8877/udp \
 -p 11019:11019 \
 -v $(pwd)/overlay:/opt/minion-etc-overlay \
 -v $(pwd)/minion-minikube.yaml:/opt/minion/minion-config.yaml \
 -v $(pwd)/minion.properties:/opt/minion-etc-overlay/custom.system.properties \
 opennms/minion:27.1.1 -c
```

> **IMPORTANT**: Make sure to use the same version as OpenNMS. The above contemplates using a custom content for the `INSTANCE_ID` (see [minion.properties](minion.properties)). Make sure it matches the content of [kustomization.yaml](manifests/kustomization.yaml).
