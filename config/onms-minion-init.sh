#!/bin/bash
# @author Alejandro Galue <agalue@opennms.org>

# Environment variables:
#
# INSTANCE_ID

CFG=/opt/minion/etc/system.properties

if [[ $INSTANCE_ID ]]; then
  echo "Configuring Instance ID..."
  cat <<EOF >> $CFG

# Used for Kafka Topics
org.opennms.instance.id=$INSTANCE_ID
EOF
  cp $CFG /etc-overlay
fi
