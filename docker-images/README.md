Custom version of Docker Images
=====

A custom set of docker images have been built based on the latest state for H24 from the following repositories:

* https://github.com/opennms-forge/docker-horizon-core-web
* https://github.com/opennms-forge/docker-minion
* https://github.com/opennms-forge/docker-sentinel

List of changes:

* Reorganize environment variables and the defaults to avoid extra layers, and simplify deployment.
* Re-group labels
* Install additional packages
  * For OpenNMS: `epel-release`, `jq`, `sshpass`, `openssh-clients`, `perl(LWP)`, `perl(XML::Twig)`
  * For Minion and Sentinel: `net-tools`, `sshpass`, `openssh-clients`
* Use OpenJDK 8 for Minion and Sentinel to avoid JAXB related issues found when testing H24.
* Default entry point parameter to be `-s` instead of `-f`.
* Added netcap/jli changes for OpenJDK 8, to run as non-root on Minion and Sentinel.

Notes:

* The SSH packages are a workaround to have access to the Karaf shell for the readiness/lifeness probes.
* The perl packages are requires to use provision.pl within the OpenNMS image.
