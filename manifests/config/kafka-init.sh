#!/bin/bash
# @author Alejandro Galue <agalue@opennms.org>
#
# Purpose:
# - Initialize topics.
#
# Expected format:
#   name:partitions:replicas:cleanup.policy

IFS="${KAFKA_CREATE_TOPICS_SEPARATOR-,}"; for topicToCreate in $KAFKA_CREATE_TOPICS; do
    echo "creating topics: $topicToCreate"
    IFS=':' read -r -a topicConfig <<< "$topicToCreate"
    config=
    if [ -n "${topicConfig[3]}" ]; then
        config="--config=cleanup.policy=${topicConfig[3]}"
    fi
    COMMAND="kafka-topics.sh \\
		--create \\
		--bootstrap-server ${KAFKA_BOOTSTRAP_SERVER} \\
		--topic ${topicConfig[0]} \\
		--partitions ${topicConfig[1]} \\
		--replication-factor ${topicConfig[2]} \\
		${config} \\
		${KAFKA_0_10_OPTS} &"
    eval "${COMMAND}"
done