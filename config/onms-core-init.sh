#!/bin/bash
# @author Alejandro Galue <agalue@opennms.org>
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
# - CASSANDRA_KEYSPACE
# - ELASTIC_SERVER

CONFIG_DIR=/opennms-etc

if [ ! -f $CONFIG_DIR/configured ]; then
  echo "Initializing configuration directory ..."
  cp -R /opt/opennms/etc/* $CONFIG_DIR/;
  echo "Applying basic changes ..."
  cat <<EOF > $CONFIG_DIR/org.opennms.features.datachoices.cfg
enabled=false
acknowledged-by=admin
acknowledged-at=Mon Jan 01 00\:00\:00 EDT 2018
EOF
fi

FEATURES_CFG=$CONFIG_DIR/org.apache.karaf.features.cfg
if [[ $FEATURES_LIST ]]; then
  if [ ! grep --quiet "$FEATURES_LIST" $FEATURES_CFG ]; then
    echo "Enabling features: $FEATURES_LIST ..."
    sed -r -i "s/.*opennms-bundle-refresher.*/  $FEATURES_LIST,opennms-bundle-refresher/" $FEATURES_CFG
  else
    echo "Features already enabled."
  fi
fi

if [[ $KAFKA_SERVER ]]; then
  echo "Configuring Kafka..."

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
# ttl (1 year expressed in ms) should be consistent with the TWCS settings on newts.cql
# ring_buffer_size and cache.max_entries should be consistent with the expected load

org.opennms.rrd.storeByGroup=true
org.opennms.rrd.storeByForeignSource=true

org.opennms.timeseries.strategy=newts
org.opennms.newts.config.hostname=$CASSANDRA_SERVER
org.opennms.newts.config.keyspace=$CASSANDRA_KEYSPACE
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

cat <<EOF > $CONFIG_DIR/newts.cql
CREATE KEYSPACE IF NOT EXISTS $CASSANDRA_KEYSPACE WITH replication = {'class' : 'NetworkTopologyStrategy', 'Main' : $CASSANDRA_REPFACTOR };

CREATE TABLE IF NOT EXISTS $CASSANDRA_KEYSPACE.samples (
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

CREATE TABLE IF NOT EXISTS $CASSANDRA_KEYSPACE.terms (
  context text,
  field text,
  value text,
  resource text,
  PRIMARY KEY((context, field, value), resource)
);

CREATE TABLE IF NOT EXISTS $CASSANDRA_KEYSPACE.resource_attributes (
  context text,
  resource text,
  attribute text,
  value text,
  PRIMARY KEY((context, resource), attribute)
);

CREATE TABLE IF NOT EXISTS $CASSANDRA_KEYSPACE.resource_metrics (
  context text,
  resource text,
  metric_name text,
  PRIMARY KEY((context, resource), metric_name)
);
EOF
fi

if [[ $ELASTIC_SERVER ]]; then
  echo "Configuring Elasticsearch..."

  cat <<EOF > $CONFIG_DIR/org.opennms.plugin.elasticsearch.rest.forwarder.cfg
elasticUrl=http://$ELASTIC_SERVER:9200
globalElasticUser=elastic
globalElasticPassword=elastic
archiveRawEvents=true
archiveAlarms=false
archiveAlarmChangeEvents=false
logAllEvents=false
retries=1
connTimeout=3000
EOF
fi

if [[ $INSTANCE_ID ]]; then
  echo "Configuring Instance ID..."

  cat <<EOF > $CONFIG_DIR/opennms.properties.d/minions.properties
# Used for Kafka Topics
org.opennms.instance.id=$INSTANCE_ID
EOF
fi

# Required changes in order to use HTTPS through Ingress
cat <<EOF > $CONFIG_DIR/opennms.properties.d/webui.properties
opennms.web.base-url=https://%x%c/
org.opennms.security.disableLoginSuccessEvent=true
EOF
