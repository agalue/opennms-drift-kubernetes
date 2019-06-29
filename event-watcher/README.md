Kubernetes Event Watcher
====

This application watches core Kubernetes events and forward them to OpenNMS through its ReST API.

This is a PoC of having a way to export internal Kubernetes events to OpenNMS.

The current implementation is very simple and doesn't have the intelligence required to avoid resending the events  when the Pod is restarted. Upcoming versions will have this fixed.

# Requirements

* A service account with get, list and watch access to namespaces, pods, services and events.
* `ONMS_URL` environment variable with the base URL of the OpenNMS WebUI.
* `ONMS_USER` environment variable with a user with `ROLE_REST` or `ROLE_ADMIN`.
* `ONMS_PASSWD` environment variable with the password for `ONMS_USER`.
* The events definitions configured in OpenNMS.

# Implemented OpenNMS Events

* uei.opennms.org/kubernetes/pod/ADDED
* uei.opennms.org/kubernetes/pod/DELETED
* uei.opennms.org/kubernetes/service/ADDED
* uei.opennms.org/kubernetes/service/DELETED
* uei.opennms.org/kubernetes/event/Warning

The first 4 events are straight forward. The last one covers different scenarios of Warning failures detected on Pods like invalid images, resource constraints problems, etc.

# Build

In order to build the application:

```bash
docker build -t agalue/onms-k8s-watcher-go:1.0-SNAPSHOT .
docker push agalue/onms-k8s-watcher-go:1.0-SNAPSHOT
```

> *NOTE*: Please use your own Docker Hub account or use the image provided on my account.

To build the controller localy for testing:

```bash
go mod init github.com/agalue/event-watcher
go build
```

> *NOTE*: Please use your own GitHub account.

The controller will use `KUBECONFIG` if the environment variable exist and points to the appropriate configuration file. Otherwise it will assume it is running within Kubernetes.

# Permissions

Do not forget to configure the service account

```yaml
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: event-watcher-user
  namespace: opennms

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: event-watcher-role
rules:
- apiGroups:
  - ""
  resources:
  - pods
  - namespaces
  - services
  - events
  verbs:
  - get
  - list
  - watch

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: event-watcher-binding
subjects:
  - kind: ServiceAccount
    name: event-watcher-user
    namespace: opennms
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: event-watcher-role
```
