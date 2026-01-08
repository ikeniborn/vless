# Certificate Renewal Sequence Diagram

**Purpose:** Visualize the automated Let's Encrypt certificate renewal workflow

**Features:**
- Automated renewal via certbot
- Certificate validation (HTTP-01 challenge)
- HAProxy graceful reload
- Zero-downtime certificate update
- Cron job automation

---

## Automated Certificate Renewal Flow

### Complete Renewal Sequence (Cron Job)

```mermaid
sequenceDiagram
    participant Cron as Cron Job<br/>(certbot renew)
    participant Certbot as Certbot Client
    participant LetsEncrypt as Let's Encrypt<br/>ACME Server
    participant CertbotNginx as Certbot Nginx Container<br/>(Port 80)
    participant CertStorage as /etc/letsencrypt/
    participant CombineScript as combine_certs.sh
    participant HAProxyConfig as HAProxy Config<br/>combined.pem
    participant HAProxy as HAProxy Container

    Note over Cron: Cron triggers renewal<br/>(daily at 03:00 UTC)

    Cron->>Certbot: certbot renew --quiet<br/>--deploy-hook /opt/vless/scripts/renew-hook.sh

    Note over Certbot: Phase 1: Check Certificate Expiry

    Certbot->>CertStorage: Read /etc/letsencrypt/live/example.com/cert.pem
    CertStorage-->>Certbot: Certificate metadata:<br/>- Issued: 2025-12-01<br/>- Expires: 2026-02-28<br/>- Days remaining: 45

    alt Days remaining > 30
        Certbot->>Cron: Certificate not due for renewal<br/>(> 30 days remaining)
        Note over Cron: Exit successfully (nothing to do)
    else Days remaining ≤ 30
        Note over Certbot,LetsEncrypt: Phase 2: Initiate Renewal

        Certbot->>LetsEncrypt: Request certificate renewal<br/>Domain: example.com, *.example.com

        LetsEncrypt->>Certbot: Challenge: HTTP-01<br/>Token: random_token_xyz

        Note over Certbot,CertbotNginx: Phase 3: HTTP-01 Challenge

        Certbot->>CertbotNginx: Start certbot-nginx container<br/>(if not running)
        CertbotNginx->>CertbotNginx: Listen on port 80<br/>Serve /.well-known/acme-challenge/

        Certbot->>CertbotNginx: Write challenge file:<br/>/var/www/html/.well-known/acme-challenge/random_token_xyz

        Certbot->>LetsEncrypt: Challenge ready

        LetsEncrypt->>CertbotNginx: HTTP GET<br/>http://example.com/.well-known/acme-challenge/random_token_xyz
        CertbotNginx-->>LetsEncrypt: 200 OK<br/>Challenge response

        LetsEncrypt->>LetsEncrypt: Validate challenge response

        alt Challenge validation success
            LetsEncrypt->>Certbot: ✓ Challenge validated

            Note over Certbot,CertStorage: Phase 4: Issue New Certificate

            LetsEncrypt->>Certbot: New certificate issued:<br/>- cert.pem<br/>- chain.pem<br/>- fullchain.pem<br/>- privkey.pem

            Certbot->>CertStorage: Write to /etc/letsencrypt/live/example.com/<br/>- cert.pem (new)<br/>- chain.pem (new)<br/>- fullchain.pem (new)<br/>- privkey.pem (new)

            CertStorage-->>Certbot: ✓ Certificate saved

            Note over Certbot,HAProxy: Phase 5: Deploy Hook (HAProxy Reload)

            Certbot->>CombineScript: Run deploy hook:<br/>/opt/vless/scripts/renew-hook.sh

            CombineScript->>CertStorage: Read fullchain.pem
            CombineScript->>CertStorage: Read privkey.pem

            CombineScript->>CombineScript: Combine certificates:<br/>cat fullchain.pem privkey.pem > combined.pem

            CombineScript->>HAProxyConfig: Write /etc/letsencrypt/live/example.com/combined.pem
            HAProxyConfig-->>CombineScript: ✓ Combined cert created

            CombineScript->>HAProxy: docker exec vless_haproxy<br/>haproxy -sf $(cat /var/run/haproxy.pid)

            Note over HAProxy: Graceful reload:<br/>- Start new HAProxy process<br/>- Finish existing connections<br/>- Stop old HAProxy process

            HAProxy->>HAProxy: Load new combined.pem
            HAProxy-->>CombineScript: ✓ HAProxy reloaded

            CombineScript->>Certbot: ✓ Deploy hook success

            Certbot->>Cron: ✓ Certificate renewed successfully

        else Challenge validation failure
            LetsEncrypt->>Certbot: ✗ Challenge validation failed
            Certbot->>Cron: ✗ Renewal failed (will retry tomorrow)
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
    participant HAProxy

    Admin->>CLI: sudo vless renew-cert<br/>(or: sudo certbot renew --force-renewal)

    CLI->>Certbot: certbot renew --force-renewal<br/>--deploy-hook /opt/vless/scripts/renew-hook.sh

    Note over Certbot: Force renewal regardless of expiry date

    Certbot->>LetsEncrypt: Request renewal (forced)
    LetsEncrypt->>Certbot: Challenge: HTTP-01

    Note over Certbot,LetsEncrypt: (Same validation flow as automated)

    LetsEncrypt->>Certbot: ✓ New certificate issued

    Certbot->>Certbot: Run deploy hook

    Note over Certbot,HAProxy: (Same deploy flow as automated)

    Certbot->>HAProxy: Graceful reload

    HAProxy-->>Certbot: ✓ Reloaded

    Certbot->>CLI: ✓ Renewal successful

    CLI->>Admin: ✓ Certificate renewed and HAProxy reloaded<br/><br/>New certificate valid until: 2026-05-28<br/>HAProxy reload: ✓ Success (0 connections dropped)
```

---

## Certificate Renewal Error Scenarios

### Scenario 1: Port 80 Blocked

```mermaid
sequenceDiagram
    participant Certbot
    participant CertbotNginx
    participant LetsEncrypt

    Certbot->>CertbotNginx: Start container on port 80
    CertbotNginx-->>Certbot: ✗ Error: Port 80 already in use

    Certbot->>Certbot: Check port 80:<br/>sudo ss -tulnp | grep :80

    Note over Certbot: Conflict detected:<br/>Another process using port 80

    Certbot->>Certbot: Error: Cannot bind to port 80<br/>Renewal failed

    Certbot->>Certbot: Log error:<br/>/var/log/letsencrypt/letsencrypt.log

    Note over Certbot: Admin must free port 80<br/>or use DNS-01 challenge
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

## HAProxy Graceful Reload Mechanism

### Zero-Downtime Certificate Update

```mermaid
sequenceDiagram
    participant Renew as renew-hook.sh
    participant OldHAProxy as HAProxy Process<br/>(Old PID: 1234)
    participant NewHAProxy as HAProxy Process<br/>(New PID: 5678)
    participant Client1 as Active Client #1
    participant Client2 as New Client #2

    Note over Renew: New combined.pem created

    Renew->>NewHAProxy: Start new HAProxy process:<br/>haproxy -sf 1234

    Note over NewHAProxy: Load new combined.pem

    NewHAProxy->>NewHAProxy: Bind to ports 443, 1080, 8118
    NewHAProxy->>OldHAProxy: Send SIGTERM to PID 1234

    Note over OldHAProxy: Graceful shutdown:<br/>- Stop accepting new connections<br/>- Finish existing connections

    OldHAProxy->>Client1: Continue serving existing connection<br/>(uses old certificate)

    NewHAProxy->>Client2: Accept new connections<br/>(uses new certificate)

    Client1->>OldHAProxy: Request completed
    OldHAProxy->>Client1: Response sent
    OldHAProxy->>OldHAProxy: All connections finished

    OldHAProxy->>OldHAProxy: Exit (PID 1234 terminated)

    Note over NewHAProxy: New HAProxy now handling<br/>all connections with new cert

    Renew->>Renew: ✓ Reload complete<br/>(0 connections dropped)
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

**Crontab Entry:**
```bash
# /etc/cron.d/certbot-renewal
0 3 * * * root certbot renew --quiet --deploy-hook /opt/vless/scripts/renew-hook.sh
```

**renew-hook.sh Script:**
```bash
#!/bin/bash
# /opt/vless/scripts/renew-hook.sh

DOMAIN="example.com"
CERT_PATH="/etc/letsencrypt/live/$DOMAIN"
COMBINED_CERT="$CERT_PATH/combined.pem"

# Combine fullchain and privkey
cat "$CERT_PATH/fullchain.pem" "$CERT_PATH/privkey.pem" > "$COMBINED_CERT"

# Reload HAProxy
docker exec vless_haproxy haproxy -sf $(docker exec vless_haproxy cat /var/run/haproxy.pid)

# Log success
echo "[$(date)] Certificate renewed and HAProxy reloaded" >> /var/log/vless/cert-renewal.log
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
- **HAProxy Graceful Reload:** < 1 second (no dropped connections)
- **Total Duration:** ~20-40 seconds

**HAProxy Reload Impact:**
- **Downtime:** 0 seconds (graceful reload)
- **Dropped Connections:** 0 (existing connections finish on old process)
- **Memory Usage:** Brief spike (+50MB for ~1-2 seconds during overlap)
- **CPU Usage:** Brief spike (+20% for ~1-2 seconds)

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

**Issue 2: HAProxy reload fails after renewal**
- **Cause:** Invalid combined.pem or HAProxy configuration error
- **Debug:**
  ```bash
  # Check combined.pem format
  openssl x509 -in /etc/letsencrypt/live/example.com/combined.pem -noout -text

  # Test HAProxy config
  docker exec vless_haproxy haproxy -c -f /etc/haproxy/haproxy.cfg
  ```

**Issue 3: Certificate not renewed despite < 30 days**
- **Cause:** Cron job not running or certbot timer disabled
- **Fix:**
  ```bash
  # Check cron job exists
  cat /etc/cron.d/certbot-renewal

  # Check certbot timer (if using systemd)
  systemctl status certbot.timer

  # Manual renewal
  sudo certbot renew --force-renewal
  ```

---

## Related Documentation

- [docker.yaml](../../yaml/docker.yaml) - Certbot nginx container configuration
- [config.yaml](../../yaml/config.yaml) - Certificate file paths and HAProxy integration
- [dependencies.yaml](../../yaml/dependencies.yaml) - Certificate renewal dependencies
- [lib-modules.yaml](../../yaml/lib-modules.yaml) - certificate_manager.sh functions

---

**Created:** 2026-01-07
**Version:** v5.26
**Status:** ✅ CURRENT (Automated renewal fully implemented)
