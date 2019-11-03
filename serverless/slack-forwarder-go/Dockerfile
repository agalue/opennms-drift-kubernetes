FROM golang:alpine AS builder
RUN mkdir /app && apk update && apk add --no-cache git
ADD ./main.go /app/
ADD ./go.mod /app/
WORKDIR /app
RUN CGO_ENABLED=0 go build -a -o slack-forwarder .

FROM alpine
ENV OPENNMS_URL="http://localhost:8980/opennms" \
    SLACK_URL="https://hooks.slack.com/services/xxx/yyy/zzzz"
COPY --from=builder /app/slack-forwarder /usr/local/bin/slack-forwarder
RUN addgroup -S onms && adduser -S -G onms onms && apk add --no-cache bash
USER onms
LABEL maintainer="Alejandro Galue <agalue@opennms.org>" \
      name="Slack Forwarder: Knative Eventing Service to forward OpenNMS Alarms to Slack"
ENTRYPOINT [ "slack-forwarder" ]
