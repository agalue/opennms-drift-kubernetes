#!/bin/bash
# @author Alejandro Galue <agalue@opennms.org>
#
# Requirements:
# - Horizon 27 or newer is required.
# - Config overlay volume mounted at /opt/opennms-etc-overlay
# - Webinf overlay volume mounted at /opt/opennms-jetty-webinf-overlay
# - Must run within a init-container based on the opennms/horizon image.
#   Version must match the runtime container.
# - The following commands must be pre-installed on the chosen image:
#   jq, curl
#
# Purpose:
# - Apply recommended changes to force OpenNMS to be a read-only WebUI server.
#   Only Eventd, Jetty and Karaf will be running.
# - Apply mandatory configuration changes based on the provided variables.
#
# External Environment variables:
# - INSTANCE_ID
# - CASSANDRA_SERVER
# - ELASTIC_SERVER
# - ELASTIC_PASSWORD
# - ELASTIC_INDEX_STRATEGY_FLOWS
# - GRAFANA_URL
# - GRAFANA_PUBLIC_URL
# - GF_SECURITY_ADMIN_PASSWORD

# To avoid issues with OpenShift
umask 002

command -v jq   >/dev/null 2>&1 || { echo >&2 "jq is required but it's not installed. Aborting.";   exit 1; }
command -v curl >/dev/null 2>&1 || { echo >&2 "curl is required but it's not installed. Aborting."; exit 1; }

CONFIG_DIR=/opt/opennms-etc-overlay
WEB_DIR=/opt/opennms-jetty-webinf-overlay
KEYSPACE=$(echo ${INSTANCE_ID-onms}_newts | tr '[:upper:]' '[:lower:]')

mkdir -p ${CONFIG_DIR}/opennms.properties.d/
touch ${CONFIG_DIR}/configured

# Configure the instance ID
# Required when having multiple OpenNMS backends sharing the same Kafka cluster.
if [[ ${INSTANCE_ID} ]]; then
  echo "Configuring Instance ID..."
  cat <<EOF > ${CONFIG_DIR}/opennms.properties.d/instanceid.properties
# Used for Kafka Topics
org.opennms.instance.id=${INSTANCE_ID}
EOF
else
  INSTANCE_ID="OpenNMS"
fi

# Disable data choices (optional)
cat <<EOF > ${CONFIG_DIR}/org.opennms.features.datachoices.cfg
enabled=false
acknowledged-by=admin
acknowledged-at=Mon Jan 01 00\:00\:00 EDT 2018
EOF

# Trim down the events configuration, as event processing is not required for the WebUI
cat <<EOF > ${CONFIG_DIR}/eventconf.xml
<?xml version="1.0"?>
<events xmlns="http://xmlns.opennms.org/xsd/eventconf">
  <global>
    <security>
      <doNotOverride>logmsg</doNotOverride>
      <doNotOverride>operaction</doNotOverride>
      <doNotOverride>autoaction</doNotOverride>
      <doNotOverride>tticket</doNotOverride>
      <doNotOverride>script</doNotOverride>
    </security>
  </global>
EOF
grep 'events\/opennms' /opt/opennms/share/etc-pristine/eventconf.xml >> ${CONFIG_DIR}/eventconf.xml
cat <<EOF >> ${CONFIG_DIR}/eventconf.xml
</events>
EOF

# Trim down the services/daemons configuration, as only the WebUI will be running
cat <<EOF > ${CONFIG_DIR}/service-configuration.xml
<?xml version="1.0"?>
<service-configuration xmlns="http://xmlns.opennms.org/xsd/config/vmmgr">
  <service>
    <name>OpenNMS:Name=Manager</name>
    <class-name>org.opennms.netmgt.vmmgr.Manager</class-name>
    <invoke at="stop" pass="1" method="doSystemExit"/>
  </service>
  <service>
    <name>OpenNMS:Name=TestLoadLibraries</name>
    <class-name>org.opennms.netmgt.vmmgr.Manager</class-name>
    <invoke at="start" pass="0" method="doTestLoadLibraries"/>
  </service>
  <service>
    <name>OpenNMS:Name=Eventd</name>
    <class-name>org.opennms.netmgt.eventd.jmx.Eventd</class-name>
    <invoke at="start" pass="0" method="init"/>
    <invoke at="start" pass="1" method="start"/>
    <invoke at="status" pass="0" method="status"/>
    <invoke at="stop" pass="0" method="stop"/>
  </service>
  <service>
    <name>OpenNMS:Name=JettyServer</name>
    <class-name>org.opennms.netmgt.jetty.jmx.JettyServer</class-name>
    <invoke at="start" pass="0" method="init"/>
    <invoke at="start" pass="1" method="start"/>
    <invoke at="status" pass="0" method="status"/>
    <invoke at="stop" pass="0" method="stop"/>
  </service>
</service-configuration>
EOF

# Required changes in order to use HTTPS through Ingress
cat <<EOF > ${CONFIG_DIR}/opennms.properties.d/webui.properties
opennms.web.base-url=https://%x%c/
opennms.report.scheduler.enabled=false
org.opennms.security.disableLoginSuccessEvent=true
org.opennms.web.console.centerUrl=/status/status-box.jsp,/geomap/map-box.jsp,/heatmap/heatmap-box.jsp
org.opennms.web.defaultGraphPeriod=last_2_hour
EOF

# Guard against allowing administration changes through the WebUI
SECURITY_CONFIG=${WEB_DIR}/applicationContext-spring-security.xml
cp /opt/opennms/jetty-webapps/opennms/WEB-INF/applicationContext-spring-security.xml ${SECURITY_CONFIG}
sed -r -i 's/ROLE_ADMIN/ROLE_DISABLED/' ${SECURITY_CONFIG}
sed -r -i 's/ROLE_PROVISION/ROLE_DISABLED/' ${SECURITY_CONFIG}
sed -r -i -e '/intercept-url.*measurements/a\' -e '    <intercept-url pattern="/rest/resources/generateId" method="POST" access="ROLE_REST,ROLE_DISABLED,ROLE_USER"/>' ${SECURITY_CONFIG}

# Enabling CORS
WEB_CONFIG=${WEB_DIR}/web.xml
cp /opt/opennms/jetty-webapps/opennms/WEB-INF/web.xml ${WEB_CONFIG}
sed -r -i '/[<][!]--/{$!{N;s/[<][!]--\n  ([<]filter-mapping)/\1/}}' ${WEB_CONFIG}
sed -r -i '/nrt/{$!{N;N;s/(nrt.*\n  [<]\/filter-mapping[>])\n  --[>]/\1/}}' ${WEB_CONFIG}

# Configure Newts (works with either Cassandra or ScyllaDB)
# This has to match the configuration of the OpenNMS Core server.
if [[ ${CASSANDRA_SERVER} ]]; then
  echo "Configuring Cassandra..."
  cat <<EOF > ${CONFIG_DIR}/opennms.properties.d/newts.properties
# Warning:
# - Make sure the properties match the content of the core OpenNMS server

org.opennms.rrd.storeByGroup=true
org.opennms.rrd.storeByForeignSource=true

org.opennms.timeseries.strategy=newts
org.opennms.newts.config.hostname=${CASSANDRA_SERVER}
org.opennms.newts.config.keyspace=${KEYSPACE}
org.opennms.newts.config.port=9042
org.opennms.newts.config.read_consistency=ONE
org.opennms.newts.config.resource_shard=604800
EOF

  # Required only when collecting data every 30 seconds
  echo "Configuring Optional Newts Settings..."
  cat <<EOF >> ${CONFIG_DIR}/opennms.properties.d/newts.properties
org.opennms.newts.query.minimum_step=30000
org.opennms.newts.query.heartbeat=450000
EOF

fi

# Configure Elasticsearch for Flow processing
if [[ ${ELASTIC_SERVER} ]]; then
  echo "Configuring Elasticsearch for Flows..."
  PREFIX=$(echo ${INSTANCE_ID} | tr '[:upper:]' '[:lower:]')-
  cat <<EOF > ${CONFIG_DIR}/org.opennms.features.flows.persistence.elastic.cfg
elasticUrl=http://${ELASTIC_SERVER}:9200
globalElasticUser=elastic
globalElasticPassword=${ELASTIC_PASSWORD}
indexPrefix=${PREFIX}
elasticIndexStrategy=${ELASTIC_INDEX_STRATEGY_FLOWS}
EOF
fi

# Configure NXOS Resource Types
echo "Configuring NXOS resource types..."
mkdir -p ${CONFIG_DIR}/resource-types.d/
cat <<EOF > ${CONFIG_DIR}/resource-types.d/nxos-intf-resources.xml
<?xml version="1.0"?>
<resource-types>
  <resourceType name="nxosIntf" label="Nxos Interface" resourceLabel="\${index}">
    <persistenceSelectorStrategy class="org.opennms.netmgt.collection.support.PersistAllSelectorStrategy"/>
    <storageStrategy class="org.opennms.netmgt.collection.support.IndexStorageStrategy"/>
  </resourceType>
</resource-types>
EOF

# Enable Grafana features
if [[ ${GRAFANA_PUBLIC_URL} ]] && [[ ${GRAFANA_URL} ]] && [[ ${GF_SECURITY_ADMIN_PASSWORD} ]]; then
  GRAFANA_AUTH="admin:${GF_SECURITY_ADMIN_PASSWORD}"
  FLOW_DASHBOARD=$(curl -u "${GRAFANA_AUTH}" "${GRAFANA_URL}/api/search?query=flow" 2>/dev/null | jq '.[0].url' | sed 's/"//g')
  echo "Flow Dashboard: ${FLOW_DASHBOARD}"
  if [ "${FLOW_DASHBOARD}" != "null" ]; then
    cat <<EOF > ${CONFIG_DIR}/org.opennms.netmgt.flows.rest.cfg
flowGraphUrl=${GRAFANA_PUBLIC_URL}${FLOW_DASHBOARD}?node=\$nodeId&interface=\$ifIndex
EOF
  else
    echo "WARNING: cannot get Dashboard URL for the Deep Dive Tool"
  fi

  KEY_ID=$(curl -u "${GRAFANA_AUTH}" "${GRAFANA_URL}/api/auth/keys" 2>/dev/null | jq '.[] | select(.name="opennms-ui") | .id')
  if [ "${KEY_ID}" != "" ]; then
    echo "WARNING: API Key exist, deleting it prior re-creating it again"
    curl -XDELETE -u "${GRAFANA_AUTH}" "${GRAFANA_URL}/api/auth/keys/${KEY_ID}" 2>/dev/null
    echo ""
  fi
  GRAFANA_KEY=$(curl -u "${GRAFANA_AUTH}" -X POST -H "Content-Type: application/json" -d '{"name":"opennms-ui", "role": "Viewer"}' "${GRAFANA_URL}/api/auth/keys" 2>/dev/null | jq .key - | sed 's/"//g')
  if [ "${GRAFANA_KEY}" != "null" ]; then
    echo "Configuring Grafana Box..."
    GRAFANA_HOSTNAME=$(echo "${GRAFANA_PUBLIC_URL}" | sed -E 's/http[s]?:|\///g')
    mkdir -p ${CONFIG_DIR}/opennms.properties.d/
    cat <<EOF > ${CONFIG_DIR}/opennms.properties.d/grafana.properties
org.opennms.grafanaBox.show=true
org.opennms.grafanaBox.hostname=${GRAFANA_HOSTNAME}
org.opennms.grafanaBox.port=443
org.opennms.grafanaBox.basePath=/
org.opennms.grafanaBox.apiKey=${GRAFANA_KEY}
EOF
  else
    echo "WARNING: cannot get Grafana Key"
  fi
fi
