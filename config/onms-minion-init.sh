#!/bin/bash
# @author Alejandro Galue <agalue@opennms.org>
#
# Requirements:
# - Must run within a init-container based on opennms/minion.
#   Version must match the runtime container.
# - Horizon 24 or newer is required.
#
# Purpose:
# - Configure instance ID and the Telemetry listeners (on fixed ports)
#
# Environment variables:
# - INSTANCE_ID

CFG=/opt/minion/etc/system.properties
OVERLAY=/etc-overlay

if [[ $INSTANCE_ID ]]; then
  echo "Configuring Instance ID..."
  cat <<EOF >> $CFG

# Used for Kafka Topics
org.opennms.instance.id=$INSTANCE_ID
EOF
  cp $CFG $OVERLAY
fi

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