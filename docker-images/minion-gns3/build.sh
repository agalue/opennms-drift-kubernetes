#!/bin/sh

TAG=${1-latest}
REPO=${2-stable}

docker build -t agalue/minion-gns3:$TAG --build-arg MINION_SOURCE=$REPO .
docker push agalue/minion-gns3:$TAG
