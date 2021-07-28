#!/bin/bash
# @author Alejandro Galue <agalue@opennms.org>
#
# Sentinel is required only for bmp, flows, and streaming telemetry processing.
#
# Requirements:
# - Horizon 27 or newer is required
# - Overlay volume mounted at /etc-overlay
# - NUM_LISTENER_THREADS (i.e. queue.threads) must be consistent with the amount of partitions on Kafka
#
# Purpose:
# - Configure instance ID.
# - Configure Telemetry adapters only if Elasticsearch is provided.
# - Configure the Kafka consumers only if Kafka is provided.
# - Configure the Telemetry persistence only if Cassandra is provided.
#
# Environment variables:
# - INSTANCE_ID
# - ELASTIC_SERVER
# - ELASTIC_PASSWORD
# - ELASTIC_INDEX_STRATEGY_FLOWS
# - ELASTIC_REPLICATION_FACTOR
# - ELASTIC_NUM_SHARDS
# - KAFKA_SERVER
# - KAFKA_SASL_USERNAME
# - KAFKA_SASL_PASSWORD
# - CASSANDRA_SERVER
# - NUM_LISTENER_THREADS
# - JAEGER_AGENT_HOST
# - USE_NEPHRON

# To avoid issues with OpenShift
umask 002

NUM_LISTENER_THREADS=${NUM_LISTENER_THREADS-6}
ELASTIC_INDEX_STRATEGY_FLOWS=${ELASTIC_INDEX_STRATEGY_FLOWS-daily}
ELASTIC_REPLICATION_FACTOR=${ELASTIC_REPLICATION_FACTOR-2}
ELASTIC_NUM_SHARDS=${ELASTIC_NUM_SHARDS-6}
USE_NEPHRON=${USE_NEPHRON-false}

OVERLAY=/etc-overlay
SENTINEL_HOME=/opt/sentinel
KEYSPACE=$(echo ${INSTANCE_ID-onms}_newts | tr '[:upper:]' '[:lower:]')

# Configure the instance ID
# Required when having multiple OpenNMS backends sharing the same Kafka cluster.
CUSTOM_PROPERTIES=${OVERLAY}/custom.system.properties
if [[ ${INSTANCE_ID} ]]; then
  echo "Configuring Instance ID..."
  cat <<EOF >> ${CUSTOM_PROPERTIES}
# Used for Kafka Topics
org.opennms.instance.id=${INSTANCE_ID}
# Refresh Interface-to-Node cache every 2 hours
org.opennms.interface-node-cache.refresh-timer=7200000
EOF
else
  INSTANCE_ID="OpenNMS"
fi

FEATURES_DIR=${OVERLAY}/featuresBoot.d
mkdir -p ${FEATURES_DIR}
cat <<EOF > ${FEATURES_DIR}/persistence.boot
sentinel-persistence
sentinel-jsonstore-postgres
EOF

# Enable tracing with jaeger
if [[ ${JAEGER_AGENT_HOST} ]]; then
  cat <<EOF >> ${CUSTOM_PROPERTIES}
# Enable Tracing
JAEGER_AGENT_HOST=${JAEGER_AGENT_HOST}
EOF
  echo "opennms-core-tracing-jaeger" > ${FEATURES_DIR}/jaeger.boot
fi

# Enable BMP
cat <<EOF > ${FEATURES_DIR}/bmp.boot
sentinel-telemetry-bmp
EOF
cat <<EOF > ${OVERLAY}/org.opennms.features.telemetry.adapters-bmp.cfg
name=BMP
adapters.0.name=BMP-PeerStatus-Adapter
adapters.0.class-name=org.opennms.netmgt.telemetry.protocols.bmp.adapter.BmpPeerStatusAdapter
EOF

if [[ ${ELASTIC_SERVER} ]]; then
  echo "Configuring Elasticsearch..."

  cat <<EOF > ${FEATURES_DIR}/flows.boot
sentinel-flows
EOF

  if [[ ! ${CASSANDRA_SERVER} ]]; then
    cat <<EOF > ${OVERLAY}/org.opennms.features.telemetry.adapters-sflow.cfg
name=SFlow
adapters.0.name=SFlow-Adapter
adapters.0.class-name=org.opennms.netmgt.telemetry.protocols.sflow.adapter.SFlowAdapter
queue.threads=${NUM_LISTENER_THREADS}
EOF
  fi

  cat <<EOF > ${OVERLAY}/org.opennms.features.telemetry.adapters-ipfix.cfg
name=IPFIX
adapters.0.name=IPFIX-Adapter
adapters.0.class-name=org.opennms.netmgt.telemetry.protocols.netflow.adapter.ipfix.IpfixAdapter
queue.threads=${NUM_LISTENER_THREADS}
EOF

  cat <<EOF > ${OVERLAY}/org.opennms.features.telemetry.adapters-netflow5.cfg
name=Netflow-5
adapters.0.name=Netflow-5-Adapter
adapters.0.class-name=org.opennms.netmgt.telemetry.protocols.netflow.adapter.netflow5.Netflow5Adapter
queue.threads=${NUM_LISTENER_THREADS}
EOF

  cat <<EOF > ${OVERLAY}/org.opennms.features.telemetry.adapters-netflow9.cfg
name=Netflow-9
adapters.0.name=Netflow-9-Adapter
adapters.0.class-name=org.opennms.netmgt.telemetry.protocols.netflow.adapter.netflow9.Netflow9Adapter
queue.threads=${NUM_LISTENER_THREADS}
EOF

  PREFIX=$(echo ${INSTANCE_ID} | tr '[:upper:]' '[:lower:]')-
  cat <<EOF > ${OVERLAY}/org.opennms.features.flows.persistence.elastic.cfg
elasticUrl=http://${ELASTIC_SERVER}:9200
globalElasticUser=elastic
indexPrefix=${PREFIX}
globalElasticPassword=${ELASTIC_PASSWORD}
elasticIndexStrategy=${ELASTIC_INDEX_STRATEGY_FLOWS}
clockSkewCorrectionThreshold=5000
# The following settings should be consistent with your ES cluster
settings.index.number_of_shards=${ELASTIC_NUM_SHARDS}
settings.index.number_of_replicas=${ELASTIC_REPLICATION_FACTOR}
EOF

  if [[ ${USE_NEPHRON} == "true" ]]; then
    curl https://raw.githubusercontent.com/OpenNMS/nephron/master/main/src/main/resources/netflow_agg-template.json
    curl -XPUT -H 'Content-Type: application/json' http://${ELASTIC_SERVER}:9200/_template/netflow_agg -d@netflow_agg-template.json
    cat <<EOF >> ${OVERLAY}/org.opennms.features.flows.persistence.elastic.cfg
enableForwarding=true
EOF
  fi
fi

if [[ ${KAFKA_SERVER} ]]; then
  echo "Configuring Kafka..."

  if [[ ${KAFKA_SASL_USERNAME} && ${KAFKA_SASL_PASSWORD} ]]; then
    read -r -d '' KAFKA_SASL <<EOF
security.protocol=SASL_PLAINTEXT
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="${KAFKA_SASL_USERNAME}" password="${KAFKA_SASL_PASSWORD}";
EOF
  fi

  echo "sentinel-kafka" > ${FEATURES_DIR}/kafka.boot

  cat <<EOF > ${OVERLAY}/org.opennms.core.ipc.sink.kafka.cfg
# Producers
bootstrap.servers=${KAFKA_SERVER}:9092
acks=1
${KAFKA_SASL}
EOF

  cat <<EOF > ${OVERLAY}/org.opennms.core.ipc.sink.kafka.consumer.cfg
# Consumers
group.id=${INSTANCE_ID}_Sentinel
bootstrap.servers=${KAFKA_SERVER}:9092
max.partition.fetch.bytes=5000000
${KAFKA_SASL}
EOF

  if [[ ${USE_NEPHRON} == "true" ]]; then
    cat <<EOF > ${OVERLAY}/org.opennms.features.flows.persistence.kafka.cfg
topic=${INSTANCE_ID}_opennms_flows
bootstrap.servers=${KAFKA_SERVER}:9092
${KAFKA_SASL}
EOF
  fi
fi

if [[ ${CASSANDRA_SERVER} ]]; then
  echo "Configuring Cassandra..."

  cat <<EOF > ${FEATURES_DIR}/telemetry.boot
sentinel-newts
sentinel-telemetry-nxos
sentinel-telemetry-jti
sentinel-telemetry-graphite
sentinel-blobstore-cassandra
EOF

  cat <<EOF >> ${CUSTOM_PROPERTIES}
# WARNING: Must match OpenNMS in order to properly store telemetry metrics on Cassandra
org.opennms.rrd.storeByGroup=true
org.opennms.rrd.storeByForeignSource=true
EOF

  cat <<EOF > ${OVERLAY}/org.opennms.newts.config.cfg
# About the properties:
# - Must match what OpenNMS has configured for Newts
# - ring_buffer_size and cache.max_entries should be consistent with the expected load and heap size

hostname=${CASSANDRA_SERVER}
keyspace=${KEYSPACE}
port=9042
read_consistency=ONE
write_consistency=ANY
resource_shard=604800
ttl=31540000
cache.strategy=org.opennms.netmgt.newts.support.GuavaSearchableResourceMetadataCache
ring_buffer_size=131072
cache.max_entries=131072
EOF

  cat <<EOF > ${OVERLAY}/org.opennms.features.telemetry.adapters-sflow-telemetry.cfg
name=SFlow
adapters.1.name=SFlow-Adapter
adapters.1.class-name=org.opennms.netmgt.telemetry.protocols.sflow.adapter.SFlowAdapter
adapters.2.name=SFlow-Telemetry
adapters.2.class-name=org.opennms.netmgt.telemetry.protocols.sflow.adapter.SFlowTelemetryAdapter
adapters.2.parameters.script=${SENTINEL_HOME}/etc/sflow-host.groovy
queue.threads=${NUM_LISTENER_THREADS}
EOF

  cat <<EOF > ${OVERLAY}/org.opennms.features.telemetry.adapters-nxos.cfg
name=NXOS
adapters.0.name=NXOS-Adapter
adapters.0.class-name=org.opennms.netmgt.telemetry.protocols.nxos.adapter.NxosGpbAdapter
adapters.0.parameters.script=${SENTINEL_HOME}/etc/cisco-nxos-telemetry-interface.groovy
queue.threads=${NUM_LISTENER_THREADS}
EOF

  cat <<EOF > ${OVERLAY}/org.opennms.features.telemetry.adapters-jti.cfg
name=JTI
adapters.0.name=JTI-Adapter
adapters.0.class-name=org.opennms.netmgt.telemetry.protocols.jti.adapter.JtiGpbAdapter
adapters.0.parameters.script=${SENTINEL_HOME}/etc/junos-telemetry-interface.groovy
queue.threads=${NUM_LISTENER_THREADS}
EOF

  cat <<EOF > ${OVERLAY}/org.opennms.features.telemetry.adapters-graphite.cfg
name=Graphite
adapters.0.name=Graphite-Adapter
adapters.0.class-name=org.opennms.netmgt.telemetry.protocols.graphite.adapter.GraphiteAdapter
adapters.0.parameters.script=${SENTINEL_HOME}/etc/graphite-telemetry-interface.groovy
EOF

  cat <<EOF >> ${OVERLAY}/org.opennms.features.telemetry.adapters-bmp.cfg
adapters.1.name=BMP-Telemetry-Adapter
adapters.1.class-name=org.opennms.netmgt.telemetry.protocols.bmp.adapter.BmpTelemetryAdapter
EOF

  cat <<EOF > ${OVERLAY}/datacollection-config.xml
<datacollection-config xmlns="http://xmlns.opennms.org/xsd/config/datacollection" rrdRepository="/var/opennms/rrd/snmp/">
  <snmp-collection name="default" snmpStorageFlag="select">
    <rrd step="300">
      <rra>RRA:AVERAGE:0.5:1:2016</rra>
      <rra>RRA:AVERAGE:0.5:12:1488</rra>
      <rra>RRA:AVERAGE:0.5:288:366</rra>
      <rra>RRA:MAX:0.5:288:366</rra>
      <rra>RRA:MIN:0.5:288:366</rra>
    </rrd>
    <include-collection dataCollectionGroup="MIB2"/>
  </snmp-collection>
</datacollection-config>
EOF

  mkdir -p ${OVERLAY}/resource-types.d
  cat <<EOF > ${OVERLAY}/resource-types.d/nxos-resources.xml
<?xml version="1.0"?>
<resource-types>
  <resourceType name="nxosCpu" label="Nxos Cpu" resourceLabel="\${index}">
    <persistenceSelectorStrategy class="org.opennms.netmgt.collection.support.PersistAllSelectorStrategy"/>
    <storageStrategy class="org.opennms.netmgt.collection.support.IndexStorageStrategy"/>
  </resourceType>
  <resourceType name="nxosIntf" label="Nxos Interface" resourceLabel="\${index}">
    <persistenceSelectorStrategy class="org.opennms.netmgt.collection.support.PersistAllSelectorStrategy"/>
    <storageStrategy class="org.opennms.netmgt.collection.support.IndexStorageStrategy"/>
  </resourceType>
</resource-types>
EOF

  mkdir -p ${OVERLAY}/datacollection
  cat <<EOF > ${OVERLAY}/datacollection/mib2.xml
<datacollection-group xmlns="http://xmlns.opennms.org/xsd/config/datacollection" name="MIB2">
  <group name="mib2-X-interfaces" ifType="all">
    <mibObj oid=".1.3.6.1.2.1.31.1.1.1.1" instance="ifIndex" alias="ifName" type="string"/>
    <mibObj oid=".1.3.6.1.2.1.31.1.1.1.15" instance="ifIndex" alias="ifHighSpeed" type="string"/>
    <mibObj oid=".1.3.6.1.2.1.31.1.1.1.6" instance="ifIndex" alias="ifHCInOctets" type="Counter64"/>
    <mibObj oid=".1.3.6.1.2.1.31.1.1.1.10" instance="ifIndex" alias="ifHCOutOctets" type="Counter64"/>
  </group>
  <systemDef name="Enterprise">
    <sysoidMask>.1.3.6.1.4.1.</sysoidMask>
    <collect>
      <includeGroup>mib2-X-interfaces</includeGroup>
    </collect>
  </systemDef>
</datacollection-group>
EOF

  cat <<EOF > ${OVERLAY}/sflow-host.groovy
import static org.opennms.netmgt.telemetry.protocols.common.utils.BsonUtils.get
import static org.opennms.netmgt.telemetry.protocols.common.utils.BsonUtils.getDouble
import static org.opennms.netmgt.telemetry.protocols.common.utils.BsonUtils.getInt64
import org.opennms.netmgt.collection.support.builder.NodeLevelResource

NodeLevelResource nodeLevelResource = new NodeLevelResource(agent.getNodeId())

get(msg, "counters", "0:2003").ifPresent { doc ->
  builder.withGauge(nodeLevelResource, "host-cpu", "load_avg_1min", getDouble(doc, "load_one").get())
  builder.withGauge(nodeLevelResource, "host-cpu", "load_avg_5min", getDouble(doc, "load_five").get())
  builder.withGauge(nodeLevelResource, "host-cpu", "load_avg_15min", getDouble(doc, "load_fifteen").get())
}

get(msg, "counters", "0:2004").ifPresent { doc ->
  builder.withGauge(nodeLevelResource, "host-memory", "mem_total", getInt64(doc, "mem_total").get())
  builder.withGauge(nodeLevelResource, "host-memory", "mem_free", getInt64(doc, "mem_free").get())
  builder.withGauge(nodeLevelResource, "host-memory", "mem_shared", getInt64(doc, "mem_shared").get())
  builder.withGauge(nodeLevelResource, "host-memory", "mem_buffers", getInt64(doc, "mem_buffers").get())
  builder.withGauge(nodeLevelResource, "host-memory", "mem_cached", getInt64(doc, "mem_cached").get())
}
EOF

  cat <<EOF > ${OVERLAY}/junos-telemetry-interface.groovy
import org.opennms.netmgt.telemetry.protocols.jti.adapter.proto.Port
import org.opennms.netmgt.telemetry.protocols.jti.adapter.proto.TelemetryTop
import groovy.util.logging.Slf4j
import org.opennms.core.utils.RrdLabelUtils
import org.opennms.netmgt.collection.api.AttributeType
import org.opennms.netmgt.collection.support.builder.InterfaceLevelResource
import org.opennms.netmgt.collection.support.builder.NodeLevelResource

@Slf4j
class CollectionSetGenerator {
  static generate(agent, builder, jtiMsg) {
    log.debug("Generating collection set for message: {}", jtiMsg)
    NodeLevelResource nodeLevelResource = new NodeLevelResource(agent.getNodeId())
    TelemetryTop.EnterpriseSensors entSensors = jtiMsg.getEnterprise()
    TelemetryTop.JuniperNetworksSensors jnprSensors = entSensors.getExtension(TelemetryTop.juniperNetworks);
    Port.GPort port = jnprSensors.getExtension(Port.jnprInterfaceExt);
    for (Port.InterfaceInfos interfaceInfos : port.getInterfaceStatsList()) {
      String interfaceLabel = RrdLabelUtils.computeLabelForRRD(interfaceInfos.getIfName(), null, null);
      InterfaceLevelResource interfaceResource = new InterfaceLevelResource(nodeLevelResource, interfaceLabel);
      builder.withNumericAttribute(interfaceResource, "mib2-interfaces", "ifInOctets", interfaceInfos.getIngressStats().getIfOctets(), AttributeType.COUNTER);
      builder.withNumericAttribute(interfaceResource, "mib2-interfaces", "ifOutOctets", interfaceInfos.getEgressStats().getIfOctets(), AttributeType.COUNTER);
    }
  }
}

TelemetryTop.TelemetryStream jtiMsg = msg
CollectionSetGenerator.generate(agent, builder, jtiMsg)
EOF

  cat <<EOF > ${OVERLAY}/cisco-nxos-telemetry-interface.groovy
import org.opennms.netmgt.telemetry.protocols.nxos.adapter.proto.TelemetryBis
import org.opennms.netmgt.telemetry.protocols.nxos.adapter.NxosGpbParserUtil
import groovy.util.logging.Slf4j
import java.util.List
import java.util.Objects
import org.opennms.netmgt.collection.api.AttributeType
import org.opennms.netmgt.collection.support.builder.DeferredGenericTypeResource
import org.opennms.netmgt.collection.support.builder.NodeLevelResource

@Slf4j
class CollectionSetGenerator {
  static generate(agent, builder, telemetryMsg) {
    log.debug("Generating collection set for node {} from message: {}", agent.getNodeId(), telemetryMsg)

    def nodeLevelResource = new NodeLevelResource(agent.getNodeId())
    if (telemetryMsg.getEncodingPath().equals("show system resources")) {
      builder.withNumericAttribute(nodeLevelResource, "nxos-stats", "load_avg_1min",
        NxosGpbParserUtil.getValueAsDouble(telemetryMsg, "load_avg_1min"), AttributeType.GAUGE)
      builder.withNumericAttribute(nodeLevelResource, "nxos-stats", "memory_usage_used",
        NxosGpbParserUtil.getValueAsDouble(telemetryMsg, "memory_usage_used"), AttributeType.GAUGE)
      NxosGpbParserUtil.getRowsFromTable(telemetryMsg, "cpu_usage").each { row ->
        def cpuId = NxosGpbParserUtil.getValueFromRowAsString(row, "cpuid")
        def genericTypeResource = new DeferredGenericTypeResource(nodeLevelResource, "nxosCpu", cpuId)
        ["idle", "kernel", "user"].each { metric ->
          builder.withNumericAttribute(genericTypeResource, "nxos-cpu-stats", metric,
            NxosGpbParserUtil.getValueFromRowAsDouble(row, metric), AttributeType.GAUGE)
        }
      }
    }

    // Requires gRPC, this won't work with UDP
    if (telemetryMsg.getEncodingPath().equals("sys/intf")) {
      findFieldWithName(telemetryMsg.getDataGpbkvList().get(0), "children").getFieldsList()
        .each { f ->
          def intfId = findFieldWithName(f, "id").getStringValue().replaceAll(/\\//,"_")
          log.debug("Processing NX-OS interface {}", intfId)
          def genericTypeResource = new DeferredGenericTypeResource(nodeLevelResource, "nxosIntf", intfId)
          def rmonIfHCIn = findFieldWithName(f, "rmonIfHCIn");
          def rmonIfHCOut = findFieldWithName(f, "rmonIfHCOut");
          if (rmonIfHCIn != null && rmonIfHCOut != null) {
            ["ucastPkts", "multicastPkts", "broadcastPkts", "octets"].each { metric ->
              builder.withNumericAttribute(genericTypeResource, "nxosRmonIntfStats", "in\$metric",
                NxosGpbParserUtil.getValueFromRowAsDouble(rmonIfHCIn, metric), AttributeType.COUNTER)
              builder.withNumericAttribute(genericTypeResource, "nxosRmonIntfStats", "out\$metric",
                NxosGpbParserUtil.getValueFromRowAsDouble(rmonIfHCOut, metric), AttributeType.COUNTER)
            }
          }
        }
    } 
  }

  static findFieldWithName(TelemetryBis.TelemetryField field, String name) {
    if (Objects.equals(field.getName(), name)) {
      return field
    }
    for (subField in field.getFieldsList()) {
      def matchingField = findFieldWithName(subField, name)
      if (matchingField != null) {
        return matchingField
      }
    }
    return null
  }
}

TelemetryBis.Telemetry telemetryMsg = msg
CollectionSetGenerator.generate(agent, builder, telemetryMsg)
EOF

  cat <<EOF > ${OVERLAY}/graphite-telemetry-interface.groovy
import groovy.util.logging.Slf4j
import org.opennms.core.utils.RrdLabelUtils
import org.opennms.netmgt.collection.api.AttributeType
import org.opennms.netmgt.telemetry.protocols.graphite.adapter.GraphiteMetric
import org.opennms.netmgt.collection.support.builder.InterfaceLevelResource
import org.opennms.netmgt.collection.support.builder.NodeLevelResource

@Slf4j
class CollectionSetGenerator {
  static generate(agent, builder, graphiteMsg) {
    log.debug("Generating collection set for message: {}", graphiteMsg)
    def nodeLevelResource = new NodeLevelResource(agent.getNodeId())
    if (graphiteMsg.path.startsWith("eth")) {
      def ifaceLabel = RrdLabelUtils.computeLabelForRRD(graphiteMsg.path.split(".")[0], null, null);
      def interfaceResource = new InterfaceLevelResource(nodeLevelResource, interfaceLabel);
      builder.withGauge(interfaceResource, "some-group", graphiteMsg.path.split(".")[1], graphitMsg.longValue());
    } else {
      log.warn("Cannot handle message from graphite. {}", graphiteMsg);
    }
  }
}

GraphiteMetric graphiteMsg = msg
CollectionSetGenerator.generate(agent, builder, graphiteMsg)
EOF
else
  cat <<EOF >> ${FEATURES_DIR}/persistence.boot
sentinel-blobstore-noop
EOF
fi
