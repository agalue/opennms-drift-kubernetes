#!/bin/sh
# @author Alejandro Galue <agalue@opennms.org>

git clone https://github.com/OpenNMS/nephron.git
cd nephron
git checkout -b $NEPHRON_VERSION $NEPHRON_VERSION
git submodule init
git submodule update
echo "Building nephron, please wait..."
mvn -q package -DskipTests
cp assemblies/flink/target/nephron-flink-bundled-${NEPHRON_VERSION:1}.jar /data/nephron-flink-bundled.jar
ls -alsh /data/
