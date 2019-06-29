FROM golang:alpine AS builder
RUN mkdir /app && apk update && apk add --no-cache git
ADD ./event-watcher.go /app/
ADD ./go.mod /app/
WORKDIR /app
RUN go get -d -v && go build -o main .

FROM alpine
COPY --from=builder /app/main /usr/local/bin/main
ENTRYPOINT [ "main" ]
