#!/bin/sh
# docker/familytraffic/certbot-renew.sh
# Certificate renewal loop — runs as supervisord program:certbot-cron
# Checks every 12 hours; uses certbot --webroot for renewal (nginx serves /.well-known/)
# On success: sends SIGHUP to nginx (graceful reload, no downtime)

while true; do
    sleep 43200  # 12 hours

    if certbot renew \
        --webroot \
        --webroot-path /var/www/html \
        --quiet 2>&1; then
        # Signal nginx to reload certificates gracefully
        supervisorctl -c /etc/familytraffic/supervisord.conf signal nginx SIGHUP
        echo "$(date): certs renewed and nginx reloaded"
    else
        echo "$(date): cert renewal skipped (not due yet or error)"
    fi
done
