#!/bin/sh

until pg_isready; do
  echo "$(date) Waiting for postgresql host $PGHOST..."
  sleep 2
done

if ! psql -lqt | cut -d \| -f 1 | grep -qw $DATABASE_NAME; then
  echo "Creating grafana user and database on $DATABASE_HOST..."
  createdb -E UTF-8 $DATABASE_NAME
  createuser $DATABASE_USER
  psql -c "alter role $DATABASE_USER with password '$DATABASE_PASSWORD';"
  psql -c "grant all on database $DATABASE_NAME to $DATABASE_USER;"
else
  echo "Grafana database already created on $DATABASE_HOST, skipping..."
fi
