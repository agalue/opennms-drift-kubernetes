#!/bin/sh

TAG=${1-latest}
REPO=${2-stable}

docker build -t agalue/horizon:$TAG --build-arg OPENNMS_VERSION=stable ./opennms
docker build -t agalue/sentinel:$TAG --build-arg SENTINEL_VERSION=stable ./sentinel
docker build -t agalue/minion:$TAG --build-arg MINION_VERSION=stable ./minion
docker build -t agalue/minion-gns3:$TAG --build-arg MINION_SOURCE=stable ./minion-gns3

docker push agalue/horizon:$TAG
docker push agalue/sentinel:$TAG
docker push agalue/minion:$TAG
docker push agalue/minion-gns3:$TAG
