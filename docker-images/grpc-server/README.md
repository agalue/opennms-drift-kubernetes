# gRPC Server

This provides a way to build a Docker image around:

https://github.com/OpenNMS/grpc-server/tree/feature/reuse-proto-files


```bash
java -jar grpc-server.jar \
  -Dorg.opennms.instance.id=K8S \
  -Dtls.enabled=true \
  -Dserver.private.key.filepath=/grpc/key.pem \
  -Dserver.cert.filepath=/grpc/cert.pem \
  -Dclient.cert.filepath=/grpc/client.pem \
  -Dport=8990 \
  -Dmax.message.size=10485760 \
  -Dorg.opennms.core.ipc.grpc.kafka.producer.acks=1 \
  kafka1:9092
```

The equivalent with Docker would be:

```bash
docker run \
  -e INSTANCE_ID=K8S \
  -e TLS_ENABLED=true \
  -e SERVER_PRIVATE_KEY=/grpc/key.pem \
  -e SERVER_CERT=/grpc/cert.pem \
  -e CLIENT_CERT=/grpc/client.pem \
  -e PORT=8990 \
  -e MAX_MESSAGE_SIZE=10485760 \
  -e PRODUCER_ACKS=1 \
  -e BOOTSTRAP_SERVERS=kafka1:9092 \
  -v $(pwd)/grpc:/grpc
  agalue/grpc-server
```

To build the image:

```bash
docker build -t agalue/grpc-server:H26 .
docker push agalue/grpc-server:H26
```
