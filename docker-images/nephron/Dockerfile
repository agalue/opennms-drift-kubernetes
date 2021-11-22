FROM maven:3-openjdk-11 AS builder

ENV NEPHRON_VERSION=v0.3.0

WORKDIR /app

RUN git clone https://github.com/OpenNMS/nephron.git && \
    cd nephron && \
    git checkout -b ${NEPHRON_VERSION} ${NEPHRON_VERSION} && \
    git submodule init && \
    git submodule update && \
    mvn package -DskipTests

FROM apache/flink:1.13-java11

RUN mkdir /data

COPY --from=builder /app/nephron/assemblies/flink/target/nephron-flink-bundled-*.jar /data/nephron-flink-bundled.jar
