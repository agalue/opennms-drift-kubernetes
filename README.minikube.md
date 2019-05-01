# Setup Cluster with Minikube

For testing purposes, it would be nice to be able to start a reduced version of this lab through `minikube`.

For this reason, the `kustomize` tool is used to generate a modified version of the templates, in order to be able to use them with `minikube`.

## Requirements

* Install the [minikube](https://kubernetes.io/docs/tasks/tools/install-minikube/) binary on your machine.

## Cluster Configuration

In order to do that, just start minikube, and make sure it has at least 2 Cores and 8GB of RAM:

```shell
minikube config view
- metrics-server: true
- WantReportError: true
- cpus: 2
- dashboard: true
- heapster: false
- ingress: true
- memory: 8192
```

## Deploy the applications

Once `minikube` is running, execute the following to apply a reduced version of the original YAML files located at the [manifests](manifests) directory, that fits the suggested settings.

```shell
kustomize build minikube | sed 's/[{}]*//' | kubectl apply -f -
```

> **WARNING**: There are a few issues when deleting resources, hance the patch with `sed`.
