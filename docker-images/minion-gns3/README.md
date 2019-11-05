# Minion image based on Ubuntu 18 for GNS3

This is a special version of the Minion image that runs as root on Ubuntu, in order to allow it to run within GNS3.

* Use Kafka as a broker
* Kafka URL is expected to be at `kafka.aws.agalue.net:9094`
* The OpenNMS Base URL is expected to be at `https://onms.aws.agalue.net/opennms`
* NetFlow 5 listener on port 8877
* NetFlow 9 listener on port 4729
* IPFIX listener on port 4738
* SFlow listener on port 6343
* NX-OS (Telemetry) listener on port 50001
* Syslog listener on port 514
* SNMP Trap listener on port 162
