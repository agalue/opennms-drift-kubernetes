#!/bin/bash
# @author Alejandro Galue <agalue@opennms.org>
#
# Requirements:
# - Horizon 27 or newer is required
# - Overlay volume mounted at /etc-overlay
#
# Purpose:
# - Configure the instance ID, SNMP4J and Kafka (for RPC and Sink)
# - Configure listeneres for Traps, Syslog, and Telemetry (on fixed ports)
#
# Warnings:
# - Even if the Kafka cluster is configured to manage large messages,
#   another source of big messages is the "batch.size" on Sink topics.
#   On large deployments, this might have to be reduced.
#
# Environment variables:
# - INSTANCE_ID
# - OPENNMS_HTTP_USER
# - OPENNMS_HTTP_PASS
# - KAFKA_SERVER
# - SINGLE_PORT
# - JAEGER_AGENT_HOST
# - DNS_LOOKUPS_ENABLED
# - DNS_SERVERS

# To avoid issues with OpenShift
umask 002

OVERLAY=/etc-overlay
CUSTOM_PROPERTIES=${OVERLAY}/custom.system.properties

### Basic Settings

FEATURES_DIR=${OVERLAY}/featuresBoot.d
mkdir -p ${FEATURES_DIR}

# Configure the instance ID
# Required when having multiple OpenNMS backends sharing the same Kafka cluster.
if [[ ${INSTANCE_ID} ]]; then
  echo "Configuring Instance ID..."
  cat <<EOF >> ${CUSTOM_PROPERTIES}
# Used for Kafka Topics
org.opennms.instance.id=${INSTANCE_ID}
EOF
fi

# Append the same relaxed SNMP4J options that OpenNMS has,
# to make sure that broken SNMP devices still work with Minions.
cat <<EOF >> ${CUSTOM_PROPERTIES}
# Adding SNMP4J Options:
snmp4j.LogFactory=org.snmp4j.log.Log4jLogFactory
org.snmp4j.smisyntaxes=opennms-snmp4j-smisyntaxes.properties
org.opennms.snmp.snmp4j.allowSNMPv2InV1=false
org.opennms.snmp.snmp4j.forwardRuntimeExceptions=false
org.opennms.snmp.snmp4j.noGetBulk=false
org.opennms.snmp.workarounds.allow64BitIpAddress=true
org.opennms.snmp.workarounds.allowZeroLengthIpAddress=true
EOF

DNS_LOOKUPS_ENABLED=${DNS_LOOKUPS_ENABLED-false}
DNS_SERVERS=${DNS_SERVERS-8.8.8.8}
if [[ ${DNS_LOOKUPS_ENABLED} == "true" ]]; then
  echo "Configuring DNS resolver..."
  cat <<EOF > ${OVERLAY}/org.opennms.features.dnsresolver.netty.cfg
num-contexts=16
nameservers=${DNS_SERVERS}
query-timeout-millis=500
max-cache-size=500000
min-ttl-seconds=60
max-ttl-seconds=300
negative-ttl-seconds=300
breaker-enabled=true
breaker-failure-rate-threshold=90
breaker-wait-duration-in-open-state=5
breaker-ring-buffer-size-in-half-open-state=100
breaker-ring-buffer-size-in-closed-state=50000
bulkhead-max-concurrent-calls=50000
bulkhead-max-wait-duration-millis=0
EOF
fi

# Enable tracing with jaeger
if [[ $JAEGER_AGENT_HOST ]]; then
  cat <<EOF >> ${CUSTOM_PROPERTIES}
# Enable Tracing
JAEGER_AGENT_HOST=${JAEGER_AGENT_HOST}
EOF
  echo "opennms-core-tracing-jaeger" > $FEATURES_DIR/jaeger.boot
fi

# Configure Sink and RPC to use Kafka
if [[ ${KAFKA_SERVER} ]]; then
  echo "Configuring Kafka..."

  cat <<EOF > ${OVERLAY}/org.opennms.core.ipc.sink.kafka.cfg
bootstrap.servers=${KAFKA_SERVER}:9092

# Producer (verify Kafka broker configuration)
acks=1
max.request.size=5000000
EOF

  cat <<EOF > ${OVERLAY}/org.opennms.core.ipc.rpc.kafka.cfg
bootstrap.servers=${KAFKA_SERVER}:9092
compression.type=gzip
request.timeout.ms=30000
single-topic=true

# Consumer (verify Kafka broker configuration)
max.partition.fetch.bytes=5000000
auto.offset.reset=latest

# Producer (verify Kafka broker configuration)
max.request.size=5000000
EOF

  cat <<EOF > ${FEATURES_DIR}/kafka.boot
!minion-jms
!opennms-core-ipc-sink-camel
!opennms-core-ipc-rpc-jms
opennms-core-ipc-sink-kafka
opennms-core-ipc-rpc-kafka
EOF
fi

# Configure SNMP Trap reception
# Port 162 cannot be used as Minion runs as non-root
# The queue.size must be consistent with the Kafka message/buffer limits; although on H24+ messages are split.
cat <<EOF > ${OVERLAY}/org.opennms.netmgt.trapd.cfg
trapd.listen.interface=0.0.0.0
trapd.listen.port=1162
# To control how many traps are included in a single message sent to Kafka
trapd.batch.size=1000
# To limit how many messages are kept in memory if Kafka is unreachable
trapd.queue.size=10000
EOF

# Configure Syslog reception
# Port 514 cannot be used as Minion runs as non-root
# The queue.size must be consistent with the Kafka message/buffer limits; although on H24+ messages are split.
cat <<EOF > ${OVERLAY}/org.opennms.netmgt.syslog.cfg
syslog.listen.interface=0.0.0.0
syslog.listen.port=1514
# To control how many syslog messages are included in a single package sent to Kafka
syslog.batch.size=1000
# To limit how many syslog messages are kept in memory if Kafka is unreachable
syslog.queue.size=10000
EOF

# Off-heap feature (must be consistent with the memory limits on the Pod)
cat <<EOF > ${OVERLAY}/org.opennms.core.ipc.sink.offheap.cfg
offHeapFilePath=
offHeapSize=512MB
# How many entries to batch in memory before writing to disk
batchSize=100
# Must be a multiple of the batch size
entriesAllowedOnHeap=100000
EOF

### Optional Settings, only relevant for processing Flows and Telemetry data

if [[ ${SINGLE_PORT} != "" ]]; then
  echo "Configuring listeners for Horizon on port ${SINGLE_PORT}"

  cat <<EOF > ${OVERLAY}/org.opennms.features.telemetry.listeners-udp-"${SINGLE_PORT}".cfg
name=Single-Port-Listener
class-name=org.opennms.netmgt.telemetry.listeners.UdpListener
parameters.host=0.0.0.0
parameters.port=${SINGLE_PORT}
parameters.maxPacketSize=16192
parsers.0.name=NXOS
parsers.0.class-name=org.opennms.netmgt.telemetry.protocols.common.parser.ForwardParser
parsers.1.name=Netflow-5
parsers.1.class-name=org.opennms.netmgt.telemetry.protocols.netflow.parser.Netflow5UdpParser
parsers.1.parameters.dnsLookupsEnabled=${DNS_LOOKUPS_ENABLED}
parsers.1.parameters.maxClockSkew=300
parsers.2.name=Netflow-9
parsers.2.class-name=org.opennms.netmgt.telemetry.protocols.netflow.parser.Netflow9UdpParser
parsers.2.parameters.dnsLookupsEnabled=${DNS_LOOKUPS_ENABLED}
parsers.2.parameters.maxClockSkew=300
parsers.3.name=IPFIX
parsers.3.class-name=org.opennms.netmgt.telemetry.protocols.netflow.parser.IpfixUdpParser
parsers.3.parameters.dnsLookupsEnabled=${DNS_LOOKUPS_ENABLED}
parsers.3.parameters.maxClockSkew=300
parsers.4.name=SFlow
parsers.4.class-name=org.opennms.netmgt.telemetry.protocols.sflow.parser.SFlowUdpParser
parsers.4.parameters.dnsLookupsEnabled=${DNS_LOOKUPS_ENABLED}
EOF

else

  echo "Configuring listeners on default ports"

  cat <<EOF > ${OVERLAY}/org.opennms.features.telemetry.listeners-udp-2003.cfg
name=Graphite-Listener
class-name=org.opennms.netmgt.telemetry.listeners.UdpListener
parameters.host=0.0.0.0
parameters.port=2003
parameters.maxPacketSize=16192
parsers.0.name=Graphite
parsers.0.class-name=org.opennms.netmgt.telemetry.protocols.common.parser.ForwardParser
EOF

  cat <<EOF > ${OVERLAY}/org.opennms.features.telemetry.listeners-udp-50001.cfg
name=NXOS-Listener
class-name=org.opennms.netmgt.telemetry.listeners.UdpListener
parameters.host=0.0.0.0
parameters.port=50001
parameters.maxPacketSize=16192
parsers.0.name=NXOS
parsers.0.class-name=org.opennms.netmgt.telemetry.protocols.common.parser.ForwardParser
EOF

  cat <<EOF > ${OVERLAY}/org.opennms.features.telemetry.listeners-udp-8877.cfg
name=Netflow-5-Listener
class-name=org.opennms.netmgt.telemetry.listeners.UdpListener
parameters.host=0.0.0.0
parameters.port=8877
parameters.maxPacketSize=16192
parsers.0.name=Netflow-5
parsers.0.class-name=org.opennms.netmgt.telemetry.protocols.netflow.parser.Netflow5UdpParser
parsers.0.parameters.dnsLookupsEnabled=${DNS_LOOKUPS_ENABLED}
parsers.0.parameters.maxClockSkew=300
EOF

  cat <<EOF > ${OVERLAY}/org.opennms.features.telemetry.listeners-udp-4729.cfg
name=Netflow-9-Listener
class-name=org.opennms.netmgt.telemetry.listeners.UdpListener
parameters.host=0.0.0.0
parameters.port=4729
parameters.maxPacketSize=16192
parsers.0.name=Netflow-9
parsers.0.class-name=org.opennms.netmgt.telemetry.protocols.netflow.parser.Netflow9UdpParser
parsers.0.parameters.dnsLookupsEnabled=${DNS_LOOKUPS_ENABLED}
parsers.0.parameters.maxClockSkew=300
EOF

  cat <<EOF > ${OVERLAY}/org.opennms.features.telemetry.listeners-udp-6343.cfg
name=SFlow-Listener
class-name=org.opennms.netmgt.telemetry.listeners.UdpListener
parameters.host=0.0.0.0
parameters.port=6343
parameters.maxPacketSize=16192
parsers.0.name=SFlow
parsers.0.class-name=org.opennms.netmgt.telemetry.protocols.sflow.parser.SFlowUdpParser
parsers.0.parameters.dnsLookupsEnabled=${DNS_LOOKUPS_ENABLED}
EOF

  cat <<EOF > ${OVERLAY}/org.opennms.features.telemetry.listeners-udp-4738.cfg
name=IPFIX-Listener
class-name=org.opennms.netmgt.telemetry.listeners.UdpListener
parameters.host=0.0.0.0
parameters.port=4738
parameters.maxPacketSize=16192
parsers.0.name=IPFIX
parsers.0.class-name=org.opennms.netmgt.telemetry.protocols.netflow.parser.IpfixUdpParser
parsers.0.parameters.dnsLookupsEnabled=${DNS_LOOKUPS_ENABLED}
parsers.0.parameters.maxClockSkew=300
EOF
fi

cat <<EOF > ${OVERLAY}/org.opennms.features.telemetry.listeners-bmp-11019.cfg
name=BMP
class-name=org.opennms.netmgt.telemetry.listeners.TcpListener
parameters.host=0.0.0.0
parameters.port=11019
parsers.0.name=BMP
parsers.0.class-name=org.opennms.netmgt.telemetry.protocols.bmp.parser.BmpParser
EOF
