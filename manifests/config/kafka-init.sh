#!/bin/bash
# @author Alejandro Galue <agalue@opennms.org>
#
# Purpose:
# - Configure user accounts for SASL-SCRAM in Kafka
# - This should be called from instance of the wurstmeister/kafka image
#
# Mandatory Environment variables:
# - ZOOKEEPER
# - KAFKA_ADMIN_USER
# - KAFKA_ADMIN_PASSWORD
# - KAFKA_CLIENT_USER
# - KAFKA_CLIENT_PASSWORD

/opt/kafka/bin/kafka-configs.sh --zookeeper $ZOOKEEPER --alter --add-config "SCRAM-SHA-512=[password=$KAFKA_ADMIN_PASSWORD]" --entity-type users --entity-name $KAFKA_ADMIN_USER
/opt/kafka/bin/kafka-configs.sh --zookeeper $ZOOKEEPER --alter --add-config "SCRAM-SHA-512=[password=$KAFKA_CLIENT_PASSWORD]" --entity-type users --entity-name $KAFKA_CLIENT_USER
