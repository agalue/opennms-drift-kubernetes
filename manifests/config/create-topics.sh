#!/bin/bash
# @author Alejandro Galue <agalue@opennms.org>

CFG="/tmp/client.properties"
cat <<EOF > $CFG
security.protocol=SASL_PLAINTEXT
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="$KAFKA_CLIENT_USER" password="$KAFKA_CLIENT_PASSWORD";
EOF

for TOPIC in $CREATE_TOPICS; do
  echo "Creating topic $TOPIC ..."
  JMX_PORT='' kafka-topics.sh --bootstrap-server $KAFKA_SERVER:9092 \
    --command-config=$CFG \
    --create --if-not-exists --topic $TOPIC \
    --partitions $KAFKA_CFG_NUM_PARTITIONS \
    --replication-factor $KAFKA_CFG_DEFAULT_REPLICATION_FACTOR
done