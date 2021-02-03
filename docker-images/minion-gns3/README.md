# Minion image based on Ubuntu 18 for GNS3

This is a special version of the Minion image that runs as root on Ubuntu, in order to allow it to run within GNS3, be able to pass NIC information (to connect it to virtual devices within GNS3), and pass all the required fields via environment variables, as passing files is not an option, and the solution uses gRPC; which is why the official minion-gns3 image cannot be used.

Environment Variables:

* `GRPC_SRV` gRPC server FQDN or IP Address (defaults to `grpc.aws.agalue.net`)
* `GRPC_PORT` gRPC server port (defaults to `443`)
* `GRPC_TLS` with `true` to enable TLS or `false` to disable it (defaults to `true`)
* `ONMS_URL` The OpenNMS Base URL (defaults to `https://onms.aws.agalue.net/opennms`)
* `LOCATION` The Minion Location (defaults to `GNS3`)

Enabled Features:

* NetFlow 5 listener on port 8877
* NetFlow 9 listener on port 4729
* IPFIX listener on port 4738
* SFlow listener on port 6343
* NX-OS (Telemetry) listener on port 50001
* Syslog listener on port 514
* SNMP Trap listener on port 162
