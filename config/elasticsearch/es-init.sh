#!/bin/sh

# This is to fix the permission on the volume. By default elasticsearch container won't run as non root user.
# https://www.elastic.co/guide/en/elasticsearch/reference/current/docker.html#_notes_for_production_use_and_defaults
chown -R 1000:1000 /usr/share/elasticsearch/data

# https://www.elastic.co/guide/en/elasticsearch/reference/current/docker.html#docker-cli-run-prod-mode
sysctl -w vm.max_map_count=262144

# https://www.elastic.co/guide/en/elasticsearch/reference/current/docker.html#_notes_for_production_use_and_defaults
ulimit -n 65536