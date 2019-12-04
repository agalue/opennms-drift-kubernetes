#!/bin/sh

TAG=${1-latest}
REPO=${2-stable}

docker build -t agalue/minion-gns3:$TAG --build-arg MINION_SOURCE=stable ./minion-gns3
docker push agalue/minion-gns3:$TAG
