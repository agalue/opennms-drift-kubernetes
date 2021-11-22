#!/bin/sh
# @author Alejandro Galue <agalue@opennms.org>
#
# Purpose:
# - Generate the client settings for Kafka
#
# Environment variables:
# - KAFKA_SASL_USERNAME
# - KAFKA_SASL_PASSWORD

cat <<EOF > /data/client.properties
security.protocol=SASL_PLAINTEXT
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="${KAFKA_SASL_USERNAME}" password="${KAFKA_SASL_PASSWORD}";
EOF
