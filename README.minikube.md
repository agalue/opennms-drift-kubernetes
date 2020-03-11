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

The [cert-manager](https://cert-manager.readthedocs.io/en/latest/) add-on is required in order to provide HTTP/TLS support through [LetsEncrypt](https://letsencrypt.org) to the HTTP services managed by the ingress controller.

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

To be able to use the Ingress controller with TLS (even if CertManager is not being in use), a good trick to test it is adding entries to `/etc/hosts` pointing to the IP of the ingress. For example:

```bash
$ kubectl get ingress -n opennms
NAME            HOSTS                                                                                 ADDRESS          PORTS     AGE
ingress-rules   onms.minikube.local,grafana.minikube.local,kafka-manager.minikube.local + 1 more...   192.168.99.106   80, 443   21m
```

Then,

```bash
cat <<EOF | sudo tee /etc/hosts
192.168.99.106 onms.minikube.local
192.168.99.106 grafana.minikube.local
192.168.99.106 kafka-manager.minikube.local
192.168.99.106 tracing.minikube.local
EOF
```

> **WARNING**: Keep in mind that the certificates are self-signed.

> **IMPORTANT**: Access to the gRPC server is pending.
