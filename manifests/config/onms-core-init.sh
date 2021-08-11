#!/bin/bash
# @author Alejandro Galue <agalue@opennms.org>
#
# Requirements:
# - Horizon 27 or newer is required.
# - Must run within a init-container based on the opennms/horizon image.
#   Version must match the runtime container.
# - Target configuration volume at /opennms-etc
# - rsync must be pre-installed on the chosen image.
#
# Purpose:
# - Initialize the config directory on the volume only once.
# - Apply mandatory configuration changes based on the provided variables.
# - Be on guard against upgrades, by always overriding Karaf/OSGi configuration
#   files from the source, with embedded versions for multiple components.
#
# Warning:
# - Multiple assumptions are made on Newts/Cassandra configuration.
# - Do not include any file that can be changed through the WebUI or is intended
#   to represent customers/users needs. The configuration directory will be
#   behind a persistent volume, precisely to save user changes.
#
# Pending:
# - If the name of the newts keyspace is changed, poller-configuration.xml and the JMX
#   mbeans must be updated as well.
#
# External Environment variables:
# - INSTANCE_ID
# - FEATURES_LIST
# - ENABLE_ALEC
# - KAFKA_SERVER
# - KAFKA_SASL_USERNAME
# - KAFKA_SASL_PASSWORD
# - CASSANDRA_SERVER
# - CASSANDRA_DC
# - CASSANDRA_REPLICATION_FACTOR
# - ELASTIC_SERVER
# - ELASTIC_PASSWORD
# - ELASTIC_REPLICATION_FACTOR
# - ELASTIC_NUM_SHARDS
# - ELASTIC_INDEX_STRATEGY_FLOWS
# - ELASTIC_INDEX_STRATEGY_REST
# - ELASTIC_INDEX_STRATEGY_ALARMS
# - KAFKA_MAX_MESSAGE_SIZE
# - JAEGER_AGENT_HOST
# - FORWARD_METRICS

# To avoid issues with OpenShift
umask 002

command -v rsync >/dev/null 2>&1 || { echo >&2 "rsync is required but it's not installed. Aborting."; exit 1; }

ELASTIC_INDEX_STRATEGY_FLOWS=${ELASTIC_INDEX_STRATEGY_FLOWS-daily}
ELASTIC_INDEX_STRATEGY_REST=${ELASTIC_INDEX_STRATEGY_REST-monthly}
ELASTIC_INDEX_STRATEGY_ALARMS=${ELASTIC_INDEX_STRATEGY_ALARMS-monthly}
ELASTIC_REPLICATION_FACTOR=${ELASTIC_REPLICATION_FACTOR-2}
ELASTIC_NUM_SHARDS=${ELASTIC_NUM_SHARDS-6}
KAFKA_MAX_MESSAGE_SIZE=${KAFKA_MAX_MESSAGE_SIZE-5000000}
FORWARD_METRICS=${FORWARD_METRICS-true}

CONFIG_DIR=/opennms-etc
BACKUP_ETC=/opt/opennms/etc
KEYSPACE=$(echo ${INSTANCE_ID-onms}_newts | tr '[:upper:]' '[:lower:]')
KARAF_FILES=( \
"config.properties" \
"startup.properties" \
"custom.properties" \
"jre.properties" \
"profile.cfg" \
"jmx.acl.*" \
"org.apache.felix.*" \
"org.apache.karaf.*" \
"org.ops4j.pax.url.mvn.cfg" \
)

# Show permissions (debug purposes)
ls -ld ${CONFIG_DIR}

# Initialize configuration directory
if [ ! -f ${CONFIG_DIR}/configured ]; then
  echo "Initializing configuration directory for the first time ..."
  rsync -arO --no-perms ${BACKUP_ETC}/ ${CONFIG_DIR}/

  echo "Disabling data choices"
  cat <<EOF > ${CONFIG_DIR}/org.opennms.features.datachoices.cfg
enabled=false
acknowledged-by=admin
acknowledged-at=Mon Jan 01 00\:00\:00 EDT 2018
EOF

  echo "Initialize default foreign source definition"
  cat <<EOF > ${CONFIG_DIR}/default-foreign-source.xml
<foreign-source xmlns="http://xmlns.opennms.org/xsd/config/foreign-source" name="default" date-stamp="2018-01-01T00:00:00.000-05:00">
  <scan-interval>1d</scan-interval>
  <detectors>
    <detector name="ICMP" class="org.opennms.netmgt.provision.detector.icmp.IcmpDetector"/>
    <detector name="SNMP" class="org.opennms.netmgt.provision.detector.snmp.SnmpDetector"/>
  </detectors>
  <policies>
    <policy name="Do Not Persist Discovered IPs" class="org.opennms.netmgt.provision.persist.policies.MatchingIpInterfacePolicy">
      <parameter key="action" value="DO_NOT_PERSIST"/>
      <parameter key="matchBehavior" value="NO_PARAMETERS"/>
    </policy>
    <policy name="Enable Data Collection" class="org.opennms.netmgt.provision.persist.policies.MatchingSnmpInterfacePolicy">
      <parameter key="action" value="ENABLE_COLLECTION"/>
      <parameter key="matchBehavior" value="ANY_PARAMETER"/>
      <parameter key="ifOperStatus" value="1"/>
    </policy>
  </policies>
</foreign-source>
EOF
else
  echo "Previous configuration found. Synchronizing only new files..."
  rsync -aruO --no-perms ${BACKUP_ETC}/ ${CONFIG_DIR}/
fi

# Guard against application upgrades
MANDATORY=/tmp/opennms-mandatory
mkdir -p ${MANDATORY}
for file in "${KARAF_FILES[@]}"; do
  echo "Backing up ${file} to ${MANDATORY}..."
  cp --force ${BACKUP_ETC}/${file} ${MANDATORY}/
done
# WARNING: if the volume behind CONFIG_DIR doesn't have the right permissions, the following fails
echo "Overriding mandatory files from ${MANDATORY}..."
rsync -aO --no-perms ${MANDATORY}/ ${CONFIG_DIR}/

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

cat <<EOF > ${CONFIG_DIR}/opennms.properties.d/rrd.properties
org.opennms.rrd.storeByGroup=true
org.opennms.rrd.storeByForeignSource=true
EOF

cat <<EOF > ${CONFIG_DIR}/opennms.properties.d/collectd.properties
# To get data as close as possible to PDP
org.opennms.netmgt.collectd.strictInterval=true
# To only retrieve data from the SNMP Interfaces that has snmpCollect=true
org.opennms.netmgt.collectd.SnmpCollector.limitCollectionToInstances=true
EOF

# Required changes in order to use HTTPS through Ingress
cat <<EOF > ${CONFIG_DIR}/opennms.properties.d/webui.properties
opennms.web.base-url=https://%x%c/
org.opennms.security.disableLoginSuccessEvent=true
EOF

# Enable OSGi features
if [[ ${FEATURES_LIST} ]]; then
  echo "Enabling features: ${FEATURES_LIST} ..."
  LAST_ENTRY="opennms-karaf-health"
  FEATURES_CFG=${CONFIG_DIR}/org.apache.karaf.features.cfg
  sed -r -i "s/^  $LAST_ENTRY.*/  ${FEATURES_LIST},$LAST_ENTRY/" ${FEATURES_CFG}
fi

# Enable ALEC (distributed mode)
if [[ ${ENABLE_ALEC} ]]; then
  echo "Enabling ALEC (distributed mode)..."
  cat <<EOF > ${CONFIG_DIR}/featuresBoot.d/alec.boot
alec-opennms-distributed wait-for-kar=opennms-alec-plugin
EOF
fi

# Enable Syslogd
sed -r -i '/enabled="false"/{$!{N;s/ enabled="false"[>]\n(.*OpenNMS:Name=Syslogd.*)/>\n\1/}}' ${CONFIG_DIR}/service-configuration.xml

# Disable Telemetryd as BMP, flows, and streaming telemetry data will be managed by sentinels
sed -i -r '/opennms-flows/d' ${CONFIG_DIR}/org.apache.karaf.features.cfg
sed -i 'N;s/service.*\n\(.*Telemetryd\)/service enabled="false">\n\1/;P;D' ${CONFIG_DIR}/service-configuration.xml

# Enable tracing with jaeger
if [[ ${JAEGER_AGENT_HOST} ]]; then
  cat <<EOF > $CONFIG_DIR/opennms.properties.d/jaeger.properties
org.opennms.core.tracer=jaeger
JAEGER_AGENT_HOST=${JAEGER_AGENT_HOST}
EOF
  echo "opennms-core-tracing-jaeger" > ${CONFIG_DIR}/featuresBoot.d/jaeger.boot
fi

# Configure Sink and RPC to use Kafka, and the Kafka Producer.
if [[ ${KAFKA_SERVER} ]]; then
  echo "Configuring Kafka..."

  cat <<EOF > ${CONFIG_DIR}/opennms.properties.d/event-sink.properties
org.opennms.netmgt.eventd.sink.enable=true
EOF

  cat <<EOF > ${CONFIG_DIR}/opennms.properties.d/amq.properties
org.opennms.activemq.broker.disable=true
EOF

  cat <<EOF > ${CONFIG_DIR}/opennms.properties.d/kafka.properties
# Sink
org.opennms.core.ipc.sink.initialSleepTime=60000
org.opennms.core.ipc.sink.strategy=kafka
org.opennms.core.ipc.sink.kafka.bootstrap.servers=${KAFKA_SERVER}:9092
org.opennms.core.ipc.sink.kafka.group.id=${INSTANCE_ID}

# Sink Consumer (verify Kafka broker configuration)
org.opennms.core.ipc.sink.kafka.session.timeout.ms=30000
org.opennms.core.ipc.sink.kafka.max.poll.records=50
org.opennms.core.ipc.sink.kafka.max.partition.fetch.bytes=${KAFKA_MAX_MESSAGE_SIZE}

# RPC
org.opennms.core.ipc.rpc.strategy=kafka
org.opennms.core.ipc.rpc.kafka.bootstrap.servers=${KAFKA_SERVER}:9092
org.opennms.core.ipc.rpc.kafka.ttl=30000
org.opennms.core.ipc.rpc.kafka.single-topic=true
org.opennms.core.ipc.rpc.kafka.group.id=${INSTANCE_ID}

# RPC Consumer (verify Kafka broker configuration)
org.opennms.core.ipc.rpc.kafka.request.timeout.ms=30000
org.opennms.core.ipc.rpc.kafka.session.timeout.ms=30000
org.opennms.core.ipc.rpc.kafka.max.poll.records=50
org.opennms.core.ipc.rpc.kafka.max.partition.fetch.bytes=${KAFKA_MAX_MESSAGE_SIZE}
org.opennms.core.ipc.rpc.kafka.auto.offset.reset=latest

# RPC Producer (verify Kafka broker configuration)
org.opennms.core.ipc.rpc.kafka.compression.type=gzip
org.opennms.core.ipc.rpc.kafka.max.request.size=${KAFKA_MAX_MESSAGE_SIZE}
EOF

  if [[ ${KAFKA_SASL_USERNAME} && ${KAFKA_SASL_PASSWORD} ]]; then
    cat <<EOF >> ${CONFIG_DIR}/opennms.properties.d/kafka.properties

# Authentication
org.opennms.core.ipc.sink.kafka.security.protocol=SASL_PLAINTEXT
org.opennms.core.ipc.sink.kafka.sasl.mechanism=PLAIN
org.opennms.core.ipc.sink.kafka.sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="${KAFKA_SASL_USERNAME}" password="${KAFKA_SASL_PASSWORD}";
org.opennms.core.ipc.rpc.kafka.security.protocol=SASL_PLAINTEXT
org.opennms.core.ipc.rpc.kafka.sasl.mechanism=PLAIN
org.opennms.core.ipc.rpc.kafka.sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="${KAFKA_SASL_USERNAME}" password="${KAFKA_SASL_PASSWORD}";
EOF
  fi

  if [[ ${FEATURES_LIST} == *"opennms-kafka-producer"* ]]; then
    cat <<EOF > $CONFIG_DIR/org.opennms.features.kafka.producer.client.cfg
bootstrap.servers=$KAFKA_SERVER:9092
compression.type=gzip
timeout.ms=30000
max.request.size=${KAFKA_MAX_MESSAGE_SIZE}
state.dir=/opennms-data/kafka
EOF
    if [[ ${KAFKA_SASL_USERNAME} && ${KAFKA_SASL_PASSWORD} ]]; then
      cat <<EOF >> $CONFIG_DIR/org.opennms.features.kafka.producer.client.cfg
security.protocol=SASL_PLAINTEXT
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="${KAFKA_SASL_USERNAME}" password="${KAFKA_SASL_PASSWORD}";
EOF
    fi
    # Make sure to enable only what's needed for your use case
    SUPPRESS_INC_ALARMS="true"
    if [[ ${ENABLE_ALEC} ]]; then
      SUPPRESS_INC_ALARMS="false"
    fi
    cat <<EOF > ${CONFIG_DIR}/org.opennms.features.kafka.producer.cfg
topologyProtocols=bridge,cdp,isis,lldp,ospf
suppressIncrementalAlarms=${SUPPRESS_INC_ALARMS}
forward.metrics=${FORWARD_METRICS}
nodeRefreshTimeoutMs=300000
kafkaSendQueueCapacity=1000
# Alarm Synchronization (Streams Application; mandatory for ALEC; requires volume to store data)
alarmSync=true
alarmSyncIntervalMs=300000
# Topic Names
nodeTopic=${INSTANCE_ID}_nodes
alarmTopic=${INSTANCE_ID}_alarms
eventTopic=${INSTANCE_ID}_events
metricTopic=${INSTANCE_ID}_metrics
alarmFeedbackTopic=${INSTANCE_ID}_alarms_feedback
topologyVertexTopic=${INSTANCE_ID}_topology_vertices
topologyEdgeTopic=${INSTANCE_ID}_edges
EOF
  fi
fi

# Configure Newts (works with either Cassandra or ScyllaDB)
if [[ ${CASSANDRA_SERVER} ]]; then
  echo "Configuring Newts..."
  cat <<EOF > ${CONFIG_DIR}/opennms.properties.d/newts.properties
# About the properties:
# - ttl (1 year expressed in ms) should be consistent with the TWCS settings on newts.cql
# - ring_buffer_size and cache.max_entries should be consistent with the expected load and heap size
#
# About the keyspace (CQL schema):
# - The value of compaction_window_size should be consistent with the chosen TTL
# - The number of SSTables will be the TTL/compaction_window_size (52 for 1 year)

org.opennms.timeseries.strategy=newts
org.opennms.newts.config.hostname=${CASSANDRA_SERVER}
org.opennms.newts.config.keyspace=${KEYSPACE}
org.opennms.newts.config.port=9042
org.opennms.newts.config.read_consistency=ONE
org.opennms.newts.config.write_consistency=ANY

org.opennms.newts.config.resource_shard=604800
org.opennms.newts.config.ttl=31540000

org.opennms.newts.config.cache.priming.enable=true
org.opennms.newts.config.cache.priming.block_ms=60000

# The following settings most be tuned in production
org.opennms.newts.config.writer_threads=2
org.opennms.newts.config.ring_buffer_size=131072
org.opennms.newts.config.cache.max_entries=131072
EOF

  # Required only when collecting data every 30 seconds
  echo "Configuring Optional Newts Settings..."
  cat <<EOF >> $CONFIG_DIR/opennms.properties.d/newts.properties
org.opennms.newts.query.minimum_step=30000
org.opennms.newts.query.heartbeat=450000
EOF

  # Fixing polling/collection settings
  sed -r -i "s/keyspace=newts/keyspace=${KEYSPACE}/" ${CONFIG_DIR}/jmx-datacollection-config.d/cassandra30x-newts.xml
  sed -r -i "s/keyspace=newts/keyspace=${KEYSPACE}/" ${CONFIG_DIR}/poller-configuration.xml
  sed -r -i "s/cassandra-username/cassandra/" ${CONFIG_DIR}/poller-configuration.xml
  sed -r -i "s/cassandra-password/cassandra/" ${CONFIG_DIR}/poller-configuration.xml
  sed -r -i "s/cassandra-username/cassandra/" ${CONFIG_DIR}/collectd-configuration.xml
  sed -r -i "s/cassandra-password/cassandra/" ${CONFIG_DIR}/collectd-configuration.xml
fi

if [[ ${CASSANDRA_REPLICATION_FACTOR} ]]; then
  echo "Building Newts Schema for Cassandra/ScyllaDB (assuming 1 year of retention/TTL)..."
  cat <<EOF > ${CONFIG_DIR}/newts.cql
CREATE KEYSPACE IF NOT EXISTS ${KEYSPACE} WITH replication = {'class' : 'NetworkTopologyStrategy', '${CASSANDRA_DC}' : ${CASSANDRA_REPLICATION_FACTOR} };

CREATE TABLE IF NOT EXISTS ${KEYSPACE}.samples (
  context text,
  partition int,
  resource text,
  collected_at timestamp,
  metric_name text,
  value blob,
  attributes map<text, text>,
  PRIMARY KEY((context, partition, resource), collected_at, metric_name)
) WITH compaction = {
  'compaction_window_size': '7',
  'compaction_window_unit': 'DAYS',
  'expired_sstable_check_frequency_seconds': '86400',
  'class': 'org.apache.cassandra.db.compaction.TimeWindowCompactionStrategy'
} AND gc_grace_seconds = 604800;

CREATE TABLE IF NOT EXISTS ${KEYSPACE}.terms (
  context text,
  field text,
  value text,
  resource text,
  PRIMARY KEY((context, field, value), resource)
);

CREATE TABLE IF NOT EXISTS ${KEYSPACE}.resource_attributes (
  context text,
  resource text,
  attribute text,
  value text,
  PRIMARY KEY((context, resource), attribute)
);

CREATE TABLE IF NOT EXISTS ${KEYSPACE}.resource_metrics (
  context text,
  resource text,
  metric_name text,
  PRIMARY KEY((context, resource), metric_name)
);
EOF
fi

# Configure Elasticsearch for Flow processing and for the event forwarder
if [[ ${ELASTIC_SERVER} ]]; then
  PREFIX=$(echo ${INSTANCE_ID} | tr '[:upper:]' '[:lower:]')-

  read -r -d '' ES_COMMON <<EOF
# Common Settings
elasticUrl=http://${ELASTIC_SERVER}:9200
globalElasticUser=elastic
globalElasticPassword=${ELASTIC_PASSWORD}
indexPrefix=${PREFIX}
connTimeout=30000
readTimeout=300000
retries=1

# The following settings should be consistent with your ES cluster
settings.index.number_of_shards=${ELASTIC_NUM_SHARDS}
settings.index.number_of_replicas=${ELASTIC_REPLICATION_FACTOR}

# Custom Settings
EOF

  echo "Configuring Elasticsearch for Flows..."
  cat <<EOF > ${CONFIG_DIR}/org.opennms.features.flows.persistence.elastic.cfg
${ES_COMMON}
elasticIndexStrategy=${ELASTIC_INDEX_STRATEGY_FLOWS}
EOF

  if [[ ${FEATURES_LIST} == *"opennms-es-rest"* ]]; then
    echo "Configuring Elasticsearch Event Forwarder..."
    cat <<EOF > ${CONFIG_DIR}/org.opennms.plugin.elasticsearch.rest.forwarder.cfg
${ES_COMMON}
elasticIndexStrategy=${ELASTIC_INDEX_STRATEGY_REST}
groupOidParameters=true
logAllEvents=true
EOF
  fi

  if [[ ${FEATURES_LIST} == *"opennms-alarm-history-elastic"* ]]; then
    echo "Configuring Alarm History Forwarder..."
    cat <<EOF > ${CONFIG_DIR}/org.opennms.features.alarms.history.elastic.cfg
${ES_COMMON}
elasticIndexStrategy=${ELASTIC_INDEX_STRATEGY_ALARMS}
EOF
  fi

  if [[ ${FEATURES_LIST} == *"opennms-situation-feedback"* ]]; then
    echo "Configuring Situations Feedback..."
    cat <<EOF > ${CONFIG_DIR}/org.opennms.features.situationfeedback.persistence.elastic.cfg
${ES_COMMON}
elasticIndexStrategy=monthly
EOF
  fi
fi

# Configure NXOS Resource Types
echo "Configuring NXOS resource types..."
cat <<EOF > ${CONFIG_DIR}/resource-types.d/nxos-intf-resources.xml
<?xml version="1.0"?>
<resource-types>
  <resourceType name="nxosIntf" label="Nxos Interface" resourceLabel="\${index}">
    <persistenceSelectorStrategy class="org.opennms.netmgt.collection.support.PersistAllSelectorStrategy"/>
    <storageStrategy class="org.opennms.netmgt.collection.support.IndexStorageStrategy"/>
  </resourceType>
</resource-types>
EOF

# Configure K8s Event Watcher
cat <<EOF > ${CONFIG_DIR}/events/kubernetes.events.xml
<events xmlns="http://xmlns.opennms.org/xsd/eventconf">
  <event>
    <uei>uei.opennms.org/kubernetes/event/Warning</uei>
    <event-label>Kubernetes Warning Event</event-label>
    <descr>Received event %parm[reason]% on %parm[kind]% %parm[name]% from namespace %parm[namespace]% at %parm[creationTimestamp]%, originated on worker node %parm[nodeName]%: %parm[message]%</descr>
    <logmsg dest="logndisplay">%parm[message]%</logmsg>
    <severity>Minor</severity>
  </event>
  <event>
    <uei>uei.opennms.org/kubernetes/pod/ADDED</uei>
    <event-label>Kubernetes Pod Added Event</event-label>
    <descr>Pod %parm[name]% has been added to namespace %parm[namespace]% at %parm[creationTimestamp]%</descr>
    <logmsg dest="logndisplay">Pod %parm[name]% added to namespace %parm[namespace]%</logmsg>
    <severity>Normal</severity>
  </event>
  <event>
    <uei>uei.opennms.org/kubernetes/pod/DELETED</uei>
    <event-label>Kubernetes Pod Deleted Event</event-label>
    <descr>Pod %parm[name]% has been removed from namespace %parm[namespace]% at %parm[creationTimestamp]%</descr>
    <logmsg dest="logndisplay">Pod %parm[name]% removed from namespace %parm[namespace]%</logmsg>
    <severity>Warning</severity>
  </event>
  <event>
    <uei>uei.opennms.org/kubernetes/service/ADDED</uei>
    <event-label>Kubernetes Service Added Event</event-label>
    <descr>Service %parm[name]% has been added to namespace %parm[namespace]% at %parm[creationTimestamp]%</descr>
    <logmsg dest="logndisplay">Service %parm[name]% added to namespace %parm[namespace]%</logmsg>
    <severity>Normal</severity>
  </event>
  <event>
    <uei>uei.opennms.org/kubernetes/service/DELETED</uei>
    <event-label>Kubernetes Service Deleted Event</event-label>
    <descr>Service %parm[name]% has been removed from namespace %parm[namespace]% at %parm[creationTimestamp]%</descr>
    <logmsg dest="logndisplay">Service %parm[name]% removed from namespace %parm[namespace]%</logmsg>
    <severity>Warning</severity>
  </event>
</events>
EOF
if ! grep -q kubernetes.events.xml ${CONFIG_DIR}/eventconf.xml; then
  sed -r -i '/[<].global[>]/a <event-file>events/kubernetes.events.xml</event-file>' ${CONFIG_DIR}/eventconf.xml
fi

# Cleanup temporary requisition files:
rm -f ${CONFIG_DIR}/imports/pending/*.xml.*
rm -f ${CONFIG_DIR}/foreign-sources/pending/*.xml.*

# Force to execute runjava and the install script
touch ${CONFIG_DIR}/do-upgrade

# Fix permissions when executing the script as root
if [[ "$(id -u)" == "0" ]]; then
  chown -R opennms:opennms ${CONFIG_DIR}
fi
