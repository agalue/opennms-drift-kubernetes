#!/bin/bash -e

# Cause false/positives
# shellcheck disable=SC2086

MINION_HOME="/usr/share/minion"
MINION_OVERLAY_ETC="$MINION_HOME/etc-overlay"

# Error codes
E_ILLEGAL_ARGS=126

# Overlay etc specific config
if [ -d "${MINION_OVERLAY_ETC}" ] && [ -n "$(ls -A ${MINION_OVERLAY_ETC})" ]; then
  echo "Apply custom etc configuration from ${MINION_OVERLAY_ETC}."
  rsync -avr ${MINION_OVERLAY_ETC}/ ${MINION_HOME}/etc/
  sed -r -i "s/^id=.*/id=${HOSTNAME}/" ${MINION_HOME}/etc/org.opennms.minion.controller.cfg
else
  echo "No custom config found in ${MINION_OVERLAY_ETC}. Use default configuration."
fi

cd ${MINION_HOME}/bin
exec ./karaf server

