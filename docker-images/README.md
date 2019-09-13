Custom version of Docker Images
=====

A custom set of docker images have been built based on the latest state for H24 from the following repositories:

* https://github.com/opennms-forge/docker-horizon-core-web
* https://github.com/opennms-forge/docker-minion
* https://github.com/opennms-forge/docker-sentinel

List of changes:

* Reorganize environment variables and the defaults to avoid extra layers, and simplify deployment.
* Re-group labels
* Install additional packages for OpenNMS: `epel-release`, `jq`, `perl(LWP)`, `perl(XML::Twig)`
* Default entry point parameter to be `-s` instead of `-f`.
* Added netcap/jli changes for OpenJDK 11, to run as non-root on Minion and Sentinel.
* Copy `/etc/skel/.bash*` to have a nice shell when accessing the containers as non-root on Minion and Sentinel.
* Added `jicmp` and `jicmp6` to Minion.
* Adding `umask 002` to Minion's docker-entrypoint.sh

Notes:

* The perl packages are requires to use provision.pl within the OpenNMS image.
