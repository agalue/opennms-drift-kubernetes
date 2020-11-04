#!/bin/bash -e

# Cause false/positives
# shellcheck disable=SC2086

MINION_HOME="/usr/share/minion"
MINION_OVERLAY_ETC="$MINION_HOME/etc-overlay"
MINION_CFG=${MINION_HOME}/etc/org.opennms.minion.controller.cfg

LOCATION=${LOCATION-GNS3}
ONMS_URL=${ONMS_URL-https://onms.aws.agalue.net/opennms}
GRPC_SRV=${GRPC_SRV-grpc.aws.agalue.net}
GRPC_PORT=${GRPC_PORT-443}
GRPC_TLS=${GRPC_TLS-true}

# Error codes
E_ILLEGAL_ARGS=126

# Overlay etc specific config
if [ -d "${MINION_OVERLAY_ETC}" ] && [ -n "$(ls -A ${MINION_OVERLAY_ETC})" ]; then
  echo "Apply custom etc configuration from ${MINION_OVERLAY_ETC}."
  rsync -avr ${MINION_OVERLAY_ETC}/ ${MINION_HOME}/etc/
  sed -r -i "/^id/s/=.*/=${HOSTNAME}/"  ${MINION_CFG}
  sed -r -i "s|_ONMS_URL_|${ONMS_URL}|" ${MINION_CFG}
  sed -r -i "s|_LOCATION_|${LOCATION}|" ${MINION_CFG}
  sed -r -i "s|_GRPC_SRV_|${GRPC_SRV}|" ${MINION_HOME}/etc/org.opennms.core.ipc.grpc.client.cfg
  sed -r -i "s|_GRPC_PORT_|${GRPC_PORT}|" ${MINION_HOME}/etc/org.opennms.core.ipc.grpc.client.cfg
  sed -r -i "s|_GRPC_TLS_|${GRPC_TLS}|" ${MINION_HOME}/etc/org.opennms.core.ipc.grpc.client.cfg
else
  echo "No custom config found in ${MINION_OVERLAY_ETC}. Use default configuration."
fi

exec ${MINION_HOME}/bin/karaf server
