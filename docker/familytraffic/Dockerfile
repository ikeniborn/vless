# docker/familytraffic/Dockerfile
# familyTraffic VPN Server - Single Container Image
# nginx + xray + certbot + supervisord
#
# 3-stage build:
#   Stage 1: xray-src     — extract xray binary from teddysun image
#   Stage 2: certbot-builder — build certbot via pip on Alpine
#   Stage 3: final        — nginx:1.27-alpine + supervisor + xray + certbot

# =============================================================================
# Stage 1: Extract Xray binary
# =============================================================================
FROM teddysun/xray:24.11.30 AS xray-src

# =============================================================================
# Stage 2: Build certbot
# =============================================================================
FROM python:3.12-alpine AS certbot-builder

RUN apk add --no-cache \
    gcc \
    musl-dev \
    libffi-dev \
    openssl-dev \
    cargo \
    && pip install --no-cache-dir certbot

# =============================================================================
# Stage 3: Final image
# =============================================================================
FROM nginx:1.27-alpine AS final

# Install supervisor (Alpine package name: supervisor, NOT supervisord)
RUN apk add --no-cache \
    supervisor \
    openssl \
    && mkdir -p /etc/familytraffic \
    && mkdir -p /var/www/html/.well-known/acme-challenge

# Copy xray binary from Stage 1
COPY --from=xray-src /usr/bin/xray /usr/bin/xray

# Copy certbot binary and Python libs from Stage 2
COPY --from=certbot-builder /usr/local/bin/certbot /usr/local/bin/certbot
COPY --from=certbot-builder /usr/local/lib /usr/local/lib

# Copy supervisord configuration
COPY docker/familytraffic/supervisord.conf /etc/familytraffic/supervisord.conf

# Copy certbot renewal script
COPY docker/familytraffic/certbot-renew.sh /etc/familytraffic/certbot-renew.sh
RUN chmod +x /etc/familytraffic/certbot-renew.sh

# Copy entrypoint
COPY docker/familytraffic/entrypoint.sh /docker/familytraffic/entrypoint.sh
RUN chmod +x /docker/familytraffic/entrypoint.sh

# Environment defaults
ENV INSTALL_PATH=/opt/familytraffic

# Expose ports
EXPOSE 443 1080 8118

ENTRYPOINT ["/docker/familytraffic/entrypoint.sh"]
