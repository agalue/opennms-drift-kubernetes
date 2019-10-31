# K8s To OpenNMS

This is a tool to retrieve all the running Pods from a given namespace, generate a requisition and push it to OpenNMS through the ReST API.

When the Pod has special labels, a Monitored Service will be added to the node definition.

Currenlty supported labels are: `kafka`, `cassandra`, `postgresql`, `elasticsearch`.

The script expects the following flags:

* `-url`, the OpenNMS Base URL. Defaults to `https://onms.aws.agalue.net/opennms`.
* `-user`, the username to access the OpenNMS ReST API. Defaults to `admin`.
* `-passwd`, the password to access the OpenNMS ReST API. Defaults to `admin`.
* `-namespace`, the Kubernetes namespace to analyze. Defaults to `opennms`.
* `-requisition`, the name of the requisition. Defaults to `Kubernetes`.
* `-config`, the full path to the Kubernetes Config to access the cluster. Defaults to `~/.kube/config`.
