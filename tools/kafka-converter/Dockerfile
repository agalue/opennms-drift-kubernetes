FROM golang:alpine AS builder
RUN mkdir /app && \
    echo "@edgecommunity http://nl.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories && \
    apk update && \
    apk add --no-cache build-base git librdkafka-dev@edgecommunity
ADD ./ /app/
WORKDIR /app
RUN go build -a -o kafka-converter .

FROM alpine
ENV BOOTSTRAP_SERVERS="localhost:9092" \
    SOURCE_TOPIC="alarms" \
    DEST_TOPIC="alarms-json" \
    GROUP_ID="opennms" \
    MESSAGE_KIND="alarm"
RUN echo "@edgecommunity http://nl.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories && \
    apk update && \
    apk add --no-cache build-base git librdkafka@edgecommunity
COPY --from=builder /app/kafka-converter /kafka-converter
COPY ./docker-entrypoint.sh /
RUN addgroup -S onms && adduser -S -G onms onms && apk add --no-cache bash
USER onms
LABEL maintainer="Alejandro Galue <agalue@opennms.org>" \
      name="OpenNMS Kafka Producer: GPB to JSON Converter"
ENTRYPOINT [ "/docker-entrypoint.sh" ]