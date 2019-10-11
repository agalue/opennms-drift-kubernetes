FROM golang:alpine AS builder
RUN mkdir /app && \
    echo "@edgecommunity http://nl.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories && \
    apk update && \
    apk add --no-cache build-base git librdkafka-dev@edgecommunity
ADD ./ /app/
WORKDIR /app
RUN GOOS=linux go build -a -o kafka-converter .

FROM alpine
RUN echo "@edgecommunity http://nl.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories && \
    apk update && \
    apk add --no-cache build-base git librdkafka@edgecommunity
COPY --from=builder /app/kafka-converter /kafka-converter
COPY ./docker-entrypoint.sh /
RUN addgroup -S onms && adduser -S -G onms onms && apk add --no-cache bash
USER onms
LABEL maintainer="Alejandro Galue <agalue@opennms.org>" name="OpenNMS Kafka Producer: GPB to JSON Converter"
ENTRYPOINT [ "/docker-entrypoint.sh" ]