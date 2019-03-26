#!/bin/bash
# @author Alejandro Galue <agalue@opennms.org>
#
# Requirements:
# - Must run within a init-container based on opennms/horizon-core-web.
#   Version must match the runtime container.
# - Horizon 23 or newer is required.
# - The jq command is required, and it is installed through YUM at runtime,
#   so Internet access is required to use this script.
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
# - GRAFANA_URL
# - GRAFANA_PUBLIC_URL
# - GF_SECURITY_ADMIN_PASSWORD

# To avoid issues with OpenShift
umask 002

CONFIG_DIR=/opt/opennms-etc-overlay
WEB_DIR=/opt/opennms-jetty-webinf-overlay
KEYSPACE=${INSTANCE_ID-onms}_newts

mkdir -p $CONFIG_DIR/opennms.properties.d/
touch $CONFIG_DIR/configured

# Configure the instance ID
# Required when having multiple OpenNMS backends sharing the same Kafka cluster.
if [[ $INSTANCE_ID ]]; then
  echo "Configuring Instance ID..."
  cat <<EOF > $CONFIG_DIR/opennms.properties.d/instanceid.properties
# Used for Kafka Topics
org.opennms.instance.id=$INSTANCE_ID
EOF
fi

# Disable data choices (optional)
cat <<EOF > $CONFIG_DIR/org.opennms.features.datachoices.cfg
enabled=false
acknowledged-by=admin
acknowledged-at=Mon Jan 01 00\:00\:00 EDT 2018
EOF

# Trim down the events configuration, as event processing is not required for the WebUI
cat <<EOF > $CONFIG_DIR/eventconf.xml
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
  <event-file>events/opennms.ackd.events.xml</event-file>
  <event-file>events/opennms.alarm.events.xml</event-file>
  <event-file>events/opennms.alarmChangeNotifier.events.xml</event-file>
  <event-file>events/opennms.bsm.events.xml</event-file>
  <event-file>events/opennms.capsd.events.xml</event-file>
  <event-file>events/opennms.config.events.xml</event-file>
  <event-file>events/opennms.correlation.events.xml</event-file>
  <event-file>events/opennms.default.threshold.events.xml</event-file>
  <event-file>events/opennms.discovery.events.xml</event-file>
  <event-file>events/opennms.internal.events.xml</event-file>
  <event-file>events/opennms.linkd.events.xml</event-file>
  <event-file>events/opennms.mib.events.xml</event-file>
  <event-file>events/opennms.pollerd.events.xml</event-file>
  <event-file>events/opennms.provisioning.events.xml</event-file>
  <event-file>events/opennms.minion.events.xml</event-file>
  <event-file>events/opennms.remote.poller.events.xml</event-file>
  <event-file>events/opennms.reportd.events.xml</event-file>
  <event-file>events/opennms.syslogd.events.xml</event-file>
  <event-file>events/opennms.ticketd.events.xml</event-file>
  <event-file>events/opennms.tl1d.events.xml</event-file>
  <event-file>events/opennms.catch-all.events.xml</event-file>
</events>
EOF

# Trim down the services/daemons configuration, as only the WebUI will be running
cat <<EOF > $CONFIG_DIR/service-configuration.xml
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
cat <<EOF > $CONFIG_DIR/opennms.properties.d/webui.properties
opennms.web.base-url=https://%x%c/
org.opennms.security.disableLoginSuccessEvent=true
org.opennms.web.console.centerUrl=/status/status-box.jsp,/geomap/map-box.jsp,/heatmap/heatmap-box.jsp
EOF

# Guard against allowing administration changes through the WebUI
SECURITY_CONFIG=$WEB_DIR/applicationContext-spring-security.xml
cp /opt/opennms/jetty-webapps/opennms/WEB-INF/applicationContext-spring-security.xml $SECURITY_CONFIG
sed -r -i 's/ROLE_ADMIN/ROLE_DISABLED/' $SECURITY_CONFIG
sed -r -i 's/ROLE_PROVISION/ROLE_DISABLED/' $SECURITY_CONFIG

# Configure Newts (works with either Cassandra or ScyllaDB)
# This has to match the configuration of the OpenNMS Core server.
if [[ $CASSANDRA_SERVER ]]; then
  echo "Configuring Cassandra..."
  cat <<EOF > $CONFIG_DIR/opennms.properties.d/newts.properties
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
  cat <<EOF >> $CONFIG_DIR/opennms.properties.d/newts.properties
org.opennms.newts.query.minimum_step=30000
org.opennms.newts.query.heartbeat=450000
EOF

fi

# Configure Elasticsearch for Flow processing
if [[ $ELASTIC_SERVER ]]; then
  echo "Configuring Elasticsearch for Flows..."
  cat <<EOF > $CONFIG_DIR/org.opennms.features.flows.persistence.elastic.cfg
elasticUrl=http://$ELASTIC_SERVER:9200
globalElasticUser=elastic
globalElasticPassword=$ELASTIC_PASSWORD
elasticIndexStrategy=daily
EOF
fi

# Enable Grafana features
if [[ $GRAFANA_PUBLIC_URL ]] && [[ $GRAFANA_URL ]] && [[ $GF_SECURITY_ADMIN_PASSWORD ]]; then
  GRAFANA_AUTH="admin:$GF_SECURITY_ADMIN_PASSWORD"

  yum -q -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
  yum -q -y install jq

  FLOW_DASHBOARD=$(curl -u $GRAFANA_AUTH "$GRAFANA_URL/api/search?query=flow" 2>/dev/null | jq '.[0].url' | sed 's/"//g')
  if [ "$FLOW_DASHBOARD" != "null" ]; then
    cat <<EOF > $CONFIG_DIR/org.opennms.netmgt.flows.rest.cfg
flowGraphUrl=$GRAFANA_PUBLIC_URL$FLOW_DASHBOARD?node=\$nodeId&interface=\$ifIndex
EOF
  else
    echo "WARNING: cannot get Dashboard URL for the Deep Dive Tool"
  fi

  KEY_ID=$(curl -u $GRAFANA_AUTH "$GRAFANA_URL/api/auth/keys" 2>/dev/null | jq '.[] | select(.name="opennms-ui") | .id')
  if [ "$KEY_ID" != "" ]; then
    echo "WARNING: API Key exist, deleting it prior re-creating it again"
    curl -XDELETE -u $GRAFANA_AUTH "$GRAFANA_URL/api/auth/keys/$KEY_ID"
  fi
  GRAFANA_KEY=$(curl -u $GRAFANA_AUTH -X POST -H "Content-Type: application/json" -d '{"name":"opennms-ui", "role": "Viewer"}' "$GRAFANA_URL/api/auth/keys" 2>/dev/null | jq .key - | sed 's/"//g')
  if [ "$GRAFANA_KEY" != "null" ]; then
    echo "Configuring Grafana Box..."
    GRAFANA_HOSTNAME=$(echo $GRAFANA_PUBLIC_URL | sed -E 's/http[s]?:|\///g')
    mkdir -p $CONFIG_DIR/opennms.properties.d/
    cat <<EOF > $CONFIG_DIR/opennms.properties.d/grafana.properties
org.opennms.grafanaBox.show=true
org.opennms.grafanaBox.hostname=$GRAFANA_HOSTNAME
org.opennms.grafanaBox.port=443
org.opennms.grafanaBox.basePath=/
org.opennms.grafanaBox.apiKey=$GRAFANA_KEY
EOF
  else
    echo "WARNING: cannot get Grafana Key"
  fi
fi
