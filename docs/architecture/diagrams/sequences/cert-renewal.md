# Certificate Renewal Sequence Diagram

**Purpose:** Visualize the automated Let's Encrypt certificate renewal workflow

**Features:**
- Automated renewal via certbot-cron (runs inside `familytraffic` container, managed by supervisord)
- Certificate validation (HTTP-01 webroot challenge, served by nginx on port 80)
- nginx graceful reload (`nginx -s reload`) after renewal
- Zero-downtime certificate update
- Cron job automation (inside container, no separate certbot container needed)

---

## Automated Certificate Renewal Flow

### Complete Renewal Sequence (Cron Job)

```mermaid
sequenceDiagram
    participant CertbotCron as certbot-cron<br/>(inside familytraffic, supervisord)
    participant Certbot as Certbot Client
    participant LetsEncrypt as Let's Encrypt<br/>ACME Server
    participant NginxWebroot as nginx port 80<br/>(inside familytraffic, webroot)
    participant CertStorage as /etc/letsencrypt/
    participant DeployHook as familytraffic-cert-renew<br/>(deploy hook)
    participant Nginx as nginx<br/>(inside familytraffic)

    Note over CertbotCron: certbot-cron triggers renewal<br/>(twice daily)

    CertbotCron->>Certbot: certbot renew --quiet<br/>--deploy-hook /usr/local/bin/familytraffic-cert-renew

    Note over Certbot: Phase 1: Check Certificate Expiry

    Certbot->>CertStorage: Read /etc/letsencrypt/live/example.com/cert.pem
    CertStorage-->>Certbot: Certificate metadata:<br/>- Issued: 2025-12-01<br/>- Expires: 2026-02-28<br/>- Days remaining: 45

    alt Days remaining > 30
        Certbot->>CertbotCron: Certificate not due for renewal<br/>(> 30 days remaining)
        Note over CertbotCron: Exit successfully (nothing to do)
    else Days remaining ≤ 30
        Note over Certbot,LetsEncrypt: Phase 2: Initiate Renewal

        Certbot->>LetsEncrypt: Request certificate renewal<br/>Domain: example.com

        LetsEncrypt->>Certbot: Challenge: HTTP-01 webroot<br/>Token: random_token_xyz

        Note over Certbot,NginxWebroot: Phase 3: HTTP-01 Webroot Challenge<br/>(nginx already running on port 80 — no container start needed)

        Certbot->>NginxWebroot: Write challenge file to webroot:<br/>/var/www/html/.well-known/acme-challenge/random_token_xyz

        Certbot->>LetsEncrypt: Challenge ready

        LetsEncrypt->>NginxWebroot: HTTP GET<br/>http://example.com/.well-known/acme-challenge/random_token_xyz
        NginxWebroot-->>LetsEncrypt: 200 OK<br/>Challenge response

        LetsEncrypt->>LetsEncrypt: Validate challenge response

        alt Challenge validation success
            LetsEncrypt->>Certbot: ✓ Challenge validated

            Note over Certbot,CertStorage: Phase 4: Issue New Certificate

            LetsEncrypt->>Certbot: New certificate issued:<br/>- cert.pem<br/>- chain.pem<br/>- fullchain.pem<br/>- privkey.pem

            Certbot->>CertStorage: Write to /etc/letsencrypt/live/example.com/<br/>- cert.pem (new)<br/>- chain.pem (new)<br/>- fullchain.pem (new)<br/>- privkey.pem (new)

            CertStorage-->>Certbot: ✓ Certificate saved

            Note over Certbot,Nginx: Phase 5: Deploy Hook (nginx reload)

            Certbot->>DeployHook: Run deploy hook:<br/>/usr/local/bin/familytraffic-cert-renew

            DeployHook->>DeployHook: Validate new certificate files
            DeployHook->>DeployHook: Check familytraffic container health

            DeployHook->>Nginx: docker exec familytraffic nginx -s reload

            Note over Nginx: Graceful reload:<br/>- nginx reloads config + new certs<br/>- Existing connections continue<br/>- Zero downtime

            Nginx->>Nginx: Load new fullchain.pem + privkey.pem
            Nginx-->>DeployHook: ✓ nginx reloaded

            DeployHook->>Certbot: ✓ Deploy hook success

            Certbot->>CertbotCron: ✓ Certificate renewed successfully

        else Challenge validation failure
            LetsEncrypt->>Certbot: ✗ Challenge validation failed
            Certbot->>CertbotCron: ✗ Renewal failed (will retry)
        end
    end
```

---

## Manual Certificate Renewal Flow

### Manual Renewal Trigger

```mermaid
sequenceDiagram
    participant Admin
    participant CLI as vless CLI<br/>(or manual command)
    participant Certbot
    participant LetsEncrypt
    participant Nginx as nginx (inside familytraffic)

    Admin->>CLI: sudo certbot renew --force-renewal<br/>or: RENEWED_DOMAINS="domain" sudo familytraffic-cert-renew

    CLI->>Certbot: certbot renew --force-renewal<br/>--deploy-hook /usr/local/bin/familytraffic-cert-renew

    Note over Certbot: Force renewal regardless of expiry date

    Certbot->>LetsEncrypt: Request renewal (forced)
    LetsEncrypt->>Certbot: Challenge: HTTP-01 webroot

    Note over Certbot,LetsEncrypt: (Same validation flow as automated)

    LetsEncrypt->>Certbot: ✓ New certificate issued

    Certbot->>Certbot: Run deploy hook

    Note over Certbot,Nginx: Deploy hook: familytraffic-cert-renew → nginx -s reload

    Certbot->>Nginx: docker exec familytraffic nginx -s reload

    Nginx-->>Certbot: ✓ nginx reloaded

    Certbot->>CLI: ✓ Renewal successful

    CLI->>Admin: ✓ Certificate renewed and nginx reloaded<br/><br/>New certificate valid until: 2026-05-28<br/>nginx reload: ✓ Success (0 connections dropped)
```

---

## Certificate Renewal Error Scenarios

### Scenario 1: nginx Not Running on Port 80

```mermaid
sequenceDiagram
    participant Certbot
    participant NginxWebroot as nginx:80 (inside familytraffic)
    participant LetsEncrypt

    Note over Certbot: Port 80 must be served by nginx inside familytraffic

    Certbot->>NginxWebroot: Write challenge file to /var/www/html/
    LetsEncrypt->>NginxWebroot: HTTP GET /.well-known/acme-challenge/token
    NginxWebroot-->>LetsEncrypt: ✗ Connection refused (familytraffic container not running)

    Certbot->>Certbot: Error: Challenge validation failed

    Note over Certbot: Fix: ensure familytraffic container is running<br/>docker start familytraffic<br/>Then retry: sudo certbot renew --force-renewal
```

### Scenario 2: DNS Not Pointing to Server

```mermaid
sequenceDiagram
    participant Certbot
    participant LetsEncrypt
    participant DNS

    Certbot->>LetsEncrypt: Request renewal for example.com
    LetsEncrypt->>DNS: Resolve example.com
    DNS-->>LetsEncrypt: A record → 203.0.113.99 (wrong IP)

    LetsEncrypt->>LetsEncrypt: Expected IP: 203.0.113.10<br/>Actual IP: 203.0.113.99<br/>✗ Mismatch

    LetsEncrypt->>Certbot: ✗ Challenge failed:<br/>Domain does not resolve to this server

    Certbot->>Certbot: Error: DNS validation failed

    Note over Certbot: Admin must update DNS records<br/>to point to correct IP
```

### Scenario 3: Challenge Response Timeout

```mermaid
sequenceDiagram
    participant Certbot
    participant CertbotNginx
    participant LetsEncrypt

    Certbot->>CertbotNginx: Write challenge file
    Certbot->>LetsEncrypt: Challenge ready

    LetsEncrypt->>CertbotNginx: HTTP GET /.well-known/acme-challenge/token

    Note over LetsEncrypt,CertbotNginx: Connection timeout (firewall blocking?)

    LetsEncrypt-->>Certbot: ✗ Connection timeout after 10s

    Certbot->>Certbot: Error: Challenge validation timeout

    Note over Certbot: Check firewall rules:<br/>- UFW allow 80/tcp<br/>- Cloud provider security groups
```

---

## nginx Graceful Reload Mechanism

### Zero-Downtime Certificate Update

```mermaid
sequenceDiagram
    participant DeployHook as familytraffic-cert-renew
    participant NginxMaster as nginx Master Process
    participant NginxWorker1 as nginx Worker<br/>(Old, finishing requests)
    participant NginxWorker2 as nginx Worker<br/>(New, with new cert)
    participant Client1 as Active Client #1
    participant Client2 as New Client #2

    Note over DeployHook: New fullchain.pem + privkey.pem available

    DeployHook->>NginxMaster: docker exec familytraffic nginx -s reload

    Note over NginxMaster: nginx graceful reload:<br/>- Fork new worker with new config<br/>- Drain old workers

    NginxMaster->>NginxWorker2: Start new worker (loads new cert)
    NginxMaster->>NginxWorker1: Send graceful shutdown signal

    NginxWorker1->>Client1: Continue serving existing connection
    NginxWorker2->>Client2: Accept new connections (new cert)

    Client1->>NginxWorker1: Request completed
    NginxWorker1->>NginxWorker1: All connections finished, exit

    Note over NginxMaster: New workers handling<br/>all connections with new cert

    DeployHook->>DeployHook: ✓ Reload complete<br/>(0 connections dropped)
```

---

## Cron Job Configuration

### Automated Renewal Schedule

```mermaid
graph TB
    Cron[Cron Daemon]
    CronTab[Crontab Entry<br/>0 3 * * *]
    CertbotRenew[certbot renew<br/>--quiet<br/>--deploy-hook]
    Success{Renewal<br/>Needed?}
    Deploy[Deploy Hook<br/>combine_certs.sh<br/>+ HAProxy reload]
    Log[Log to<br/>/var/log/letsencrypt/]

    Cron --> CronTab
    CronTab -->|Daily at 03:00 UTC| CertbotRenew
    CertbotRenew --> Success

    Success -->|Yes<br/>(≤ 30 days)| Deploy
    Success -.->|No<br/>(> 30 days)| Log

    Deploy --> Log

    style Cron fill:#e1f5ff
    style CertbotRenew fill:#e1ffe1
    style Deploy fill:#ffe1f5
    style Success fill:#fff9e1
```

**Crontab Entry (inside familytraffic container, managed by supervisord):**
```bash
# certbot-cron runs twice daily inside the familytraffic container
# Configured via supervisord in /etc/supervisor/conf.d/certbot.conf

# Equivalent manual command:
certbot renew --quiet --webroot -w /var/www/html \
  --deploy-hook "docker exec familytraffic nginx -s reload"
```

**familytraffic-cert-renew deploy hook:**
```bash
#!/bin/bash
# /usr/local/bin/familytraffic-cert-renew
# Called by certbot --deploy-hook after successful renewal

# Reload nginx to pick up new certificates
docker exec familytraffic nginx -s reload

# Log success
echo "[$(date)] Certificate renewed and nginx reloaded for: $RENEWED_DOMAINS" \
  >> /opt/familytraffic/logs/certbot-renew.log
```

---

## Certificate Lifecycle

### Certificate State Diagram

```mermaid
stateDiagram-v2
    [*] --> PendingIssuance : Initial installation

    PendingIssuance --> DNSValidation : Validate DNS records
    DNSValidation --> ChallengeSetup : DNS points to server
    ChallengeSetup --> ChallengeServed : Certbot nginx serves HTTP-01
    ChallengeServed --> Validated : Let's Encrypt validates
    Validated --> Issued : Certificate issued
    Issued --> Active : Deploy hook runs

    Active --> RenewalCheck : Daily cron job
    RenewalCheck --> Active : > 30 days remaining
    RenewalCheck --> PendingRenewal : ≤ 30 days remaining

    PendingRenewal --> ChallengeSetup : Initiate renewal
    ChallengeServed --> RenewalFailed : Validation failed
    RenewalFailed --> PendingRenewal : Retry tomorrow

    Active --> Expired : 90 days (no renewal)
    Expired --> [*]

    Active --> Revoked : Manual revocation
    Revoked --> [*]
```

---

## Monitoring and Alerts

### Certificate Expiry Monitoring

```bash
# Check certificate expiry date
openssl x509 -in /etc/letsencrypt/live/example.com/cert.pem -noout -enddate

# Output: notAfter=Feb 28 12:00:00 2026 GMT

# Check days until expiry
cert_expiry=$(date -d "$(openssl x509 -in /etc/letsencrypt/live/example.com/cert.pem -noout -enddate | cut -d= -f2)" +%s)
current_time=$(date +%s)
days_remaining=$(( ($cert_expiry - $current_time) / 86400 ))

echo "Days until expiry: $days_remaining"

# Alert if < 7 days
if [ $days_remaining -lt 7 ]; then
    echo "WARNING: Certificate expires in $days_remaining days!"
    # Send alert (email, Slack, etc.)
fi
```

### Renewal Log Monitoring

```bash
# Check recent renewal attempts
tail -50 /var/log/letsencrypt/letsencrypt.log

# Check for failures
grep "FAILED" /var/log/letsencrypt/letsencrypt.log

# Check last successful renewal
grep "Certificate not yet due for renewal" /var/log/letsencrypt/letsencrypt.log | tail -1
```

---

## Performance Metrics

**Renewal Process:**
- **DNS Validation:** ~1-2 seconds
- **HTTP-01 Challenge:** ~5-10 seconds
- **Certificate Issuance:** ~10-20 seconds
- **Deploy Hook Execution:** ~2-3 seconds
- **nginx Graceful Reload:** < 1 second (no dropped connections)
- **Total Duration:** ~20-40 seconds

**nginx Reload Impact:**
- **Downtime:** 0 seconds (graceful reload with `nginx -s reload`)
- **Dropped Connections:** 0 (workers drain gracefully)
- **Memory Usage:** Brief spike for ~1-2 seconds during worker overlap
- **CPU Usage:** Negligible

---

## Troubleshooting

### Common Issues

**Issue 1: Renewal fails with "Port 80 already in use"**
- **Cause:** Another service binding to port 80
- **Fix:**
  ```bash
  # Find process on port 80
  sudo ss -tulnp | grep :80

  # Stop conflicting service
  sudo systemctl stop <service>

  # Retry renewal
  sudo certbot renew --force-renewal
  ```

**Issue 2: nginx reload fails after renewal**
- **Cause:** Invalid certificate files or nginx configuration error
- **Debug:**
  ```bash
  # Check certificate files
  openssl x509 -in /etc/letsencrypt/live/example.com/fullchain.pem -noout -text

  # Test nginx config
  docker exec familytraffic nginx -t

  # Manual reload
  docker exec familytraffic nginx -s reload
  ```

**Issue 3: Certificate not renewed despite < 30 days**
- **Cause:** certbot-cron not running inside familytraffic container
- **Fix:**
  ```bash
  # Check supervisord status inside container
  docker exec familytraffic supervisorctl status

  # Check certbot-cron is running
  docker exec familytraffic supervisorctl status certbot-cron

  # Restart certbot-cron
  docker exec familytraffic supervisorctl restart certbot-cron

  # Manual renewal
  docker exec familytraffic certbot renew --force-renewal
  ```

---

## Related Documentation

- [docker.yaml](../../yaml/docker.yaml) - Certbot nginx container configuration
- [config.yaml](../../yaml/config.yaml) - Certificate file paths and HAProxy integration
- [dependencies.yaml](../../yaml/dependencies.yaml) - Certificate renewal dependencies
- [lib-modules.yaml](../../yaml/lib-modules.yaml) - certificate_manager.sh functions

---

**Created:** 2026-01-07
**Version:** v5.33
**Status:** UPDATED — certbot-cron inside familytraffic, nginx deploy hook (no separate certbot container)
