#!/bin/bash

type protoc >/dev/null 2>&1 || { echo >&2 "protoc required but it's not installed; aborting."; exit 1; }

protoc -I . opennms-kafka-producer.proto --go_out=./producer
protoc -I . collectionset.proto --go_out=./producer
