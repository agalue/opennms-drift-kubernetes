#!/bin/bash
# @author Alejandro Galue <agalue@opennms.org>
#
# Requirements:
# - Must run within a init-container based on opennms/sentinel.
#   Version must match the runtime container.
# - Horizon 23 or newer is required (if H23 is used, features.xml must be mounted on the Sentinel Pods)
#
# Purpose:
# - Configure instance ID and the Telemetry adapters only if Elasticsearch is provided.
# - Configure the Kafka consumers only if Kafka is provided.
# - Configure the Telemetry persistence only if Cassandra is provided.
#
# Environment variables:
# - INSTANCE_ID
# - ELASTIC_SERVER
# - ELASTIC_PASSWORD
# - KAFKA_SERVER
# - KAFKA_GROUP_ID
# - CASSANDRA_SERVER

GROUP_ID=${KAFKA_GROUP_ID-Sentinel}
CFG=/opt/sentinel/etc/system.properties
OVERLAY=/etc-overlay
VERSION=$(rpm -q --queryformat '%{VERSION}' opennms-sentinel)

if [[ $INSTANCE_ID ]]; then
  echo "Configuring Instance ID..."
  cat <<EOF >> $CFG

# Used for Kafka Topics
org.opennms.instance.id=$INSTANCE_ID
EOF
  cp $CFG $OVERLAY
fi

# WARNING: The following directory only exist on H24. For H23 create $MINION_HOME/deploy/features.xml
FEATURES_DIR=$OVERLAY/featuresBoot.d
mkdir -p $FEATURES_DIR

# Horizon 23 Classes
SFLOW_CLASS=org.opennms.netmgt.telemetry.adapters.netflow.sflow.SFlowAdapter
IPFIX_CLASS=org.opennms.netmgt.telemetry.adapters.netflow.ipfix.IpfixAdapter
NETFLOW5_CLASS=org.opennms.netmgt.telemetry.adapters.netflow.v5.Netflow5Adapter
NETFLOW9_CLASS=org.opennms.netmgt.telemetry.adapters.netflow.v9.Netflow9Adapter
SFLOW_TELEMETRY_CLASS=org.opennms.netmgt.telemetry.adapters.netflow.sflow.SFlowTelemetryAdapter
NXOS_TELEMETRY_CLASS=org.opennms.netmgt.telemetry.adapters.nxos.NxosGpbAdapter
JTI_TELEMETRY_CLASS=org.opennms.netmgt.telemetry.adapters.jti.JtiGpbAdapter

if [[ $VERSION == "24"* ]]; then
  SFLOW_CLASS=org.opennms.netmgt.telemetry.protocols.sflow.adapter.SFlowAdapter
  IPFIX_CLASS=org.opennms.netmgt.telemetry.protocols.netflow.adapter.ipfix.IpfixAdapter
  NETFLOW5_CLASS=org.opennms.netmgt.telemetry.protocols.netflow.adapter.netflow5.Netflow5Adapter
  NETFLOW9_CLASS=org.opennms.netmgt.telemetry.protocols.netflow.adapter.netflow9.Netflow9Adapter
  SFLOW_TELEMETRY_CLASS=org.opennms.netmgt.telemetry.protocols.sflow.adapter.SFlowTelemetryAdapter
  NXOS_TELEMETRY_CLASS=org.opennms.netmgt.telemetry.protocols.nxos.adapter.NxosGpbAdapter
  JTI_TELEMETRY_CLASS=org.opennms.netmgt.telemetry.protocols.jti.adapter.JtiGpbAdapter
fi

if [[ $ELASTIC_SERVER ]]; then
  echo "Configuring Elasticsearch..."

  echo "sentinel-flows" > $FEATURES_DIR/flows.boot

  if [[ ! $CASSANDRA_SERVER ]]; then
    cat <<EOF > $OVERLAY/org.opennms.features.telemetry.adapters-sflow.cfg
name = SFlow
class-name = $SFLOW_CLASS
EOF
  fi

  cat <<EOF > $OVERLAY/org.opennms.features.telemetry.adapters-ipfix.cfg
name = IPFIX
class-name = $IPFIX_CLASS
EOF

  cat <<EOF > $OVERLAY/org.opennms.features.telemetry.adapters-netflow5.cfg
name = Netflow-5
class-name = $NETFLOW5_CLASS
EOF

  cat <<EOF > $OVERLAY/org.opennms.features.telemetry.adapters-netflow9.cfg
name = Netflow-9
class-name = $NETFLOW9_CLASS
EOF

  cat <<EOF > $OVERLAY/org.opennms.features.flows.persistence.elastic.cfg
elasticUrl = http://$ELASTIC_SERVER:9200
globalElasticUser = elastic
globalElasticPassword = $ELASTIC_PASSWORD
elasticIndexStrategy = daily
settings.index.number_of_shards = 6
settings.index.number_of_replicas = 1
EOF
fi

if [[ $KAFKA_SERVER ]]; then
  echo "Configuring Kafka..."

  echo "sentinel-kafka" > $FEATURES_DIR/kafka.boot

  cat <<EOF > $OVERLAY/org.opennms.core.ipc.sink.kafka.consumer.cfg
group.id = $GROUP_ID
bootstrap.servers = $KAFKA_SERVER:9092
max.partition.fetch.bytes=5000000
EOF
fi

if [[ $CASSANDRA_SERVER ]]; then
  echo "Configuring Cassandra..."

  cat <<EOF > $FEATURES_DIR/telemetry.boot
sentinel-newts
sentinel-telemetry-nxos
sentinel-telemetry-jti
EOF

  cat <<EOF > $OVERLAY/org.opennms.newts.config.cfg
# WARNING: Must match what OpenNMS has configured for Newts
hostname = ${CASSANDRA_SERVER}
keyspace = ${INSTANCE_ID}_newts
port = 9042
read_consistency = ONE
write_consistency = ANY
resource_shard = 604800
ttl = 31540000
ring_buffer_size = 131072
cache.max_entries = 131072
cache.strategy = org.opennms.netmgt.newts.support.GuavaSearchableResourceMetadataCache
EOF

  cat <<EOF > $OVERLAY/org.opennms.features.telemetry.adapters-sflow-telemetry.cfg
adapters.1.name = SFlow
adapters.1.class-name = $SFLOW_CLASS
adapters.2.name = SFlow-Telemetry
adapters.2.class-name = $SFLOW_TELEMETRY_CLASS
adapters.2.parameters.script = /opt/minion/etc/sflow-host.groovy
EOF

  cat <<EOF > $OVERLAY/org.opennms.features.telemetry.adapters-nxos.cfg
name = NXOS
class-name = $NXOS_TELEMETRY_CLASS
parameters.script = /opt/minion/etc/cisco-nxos-telemetry-interface.groovy
EOF

cat <<EOF > $OVERLAY/org.opennms.features.telemetry.adapters-jti.cfg
name = JTI
class-name = $JTI_TELEMETRY_CLASS
parameters.script = /opt/minion/etc/junos-telemetry-interface.groovy
EOF

cat <<EOF > $OVERLAY/datacollection-config.xml
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

mkdir -p $OVERLAY/resource-types.d
cat <<EOF > $OVERLAY/resource-types.d/nxos-resources.xml
<?xml version="1.0"?>
<resource-types>
  <resourceType name="nxosCpu" label="Nxos Cpu" resourceLabel="${index}">
    <persistenceSelectorStrategy class="org.opennms.netmgt.collection.support.PersistAllSelectorStrategy"/>
    <storageStrategy class="org.opennms.netmgt.collection.support.IndexStorageStrategy"/>
  </resourceType>
  <resourceType name="nxosIntf" label="Nxos Interface" resourceLabel="${index}">
    <persistenceSelectorStrategy class="org.opennms.netmgt.collection.support.PersistAllSelectorStrategy"/>
    <storageStrategy class="org.opennms.netmgt.collection.support.IndexStorageStrategy"/>
  </resourceType>
</resource-types>
EOF

mkdir -p $OVERLAY/datacollection
cat <<EOF > $OVERLAY/datacollection/mib2.xml
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

cat <<EOF > $OVERLAY/sflow-host.groovy
import org.opennms.netmgt.collection.support.builder.NodeLevelResource
import static org.opennms.netmgt.telemetry.adapters.netflow.BsonUtils.get
import static org.opennms.netmgt.telemetry.adapters.netflow.BsonUtils.getDouble
import static org.opennms.netmgt.telemetry.adapters.netflow.BsonUtils.getInt64

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

  cat <<EOF > $OVERLAY/junos-telemetry-interface.groovy
import groovy.util.logging.Slf4j
import org.opennms.core.utils.RrdLabelUtils
import org.opennms.netmgt.collection.api.AttributeType
import org.opennms.netmgt.telemetry.adapters.jti.proto.Port
import org.opennms.netmgt.telemetry.adapters.jti.proto.TelemetryTop
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

  cat <<EOF > $OVERLAY/cisco-nxos-telemetry-interface.groovy
import groovy.util.logging.Slf4j
import java.util.List
import java.util.Objects
import org.opennms.netmgt.collection.api.AttributeType
import org.opennms.netmgt.collection.support.builder.DeferredGenericTypeResource
import org.opennms.netmgt.collection.support.builder.NodeLevelResource
import org.opennms.netmgt.telemetry.adapters.nxos.proto.TelemetryBis
import org.opennms.netmgt.telemetry.adapters.nxos.NxosGpbParserUtil
import org.opennms.netmgt.telemetry.adapters.nxos.proto.TelemetryBis.TelemetryField

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

    def m;
    if ((m = telemetryMsg.getEncodingPath() =~ /sys\/intf\/phys-\[(.+)\]\/dbgIfHC(In|Out)/)) {
      def intfId = m.group(1).replaceAll(/\//,"-")
      def statsType = m.group(2)
      def genericTypeResource = new DeferredGenericTypeResource(nodeLevelResource, "nxosIntf", intfId)
      ["ucastPkts", "multicastPkts", "broadcastPkts", "octets"].each { metric ->
        builder.withNumericAttribute(genericTypeResource, "nxos-intfHC$statsType", "$metric$statsType",
          NxosGpbParserUtil.getValueAsDouble(telemetryMsg, metric), AttributeType.COUNTER)
      }
    }

    if (telemetryMsg.getEncodingPath().equals("sys/intf")) {
      findFieldWithName(telemetryMsg.getDataGpbkvList().get(0), "children").getFieldsList()
        .each { f ->
          def intfId = findFieldWithName(f, "id").getStringValue().replaceAll(/\//,"_")
          log.debug("Processing NX-OS interface {}", intfId)
          def genericTypeResource = new DeferredGenericTypeResource(nodeLevelResource, "nxosIntf", intfId)
          def rmonIfHCIn = findFieldWithName(f, "rmonIfHCIn");
          def rmonIfHCOut = findFieldWithName(f, "rmonIfHCOut");
          if (rmonIfHCIn != null && rmonIfHCOut != null) {
            ["ucastPkts", "multicastPkts", "broadcastPkts", "octets"].each { metric ->
              builder.withNumericAttribute(genericTypeResource, "nxosRmonIntfStats", "in$metric",
                NxosGpbParserUtil.getValueFromRowAsDouble(rmonIfHCIn, metric), AttributeType.COUNTER)
              builder.withNumericAttribute(genericTypeResource, "nxosRmonIntfStats", "out$metric",
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
fi
