#!/bin/sh
# @author Alejandro Galue <agalue@opennms.org>

# Required environment variables:
# FEATURES_LIST
# KAFKA_SERVER
# CASSANDRA_SERVER
# CASSANDRA_REPFACTOR
# ELASTIC_SERVER

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

if ! grep --quiet "opennms-bundle-refresher," $FEATURES_CFG; then
  echo "Enabling features: $FEATURES_LIST ..."
  sed -r -i "s/opennms-bundle-refresher.*/opennms-bundle-refresher,$FEATURES_LIST/" $CONFIG_DIR/org.apache.karaf.features.cfg
else
  echo "Features already enabled."
fi

if [ "$KAFKA_SERVER" != ""]; then
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
nodeTopic=OpenNMS.Nodes
alarmTopic=OpenNMS.Alarms
eventTopic=
metricTopic=OpenNMS.Metrics
forward.metrics=true
nodeRefreshTimeoutMs=300000
alarmSyncIntervalMs=300000
EOF
fi

if [ "$CASSANDRA_SERVER" != ""]; then
  cat <<EOF > $CONFIG_DIR/opennms.properties.d/newts.properties
# ttl (1 year expressed in ms) should be consistent with the TWCS settings on newts.cql
# ring_buffer_size and cache.max_entries should be consistent with the expected load

org.opennms.rrd.storeByGroup=true
org.opennms.rrd.storeByForeignSource=true

org.opennms.timeseries.strategy=newts
org.opennms.newts.config.hostname=$CASSANDRA_SERVER
org.opennms.newts.config.keyspace=newts
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

if [ "$ELASTIC_SERVER" != ""]; then
  cat <<EOF > $CONFIG_DIR/org.opennms.plugin.elasticsearch.rest.forwarder.cfg
elasticUrl=http://$ELASTIC_SERVER:9200
globalElasticUser=elastic
globalElasticPassword=elastic
archiveRawEvents=true
archiveAlarms=true
archiveAlarmChangeEvents=false
logAllEvents=false
retries=1
connTimeout=3000
EOF
fi

