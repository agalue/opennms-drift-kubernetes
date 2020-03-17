#!/bin/bash -e

join() {
  local IFS="$1"; shift; echo "$*";
}

get_key() {
  echo "$1" | cut -d_ -f2- | tr '[:upper:]' '[:lower:]' | tr _ .
}

IFS=$'\n'
PRODUCER=()
CONSUMER=("acks=1")
for VAR in $(env)
do
  env_var=$(echo "$VAR" | cut -d= -f1)
  if [[ $env_var =~ ^CONSUMER_ ]]; then
    echo "[configuring consumer] processing $env_var"
    key=$(get_key $env_var)
    echo "[configuring consumer] key: $key"
    val=${!env_var}
    echo "[configuring consumer] value: $val"
    CONSUMER+=("$key=$val")
  fi
  if [[ $env_var =~ ^PRODUCER_ ]]; then
    echo "[configuring producer] processing $env_var"
    key=$(get_key $env_var)
    echo "[configuring producer] key: $key"
    val=${!env_var}
    echo "[configuring producer] '$key'='$val'"
    PRODUCDER+=("$key=$val")
  fi
done

exec /kafka-converter \
  -bootstrap ${BOOTSTRAP_SERVERS} \
  -source-topic ${SOURCE_TOPIC} \
  -dest-topic ${DEST_TOPIC} \
  -group-id ${GROUP_ID-opennms} \
  -message-kind ${MESSAGE_KIND-alarm} \
  -producer-params "$(join , ${PRODUCER[@]})" \
  -consumer-params "$(join , ${CONSUMER[@]})" \
  -debug ${DEBUG} \
  -flat-json ${FLAT_JSON}
