#!/bin/bash -e
# =====================================================================
# Build script running OpenNMS gRPC Server in Docker environment
# =====================================================================

function join { local IFS="$1"; shift; echo "$*"; }

TLS_ENABLED=${TLS_ENABLED-false}
IFS=$'\n'
OPTIONS=(
  "-Dorg.opennms.instance.id=${INSTANCE_ID-OpenNMS}"
  "-Dtls.enabled=${TLS_ENABLED}"
  "-Dport=${PORT-8990}"
  "-Dmax.message.size=${MAX_MESSAGE_SIZE-10485760}"
)
if [[ $TLS_ENABLED == true ]]; then
  OPTIONS+=(-Dserver.private.key.filepath=${SERVER_PRIVATE_KEY-/grpc/key.pem})
  OPTIONS+=(-Dserver.cert.filepath=${SERVER_CERT-/grpc/cert.pem})
  OPTIONS+=(-Dclient.cert.filepath=${CLIENT_CERT-/grpc/client.pem})
fi

for VAR in $(env)
do
  env_var=$(echo "$VAR" | cut -d= -f1)
  if [[ $env_var =~ ^PRODUCER_ || $env_var =~ ^CONSUMER_ ]]; then
    key="org.opennms.core.ipc.grpc.kafka."$(echo "$env_var" | tr '[:upper:]' '[:lower:]' | tr _ .)
    val=${!env_var}
    echo "[Configuring] '$key'='$val'"
    OPTIONS+=("-D$key=$val")
  fi
done

export JAVA_TOOL_OPTIONS="${JAVA_OPTS} $(join ' ' ${OPTIONS[@]})"
exec java -jar /grpc-ipc-server.jar ${BOOTSTRAP_SERVERS-localhost:9092}
