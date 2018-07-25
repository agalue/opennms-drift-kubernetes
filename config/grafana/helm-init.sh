#!/bin/bash

GRAFANA_AUTH="admin:$GF_SECURITY_ADMIN_PASSWORD"
HELM_URL="$GRAFANA_URL/api/plugins/opennms-helm-app/settings"
DS_URL="$GRAFANA_URL/api/datasources"

JSON_FILE=/tmp/data.json
cat <<EOF > $JSON_FILE
{
  "name": "opennms-performance",
  "type": "opennms-helm-performance-datasource",
  "access": "proxy",
  "url": "$ONMS_URL",
  "basicAuth": true,
  "basicAuthUser": "$ONMS_USER",
  "basicAuthPassword": "$ONMS_PASSWD"
}
EOF

until $(curl --output /dev/null --silent --head --fail $GRAFANA_URL); do
  echo "$(date) Waiting for grafana to be ready on $GRAFANA_URL ..."
  sleep 5
done

if (( $( curl -u $GRAFANA_AUTH "$HELM_URL" 2>/dev/null | grep -c '"enabled":false' ) > 0 )); then
  echo "$(date) Enabling helm..."
  curl -u $GRAFANA_AUTH -XPOST "$HELM_URL" -d "id=opennms-helm-app&enabled=true" 2>/dev/null
  echo "$(date) Adding data source for performance metrics..."
  curl -u $GRAFANA_AUTH -H 'Content-Type: application/json' -XPOST -d @$JSON_FILE $DS_URL
  sed -i -r 's/-performance/-fault/g' $JSON_FILE
  echo "$(date) Adding data source for alarms..."
  curl -u $GRAFANA_AUTH -H 'Content-Type: application/json' -XPOST -d @$JSON_FILE $DS_URL
  sed -i -r 's/-fault/-flow/g' $JSON_FILE
  echo "$(date) Adding data source for flows..."
  curl -u $GRAFANA_AUTH -H 'Content-Type: application/json' -XPOST -d @$JSON_FILE $DS_URL
else
  echo "$(date) OpenNMS Helm was already enabled and configured."
fi

rm -f $JSON_FILE