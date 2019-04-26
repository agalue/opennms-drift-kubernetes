#!/bin/bash
# @author Alejandro Galue <agalue@opennms.org>
#
# Purpose:
# - Mount shared configuration files from core OpenNMS to the configuation directory.
#
# External Environment variables:
# - ONMS_SERVER
# - NFS_MOUNT_POINT

if [[ $ONMS_SERVER ]] && [[ $NFS_MOUNT_POINT ]]; then
  mount -t $ONMS_SERVER:/opt/opennms/etc $NFS_MOUNT_POINT

  SHARED_FILES=( \
    "users.xml" \
    "groups.xml" \
    "datacollection-config.xml" \
    "resource-types.d" \
    "opennms.properties.d/newts.properties" \
    "snmp-config.xml" \
    "org.opennms.features.geocoder.google.cfg" \
    "org.opennms.features.geocoder.nominatim.cfg" \
    "notifd-configuration.xml" \
    "poll-outages.xml" \
    "collectd-configuration.xml" \
    "poller-configuration.xml" \
    "ksc-performance-reports.xml" \
    "database-reports.xml" \
    "jasper-reports.xml" \
    "reports" \
    "report-templates" \
    "response-graph.properties" \
    "snmp-graph.properties" \
    "snmp-graph.properties.d" \
  )

  for SHARED_FILE in "${SHARED_FILES[@]}"; do
    echo "Point $OPENNMS_ETC/$SHARED_FILE to $NFS_MOUNT_POINT/$SHARED_FILE..."
    rm -rf $OPENNMS_ETC/$SHARED_FILE
    ln -s $NFS_MOUNT_POINT/$SHARED_FILE $OPENNMS_ETC/$SHARED_FILE
  done

fi
