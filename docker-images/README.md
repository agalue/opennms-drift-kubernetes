# Custom version of Docker Images

A custom set of docker images have been built based on the following repositories:

* [docker-horizon-core-web](https://github.com/opennms-forge/docker-horizon-core-web)
* [docker-minion](https://github.com/opennms-forge/docker-minion)
* [docker-sentinel](https://github.com/opennms-forge/docker-sentinel)

List of changes:

* Reorganize environment variables and the defaults to avoid extra layers, and simplify deployment.
* Add `netcap` abd `jli` changes for OpenJDK 11, to run as non-root on Minion and Sentinel.
* Add `skel` files to Minion and Sentinel.
* Run as non-root by default on all the Images.
* Add changes to the `opennms` scripts to run as non-root by default.
* Install additional packages for OpenNMS: `epel-release`, `jq`, `perl(LWP)`, `perl(XML::Twig)`, `net-tools`, `sshpass` `openssh-clients`.
* Default entry point parameter to be `-s` instead of `-f`.
* Adding `umask 002` to `docker-entrypoint.sh`.
* Adding a custom health check command (i.e. `/health.sh`) for Sentinel and Minion.
* Re-group labels.

Notes:

* The perl packages are requires to use `provision.pl` within the OpenNMS image.
* The `ssh` packages are required to properly implement a reliable health check as the Karaf CLI wrapper cannot be used.
