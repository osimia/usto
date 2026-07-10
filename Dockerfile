FROM golang:1.22 AS builder

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /usto-server .

FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=builder /usto-server /app/usto-server

ENV APP_ENV=production
ENV PORT=8080
ENV DB_PATH=/data/usto.db

EXPOSE 8080

CMD ["/app/usto-server"]
