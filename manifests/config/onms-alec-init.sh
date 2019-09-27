#!/bin/bash
# @author Alejandro Galue <agalue@opennms.org>
#
# ALEC is required only when advanced AI correlation is required.
#
# Requirements:
# - Must run within a init-container based on opennms/sentinel.
#   Version must match the runtime container.
# - Horizon 25 or newer is required.
#
# Environment variables:
# - INSTANCE_ID
# - ZOOKEEPER_SERVER
# - KAFKA_SERVER

# To avoid issues with OpenShift
umask 002

OVERLAY=/etc-overlay
SENTINEL_HOME=/opt/sentinel
VERSION=$(rpm -q --queryformat '%{VERSION}' opennms-sentinel)

# Configure the instance ID
# Required when having multiple OpenNMS backends sharing the same Kafka cluster.
SYSTEM_CFG=$SENTINEL_HOME/etc/system.properties
if [[ $INSTANCE_ID ]]; then
  echo "Configuring Instance ID..."
  cat <<EOF >> $SYSTEM_CFG

# Used for Kafka Topics
org.opennms.instance.id=$INSTANCE_ID
EOF
fi
cp $SYSTEM_CFG $OVERLAY

FEATURES_DIR=$OVERLAY/featuresBoot.d
mkdir -p $FEATURES_DIR
echo "Configuring Features..."
cat <<EOF > $FEATURES_DIR/alec.boot
sentinel-core
alec-datasource-opennms-kafka wait-for-kar=opennms-alec-plugin
alec-engine-cluster wait-for-kar=opennms-alec-plugin
alec-processor-redundant wait-for-kar=opennms-alec-plugin
alec-driver-main wait-for-kar=opennms-alec-plugin
EOF

if [[ $ZOOKEEPER_SERVER ]]; then
  echo "Configure ZooKeeper for distributed coordination..."
  cat <<EOF > $OVERLAY/org.opennms.features.distributed.coordination.zookeeper.cfg
connectString=$ZOOKEEPER_SERVER:2181
EOF
  cat <<EOF > $FEATURES_DIR/zk.boot
sentinel-coordination-zookeeper
EOF
fi

if [[ $KAFKA_SERVER ]]; then
  echo "Configuring Kafka..."

  cat <<EOF > $OVERLAY/org.opennms.core.ipc.sink.kafka.consumer.cfg
bootstrap.servers = $KAFKA_SERVER:9092
EOF

  cat <<EOF > $OVERLAY/org.opennms.alec.datasource.opennms.kafka.producer.cfg
bootstrap.servers = $KAFKA_SERVER:9092
EOF

  cat <<EOF > $OVERLAY/org.opennms.alec.datasource.opennms.kafka.streams.cfg
bootstrap.servers = $KAFKA_SERVER:9092
commit.interval.ms=5000
EOF

  cat <<EOF > $OVERLAY/org.opennms.alec.datasource.opennms.kafka.cfg
# Make sure to configure the topics on OpenNMS the same way
eventSinkTopic=$INSTANCE_ID.Sink.Events
inventoryTopic=$INSTANCE_ID.ALEC.Inventory
nodeTopic=$INSTANCE_ID.Nodes
alarmTopic=$INSTANCE_ID.Alarms
alarmFeedbackTopic=$INSTANCE_ID.Alarm.Feedback
edgesTopic=$INSTANCE_ID.Topology.Edges
EOF
fi
