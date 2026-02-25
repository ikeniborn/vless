# ============================================================================
# MTProxy Docker Image (v6.0)
# Multi-stage build for minimal image size
# ============================================================================
#
# Purpose:
#   Official Telegram MTProxy server for tunneling MTProto traffic
#
# Features:
#   - Transport obfuscation (AES-256-CTR)
#   - Random padding for DPI resistance
#   - Multi-user support (v6.1)
#   - Statistics endpoint (:8888/stats)
#
# Build:
#   docker build -t familytraffic/mtproxy:latest -f docker/mtproxy/Dockerfile .
#
# Run:
#   docker run -d --name familytraffic_mtproxy \
#     -p 8443:8443 -p 127.0.0.1:8888:8888 \
#     -v /opt/familytraffic/config/mtproxy:/etc/mtproxy:ro \
#     -v /opt/familytraffic/logs/mtproxy:/var/log/mtproxy \
#     familytraffic/mtproxy:latest
#
# Author: familyTraffic Development Team
# Date: 2025-11-08
# ============================================================================

# ===========================================================================
# Stage 1: Builder (compile MTProxy from source)
# ===========================================================================
FROM alpine:latest AS builder

LABEL stage=builder \
      description="MTProxy builder stage - compiles from TelegramMessenger/MTProxy"

# Install build dependencies
RUN apk add --no-cache \
    git \
    gcc \
    g++ \
    make \
    openssl-dev \
    zlib-dev \
    linux-headers

# Clone MTProxy repository (official Telegram repo)
# Use specific commit/tag for reproducibility (latest stable as of 2025-11-08)
WORKDIR /build
RUN git clone https://github.com/TelegramMessenger/MTProxy.git mtproxy && \
    cd mtproxy && \
    git checkout master

# Compile MTProxy
WORKDIR /build/mtproxy
RUN make && \
    strip objs/bin/mtproto-proxy

# Verify binary was created
RUN test -f objs/bin/mtproto-proxy || (echo "ERROR: mtproto-proxy binary not found" && exit 1)

# ===========================================================================
# Stage 2: Runtime (minimal alpine with only runtime dependencies)
# ===========================================================================
FROM alpine:latest

LABEL maintainer="familyTraffic Development Team" \
      version="6.0.0" \
      description="MTProxy server for Telegram (Transport Obfuscation + Multi-User)" \
      org.opencontainers.image.source="https://github.com/TelegramMessenger/MTProxy"

# Install runtime dependencies only
RUN apk add --no-cache \
    openssl \
    zlib \
    curl \
    ca-certificates \
    su-exec

# Create non-root user for MTProxy (security best practice)
RUN addgroup -g 9999 mtproxy && \
    adduser -D -u 9999 -G mtproxy -h /var/lib/mtproxy -s /sbin/nologin mtproxy

# Copy compiled binary from builder stage
COPY --from=builder /build/mtproxy/objs/bin/mtproto-proxy /usr/local/bin/mtproto-proxy

# Set executable permissions
RUN chmod +x /usr/local/bin/mtproto-proxy

# Create directories for config and logs
RUN mkdir -p /etc/mtproxy /var/log/mtproxy /var/lib/mtproxy && \
    chown -R mtproxy:mtproxy /etc/mtproxy /var/log/mtproxy /var/lib/mtproxy

# Expose ports
# 8443: MTProxy public port (Telegram traffic)
# 8888: Stats endpoint (localhost only - use port mapping 127.0.0.1:8888:8888)
EXPOSE 8443 8888

# Working directory
WORKDIR /var/lib/mtproxy

# Volume mounts (override in docker-compose.yml)
VOLUME ["/etc/mtproxy", "/var/log/mtproxy"]

# Healthcheck (TCP check on port 8443)
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD nc -z 127.0.0.1 8443 || exit 1

# Entrypoint script (dynamic configuration from mounted files)
COPY docker/mtproxy/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Run as non-root user (security)
USER mtproxy

# Start MTProxy via entrypoint script
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# Default CMD (can be overridden)
CMD ["mtproto-proxy"]
