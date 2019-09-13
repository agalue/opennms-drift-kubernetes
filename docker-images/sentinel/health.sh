#!/usr/bin/env bash
TMP_FILE="/tmp/health"
SENTINEL_HOME="/opt/sentinel"

${SENTINEL_HOME}/bin/client "health:check | tac ${TMP_FILE}"
grep "Everything is awesome" ${TMP_FILE}