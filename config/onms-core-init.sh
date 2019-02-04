#!/bin/bash
# @author Alejandro Galue <agalue@opennms.org>
#
# Requirements:
# - Must run within a init-container based on opennms/horizon-core-web.
#   Version must match the runtime container.
# - Horizon 23 or newer is required.
#
# Purpose:
# - Initialize the config directory on the volume only one.
# - Apply mandatory configuration changes based on the provided variables.
#
# Warning:
# - Multiple assumptions are made on Newts/Cassandra configuration.
#
# External Environment variables:
# - INSTANCE_ID
# - FEATURES_LIST
# - KAFKA_SERVER
# - CASSANDRA_SERVER
# - CASSANDRA_REPFACTOR
# - ELASTIC_SERVER
# - ELASTIC_PASSWORD

CONFIG_DIR=/opennms-etc
BACKUP_ETC=/opt/opennms/etc
FEATURES_CFG=$CONFIG_DIR/org.apache.karaf.features.cfg
KEYSPACE=${INSTANCE_ID-onms}_newts
KARAF_FILES=( \
"create.sql" \
"config.properties" \
"custom.properties" \
"jre.properties" \
"profile.cfg" \
"jmx.acl.*" \
"org.apache.felix.*" \
"org.apache.karaf.*" \
"org.ops4j.pax.url.mvn.cfg" \
)

# Initialize configuration directory
yum install -y -q rsync git
if [ ! -f $CONFIG_DIR/configured ]; then
  echo "Initializing configuration directory for the first time ..."
  rsync -ar $BACKUP_ETC/ $CONFIG_DIR/
  cd $CONFIG_DIR
  git config --global user.name "Kubernetes"
  git config --global user.email "root@localhost"
  git init .
  git add .
  git commit -m "Fresh OpenNMS configuration"
else
  echo "Previous configuration found. Synchronizing only new files..."
  rsync -aru $BACKUP_ETC/ $CONFIG_DIR/
fi

# Guard against application upgrades
MANDATORY=/tmp/opennms-mandatory
mkdir -p $MANDATORY
for file in "${KARAF_FILES[@]}"; do
  echo "Backing up $file to $MANDATORY..."
  cp --force $BACKUP_ETC/$file $MANDATORY/
done
echo "Overriding mandatory files from $MANDATORY..."
rsync -a $MANDATORY/ $CONFIG_DIR/

if [[ $INSTANCE_ID ]]; then
  echo "Configuring Instance ID..."
  cat <<EOF > $CONFIG_DIR/opennms.properties.d/instanceid.properties
# Used for Kafka Topics
org.opennms.instance.id=$INSTANCE_ID
EOF
fi

cat <<EOF > $CONFIG_DIR/org.opennms.features.datachoices.cfg
enabled=false
acknowledged-by=admin
acknowledged-at=Mon Jan 01 00\:00\:00 EDT 2018
EOF

if [[ $FEATURES_LIST ]]; then
  echo "Enabling features: $FEATURES_LIST ..."
  sed -r -i "s/.*opennms-bundle-refresher.*/  $FEATURES_LIST,opennms-bundle-refresher/" $FEATURES_CFG
fi

if [[ $KAFKA_SERVER ]]; then
  echo "Configuring Kafka..."

  cat <<EOF > $CONFIG_DIR/opennms.properties.d/amq.properties
org.opennms.activemq.broker.disable=true
EOF

  cat <<EOF > $CONFIG_DIR/opennms.properties.d/kafka.properties
# Sink
org.opennms.core.ipc.sink.initialSleepTime=60000
org.opennms.core.ipc.sink.strategy=kafka
org.opennms.core.ipc.sink.kafka.bootstrap.servers=$KAFKA_SERVER:9092
org.opennms.core.ipc.sink.kafka.group.id=OpenNMS

# RPC
org.opennms.core.ipc.rpc.strategy=kafka
org.opennms.core.ipc.rpc.kafka.bootstrap.servers=$KAFKA_SERVER:9092
org.opennms.core.ipc.rpc.kafka.ttl=30000
org.opennms.core.ipc.rpc.kafka.compression.type=gzip
org.opennms.core.ipc.rpc.kafka.request.timeout.ms=30000

# RPC Consumer (verify Kafka broker configuration)
org.opennms.core.ipc.rpc.kafka.max.partition.fetch.bytes=5000000

# RPC Producer (verify Kafka broker configuration)
org.opennms.core.ipc.rpc.kafka.max.request.size=5000000
EOF

  cat <<EOF > $CONFIG_DIR/org.opennms.features.kafka.producer.client.cfg
bootstrap.servers=$KAFKA_SERVER:9092
EOF

  cat <<EOF > $CONFIG_DIR/org.opennms.features.kafka.producer.cfg
nodeTopic=${INSTANCE_ID}_nodes
alarmTopic=${INSTANCE_ID}_alarms
eventTopic=${INSTANCE_ID}_events
metricTopic=${INSTANCE_ID}_metrics
forward.metrics=true
nodeRefreshTimeoutMs=300000
alarmSyncIntervalMs=300000
EOF
fi

if [[ $CASSANDRA_SERVER ]]; then
  echo "Configuring Cassandra..."
  cat <<EOF > $CONFIG_DIR/opennms.properties.d/newts.properties
# About the properties:
# - ttl (1 year expressed in ms) should be consistent with the TWCS settings on newts.cql
# - ring_buffer_size and cache.max_entries should be consistent with the expected load
#
# About the keyspace:
# - The value of compaction_window_size should be consistent with the chosen TTL
# - The number of SSTables will be the TTL/compaction_window_size (52 for 1 year)

org.opennms.rrd.storeByGroup=true
org.opennms.rrd.storeByForeignSource=true

org.opennms.timeseries.strategy=newts
org.opennms.newts.config.hostname=${CASSANDRA_SERVER}
org.opennms.newts.config.keyspace=${KEYSPACE}
org.opennms.newts.config.port=9042
org.opennms.newts.config.read_consistency=ONE
org.opennms.newts.config.write_consistency=ANY

org.opennms.newts.config.resource_shard=604800
org.opennms.newts.config.ttl=31540000
org.opennms.newts.config.writer_threads=2
org.opennms.newts.config.ring_buffer_size=8192
org.opennms.newts.config.cache.max_entries=8192
org.opennms.newts.config.cache.priming.enable=true
org.opennms.newts.config.cache.priming.block_ms=60000
org.opennms.newts.query.minimum_step=30000
org.opennms.newts.query.heartbeat=450000
EOF
fi

if [[ $CASSANDRA_REPFACTOR ]]; then
  echo "Building Newts Schema for Cassandra/ScyllaDB..."
  cat <<EOF > $CONFIG_DIR/newts.cql
CREATE KEYSPACE IF NOT EXISTS ${KEYSPACE} WITH replication = {'class' : 'NetworkTopologyStrategy', 'Main' : $CASSANDRA_REPFACTOR };

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
} AND gc_grace_seconds = 604800
  AND read_repair_chance = 0;

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

if [[ $ELASTIC_SERVER ]]; then
  echo "Configuring Elasticsearch for Flows..."
  cat <<EOF > $CONFIG_DIR/org.opennms.features.flows.persistence.elastic.cfg
elasticUrl=http://$ELASTIC_SERVER:9200
globalElasticUser=elastic
globalElasticPassword=$ELASTIC_PASSWORD
elasticIndexStrategy=daily
EOF

  echo "Configuring Elasticsearch Event Forwarder..."
  cat <<EOF > $CONFIG_DIR/org.opennms.plugin.elasticsearch.rest.forwarder.cfg
elasticUrl=http://$ELASTIC_SERVER:9200
globalElasticUser=elastic
globalElasticPassword=$ELASTIC_PASSWORD
archiveRawEvents=true
archiveAlarms=false
archiveAlarmChangeEvents=false
logAllEvents=false
retries=1
connTimeout=3000
EOF
fi

# Required changes in order to use HTTPS through Ingress
cat <<EOF > $CONFIG_DIR/opennms.properties.d/webui.properties
opennms.web.base-url=https://%x%c/
org.opennms.security.disableLoginSuccessEvent=true
EOF
