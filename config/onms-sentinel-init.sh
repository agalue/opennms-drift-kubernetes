#!/bin/bash
# @author Alejandro Galue <agalue@opennms.org>

# Environment variables:
#
# INSTANCE_ID
# ELASTIC_SERVER
# KAFKA_SERVER
# KAFKA_GROUP_ID
# CASSANDRA_SERVER

GROUP_ID=${KAFKA_GROUP_ID-Sentinel}
CFG=/opt/sentinel/etc/system.properties
OVERLAY=/etc-overlay

if [[ $INSTANCE_ID ]]; then
  echo "Configuring Instance ID..."
  cat <<EOF >> $CFG

# Used for Kafka Topics
org.opennms.instance.id=$INSTANCE_ID
EOF
  cp $CFG $OVERLAY
fi

FEATURES=$OVERLAY/featuresBoot.d
mkdir -p $FEATURES

if [[ $ELASTIC_SERVER ]]; then
  echo "Configuring Elasticsearch..."

  echo "sentinel-flows" > $FEATURES/flows.boot

  if [[ ! $CASSANDRA_SERVER ]]; then
    cat <<EOF > $OVERLAY/org.opennms.features.telemetry.adapters-sflow.cfg
name = SFlow
class-name = org.opennms.netmgt.telemetry.protocols.sflow.adapter.SFlowAdapter
EOF
  fi

  cat <<EOF > $OVERLAY/org.opennms.features.telemetry.adapters-ipfix.cfg
name = IPFIX
class-name = org.opennms.netmgt.telemetry.protocols.netflow.adapter.ipfix.IpfixAdapter
EOF

  cat <<EOF > $OVERLAY/org.opennms.features.telemetry.adapters-netflow5.cfg
name = Netflow-5
class-name = org.opennms.netmgt.telemetry.protocols.netflow.adapter.netflow5.Netflow5Adapter
EOF

  cat <<EOF > $OVERLAY/org.opennms.features.telemetry.adapters-netflow9.cfg
name = Netflow-9
class-name = org.opennms.netmgt.telemetry.protocols.netflow.adapter.netflow9.Netflow9Adapter
EOF

  cat <<EOF > $OVERLAY/org.opennms.features.flows.persistence.elastic.cfg
elasticUrl = http://$ELASTIC_SERVER:9200
globalElasticUser = elastic
globalElasticPassword = elastic
elasticIndexStrategy = daily
settings.index.number_of_shards = 6
settings.index.number_of_replicas = 1
EOF

if [[ $KAFKA_SERVER ]]; then
  echo "Configuring Kafka..."

  echo "sentinel-kafka" > $FEATURES/kafka.boot

  cat <<EOF > $OVERLAY/org.opennms.core.ipc.sink.kafka.consumer.cfg
group.id = $GROUP_ID
bootstrap.servers = $KAFKA_SERVER:9092
EOF
fi

if [[ $CASSANDRA_SERVER ]]; then
  echo "Configuring Cassandra..."

  cat <<EOF > $FEATURES/telemetry.boot
sentinel-newts
sentinel-telemetry-nxos
sentinel-telemetry-jti
EOF

  cat <<EOF > $FEATURES/org.opennms.newts.config.cfg
hostname = $CASSANDRA_SERVER
keyspace = newts
port = 9042
read_consistency = ONE
write_consistency = ANY
resource_shard = 604800
ttl = 31540000
ring_buffer_size = 131072
cache.max_entries = 131072
cache.strategy = org.opennms.netmgt.newts.support.GuavaSearchableResourceMetadataCache
EOF

  cat <<EOF > $FEATURES/org.opennms.features.telemetry.adapters-sflow-telemetry.cfg
adapters.1.name = SFlow
adapters.1.class-name = org.opennms.netmgt.telemetry.adapters.netflow.sflow.SFlowAdapter
adapters.2.name = SFlow-Telemetry
adapters.2.class-name = org.opennms.netmgt.telemetry.adapters.netflow.sflow.SFlowTelemetryAdapter
adapters.2.parameters.script = $telemedry_dir/sflow-host.groovy
EOF

  cat <<EOF > $FEATURES/org.opennms.features.telemetry.adapters-nxos.cfg
name = NXOS
class-name = org.opennms.netmgt.telemetry.adapters.nxos.NxosGpbAdapter
parameters.script = $telemedry_dir/cisco-nxos-telemetry-interface.groovy
EOF
fi