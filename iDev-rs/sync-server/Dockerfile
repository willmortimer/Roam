FROM rust:1.83-alpine AS builder
RUN apk add --no-cache musl-dev
WORKDIR /build
COPY . .
RUN cargo build --release -p idev-sync-server

FROM alpine:3.21
RUN adduser -D -u 1000 idev
COPY --from=builder /build/target/release/idev-sync-server /usr/local/bin/
USER idev
EXPOSE 8080
VOLUME /data
ENV IDEV_SYNC_DATA_DIR=/data
CMD ["idev-sync-server", "--listen", "0.0.0.0:8080", "--data-dir", "/data"]
