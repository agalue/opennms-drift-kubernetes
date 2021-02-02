#!/bin/bash
# @author Alejandro Galue <agalue@opennms.org>
#
# ALEC is required only for advanced alarms correlation.
#
# Requirements:
# - Horizon 27 or newer is required.
# - ALEC 1.1.0 or newer is required.
# - Overlay volume mounted at /etc-overlay
#
# Environment variables:
# - INSTANCE_ID
# - ZOOKEEPER_SERVER
# - KAFKA_SERVER
# - KAFKA_SASL_USERNAME
# - KAFKA_SASL_PASSWORD

# To avoid issues with OpenShift
umask 002

OVERLAY=/etc-overlay
SENTINEL_HOME=/opt/sentinel

# Configure the instance ID
# Required when having multiple OpenNMS backends sharing the same Kafka cluster.
CUSTOM_PROPERTIES=${OVERLAY}/custom.system.properties
if [[ ${INSTANCE_ID} ]]; then
  echo "Configuring Instance ID..."
  cat <<EOF >> ${CUSTOM_PROPERTIES}
# Used for Kafka Topics
org.opennms.instance.id=${INSTANCE_ID}
EOF
else
  INSTANCE_ID="OpenNMS"
fi

FEATURES_DIR=${OVERLAY}/featuresBoot.d
mkdir -p ${FEATURES_DIR}
echo "Configuring Features..."

cat <<EOF > ${FEATURES_DIR}/alec.boot
sentinel-core
alec-sentinel-distributed wait-for-kar=opennms-alec-plugin
EOF

if [[ ${ZOOKEEPER_SERVER} ]]; then
  echo "Configure ZooKeeper for distributed coordination..."

  cat <<EOF > ${OVERLAY}/org.opennms.features.distributed.coordination.zookeeper.cfg
connectString=${ZOOKEEPER_SERVER}:2181
EOF

  cat <<EOF > ${FEATURES_DIR}/zk.boot
sentinel-coordination-zookeeper
EOF
fi

if [[ ${KAFKA_SERVER} ]]; then
  echo "Configuring Kafka..."

  if [[ ${KAFKA_SASL_USERNAME} && ${KAFKA_SASL_PASSWORD} ]]; then
    read -r -d '' KAFKA_SASL <<EOF
security.protocol=SASL_PLAINTEXT
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="${KAFKA_SASL_USERNAME}" password="${KAFKA_SASL_PASSWORD}";
EOF
  fi

  cat <<EOF > ${OVERLAY}/org.opennms.core.ipc.sink.kafka.consumer.cfg
bootstrap.servers=${KAFKA_SERVER}:9092
${KAFKA_SASL}
EOF

  cat <<EOF > ${OVERLAY}/org.opennms.alec.datasource.opennms.kafka.producer.cfg
bootstrap.servers=${KAFKA_SERVER}:9092
${KAFKA_SASL}
EOF

  cat <<EOF > ${OVERLAY}/org.opennms.alec.datasource.opennms.kafka.streams.cfg
bootstrap.servers=${KAFKA_SERVER}:9092
application.id=${INSTANCE_ID}_alec_datasource
commit.interval.ms=5000
${KAFKA_SASL}
EOF

  cat <<EOF > ${OVERLAY}/org.opennms.alec.datasource.opennms.kafka.cfg
# Make sure to configure the topics on OpenNMS the same way
eventSinkTopic=${INSTANCE_ID}.Sink.Events
inventoryTopic=${INSTANCE_ID}_alec_inventory
nodeTopic=${INSTANCE_ID}_nodes
alarmTopic=${INSTANCE_ID}_alarms
alarmFeedbackTopic=${INSTANCE_ID}_alarms_feedback
edgesTopic=${INSTANCE_ID}_edges
EOF
fi
