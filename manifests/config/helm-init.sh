#!/bin/bash
# @author Alejandro Galue <agalue@opennms.org>
#
# Purpose:
# - Enable the Helm plugin and initialize the data sources, if Helm is disable.
#
# Mandatory Environment variables:
# - GF_SECURITY_ADMIN_PASSWORD
# - GRAFANA_URL

GRAFANA_AUTH="admin:${GF_SECURITY_ADMIN_PASSWORD}"
HELM_URL="${GRAFANA_URL}/api/plugins/opennms-helm-app/settings"
DS_URL="${GRAFANA_URL}/api/datasources"

JSON_FILE=/tmp/data.json
cat <<EOF > ${JSON_FILE}
{
  "name": "opennms-performance",
  "type": "opennms-helm-performance-datasource",
  "access": "proxy",
  "url": "${ONMS_URL}",
  "basicAuth": true,
  "basicAuthUser": "${ONMS_USER}",
  "basicAuthPassword": "${ONMS_PASSWD}"
}
EOF

until curl --output /dev/null --silent --head --fail "${GRAFANA_URL}"; do
  echo "$(date) Waiting for grafana to be ready on ${GRAFANA_URL} ..."
  sleep 5
done

echo "$(date) Checking if OpenNMS Helm is enabled..."
if curl -u "${GRAFANA_AUTH}" "${HELM_URL}" 2>/dev/null | grep -q '"enabled":false'; then
  echo
  echo "$(date) Enabling OpenNMS Helm..."
  curl -u "${GRAFANA_AUTH}" -XPOST "${HELM_URL}" -d "id=opennms-helm-app&enabled=true" 2>/dev/null
  echo
  echo "$(date) Adding data source for performance metrics..."
  curl -u "${GRAFANA_AUTH}" -H 'Content-Type: application/json' -XPOST -d @${JSON_FILE} "${DS_URL}" 2>/dev/null
  echo
  echo "$(date) Adding data source for entities..."
  sed -i -r 's/-performance/-entity/g' ${JSON_FILE}
  curl -u "${GRAFANA_AUTH}" -H 'Content-Type: application/json' -XPOST -d @${JSON_FILE} "${DS_URL}" 2>/dev/null
  echo
  echo "$(date) Adding data source for flows..."
  sed -i -r 's/-entity/-flow/g' ${JSON_FILE}
  curl -u "${GRAFANA_AUTH}" -H 'Content-Type: application/json' -XPOST -d @${JSON_FILE} "${DS_URL}" 2>/dev/null
else
  echo "$(date) OpenNMS Helm was already enabled and configured."
fi

rm -f ${JSON_FILE}
