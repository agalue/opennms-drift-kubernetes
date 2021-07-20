FROM golang:alpine AS builder
RUN mkdir /app && \
    echo "@edgecommunity http://nl.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories && \
    apk update && \
    apk add --no-cache build-base git librdkafka-dev@edgecommunity
ADD ./ /app/
WORKDIR /app
RUN CGO_ENABLED=1 GOOS=linux GOARCH=amd64 go build -tags static_all,netgo,musl -o kafka-converter .

FROM alpine
ENV BOOTSTRAP_SERVERS="localhost:9092" \
    SOURCE_TOPIC="alarms" \
    DEST_TOPIC="alarms-json" \
    DEST_TOPIC_FLAT="" \
    GROUP_ID="opennms" \
    MESSAGE_KIND="alarm" \
    DEBUG="false"
RUN apk add --no-cache bash tzdata && \
    addgroup -S onms && \
    adduser -S -G onms onms
COPY --from=builder /app/kafka-converter /kafka-converter
COPY ./docker-entrypoint.sh /
USER onms
LABEL maintainer="Alejandro Galue <agalue@opennms.org>" \
      name="OpenNMS Kafka Producer: GPB to JSON Converter"
ENTRYPOINT [ "/docker-entrypoint.sh" ]
