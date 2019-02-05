#!/bin/bash
# @author Alejandro Galue <agalue@opennms.org>
#
# Requirements:
# - Must run within a init-container based on opennms/minion.
#   Version must match the runtime container.
# - Horizon 23 or newer is required.
#
# Purpose:
# - Configure instance ID and the Telemetry listeners (on fixed ports)
#
# Environment variables:
# - INSTANCE_ID
# - OPENNMS_HTTP_USER
# - OPENNMS_HTTP_PASS
# - KAFKA_SERVER

SYSTEM_CFG=/opt/minion/etc/system.properties
SCV_CFG=/opt/minion/etc/scv.jce
OVERLAY=/etc-overlay
VERSION=$(rpm -q --queryformat '%{VERSION}' opennms-minion)

if [[ $INSTANCE_ID ]]; then
  echo "Configuring Instance ID..."
  cat <<EOF >> $SYSTEM_CFG

# Used for Kafka Topics
org.opennms.instance.id=$INSTANCE_ID
EOF
  cp $SYSTEM_CFG $OVERLAY
fi

if [[ $OPENNMS_HTTP_USER && $OPENNMS_HTTP_PASS ]]; then
  /opt/minion/bin/scvcli set opennms.http $OPENNMS_HTTP_USER $OPENNMS_HTTP_PASS
  cp $SCV_CFG $OVERLAY
fi

if [[ $KAFKA_SERVER ]]; then
  echo "Configuring Kafka..."

  cat <<EOF > $OVERLAY/org.opennms.core.ipc.sink.kafka.cfg
bootstrap.servers=$KAFKA_SERVER:9092
EOF

  cat <<EOF > $OVERLAY/org.opennms.core.ipc.rpc.kafka.cfg
bootstrap.servers=$KAFKA_SERVER:9092
acks=1
compression.type=gzip
request.timeout.ms=30000
# Consumer
max.partition.fetch.bytes=5000000
# Producer
max.request.size=5000000
EOF

  FEATURES_DIR=$OVERLAY/featuresBoot.d
  mkdir -p $FEATURES_DIR
  cat <<EOF > $FEATURES_DIR/kafka.boot
!minion-jms
!opennms-core-ipc-sink-camel
!opennms-core-ipc-rpc-jms
opennms-core-ipc-sink-kafka
opennms-core-ipc-rpc-kafka
EOF
fi

cat <<EOF > $OVERLAY/org.opennms.netmgt.trapd.cfg
trapd.listen.interface=0.0.0.0
trapd.listen.port=1162
trapd.queue.size=100000
EOF

cat <<EOF > $OVERLAY/org.opennms.netmgt.syslog.cfg
syslog.listen.interface=0.0.0.0
syslog.listen.port=1514
syslog.queue.size=100000
EOF

if [[ $VERSION == "23"* ]]; then
  echo "Configuring listeners for Horizon $VERSION"

  cat <<EOF > $OVERLAY/org.opennms.features.telemetry.listeners-udp-50001.cfg
name=NXOS
class-name=org.opennms.netmgt.telemetry.listeners.udp.UdpListener
host=0.0.0.0
port=50001
maxPacketSize=16192
EOF

  cat <<EOF > $OVERLAY/org.opennms.features.telemetry.listeners-udp-8877.cfg
name=Netflow-5
class-name=org.opennms.netmgt.telemetry.listeners.udp.UdpListener
host=0.0.0.0
port=8877
maxPacketSize=8096
EOF

  cat <<EOF > $OVERLAY/org.opennms.features.telemetry.listeners-udp-4729.cfg
name=Netflow-9
class-name=org.opennms.netmgt.telemetry.listeners.flow.netflow9.UdpListener
host=0.0.0.0
port=4729
maxPacketSize=8096
EOF

  cat <<EOF > $OVERLAY/org.opennms.features.telemetry.listeners-udp-6343.cfg
name=SFlow
class-name=org.opennms.netmgt.telemetry.listeners.sflow.Listener
host=0.0.0.0
port=6343
maxPacketSize=8096
EOF

  cat <<EOF > $OVERLAY/org.opennms.features.telemetry.listeners-udp-4738.cfg
name=IPFIX-Listener
class-name=org.opennms.netmgt.telemetry.listeners.flow.ipfix.UdpListener
host=0.0.0.0
port=4738
maxPacketSize=8096
EOF
fi

if [[ $VERSION == "24"* ]]; then
  echo "Configuring listeners for Horizon $VERSION"

  cat <<EOF > $OVERLAY/org.opennms.features.telemetry.listeners-udp-50001.cfg
name=NXOS-Listener
class-name=org.opennms.netmgt.telemetry.listeners.UdpListener
parameters.host=0.0.0.0
parameters.port=50001
parameters.maxPacketSize=16192
parsers.0.name=NXOS
parsers.0.class-name=org.opennms.netmgt.telemetry.protocols.common.parser.ForwardParser
EOF

  cat <<EOF > $OVERLAY/org.opennms.features.telemetry.listeners-udp-8877.cfg
name=Netflow-5-Listener
class-name=org.opennms.netmgt.telemetry.listeners.UdpListener
parameters.host=0.0.0.0
parameters.port=8877
parameters.maxPacketSize=8096
parsers.0.name=Netflow-5
parsers.0.class-name=org.opennms.netmgt.telemetry.protocols.netflow.parser.Netflow5UdpParser
EOF

  cat <<EOF > $OVERLAY/org.opennms.features.telemetry.listeners-udp-4729.cfg
name=Netflow-9-Listener
class-name=org.opennms.netmgt.telemetry.listeners.UdpListener
parameters.host=0.0.0.0
parameters.port=4729
parameters.maxPacketSize=8096
parsers.0.name=Netflow-9
parsers.0.class-name=org.opennms.netmgt.telemetry.protocols.netflow.parser.Netflow9UdpParser
EOF

  cat <<EOF > $OVERLAY/org.opennms.features.telemetry.listeners-udp-6343.cfg
name=SFlow-Listener
class-name=org.opennms.netmgt.telemetry.listeners.UdpListener
parameters.host=0.0.0.0
parameters.port=6343
parameters.maxPacketSize=8096
parsers.0.name=SFlow
parsers.0.class-name=org.opennms.netmgt.telemetry.protocols.sflow.parser.SFlowUdpParser
EOF

  cat <<EOF > $OVERLAY/org.opennms.features.telemetry.listeners-udp-4738.cfg
name=IPFIX-Listener
class-name=org.opennms.netmgt.telemetry.listeners.UdpListener
parameters.host=0.0.0.0
parameters.port=4738
parameters.maxPacketSize=8096
parsers.0.name=IPFIX
parsers.0.class-name=org.opennms.netmgt.telemetry.protocols.netflow.parser.IpfixUdpParser
EOF
fi
