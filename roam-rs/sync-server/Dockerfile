FROM rust:1.83-alpine AS builder
RUN apk add --no-cache musl-dev
WORKDIR /build
COPY . .
RUN cargo build --release -p roam-sync-server

FROM alpine:3.21
RUN adduser -D -u 1000 roam
COPY --from=builder /build/target/release/roam-sync-server /usr/local/bin/
USER roam
EXPOSE 8080
VOLUME /data
ENV ROAM_SYNC_DATA_DIR=/data
CMD ["roam-sync-server", "--listen", "0.0.0.0:8080", "--data-dir", "/data"]
