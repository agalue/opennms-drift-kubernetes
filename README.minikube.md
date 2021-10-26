# Setup Cluster with Minikube

For testing purposes, it would be nice to be able to start a reduced version of this lab through `minikube`.

For this reason, we use `kustomize` to generate a reduced version of the templates through `kubectl`.

## Requirements

* Install the [minikube](https://kubernetes.io/docs/tasks/tools/install-minikube/) binary on your machine; version 1.22.x or newer recommended.

> **WARNING:** Please note that all the manifests were verified for Kubernetes 1.20. If you're going to use a newer version, please adjust the API versions of the manifests. In particular, `batch/v1beta1` for `CrobJobs` in [elasticsearch.curator.yaml](manifests/elasticsearch.curator.yaml), and `policy/v1beta1` for `PodDisruptionBudget` in [zookeeper.yaml](manifests/zookeeper.yaml). Similarly, if you're planing to use a version is older than 1.20, make sure to do the same for `networking.k8s.io/v1` in [external-access.yaml](manifests/external-access.yaml).

## Cluster Configuration

Start minikube with the following recommended settings:

```bash
minikube start --cpus=8 --memory=32g --disk-size=60g \
  --cni=calico \
  --container-runtime=containerd \
  --addons=ingress \
  --addons=ingress-dns \
  --addons=metrics-server
```

> **IMPORTANT**: on macOS, it is better to use Hyperkit rather than VirtualBox, as I found it a lot faster to work with. You can enforce it by passing `--driver hyperkit`.

Depending on the version you're running, you might encounter problems when creating ingress resources due to admission control validations. The following is a workaround you could use:

```bash
kubectl delete -A ValidatingWebhookConfiguration ingress-nginx-admission
```

## Install the CertManager

The [cert-manager](https://cert-manager.readthedocs.io/en/latest/) add-on is required in order to provide HTTP/TLS support through [LetsEncrypt](https://letsencrypt.org) to the HTTP services managed by the ingress controller. Although, for `minikube`, a self-signed certificate will be used.

```bash
CMVER=$(curl -s https://api.github.com/repos/jetstack/cert-manager/releases/latest | grep tag_name | cut -d '"' -f 4)
kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/$CMVER/cert-manager.yaml
```

> **NOTE**: For more details, check the [installation guide](http://docs.cert-manager.io/en/latest/getting-started/install.html).

## Install Jaeger CRDs

```bash
kubectl apply -f https://raw.githubusercontent.com/jaegertracing/jaeger-operator/master/deploy/crds/jaegertracing.io_jaegers_crd.yaml
```

## Manifets

Execute the following to apply a reduced version of the original YAML files located at the [manifests](manifests) directory, that fits the suggested settings.

```bash
kubectl apply -k minikube
```

It could about 15 minutes to have all the components up and running compared to cloud-based solutions (as we have one node, despite the resource reduction), which is why I encourage you to use a cloud-based solution or a bare-metal Kubernetes cluster.

## Install Jaeger Tracing

```bash
kubectl apply -n opennms -f https://raw.githubusercontent.com/jaegertracing/jaeger-operator/master/deploy/service_account.yaml
kubectl apply -n opennms -f https://raw.githubusercontent.com/jaegertracing/jaeger-operator/master/deploy/role.yaml
kubectl apply -n opennms -f https://raw.githubusercontent.com/jaegertracing/jaeger-operator/master/deploy/role_binding.yaml
kubectl apply -n opennms -f https://raw.githubusercontent.com/jaegertracing/jaeger-operator/master/deploy/operator.yaml
```

## DNS

Please take a look at the documentation of [ingress-dns](https://github.com/kubernetes/minikube/tree/master/deploy/addons/ingress-dns) for more information about how to use it, to avoid messing with `/etc/hosts`.

For instance, for macOS:

```bash
cat <<EOF | sudo tee /etc/resolver/minikube-default-test
domain test
nameserver $(minikube ip)
search_order 1
timeout 5
EOF
```

> **WARNING**: Keep in mind that the certificates used here are self-signed.

# Start Minion

From the directory on which you checked out this repository, do the following:

```bash
sed 's/aws.agalue.net/test/' minion.yaml > minion-minikube.yaml

kubectl get secret minion-cert -n opennms -o json | jq -r '.data["tls.crt"]' | base64 --decode > client.pem
kubectl get secret minion-cert -n opennms -o json | jq -r '.data["tls.key"]' | base64 --decode > client-key.pem
openssl pkcs8 -topk8 -nocrypt -in client-key.pem -out client-pkcs8_key.pem

kubectl get secret onms-ca -n opennms -o json | jq -r '.data["tls.crt"]' | base64 --decode > onms-ca.pem
keytool -importcert -alias onms-ca -file onms-ca.pem -storepass 0p3nNM5 -keystore onms-ca-trust.jks -noprompt

docker run --name minion \
 -e OPENNMS_HTTP_USER=admin \
 -e OPENNMS_HTTP_PASS=admin \
 -e JAVA_OPTS="-Djavax.net.ssl.trustStore=/opt/minion/etc/onms-ca-trust.jks -Djavax.net.ssl.trustStorePassword=0p3nNM5" \
 -p 8201:8201 \
 -p 1514:1514/udp \
 -p 1162:1162/udp \
 -p 8877:8877/udp \
 -p 11019:11019 \
 -v $(pwd)/client.pem:/opt/minion/etc/client.pem \
 -v $(pwd)/client-pkcs8_key.pem:/opt/minion/etc/client-key.pem \
 -v $(pwd)/onms-ca-trust.jks:/opt/minion/onms-ca-trust.jks \
 -v $(pwd)/minion-minikube.yaml:/opt/minion/minion-config.yaml \
 opennms/minion:28.1.1 -c
```

> **IMPORTANT**: Make sure to use the same version as OpenNMS. The above requires using a custom content for the `INSTANCE_ID` (see [minion.yaml](minion.yaml)). Make sure it matches the content of [kustomization.yaml](manifests/kustomization.yaml).

# Cleanup

```bash
sudo rm -f /etc/resolver/minikube-default-test
minikube delete
rm -f *.pem *.jks minion-minikube.yaml
```
