#!/bin/sh
# docker/familytraffic/certbot-renew.sh
# Certificate renewal loop — runs as supervisord program:certbot-cron
# Checks every 12 hours; uses certbot --webroot for renewal (nginx serves /.well-known/)
# On success: sends SIGHUP to nginx (graceful reload, no downtime)

while true; do
    # BUG-2 fix: correct supervisorctl signal argument order is: signal SIGNAL PROCESS
    # WARN-6 fix: check immediately on startup, then sleep — avoids 12h delay after restart
    if certbot renew \
        --webroot \
        --webroot-path /var/www/html \
        --quiet 2>&1; then
        # Graceful nginx reload — picks up renewed certificates without downtime
        supervisorctl -c /etc/familytraffic/supervisord.conf signal SIGHUP nginx
        echo "$(date): certs renewed and nginx reloaded"
    else
        echo "$(date): cert renewal skipped (not due yet or error)"
    fi

    sleep 43200  # 12 hours — check again after sleeping
done
