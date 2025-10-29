FROM golang:1.21-alpine AS builder

RUN apk add --no-cache git docker-cli

WORKDIR /app

COPY main.go .
COPY go.mod go.sum* ./

RUN go mod download || true
RUN go build -o webhook-service main.go

FROM alpine:latest

RUN apk add --no-cache git docker-cli

COPY --from=builder /app/webhook-service /webhook-service

CMD ["/webhook-service"]
