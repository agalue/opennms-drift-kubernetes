FROM golang:alpine AS builder
RUN mkdir /app && apk update && apk add --no-cache git
ADD ./event-watcher.go /app/
ADD ./go.* /app/
WORKDIR /app
RUN CGO_ENABLED=0 go build -a -o event-watcher .

FROM alpine
ENV ONMS_URL="http://localhost:8980/opennms" \
    ONMS_USER="admin" \
    ONMS_PASSWD="admin"
COPY --from=builder /app/event-watcher /usr/local/bin/event-watcher
RUN addgroup -S onms && adduser -S -G onms onms && apk add --no-cache bash tzdata

USER onms
LABEL maintainer="Alejandro Galue <agalue@opennms.org>" \
      name="Event Watcher: Send K8s events to OpenNMS"
ENTRYPOINT [ "event-watcher" ]
