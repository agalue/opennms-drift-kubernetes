#!/bin/sh
# @author Alejandro Galue <agalue@opennms.org>

# Mandatory Environment variables:
#
# PGHOST
# GF_DATABASE_NAME
# GF_DATABASE_USER
# GF_DATABASE_PASSWORD

until pg_isready; do
  echo "$(date) Waiting for postgresql host $PGHOST..."
  sleep 2
done

if ! psql -lqt | cut -d \| -f 1 | grep -qw $GF_DATABASE_NAME; then
  echo "Creating grafana user and database on $PGHOST..."
  createdb -E UTF-8 $GF_DATABASE_NAME
  createuser $GF_DATABASE_USER
  psql -c "alter role $GF_DATABASE_USER with password '$GF_DATABASE_PASSWORD';"
  psql -c "grant all on database $GF_DATABASE_NAME to $GF_DATABASE_USER;"
else
  echo "Grafana database already created on $PGHOST, skipping..."
fi
