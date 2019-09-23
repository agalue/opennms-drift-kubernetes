#!/bin/sh

BUILD=${1-unknown}

docker build -t agalue/horizon-core-web:h25-b$BUILD --build-arg OPENNMS_VERSION=branches-release-25.0.0 -d ./opennms
docker build -t agalue/sentinel:h25-b$BUILD --build-arg SENTINEL_VERSION=branches-release-25.0.0 -d ./sentinel
docker build -t agalue/minion:h25-b$BUILD --build-arg MINION_VERSION=branches-release-25.0.0 -d ./minion
docker build -t agalue/minion-gns3:h25-b$BUILD --build-arg MINION_SOURCE=branches/release-25.0.0 ./minion-gns3

docker push agalue/horizon-core-web:h25-b$BUILD
docker push agalue/sentinel:h25-b$BUILD
docker push agalue/minion:h25-b$BUILD
docker push agalue/minion-gns3:h25-b$BUILD
