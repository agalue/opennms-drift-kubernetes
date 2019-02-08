# Minikube

For testing purposes, it would be nice to be able to start a reduced version of this lab through `minikube`.

For this reason, the `kustomize` tool is used to generate a modified version of the templates, in order to be able to use them with `minikube`.

## Requirements

* Install the [minikube](https://kubernetes.io/docs/tasks/tools/install-minikube/) binary on your machine.
* Install the [kustomize](https://github.com/kubernetes-sigs/kustomize/blob/master/docs/INSTALL.md) binary on your machine.

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
- kubernetes-version: v1.13.3
- memory: 8192
```

## Deploy the applications

Once `minikube` is running, execute the following to modify the original YAML files designed for `kops` in order to run a reduced version of the environment here:

```shell
kustomize build | kubectl apply -f -
```

Of course, the ingresses, and the cert-manager are not going to run here for obviuos reasons.