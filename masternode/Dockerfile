# TPIX Master Node — Docker Image
# ================================
# Multi-stage build for minimal image size
#
# Build:
#   docker build -t tpix-node:latest .
#
# Run:
#   docker run -d --name tpix-node \
#     -p 30303:30303 -p 3847:3847 -p 8545:8545 \
#     -e TPIX_TIER=light \
#     -e TPIX_WALLET=0xYourAddress \
#     -v tpix-data:/root/.tpix-node \
#     tpix-node:latest

# Stage 1: Build
FROM golang:1.22-alpine AS builder

RUN apk add --no-cache git make gcc musl-dev

WORKDIR /build
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 go build \
    -ldflags="-s -w -X main.Version=1.0.0 -X main.BuildDate=$(date -u +%Y-%m-%d)" \
    -o /build/tpix-node \
    ./cmd/tpix-node/

# Stage 2: Runtime
FROM alpine:3.19

RUN apk add --no-cache ca-certificates tzdata curl

COPY --from=builder /build/tpix-node /usr/local/bin/tpix-node

# Default environment
ENV TPIX_TIER=light
ENV TPIX_WALLET=""
ENV TPIX_RPC=https://rpc.tpix.online
ENV TPIX_DASHBOARD_PORT=3847
ENV TPIX_P2P_PORT=30303

# Expose ports
EXPOSE 30303 3847 8545 9090

# Data volume
VOLUME /root/.tpix-node

# Health check
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD curl -f http://localhost:${TPIX_DASHBOARD_PORT}/api/status || exit 1

ENTRYPOINT ["tpix-node"]
CMD ["--config=/root/.tpix-node/tpix-node.yaml"]
