#!/bin/sh

until pg_isready -h $DATABASE_HOST; do
  echo "Waiting for postgresql host $DATABASE_HOST..."
  sleep 2
done

echo "*:*:*:$DATABASE_ROOT_USER:$DATABASE_ROOT_PASSWORD" > ~/.pgpass
chmod 0600 ~/.pgpass

if ! psql -U $DATABASE_ROOT_USER -h $DATABASE_HOST -lqt | cut -d \| -f 1 | grep -qw $DATABASE_NAME; then
  echo "Creating grafana user and database on $DATABASE_HOST..."
  createdb -U $DATABASE_ROOT_USER -h $DATABASE_HOST -E UTF-8 $DATABASE_NAME
  createuser -U $DATABASE_ROOT_USER -h $DATABASE_HOST $DATABASE_USER
  psql -U $DATABASE_ROOT_USER -h $DATABASE_HOST -c "alter role $DATABASE_USER with password '$DATABASE_PASSWORD';"
  psql -U $DATABASE_ROOT_USER -h $DATABASE_HOST -c "grant all on database $DATABASE_NAME to $DATABASE_USER;"
else
  echo "Grafana database already created on $DATABASE_HOST, skipping..."
fi

rm -f ~/.pgpass
