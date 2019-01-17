#!/bin/bash
# @author Alejandro Galue <agalue@opennms.org>

# External Environment variables:
#
# CASSANDRA_SERVER
# ELASTIC_SERVER
# GRAFANA_URL
# GRAFANA_PUBLIC_URL
# GF_SECURITY_ADMIN_PASSWORD

CONFIG_DIR=/opt/opennms-etc-overlay
WEB_DIR=/opt/opennms-jetty-webinf-overlay

mkdir -p $CONFIG_DIR/opennms.properties.d/
touch $CONFIG_DIR/configured

cat <<EOF > $CONFIG_DIR/org.opennms.features.datachoices.cfg
enabled=false
acknowledged-by=admin
acknowledged-at=Mon Jan 01 00\:00\:00 EDT 2018
EOF

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

cat <<EOF > $CONFIG_DIR/opennms.properties.d/webui.properties
opennms.web.base-url = https://%x%c/
org.opennms.security.disableLoginSuccessEvent=true
org.opennms.web.console.centerUrl=/status/status-box.jsp,/geomap/map-box.jsp,/heatmap/heatmap-box.jsp
EOF

SECURITY_CONFIG=$WEB_DIR/applicationContext-spring-security.xml
cp /opt/opennms/jetty-webapps/opennms/WEB-INF/applicationContext-spring-security.xml $SECURITY_CONFIG
sed -r -i 's/ROLE_ADMIN/ROLE_DISABLED/' $SECURITY_CONFIG
sed -r -i 's/ROLE_PROVISION/ROLE_DISABLED/' $SECURITY_CONFIG

if [[ $CASSANDRA_SERVER ]]; then
  echo "Configuring Cassandra..."

  cat <<EOF > $CONFIG_DIR/opennms.properties.d/newts.properties
org.opennms.rrd.storeByGroup=true
org.opennms.rrd.storeByForeignSource=true

org.opennms.timeseries.strategy=newts
org.opennms.newts.config.hostname=$CASSANDRA_SERVER
org.opennms.newts.config.keyspace=newts
org.opennms.newts.config.port=9042
org.opennms.newts.config.read_consistency=ONE
org.opennms.newts.config.write_consistency=ANY

org.opennms.newts.query.minimum_step=30000
org.opennms.newts.query.heartbeat=450000
EOF
fi

if [[ $ELASTIC_SERVER ]]; then
  echo "Configuring Elasticsearch..."

  cat <<EOF > $CONFIG_DIR/org.opennms.features.flows.persistence.elastic.cfg
elasticUrl=http://$ELASTIC_SERVER:9200
globalElasticUser=elastic
globalElasticPassword=elastic
EOF
fi

if [[ $GRAFANA_PUBLIC_URL ]] && [[ $GRAFANA_URL ]] && [[ $GF_SECURITY_ADMIN_PASSWORD ]]; then
  GRAFANA_AUTH="admin:$GF_SECURITY_ADMIN_PASSWORD"

  yum -q -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
  yum -q -y install jq

  FLOW_DASHBOARD=$(curl -u $GRAFANA_AUTH "$GRAFANA_URL/api/search?query=flow" 2>/dev/null | jq '.[0].url' | sed 's/"//g')
  cat <<EOF > $CONFIG_DIR/org.opennms.netmgt.flows.rest.cfg
flowGraphUrl=$GRAFANA_PUBLIC_URL$FLOW_DASHBOARD?node=\$nodeId&interface=\$ifIndex
EOF

  GRAFANA_KEY=$(curl -u $GRAFANA_AUTH -X POST -H "Content-Type: application/json" -d '{"name":"opennms-ui", "role": "Viewer"}' $GRAFANA_URL/api/auth/keys 2>/dev/null | jq .key - | sed 's/"//g')
  if [ "$GRAFANA_KEY" != "null" ]; then
    GRAFANA_HOSTNAME=$(echo $GRAFANA_URL | sed -E 's/http[s]?:|\///g')
    cat <<EOF > $opennms_etc/opennms.properties.d/grafana.properties
org.opennms.grafanaBox.show=true
org.opennms.grafanaBox.hostname=$GRAFANA_HOSTNAME
org.opennms.grafanaBox.port=443
org.opennms.grafanaBox.basePath=/
org.opennms.grafanaBox.apiKey=$GRAFANA_KEY
EOF
  fi
fi