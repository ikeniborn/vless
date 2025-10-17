# ПЛАН ДОРАБОТОК v4.3: Unified HAProxy Solution

**Версия:** 4.3 (HAProxy Unified Solution + Subdomain Access)
**Дата создания:** 2025-10-17
**Статус:** В ПРОЦЕССЕ
**Оценка времени:** 19-27 часов (реалистично: 23 часа)

---

## 📐 АРХИТЕКТУРА v4.3

### Ключевые изменения от v4.2:
- ❌ **stunnel удален полностью**
- ✅ **HAProxy обрабатывает все 3 порта** (443, 1080, 8118)
- ✅ **1 контейнер вместо 2** (HAProxy заменяет HAProxy + stunnel)
- ✅ **Subdomain-based access** без портов: `https://claude.ikeniborn.ru`
- ✅ **Unified configuration, logging, monitoring**

### Финальная архитектура:
```
Port 443 (HAProxy, 3 frontends):
  Frontend 1: SNI Routing (NO TLS termination)
    - vless.domain.ru → Xray:8443 (VLESS Reality)
    - claude.domain.ru → Nginx:9443 (Reverse Proxy 1)
    - proxy2.domain.ru → Nginx:9444 (Reverse Proxy 2)

  Frontend 2: SOCKS5 TLS Termination
    - Port 1080 → Xray:10800 (plaintext)

  Frontend 3: HTTP Proxy TLS Termination
    - Port 8118 → Xray:18118 (plaintext)
```

---

## 🚀 ФАЗЫ РЕАЛИЗАЦИИ

### Фаза 1: Подготовка инфраструктуры (4-5 часов)
**Приоритет:** CRITICAL
**Статус:** ⏳ В ПРОЦЕССЕ

- [x] **Задача 1.1:** Установка unified HAProxy (1.5 часа) ✅ ЗАВЕРШЕНО
  - [x] Добавить haproxy service в lib/docker_compose_generator.sh ✅
  - [x] Создать /opt/vless/logs/haproxy/ directory ✅
  - [x] УДАЛИТЬ stunnel service из docker-compose.yml ✅
  - [x] Добавить certbot_nginx service ✅
  - [x] Обновить порты: Xray → 127.0.0.1:8443, Nginx → 127.0.0.1:9443-9452 ✅
  - [x] **Acceptance:** HAProxy service добавлен в generator ✅

- [x] **Задача 1.2:** Создание unified haproxy.cfg (2 часа) ✅ ЗАВЕРШЕНО
  - [x] Создать lib/haproxy_config_manager.sh ✅
  - [x] Реализовать generate_haproxy_config() с heredoc ✅
  - [x] 3 frontends: 443 (SNI), 1080 (TLS), 8118 (TLS) ✅
  - [x] Dynamic ACL section для reverse proxies ✅
  - [x] add_reverse_proxy_route() и remove_reverse_proxy_route() ✅
  - [x] validate_haproxy_config() и reload_haproxy() ✅
  - [x] list_haproxy_routes() ✅
  - [x] **Acceptance:** haproxy.cfg генерируется через heredoc ✅

- [ ] **Задача 1.3:** Удаление stunnel артефактов (30 мин)
  - [ ] Удалить config/stunnel.conf
  - [ ] Удалить lib/stunnel_setup.sh
  - [ ] Удалить logs/stunnel/
  - [ ] Обновить lib/orchestrator.sh (удалить setup_stunnel())
  - [ ] **Acceptance:** Все stunnel файлы удалены

- [ ] **Задача 1.4:** Certificate combined.pem generation (1 час)
  - [ ] Создать create_haproxy_combined_cert() в lib/certificate_manager.sh
  - [ ] Обновить /usr/local/bin/vless-cert-renew
  - [ ] Интегрировать с certbot deploy hook
  - [ ] **Acceptance:** combined.pem создается автоматически

- [ ] **Задача 1.5:** Создание Certbot Nginx Service (1 час)
  - [ ] Добавить certbot_nginx service в docker-compose.yml
  - [ ] Создать lib/certbot_manager.sh
  - [ ] Реализовать acquire_certificate()
  - [ ] **Acceptance:** Certbot nginx запускается по требованию

- [ ] **Задача 1.6:** Переназначение портов бэкендов (1 час)
  - [ ] Xray: 443 → 127.0.0.1:8443
  - [ ] Nginx: 8443-8452 → 127.0.0.1:9443-9452
  - [ ] Обновить lib/docker_compose_generator.sh
  - [ ] **Acceptance:** Бэкенды на localhost only

- [ ] **Задача 1.7:** UFW правила (30 мин)
  - [ ] Удалить правила для 8443-8452/tcp
  - [ ] Добавить правило для HAProxy 443/tcp
  - [ ] Проверить правила для 1080/8118
  - [ ] **Acceptance:** Port 443 открыт, 8443-8452 закрыты

---

### Фаза 2: Конфигурация HAProxy Dynamic Routing (2-3 часа)
**Приоритет:** HIGH
**Статус:** ⏳ ОЖИДАНИЕ

- [ ] **Задача 2.1:** Dynamic ACL/Backend Management (2 часа)
  - [ ] Реализовать add_reverse_proxy_route()
  - [ ] Реализовать remove_reverse_proxy_route()
  - [ ] Реализовать list_haproxy_routes()
  - [ ] Graceful reload без downtime
  - [ ] **Acceptance:** Dynamic routes работают

- [ ] **Задача 2.2:** HAProxy Monitoring & Stats (1 час)
  - [ ] Включить stats page на :9000
  - [ ] Создать check_haproxy_status()
  - [ ] Интегрировать в vless-status
  - [ ] **Acceptance:** Stats page доступна

---

### Фаза 3: Обновление Nginx Reverse Proxy (2-3 часа)
**Приоритет:** HIGH
**Статус:** ⏳ ОЖИДАНИЕ

- [ ] **Задача 3.1:** Обновление nginx configs (1.5 часа)
  - [ ] Обновить lib/nginx_config_generator.sh
  - [ ] Новые порты: 9443-9452
  - [ ] Subdomain в server_name
  - [ ] **Acceptance:** Nginx на новых портах

- [ ] **Задача 3.2:** Обновление lib/docker_compose_manager.sh (1 час)
  - [ ] Port range: 9443-9452 (не 8443-8452)
  - [ ] get_next_available_port() для 9443-9452
  - [ ] **Acceptance:** Port allocation работает

---

### Фаза 4: Certificate Management (2-3 часа)
**Приоритет:** HIGH
**Статус:** ⏳ ОЖИДАНИЕ

- [ ] **Задача 4.1:** DNS Validation (30 мин)
  - [ ] validate_dns_for_domain()
  - [ ] dig + IP comparison
  - [ ] **Acceptance:** DNS validation работает

- [ ] **Задача 4.2:** Unified certificate acquisition (2 часа)
  - [ ] acquire_certificate_for_domain()
  - [ ] Certbot nginx integration
  - [ ] combined.pem creation
  - [ ] **Acceptance:** Certificate acquisition автоматизирован

- [ ] **Задача 4.3:** Certificate renewal (30 мин)
  - [ ] Обновить vless-cert-renew
  - [ ] HAProxy graceful reload
  - [ ] Cron job для auto-renewal
  - [ ] **Acceptance:** Renewal работает

---

### Фаза 5: Обновление CLI инструментов (2-3 часа)
**Приоритет:** MEDIUM
**Статус:** ⏳ ОЖИДАНИЕ

- [ ] **Задача 5.1:** vless-setup-proxy Updates (1.5 часа)
  - [ ] Subdomain-based prompts
  - [ ] Автоматическое назначение порта 9443-9452
  - [ ] DNS validation обязательна
  - [ ] **Acceptance:** Setup wizard работает

- [ ] **Задача 5.2:** vless-proxy CLI Updates (1 час)
  - [ ] show: subdomain без порта
  - [ ] list: все reverse proxies
  - [ ] URL format: https://domain (NO :8443!)
  - [ ] **Acceptance:** CLI commands обновлены

- [ ] **Задача 5.3:** vless-status Updates (30 мин)
  - [ ] HAProxy status section
  - [ ] 3 frontends info
  - [ ] Active routes
  - [ ] **Acceptance:** Status показывает HAProxy

---

### Фаза 6: fail2ban Integration (1-2 часа)
**Приоритет:** MEDIUM
**Статус:** ⏳ ОЖИДАНИЕ

- [ ] **Задача 6.1:** HAProxy Logging (30 мин)
  - [ ] Docker logging driver
  - [ ] Logs в /opt/vless/logs/haproxy/
  - [ ] **Acceptance:** Logging работает

- [ ] **Задача 6.2:** fail2ban Filter & Jail (1 час)
  - [ ] /etc/fail2ban/filter.d/haproxy-sni.conf
  - [ ] /etc/fail2ban/jail.d/haproxy.conf
  - [ ] **Acceptance:** fail2ban защищает HAProxy

---

### Фаза 7: Testing & Validation (4-5 часов)
**Приоритет:** CRITICAL
**Статус:** ⏳ ОЖИДАНИЕ

- [ ] **Test Case 1:** VLESS Reality через HAProxy (30 мин)
  - [ ] Configure client: vless://...@vless.domain.ru:443
  - [ ] Verify HAProxy routes to Xray:8443
  - [ ] Verify Reality handshake
  - [ ] **Expected:** VPN tunnel работает

- [ ] **Test Case 2:** SOCKS5/HTTP Proxy через HAProxy (30 мин)
  - [ ] Test SOCKS5: curl --proxy socks5s://...
  - [ ] Test HTTP: curl --proxy https://...
  - [ ] Verify HAProxy logs
  - [ ] **Expected:** Proxies работают

- [ ] **Test Case 3:** Reverse Proxy без порта (1 час)
  - [ ] Setup: vless-setup-proxy
  - [ ] Access: https://claude.ikeniborn.ru (no port!)
  - [ ] Verify certificate, auth, backend
  - [ ] **Expected:** Access работает

- [ ] **Test Case 4:** Certificate Acquisition & Renewal (1 час)
  - [ ] Acquire certificate
  - [ ] Verify combined.pem
  - [ ] Test renewal dry-run
  - [ ] **Expected:** Certificates работают

- [ ] **Test Case 5:** Multi-Domain Concurrent Access (1 час)
  - [ ] VLESS + 2 reverse proxies + SOCKS5 proxy
  - [ ] All simultaneously
  - [ ] **Expected:** No conflicts

- [ ] **Test Case 6:** Migration from v4.0/v4.1 (1 час)
  - [ ] Pre-migration: stunnel exists
  - [ ] Run migration
  - [ ] Post-migration: stunnel removed, HAProxy works
  - [ ] **Expected:** Backward compatible

---

### Фаза 8: Документация (2-3 часа)
**Приоритет:** MEDIUM
**Статус:** ⏳ ОЖИДАНИЕ

- [ ] **Задача 8.1:** Обновление PRD (1 час)
  - [ ] docs/prd/04_architecture.md: Add Section 4.7
  - [ ] docs/prd/02_functional_requirements.md: Update FR-REVERSE-PROXY-001
  - [ ] docs/prd/03_nfr.md: Update NFR-RPROXY-002
  - [ ] **Acceptance:** PRD обновлен

- [ ] **Задача 8.2:** Обновление CLAUDE.md (1 час)
  - [ ] Version: 4.3
  - [ ] Remove stunnel references
  - [ ] Add HAProxy sections
  - [ ] **Acceptance:** CLAUDE.md актуален

- [ ] **Задача 8.3:** User Documentation (1 час)
  - [ ] Создать docs/HAPROXY.md
  - [ ] Architecture explanation
  - [ ] Troubleshooting guide
  - [ ] **Acceptance:** Documentation полная

---

## ⏱️ ОЦЕНКА ВРЕМЕНИ

| Фаза | Задачи | Время | Приоритет | Статус |
|------|--------|-------|-----------|--------|
| 1. Подготовка инфраструктуры | 7 | 4-5 ч | CRITICAL | ⏳ В ПРОЦЕССЕ |
| 2. Конфигурация HAProxy | 2 | 2-3 ч | HIGH | ⏳ ОЖИДАНИЕ |
| 3. Обновление Nginx | 2 | 2-3 ч | HIGH | ⏳ ОЖИДАНИЕ |
| 4. Certificate Management | 3 | 2-3 ч | HIGH | ⏳ ОЖИДАНИЕ |
| 5. Обновление CLI | 3 | 2-3 ч | MEDIUM | ⏳ ОЖИДАНИЕ |
| 6. fail2ban Integration | 2 | 1-2 ч | MEDIUM | ⏳ ОЖИДАНИЕ |
| 7. Testing & Validation | 6 | 4-5 ч | CRITICAL | ⏳ ОЖИДАНИЕ |
| 8. Документация | 3 | 2-3 ч | MEDIUM | ⏳ ОЖИДАНИЕ |
| **ИТОГО** | **27** | **19-27 ч** | — | — |

**Реалистичная оценка:** 23 часа

---

## 📦 DELIVERABLES

После завершения:

1. ✅ Unified HAProxy solution для всех портов (443, 1080, 8118)
2. ✅ Subdomain-based access: `https://claude.ikeniborn.ru` (no port!)
3. ✅ stunnel полностью удален
4. ✅ VLESS Reality работает через HAProxy passthrough
5. ✅ SOCKS5/HTTP proxy через HAProxy TLS termination
6. ✅ До 10 reverse proxy domains (9443-9452)
7. ✅ Backward compatible с v4.0/v4.1
8. ✅ Единая конфигурация (haproxy.cfg)
9. ✅ HAProxy stats page для мониторинга

---

## 📝 ИСТОРИЯ ИЗМЕНЕНИЙ

- **2025-10-17:** План создан, начата Фаза 1

---

## 🔗 СВЯЗАННЫЕ ДОКУМЕНТЫ

- [PRD v4.1 Architecture](04_architecture.md)
- [PRD v4.1 Functional Requirements](02_functional_requirements.md)
- [PRD v4.1 NFR](03_nfr.md)
- [CLAUDE.md Project Memory](../../CLAUDE.md)
