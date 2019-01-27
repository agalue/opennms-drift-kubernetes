# @author Alejandro Galue <agalue@opennms.org>
#
# Creates the Newts keyspace assuming a single-dc cluster with at least 3 nodes,
# only if the keyspace/tables are not present.
# The name of the keyspace must be consistent with org.opennms.newts.config.keyspace
# See onms-core-init.sh for more details.

CREATE KEYSPACE IF NOT EXISTS newts WITH replication = {'class' : 'NetworkTopologyStrategy', 'Main' : 2 };

CREATE TABLE IF NOT EXISTS newts.samples (
  context text,
  partition int,
  resource text,
  collected_at timestamp,
  metric_name text,
  value blob,
  attributes map<text, text>,
  PRIMARY KEY((context, partition, resource), collected_at, metric_name)
) WITH compaction = {
  'compaction_window_size': '7',
  'compaction_window_unit': 'DAYS',
  'expired_sstable_check_frequency_seconds': '86400',
  'class': 'org.apache.cassandra.db.compaction.TimeWindowCompactionStrategy'
} AND gc_grace_seconds = 604800
  AND read_repair_chance = 0;

CREATE TABLE IF NOT EXISTS newts.terms (
  context text,
  field text,
  value text,
  resource text,
  PRIMARY KEY((context, field, value), resource)
);

CREATE TABLE IF NOT EXISTS newts.resource_attributes (
  context text,
  resource text,
  attribute text,
  value text,
  PRIMARY KEY((context, resource), attribute)
);

CREATE TABLE IF NOT EXISTS newts.resource_metrics (
  context text,
  resource text,
  metric_name text,
  PRIMARY KEY((context, resource), metric_name)
);
