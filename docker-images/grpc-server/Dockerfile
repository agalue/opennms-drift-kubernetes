FROM maven:3.6-jdk-8 AS builder
WORKDIR /app
RUN git clone https://github.com/OpenNMS/grpc-server.git && \
    cd grpc-server && \
    mvn package

FROM openjdk:8-jdk-slim
COPY --from=builder /app/grpc-server/target/grpc-ipc-server.jar /
COPY docker-entrypoint.sh /
ENTRYPOINT [ "/docker-entrypoint.sh" ]
