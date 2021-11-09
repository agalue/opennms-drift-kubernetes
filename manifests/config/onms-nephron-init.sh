#!/bin/sh
# @author Alejandro Galue <agalue@opennms.org>
#
# Purpose:
# - Compile Nephron from source as there are no alternatives at the moment.
# - Generate the client settings for Kafka
#
# Environment variables:
# - KAFKA_SASL_USERNAME
# - KAFKA_SASL_PASSWORD

git clone https://github.com/OpenNMS/nephron.git
cd nephron
git checkout -b $NEPHRON_VERSION $NEPHRON_VERSION
git submodule init
git submodule update
mvn package -DskipTests
cp assemblies/flink/target/nephron-flink-bundled-${NEPHRON_VERSION:1}.jar /data/nephron-flink-bundled.jar

cat <<EOF > /data/client.properties
security.protocol=SASL_PLAINTEXT
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="${KAFKA_SASL_USERNAME}" password="${KAFKA_SASL_PASSWORD}";
EOF

ls -alsh /data/
