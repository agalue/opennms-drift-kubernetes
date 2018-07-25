#!/bin/sh

if ! grep --quiet "opennms-bundle-refresher," $FEATURES_CFG; then
  echo "Enabling features: $FEATURES_LIST ..."
  sed -r -i "s/opennms-bundle-refresher/opennms-bundle-refresher, \\n  $FEATURES_LIST/" $FEATURES_CFG
else
  echo "Features already enabled."
fi