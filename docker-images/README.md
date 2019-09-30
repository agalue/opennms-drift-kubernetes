Custom version of Docker Images
=====

A custom set of docker images have been built based on the following repositories:

* https://github.com/opennms-forge/docker-horizon-core-web
* https://github.com/opennms-forge/docker-minion
* https://github.com/opennms-forge/docker-sentinel

List of changes:

* Reorganize environment variables and the defaults to avoid extra layers, and simplify deployment.
* Create the runtime for all the images before installing packages.
* Add netcap/jli changes for OpenJDK 11, to run as non-root on Minion and Sentinel.
* Install additional packages for OpenNMS: `epel-release`, `jq`, `perl(LWP)`, `perl(XML::Twig)`
* Default entry point parameter to be `-s` instead of `-f`.
* Adding `umask 002` to Minion's docker-entrypoint.sh
* Re-group labels

Notes:

* The perl packages are requires to use provision.pl within the OpenNMS image.
