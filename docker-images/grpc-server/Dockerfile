FROM maven:3.6-jdk-8 AS builder
WORKDIR /app
COPY H26.patch .
RUN apt update && apt install patch && \
    git clone https://github.com/OpenNMS/grpc-server.git && \
    cd grpc-server && \
    patch -p1 < ../H26.patch && \
    mvn package

FROM openjdk:8-jdk-slim
COPY --from=builder /app/grpc-server/target/grpc-ipc-server.jar /
COPY docker-entrypoint.sh /
ENTRYPOINT [ "/docker-entrypoint.sh" ]
