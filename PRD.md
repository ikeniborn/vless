# VLESS + Reality VPN Server
## Product Requirements Document

---

**Version:** 1.1
**Date:** 2025-10-03
**Status:** Final (Updated with Proxy Support)
**Author:** Product Management & Technical Architecture Team

---

## Document Information

| Field | Value |
|-------|-------|
| **Product Name** | VLESS + Reality VPN Server |
| **Document Type** | Product Requirements Document (PRD) |
| **Target Audience** | System Administrators, DevOps Engineers, Technical Decision Makers |
| **Deployment Target** | Linux Servers (Ubuntu 20.04+, Debian 10+) |
| **Scale** | 10-50 concurrent users |
| **Technology Stack** | Docker, Xray-core, VLESS, Reality Protocol, Nginx |

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
   - 1.1 [Product Vision](#11-product-vision)
   - 1.2 [Key Features](#12-key-features)
   - 1.3 [Technical Highlights](#13-technical-highlights)
   - 1.4 [Success Criteria Summary](#14-success-criteria-summary)

2. [Product Overview](#2-product-overview)
   - 2.1 [Product Description](#21-product-description)
   - 2.2 [Goals and Objectives](#22-goals-and-objectives)
   - 2.3 [Target Users](#23-target-users)
   - 2.4 [Constraints and Assumptions](#24-constraints-and-assumptions)
   - 2.5 [Out of Scope](#25-out-of-scope)

3. [Technical Architecture](#3-technical-architecture)
   - 3.1 [System Overview](#31-system-overview)
   - 3.2 [Components Detail](#32-components-detail)
   - 3.3 [Component Interactions](#33-component-interactions)
   - 3.4 [Data Flows](#34-data-flows)
   - 3.5 [Network Architecture](#35-network-architecture)
   - 3.6 [Storage Architecture](#36-storage-architecture)
   - 3.7 [Technology Stack](#37-technology-stack)

4. [Functional Requirements](#4-functional-requirements)
   - 4.1 [Installation and Deployment](#41-installation-and-deployment)
   - 4.2 [User Management](#42-user-management)
   - 4.3 [Network Configuration](#43-network-configuration)
   - 4.4 [Fake-site Functionality](#44-fake-site-functionality)
   - 4.5 [Xray Configuration](#45-xray-configuration)
   - 4.6 [Docker Compose Setup](#46-docker-compose-setup)
   - 4.7 [Operations and Management](#47-operations-and-management)
   - 4.8 [Client Configuration Export](#48-client-configuration-export)
   - 4.9 [Security and Accessibility](#49-security-and-accessibility)
   - 4.10 [Proxy Server Support](#410-proxy-server-support)

5. [Non-Functional Requirements](#5-non-functional-requirements)
   - 5.1 [Performance Requirements](#51-performance-requirements)
   - 5.2 [Reliability Requirements](#52-reliability-requirements)
   - 5.3 [Security Requirements](#53-security-requirements)
   - 5.4 [Usability Requirements](#54-usability-requirements)
   - 5.5 [Maintainability Requirements](#55-maintainability-requirements)
   - 5.6 [Compatibility Requirements](#56-compatibility-requirements)

6. [User Workflows](#6-user-workflows)
   - 6.1 [Initial Installation Workflow](#61-initial-installation-workflow)
   - 6.2 [Adding a New User Workflow](#62-adding-a-new-user-workflow)
   - 6.3 [Client Connection Workflow](#63-client-connection-workflow)
   - 6.4 [Removing a User Workflow](#64-removing-a-user-workflow)
   - 6.5 [System Update Workflow](#65-system-update-workflow)
   - 6.6 [Troubleshooting Workflow](#66-troubleshooting-workflow)
   - 6.7 [Uninstallation Workflow](#67-uninstallation-workflow)

7. [Configuration Specifications](#7-configuration-specifications)
   - 7.1 [Xray Configuration (config.json)](#71-xray-configuration-configjson)
   - 7.2 [Docker Compose Configuration](#72-docker-compose-configuration)
   - 7.3 [Nginx Configuration](#73-nginx-configuration)
   - 7.4 [User Data Structure (users.json)](#74-user-data-structure-usersjson)
   - 7.5 [Reality Keys (reality_keys.json)](#75-reality-keys-reality_keysjson)
   - 7.6 [Environment Variables (.env)](#76-environment-variables-env)
   - 7.7 [UFW Rules](#77-ufw-rules)
   - 7.8 [Client Configuration Examples](#78-client-configuration-examples)

8. [Security Considerations](#8-security-considerations)
   - 8.1 [Security Architecture](#81-security-architecture)
   - 8.2 [Authentication and Authorization](#82-authentication-and-authorization)
   - 8.3 [Key Management](#83-key-management)
   - 8.4 [Network Security](#84-network-security)
   - 8.5 [Container Security](#85-container-security)
   - 8.6 [Access Control](#86-access-control)
   - 8.7 [Threat Model](#87-threat-model)
   - 8.8 [Security Best Practices](#88-security-best-practices)

9. [Deployment and Operations](#9-deployment-and-operations)
   - 9.1 [Prerequisites](#91-prerequisites)
   - 9.2 [Installation Guide](#92-installation-guide)
   - 9.3 [CLI Commands Reference](#93-cli-commands-reference)
   - 9.4 [Operational Procedures](#94-operational-procedures)
   - 9.5 [Maintenance Tasks](#95-maintenance-tasks)
   - 9.6 [Troubleshooting Guide](#96-troubleshooting-guide)
   - 9.7 [Upgrade and Migration](#97-upgrade-and-migration)

10. [Success Criteria and Metrics](#10-success-criteria-and-metrics)
    - 10.1 [Success Criteria](#101-success-criteria)
    - 10.2 [Key Performance Indicators](#102-key-performance-indicators)
    - 10.3 [Acceptance Testing](#103-acceptance-testing)
    - 10.4 [Verification Methods](#104-verification-methods)

11. [Risks and Mitigations](#11-risks-and-mitigations)
    - 11.1 [Risk Overview](#111-risk-overview)
    - 11.2 [Technical Risks](#112-technical-risks)
    - 11.3 [Operational Risks](#113-operational-risks)
    - 11.4 [Security Risks](#114-security-risks)
    - 11.5 [Risk Matrix](#115-risk-matrix)
    - 11.6 [Contingency Plans](#116-contingency-plans)

12. [Appendices](#12-appendices)
    - 12.1 [Appendix A: Glossary](#appendix-a-glossary)
    - 12.2 [Appendix B: References](#appendix-b-references)
    - 12.3 [Appendix C: Acronyms](#appendix-c-acronyms)
    - 12.4 [Appendix D: Command Quick Reference](#appendix-d-command-quick-reference)
    - 12.5 [Appendix E: File Structure Reference](#appendix-e-file-structure-reference)
    - 12.6 [Appendix F: Version History](#appendix-f-version-history)

---

# 1. Executive Summary

## 1.1 Product Vision

**VLESS + Reality VPN Server** is an intelligent deployment and management system for modern, DPI-resistant VPN infrastructure. This solution enables system administrators to deploy a production-ready VPN server in under 5 minutes with zero manual configuration, leveraging the cutting-edge Reality protocol that requires no domain purchases or TLS certificate management.

### What We Build
An intelligent VLESS + Reality VPN deployment and management system that combines:
- **Automated Installation:** Interactive CLI-based setup with intelligent parameter detection
- **Conflict Resolution:** Automatic detection and resolution of port/subnet conflicts with existing services
- **User Management:** One-command user creation with automatic QR code generation
- **Stealth Operation:** Nginx-based fake-site masquerading indistinguishable from normal HTTPS traffic
- **Integrated Proxy Servers:** SOCKS5 and HTTP proxy accessible through encrypted VPN tunnel for application integration (VSCode, Docker, CLI tools)

### Why It Matters
Traditional VPN protocols (OpenVPN, IPSec) are easily detected by Deep Packet Inspection (DPI) systems deployed by ISPs and governments. The Reality protocol solves this fundamental challenge by:
- Eliminating TLS fingerprints through "traffic stealing" from legitimate websites
- Removing the operational burden of domain and certificate management
- Providing forward secrecy and anti-fingerprinting capabilities
- Enabling seamless coexistence with other VPN services (Outline, Wireguard)

### Who Should Use This
- **System Administrators** managing Linux servers for small to medium organizations (10-50 users)
- **DevOps Engineers** requiring scriptable, reproducible VPN infrastructure deployment
- **Privacy-conscious individuals** seeking DPI-resistant connectivity in restrictive network environments

### Deployment Context
- **Platform:** Linux servers (Ubuntu 20.04+, Debian 10+)
- **Scale:** 10-50 concurrent users per deployment
- **Deployment Path:** `/opt/vless` with persistent Docker volumes

## 1.2 Key Features

Our solution delivers comprehensive VPN infrastructure with the following capabilities:

✅ **Interactive CLI Installation with Intelligent Detection**
- Automated environment validation (OS, Docker, UFW)
- Dynamic detection of occupied ports and Docker subnets
- Validation of destination sites for Reality masquerading
- Old installation detection with data preservation during updates

✅ **Automatic Conflict Detection and Resolution**
- Scans existing services (Outline, Wireguard, etc.) to avoid conflicts
- Proposes alternative ports if 443 is occupied
- Finds free Docker subnets automatically
- Identifies and handles previous VLESS installations

✅ **One-Command User Management**
- Create users: `sudo vless-user add username`
- Automatic UUID and shortId generation
- Client configuration export (JSON, URI, QR code)
- Support for v2rayN, v2rayNG mobile clients

✅ **Nginx Fake-site for Traffic Masquerading**
- Reverse proxy to legitimate websites (google.com, microsoft.com)
- Fallback mechanism for invalid VPN connections
- Makes VPN server indistinguishable from normal HTTPS website
- Enhances DPI resistance through traffic camouflage

✅ **UFW Firewall Integration with Docker Support**
- Automatic UFW rule management
- Docker forwarding configuration in `/etc/ufw/after.rules`
- No duplicate rule creation
- Validation of firewall + Docker integration

✅ **Multi-VPN Coexistence**
- Isolated Docker bridge network (`vless_reality_net`)
- Zero conflicts with Outline, Wireguard, or other VPN services
- Independent subnet management
- Resource sharing without interference

✅ **Reality Protocol: No Domains, No Certificates**
- TLS 1.3 traffic masquerading
- X25519 key exchange for forward secrecy
- "Steals" TLS handshake from target website
- High resistance to active/passive DPI detection

✅ **Sudo-Accessible CLI for Non-Root Users**
- Commands accessible via `sudo` for regular users
- Automatic privilege escalation when needed
- Secure permission model (600/700 for sensitive files)
- Separation of administrative and operational commands

✅ **Integrated SOCKS5 and HTTP Proxy Servers**
- Localhost-only proxy servers (127.0.0.1:1080, 127.0.0.1:8118)
- Accessible only through encrypted VLESS tunnel
- Individual authentication per user (auto-generated passwords)
- Support for VSCode, Docker, npm, pip, curl, and other development tools
- Secure architecture: No direct internet exposure, only via VPN

## 1.3 Technical Highlights

### Protocol Architecture
- **VPN Protocol:** VLESS (lightweight, no built-in encryption)
- **Security:** Reality (TLS 1.3 masquerading, forward secrecy)
- **Flow Control:** xtls-rprx-vision (optimized for performance)
- **Transport:** TCP with Reality encryption layer
- **Proxy Protocols:** SOCKS5 (port 1080) and HTTP (port 8118) on localhost only

### Container Stack
- **Xray Container:** `teddysun/xray:24.11.30` (VLESS + Reality + SOCKS5 + HTTP proxy server)
- **Nginx Container:** `nginx:alpine` (fake-site reverse proxy)
- **Network:** Isolated Docker bridge network
- **Orchestration:** Docker Compose v2.0+
- **Proxy Binding:** Localhost-only (127.0.0.1) for security

### Deployment Model
- **Installation Path:** `/opt/vless` (all components)
- **Configuration:** JSON-based (config.json, users.json, reality_keys.json)
- **Persistence:** Docker volumes for config, logs, client data
- **Management:** Bash CLI scripts with sudo support

### User Storage
- **Format:** JSON files (sufficient for 10-50 users)
- **Structure:** users.json with UUID, shortId, proxy_password, metadata
- **Operations:** Atomic read/write with file locking
- **Performance:** Sub-second operations for all user management tasks
- **Proxy Credentials:** Auto-generated 16-character passwords per user

### Key Management
- **Algorithm:** X25519 elliptic curve Diffie-Hellman
- **Generation:** Automatic via `xray x25519` command
- **Storage:** Private key (600 permissions), public key (distributed to clients)
- **Rotation:** Supported through CLI command

### Client Support
- **VPN Clients:** v2rayN (Windows), v2rayNG (Android), Qv2ray (Linux/macOS)
- **Configuration Formats:** JSON, VLESS URI, QR code (PNG/text)
- **Proxy Integration:** VSCode, Docker, npm, pip, git, curl/wget
- **Auto-generation:** VPN and proxy configs created automatically on user addition
- **Export Formats:** VLESS configs + SOCKS5/HTTP proxy configs + integration examples

## 1.4 Success Criteria Summary

The system is considered successful when meeting the following criteria:

| Criterion | Target | Weight | Measurement Method |
|-----------|--------|--------|-------------------|
| **Installation Time** | < 5 minutes | 20% | Time from script start to first user ready |
| **User Creation Speed** | < 5 seconds | 25% | Time from command to QR code display |
| **DPI Masquerading** | 100% undetectable | 20% | Traffic analysis tools, DPI testing |
| **Multi-VPN Compatibility** | Zero conflicts | 15% | Coexistence with Outline/Wireguard |
| **Update Data Preservation** | 100% retention | 10% | Users retained after vless-update |
| **CLI Intuitiveness** | 8/10 rating | 10% | User survey, first-time user feedback |

**Overall Target:** All criteria met with confidence level 95%+

### System Architecture Overview

```mermaid
graph LR
    Client[VPN Client] -->|Reality Handshake| Xray[Xray Container<br/>teddysun/xray:24.11.30]
    Browser[Web Browser] -->|HTTP/HTTPS| Xray
    Xray -->|Valid Auth| Internet[Internet]
    Xray -->|Invalid/Fallback| Nginx[Nginx Container<br/>nginx:alpine]
    Nginx -->|Proxy| Dest[google.com]
    Xray -.->|Network| Docker[vless_reality_net<br/>172.20.0.0/16]
    Nginx -.->|Network| Docker

    style Xray fill:#e1f5ff
    style Nginx fill:#fff3e0
    style Docker fill:#f3e5f5
```

**Figure 1.1:** High-level system architecture showing VPN client authentication flow and fake-site fallback mechanism.

---

**End of Section 1**

Next: Section 2 (Product Overview) will provide detailed problem statement, comparison with alternatives, goals, constraints, and scope boundaries.


# 2. Product Overview

## 2.1 Product Description

### Problem Statement

Traditional VPN protocols face a fundamental challenge in restrictive network environments:

**DPI Detection:** Deep Packet Inspection (DPI) systems deployed by ISPs and governments can easily identify and block conventional VPN traffic. Protocols like OpenVPN and IPSec have distinctive fingerprints in their handshakes, making them trivial to detect and throttle.

**Certificate Management Overhead:** Modern stealth protocols like Trojan require purchasing domains and managing TLS certificates, adding operational complexity and recurring costs. Certificate expiration, renewal, and SNI configuration become operational burdens.

**Limited Evasion Capabilities:** While Shadowsocks and VMess provide some obfuscation, they still exhibit patterns detectable by advanced DPI systems. As detection technologies evolve, these protocols become increasingly vulnerable.

### The Reality Solution

VLESS + Reality protocol addresses these challenges through innovative "traffic stealing" technology:

- **TLS Indistinguishability:** Reality-protected connections are mathematically indistinguishable from legitimate HTTPS traffic to the target website (dest). DPI systems cannot differentiate VPN traffic from normal web browsing.

- **No Domain Requirements:** Unlike Trojan or traditional TLS-based VPNs, Reality doesn't require owning a domain. It "borrows" the TLS handshake from existing websites like google.com or microsoft.com.

- **Zero Certificate Management:** No certificates to purchase, renew, or configure. The system uses the target website's existing certificates, eliminating this operational overhead entirely.

- **Forward Secrecy:** X25519 key exchange ensures that compromising long-term keys doesn't compromise past sessions, providing cryptographic

 forward secrecy.

- **Anti-Fingerprinting:** Reality eliminates server-side TLS fingerprints that would otherwise reveal the VPN server's presence.

### Value Proposition

**For System Administrators:**
- Deploy production-ready VPN in under 5 minutes
- Zero manual configuration through intelligent automation
- Automatic conflict detection with existing services
- Sudo-accessible commands for delegated management

**For Organizations:**
- No recurring domain/certificate costs
- Minimal maintenance (update via single command)
- Scales to 50 users without infrastructure changes
- Compatible with existing VPN infrastructure (Outline, Wireguard)

**For End Users:**
- One-click connection via QR code
- No manual configuration required
- Works reliably in restrictive networks
- Indistinguishable from normal HTTPS traffic

### Comparison with Alternatives

| Feature | OpenVPN | Wireguard | Outline (SS) | Trojan | **VLESS + Reality** |
|---------|---------|-----------|--------------|--------|---------------------|
| DPI Resistance | Low | Low | Medium | High | **Very High** |
| Setup Complexity | Medium | Low | Low | High | **Low** |
| Certificates Required | Yes | No | No | Yes | **No** |
| Domain Required | Optional | No | No | Yes | **No** |
| Maintenance Burden | High | Low | Low | High | **Low** |
| Performance Overhead | High | Very Low | Low | Low | **Low** |
| Detection Risk | Very High | High | Medium | Low | **Very Low** |
| Multi-VPN Coexistence | Poor | Good | Good | Poor | **Excellent** |

## 2.2 Goals and Objectives

### Primary Goals

1. **Provide DPI-Resistant VPN Without Certificate Burden**
   - Eliminate the need for domain purchases and TLS certificate management
   - Achieve traffic indistinguishability from normal HTTPS
   - Maintain cryptographic security (forward secrecy, authentication)

2. **Enable 5-Minute Installation With Zero Manual Configuration**
   - Interactive CLI guides user through all parameters
   - Automatic validation of dest sites, ports, subnets
   - Intelligent detection and resolution of conflicts
   - First user created automatically at end of installation

3. **Ensure Coexistence With Existing VPN Services**
   - Isolated Docker network prevents subnet conflicts
   - Dynamic port detection avoids service conflicts
   - UFW rules managed without breaking existing configurations
   - Tested compatibility with Outline and Wireguard

4. **Deliver Intuitive CLI Management for 10-50 Users**
   - One-command user operations (add/remove/list)
   - Automatic QR code generation for mobile clients
   - Export to multiple client formats (JSON, URI, QR)
   - Sudo accessibility for non-root administrators

### Secondary Goals

1. **Fake-Site Masquerading for Additional Stealth**
   - Nginx reverse proxy to dest website
   - Fallback mechanism for invalid VPN attempts
   - Makes server appear as normal HTTPS website
   - Enhances overall DPI resistance

2. **Automated UFW Firewall Integration**
   - Detect UFW status and existing rules
   - Configure Docker forwarding in /etc/ufw/after.rules
   - Avoid duplicate rule creation
   - Validate connectivity after configuration

3. **QR Code Generation for Mobile Clients**
   - PNG image generation via qrencode
   - ASCII art for terminal display
   - Embedded in client config export
   - Scannable by v2rayNG on Android

4. **Intelligent Reinstallation Preserving User Data**
   - Detect old installations automatically
   - Backup users.json before destructive operations
   - Migrate configurations during updates
   - Rollback capability on failures

### Non-Goals (Explicitly Out of Scope)

The following features are **intentionally excluded** from this version:

1. **Web UI or Graphical Interface**
   - *Rationale:* CLI-only interface enforced by constraints. Web UI adds attack surface and complexity inappropriate for target scale (10-50 users).

2. **Built-in Monitoring and Alerting**
   - *Rationale:* User explicitly declined monitoring requirements. Basic Docker logs sufficient for troubleshooting.

3. **Traffic Shaping or Per-User Bandwidth Limits**
   - *Rationale:* User declined bandwidth management features. All users have equal network access.

4. **Support for 100+ Concurrent Users**
   - *Rationale:* System designed for 10-50 user scale. JSON-based storage and simple architecture intentionally limit scalability.

5. **CDN Integration (Cloudflare Workers, etc.)**
   - *Rationale:* Direct server connections preferred. CDN integration adds complexity and external dependencies.

6. **Multi-Protocol Support (Shadowsocks, Trojan, VMess)**
   - *Rationale:* Focused exclusively on VLESS + Reality. Other protocols have different operational models.

7. **Connection Multiplexing (mux)**
   - *Rationale:* Reality + xtls-rprx-vision doesn't require multiplexing. Direct connections provide better performance.

8. **Database for User Storage**
   - *Rationale:* JSON files sufficient for target scale. Database adds unnecessary complexity.

9. **Automatic Docker Image Updates**
   - *Rationale:* Manual updates via `vless-update` preferred for control. Automatic updates risk breaking changes.

10. **Cross-Platform Server Support (Windows, macOS)**
    - *Rationale:* Linux-only deployment (Ubuntu/Debian). Bash scripts, UFW, iptables are Linux-specific.

## 2.3 Target Users

### Primary User: System Administrator

**Profile:**
- **Role:** Manages Linux servers for small/medium organization or personal use
- **Technical Level:** Comfortable with CLI, basic Docker knowledge, understands networking fundamentals
- **Environment:** Ubuntu/Debian server, possibly shared with other services (web, databases, other VPNs)
- **User Count:** Manages 10-50 VPN users (employees, family, friends)

**Pain Points:**
- Traditional VPN protocols blocked by ISP/government DPI
- Certificate management for Trojan/TLS-based VPNs is time-consuming
- Conflicts between multiple VPN services on same server
- Manual user management becomes tedious at scale

**Goals:**
- Deploy VPN quickly without infrastructure preparation
- Minimal ongoing maintenance (set and forget)
- User self-service through shared QR codes/configs
- Reliable connectivity even in restrictive networks

**Success Metrics:**
- Installation completed in under 10 minutes
- Add new user in under 1 minute
- Zero manual troubleshooting in normal operation

### Secondary User: DevOps Engineer

**Profile:**
- **Role:** Infrastructure automation and reliability engineering
- **Technical Level:** Advanced CLI, scripting (Bash/Python), containerization expert
- **Environment:** Multi-service infrastructure, infrastructure-as-code workflows
- **Focus:** Reproducibility, automation, integration

**Pain Points:**
- VPN integration with existing monitoring/logging infrastructure
- Need for scriptable, non-interactive deployment
- Configuration drift between environments
- Manual steps break automation pipelines

**Goals:**
- Scriptable installation for automated provisioning
- Configuration management compatibility (Ansible, Terraform)
- Monitoring integration (though out of scope in v1.0)
- Version-controlled configuration

**Success Metrics:**
- Can deploy via CI/CD pipeline
- Configuration files under version control
- Reproducible deployments across environments

### User Scale and Characteristics

**Typical Deployment:**
- **User Count:** 10-50 concurrent users
- **User Types:** Mix of technical and non-technical end users
- **Geographic Distribution:** Often international, accessing from restrictive regions
- **Client Devices:** Mobile (Android/iOS) and desktop (Windows/Linux/macOS)
- **Connection Patterns:** Persistent connections, occasional reconnects, varying bandwidth needs

**End-User Characteristics:**
- May not be technically savvy (QR code scanning is extent of configuration)
- Expect reliable, "just works" connectivity
- Primarily use for web browsing, messaging, occasional streaming
- Connect from various network conditions (cellular, WiFi, restrictive networks)

## 2.4 Constraints and Assumptions

### Constraints

| ID | Constraint | Impact | Justification |
|----|------------|--------|---------------|
| **C-001** | **Follow XTLS/Xray-examples Documentation** | Architecture limited to proven practices from official examples | Ensures technical correctness and community support. Deviating risks incompatibility or security issues. |
| **C-002** | **Compatible with Outline, Wireguard** | Requires network isolation strategy and dynamic resource detection | Servers often run multiple VPN services. Breaking existing services unacceptable. |
| **C-003** | **Docker Image: teddysun/xray:24.11.30** | Fixed version, manual updates required | Stability over bleeding-edge features. Version pinning prevents breaking changes. |
| **C-004** | **Install Path: /opt/vless** | Hard-coded in all scripts, cannot be changed without modification | Standardization simplifies support and documentation. Flexibility adds unnecessary complexity. |
| **C-005** | **CLI-Only Interface** | No Web UI, all management via terminal commands | Reduces attack surface, aligns with sysadmin workflows. GUI out of scope for target scale. |
| **C-006** | **Linux Only (Ubuntu/Debian)** | No Windows/macOS server support | Bash scripts, UFW, iptables are Linux-specific. Cross-platform support quintuples complexity. |
| **C-007** | **Scale: 10-50 Users** | Simple solutions (JSON storage, file-based configs) intentionally limit scalability | Designed for small-medium deployments. Over-engineering for larger scale avoided. |
| **C-008** | **All Parameters via Terminal** | Interactive installation, no config files to edit | Enforces guided setup, reduces configuration errors. Pre-filled configs risk copy-paste mistakes. |

### Assumptions

| ID | Assumption | Validation Method | Risk if Invalid | Mitigation |
|----|------------|-------------------|-----------------|------------|
| **A-001** | **Server has clean IP (not blacklisted)** | User verification via online tools | VPN may be blocked by destination services or ISPs | Installation warns user to check IP reputation before deployment |
| **A-002** | **Dest site (google.com) is stably available** | Continuous validation during installation and runtime | Reality handshake fails, VPN becomes unusable | Multiple dest options (google, microsoft, apple), fallback strategy, health checks |
| **A-003** | **UFW installed on server** | Installation script checks for `ufw` binary | Cannot configure firewall, manual setup required | Auto-install UFW via `apt-get install ufw` if missing |
| **A-004** | **Docker + docker-compose installed** | Version checks: `docker --version`, `docker-compose --version` | Cannot deploy containers, installation fails | Auto-install Docker and docker-compose if absent or outdated |
| **A-005** | **Root or sudo access available** | Check `$EUID` or `sudo -n true` at script start | Installation cannot proceed, file permissions fail | Clear error message, exit installation, guide user to run with sudo |
| **A-006** | **Stable internet connection** | Connectivity test: `curl -s https://www.google.com` | Cannot download Docker images, validate dest sites | Pre-flight connectivity check, clear error if offline |
| **A-007** | **Port 443 is preferred and often free** | Dynamic check: `ss -tlnp | grep :443` during installation | Need alternative port, slightly reduced masquerading effectiveness | Propose alternatives (8443, 2053), allow custom port, warn about non-standard port detection |

### Implications of Constraints

**C-001 (Follow XTLS Documentation):**
- All Reality parameters (dest, serverNames, keys) must match documented formats
- Cannot experiment with unsupported Xray features
- Configuration examples must be copy-paste compatible with official docs

**C-002 (Multi-VPN Compatibility):**
- Docker network isolation mandatory (separate bridge networks)
- Port and subnet detection required at installation
- UFW rules must be additive, not replace existing rules

**C-003 (Fixed Docker Image Version):**
- Manual update process via `vless-update` command
- Version pinning in docker-compose.yml: `image: teddysun/xray:24.11.30`
- Update documentation must guide through breaking changes between versions

**C-005 (CLI-Only):**
- All operations scriptable via bash commands
- No browser-based user management
- QR codes displayed in terminal (ASCII art) or saved as PNG files

**C-007 (10-50 User Scale):**
- JSON file storage (users.json) instead of database
- Simple bash scripts instead of application server
- File-based locking for concurrent access control

## 2.5 Out of Scope

### Detailed Exclusions

#### 1. Web-Based Administration Interface
**Excluded:** Browser-based UI for server management, user creation, log viewing.

**Rationale:**
- CLI-only constraint (C-005) explicitly prohibits GUI
- Web UI increases attack surface (authentication, session management, XSS/CSRF vulnerabilities)
- For 10-50 users, CLI efficiency exceeds GUI benefits
- Target audience (system administrators) comfortable with terminal operations

**Future Consideration:** Could be added in v2.0 if scale increases beyond 50 users or non-technical administrators need access.

#### 2. Integrated Monitoring and Alerting
**Excluded:** Built-in metrics collection, Prometheus exporters, alerting on connection failures/performance degradation.

**Rationale:**
- User explicitly declined monitoring in requirements gathering
- Docker logs (`vless-logs`) sufficient for troubleshooting
- Integration with existing monitoring (if needed) can be done externally via log parsing
- Adds complexity inappropriate for target scale

**Future Consideration:** Exporters for Prometheus/Grafana could be optional plugins.

#### 3. Per-User Traffic Shaping and Bandwidth Limits
**Excluded:** QoS configuration, bandwidth quotas, speed limiting per user.

**Rationale:**
- User explicitly declined this feature
- Requires iptables/tc configuration complexity
- Trust model assumes all users have equal access rights
- Enforcement difficult without deep integration into Xray

**Future Consideration:** If resource contention becomes issue, could add in v1.1.

#### 4. Automated Backup and Disaster Recovery
**Excluded:** Scheduled backups of configurations, automatic cloud uploads, one-click restore.

**Rationale:**
- User explicitly declined automatic backup
- Manual backup via `cp -r /opt/vless /opt/vless.backup` sufficient
- Reinstallation process includes backup prompt
- Automation adds cron jobs and external dependencies

**Actual Behavior:** Backup created only during `vless-uninstall` (saved to `/tmp/vless_backup_*.tar.gz`).

#### 5. Support for 100+ Concurrent Users
**Excluded:** Database-backed user storage, connection pooling, horizontal scaling.

**Rationale:**
- Constraint C-007 explicitly limits to 10-50 users
- JSON file storage performant up to ~100 users
- Scaling beyond requires architectural redesign (PostgreSQL, API server, etc.)
- Target audience doesn't need enterprise scale

**Alternative:** For larger deployments, recommend multiple independent instances.

#### 6. Additional Protocol Support (Shadowsocks, Trojan, VMess)
**Excluded:** Multi-protocol server supporting VLESS + others simultaneously.

**Rationale:**
- Focus on VLESS + Reality for DPI resistance
- Each protocol has different configuration models
- Multi-protocol setup complicates port management and client configs
- Outline and Wireguard handle Shadowsocks/Wireguard use cases

**Future Consideration:** Could support multiple Xray protocols in v2.0.

#### 7. CDN/Cloudflare Integration
**Excluded:** Cloudflare Workers for traffic proxying, CDN hiding of server IP.

**Rationale:**
- Direct server connections provide lower latency
- CDN integration requires domain ownership (contradicts "no domain" value proposition)
- Adds external dependency and potential single point of failure
- Reality protocol already provides strong DPI resistance

#### 8. Automatic Certificate Management (Let's Encrypt)
**Excluded:** ACME protocol integration for automated certificate issuance/renewal.

**Rationale:**
- Reality protocol doesn't use own certificates (borrows from dest site)
- No domain = no certificates to manage
- This is a core value proposition, not a missing feature

#### 9. Advanced Routing Rules (Split Tunneling, Geo-Routing)
**Excluded:** Client-side routing rules, bypass for local traffic, country-based routing.

**Rationale:**
- Routing rules are client-side configuration, not server-side
- v2rayN/v2rayNG handle this independently
- Server provides simple "all traffic through tunnel" model
- Advanced routing adds client config complexity

**Actual Behavior:** Basic Xray routing (direct for private IPs, proxy for everything else).

#### 10. Multi-Server Load Balancing
**Excluded:** Distributing users across multiple backend servers, automatic failover.

**Rationale:**
- Single-server deployment model
- 10-50 users easily handled by one server
- Load balancing requires proxy layer or client-side server lists
- Adds significant operational complexity

**Alternative:** Deploy multiple independent instances for different user groups.

### System Context Diagram

```mermaid
graph TB
    subgraph External
        Admin[System Administrator]
        Users[VPN Users<br/>10-50 concurrent]
        DockerHub[Docker Hub<br/>Image Registry]
        DestSite[Dest Websites<br/>google.com, microsoft.com]
        ExistingVPN[Existing VPN Services<br/>Outline, Wireguard]
    end

    subgraph "VLESS Reality System Boundary"
        CLI[Installation & Management CLI<br/>Bash scripts, sudo accessible]
        Xray[Xray Container<br/>VLESS + Reality]
        Nginx[Nginx Container<br/>Fake-site Proxy]
        UFW[UFW Firewall<br/>Port rules, Docker integration]
        Storage[Configuration Storage<br/>/opt/vless/]
    end

    Admin -->|1. Install, Configure| CLI
    Admin -->|2. Manage Users| CLI
    Users -->|3. VPN Connect| Xray
    CLI -->|4. Deploy Containers| Xray
    CLI -->|4. Deploy Containers| Nginx
    CLI -->|5. Configure Rules| UFW
    Xray -->|6. Pull Image| DockerHub
    Nginx -->|7. Proxy Traffic| DestSite
    Xray -.->|8. Isolated Network| ExistingVPN
    CLI -->|9. Read/Write Configs| Storage
    UFW -->|10. Protect| Xray

    style CLI fill:#e3f2fd
    style Xray fill:#fff3e0
    style Nginx fill:#f3e5f5
    style Storage fill:#e8f5e9
```

**Figure 2.1:** System context showing external entities, system boundary, and key interactions. Dotted line indicates isolation from existing VPN services.

---

**End of Section 2**

---

## 3. Technical Architecture

### 3.1 System Overview

The system implements a **multi-container Docker architecture** with intelligent CLI orchestration. The architecture is designed around three layers that work together to provide a secure, isolated, and user-friendly VLESS + Reality VPN deployment:

**Container Layer:** Xray (VLESS + Reality protocol server with integrated SOCKS5/HTTP proxies) and Nginx (fake-site reverse proxy) run in an isolated Docker network (`vless_reality_net`). Proxy servers listen on localhost only (127.0.0.1), accessible exclusively through the encrypted VPN tunnel. This isolation ensures zero conflicts with existing VPN services like Outline or Wireguard by maintaining completely separate network namespaces and subnets.

**Management Layer:** Bash-based CLI tools provide installation, user management, and service operations. All scripts are designed with sudo accessibility for non-root users, featuring automatic privilege escalation and comprehensive error handling.

**Infrastructure Layer:** UFW firewall integration with Docker forwarding support, persistent storage structure in `/opt/vless/`, and configuration management through JSON files. The infrastructure layer handles conflict detection, parameter validation, and automated recovery from common failure scenarios.

**Key Innovation:** The installation process implements intelligent environment detection that automatically discovers existing resources (occupied ports, used subnets, old installations) and adapts configuration accordingly. This eliminates manual conflict resolution and enables safe coexistence with other VPN services on the same server.

### 3.2 Core Components

The system consists of 8 interconnected components:

| Component | Type | Responsibility | Technology | Dependencies |
|-----------|------|----------------|------------|--------------|
| **Installation CLI** | Bash Script | Interactive installation with environment detection, conflict resolution, parameter validation | Bash 4.0+, jq, curl, openssl | Docker, Docker Compose, UFW |
| **Xray Container** | Docker Container | VLESS + Reality protocol server, SOCKS5/HTTP proxy, traffic encryption, client authentication | teddysun/xray:24.11.30 | Docker network, config volumes |
| **Nginx Container** | Docker Container | Fake-site reverse proxy to destination for traffic masquerading | nginx:alpine | Docker network, config volumes |
| **User Management CLI** | Bash Scripts | Add/remove/list/export users, QR code generation, config management | Bash, jq, qrencode | Xray config, users.json |
| **Service Management CLI** | Bash Scripts | Start/stop/restart/status/logs operations, Docker orchestration | Bash, docker-compose | Docker daemon |
| **Docker Network** | Infrastructure | Isolated bridge network preventing conflicts with other VPN services | Docker bridge driver | Docker engine |
| **UFW Firewall** | System Service | Access control, Docker forwarding integration, traffic filtering | UFW, iptables | Linux kernel |
| **Configuration Storage** | Filesystem | Persistent storage for configs, user data, logs, client files | /opt/vless/ directory structure | Host filesystem |

**Table 3.1:** Core system components with their technologies and dependencies.

### 3.3 Component Interactions

The components interact through 6 primary workflows:

**Interaction 1: Installation Flow**
```
Administrator runs vless-install
→ CLI detects environment (OS, Docker, UFW status)
→ Prompts for parameters (dest, port, subnet) with intelligent defaults
→ Validates each parameter (dest reachability, port availability, subnet conflicts)
→ Generates configurations (Xray config.json, docker-compose.yml, .env, Nginx config)
→ Deploys containers via docker-compose up -d
→ Creates first admin user with QR code
→ System ready for client connections
```

**Interaction 2: User Creation**
```
Administrator: vless-user add username
→ Generate UUID (uuidgen) and shortId (openssl rand -hex 8)
→ Generate proxy password (openssl rand -base64 16)
→ Update users.json with new user metadata (UUID, shortId, proxy_password)
→ Update Xray config.json:
  - Add to VLESS clients[] array
  - Add to SOCKS5 accounts[] array
  - Add to HTTP accounts[] array
→ Reload Xray container (docker-compose restart xray)
→ Generate client configurations:
  - VLESS: JSON, URI, QR code
  - SOCKS5: config.txt
  - HTTP: config.txt
  - VSCode: settings.json
  - Docker: daemon.json
  - Bash: exports.sh
→ Save to /opt/vless/data/clients/username/
→ Display VLESS and proxy configurations to administrator
```

**Interaction 3: VPN Client Connection**
```
Client initiates TLS connection to server:${VLESS_PORT}
→ Xray receives connection and extracts Reality parameters
→ Reality validates: publicKey match, shortId in allowed list, SNI matches dest
→ If VALID: Establish VLESS tunnel, forward traffic to Internet
→ If INVALID: Fallback to Nginx:8080 (fake-site mode)
```

**Interaction 4: Fake-site Fallback**
```
Browser/Scanner connects to server:${VLESS_PORT} with HTTP(S) request
→ Xray detects non-VPN traffic (wrong Reality handshake or plain HTTP)
→ Forward connection to Nginx:8080
→ Nginx reverse proxies request to ${REALITY_DEST} (e.g., google.com)
→ Returns destination site response
→ Server appears as legitimate HTTPS website to external observers
```

**Interaction 5: UFW Configuration**
```
Installation → Check UFW status (active/inactive)
→ Parse existing rules in /etc/ufw/after.rules
→ Check for Docker forwarding chains (DOCKER-USER, DOCKER)
→ Add Docker chains if missing (no duplication)
→ Add port allow rule: ufw allow ${VLESS_PORT}/tcp
→ Reload UFW: ufw reload
→ Test connectivity: curl test to verify forwarding works
```

**Interaction 6: Service Management**
```
Administrator: vless-start / vless-stop / vless-restart
→ Check existence of /opt/vless/docker-compose.yml
→ Execute docker-compose command (up -d / down / restart)
→ Wait for container readiness (health checks)
→ Verify containers are running (docker ps)
→ Display status and logs summary
```

**Interaction 7: Proxy Usage Through VPN Tunnel**
```
Client connects to VLESS VPN (as per Interaction 3)
→ VPN tunnel established, client has access to server's localhost
→ Application configured to use proxy:
  - SOCKS5: socks5://username:password@127.0.0.1:1080
  - HTTP: http://username:password@127.0.0.1:8118
→ Application sends request to localhost proxy
→ Proxy authenticates user credentials
→ If VALID: Forward request through VPN tunnel → Server → Internet
→ If INVALID: Reject connection (authentication failed)
→ Response flows back: Internet → Server → VPN tunnel → Client → Application

Example Use Cases:
- VSCode: Remote extensions install through proxy
- Docker: Image pulls through proxy (docker pull nginx)
- curl/wget: API requests through proxy
- npm/pip: Package installations through proxy
```

### 3.4 Network Architecture

**Docker Network Topology:**

The system uses an isolated Docker bridge network to ensure complete separation from other VPN services:

- **Network Name:** `vless_reality_net`
- **Driver:** bridge
- **Subnet:** Dynamically determined during installation (default: 172.20.0.0/16)
  - Installation scans existing Docker networks (outline_net, wireguard_net, default bridge)
  - Selects unused subnet from available ranges
  - Can reuse subnet from previous VLESS installation
- **Gateway:** Auto-assigned by Docker (typically .0.1 of subnet)
- **Isolation:** Complete network namespace separation from other VPN containers

**Port Mapping:**

- **Host:${VLESS_PORT} → Xray:443** - VLESS + Reality inbound (default 443, customizable if occupied)
- **Xray:1080** - SOCKS5 proxy (localhost only, not exposed to host)
- **Xray:8118** - HTTP proxy (localhost only, not exposed to host)
- **Nginx:8080** - Internal only, accessed via fallback from Xray

**Note:** Proxy ports (1080, 8118) are bound to 127.0.0.1 inside the Xray container and are NOT mapped to host ports. Access is only possible through the VPN tunnel.

**UFW Firewall Rules:**

The installation configures UFW with Docker integration:

```
# Allow incoming VLESS connections
ufw allow ${VLESS_PORT}/tcp comment 'VLESS Reality VPN'

# Docker forwarding in /etc/ufw/after.rules
*filter
:DOCKER-USER - [0:0]
-A DOCKER-USER -j RETURN
COMMIT

*nat
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -s 172.20.0.0/16 -j MASQUERADE
COMMIT
```

**Traffic Flow:**

```
Internet → UFW:${VLESS_PORT} → Docker bridge → Xray container
  ├─ Valid VLESS auth → Docker gateway → Internet (VPN tunnel)
  └─ Invalid/HTTP → Nginx container → Proxy to ${REALITY_DEST} → Response (fake-site)
```

### 3.5 Data Flows

**Flow 1: User Authentication**

```
1. Client → Xray: VLESS + Reality handshake (UUID, shortId, publicKey, SNI)
2. Xray: Read /opt/vless/config/users.json
3. Xray: Validate UUID exists in users list
4. Xray: Verify shortId in allowed shortIds array
5. Xray: Check publicKey matches server Reality configuration
6. Xray: Verify SNI matches destination site
7. Decision:
   - All checks PASS → Establish VLESS tunnel → Forward traffic
   - Any check FAIL → Fallback to Nginx → Serve fake-site
```

**Flow 2: Fake-site Masquerading**

```
1. Browser/Scanner → Server:${VLESS_PORT}: HTTP(S) request (no Reality handshake)
2. Xray: Detect non-VLESS traffic via sniffing
3. Xray → Nginx:8080: Forward connection (fallback)
4. Nginx: Read /opt/vless/fake-site/default.conf
5. Nginx → ${REALITY_DEST}: Reverse proxy request
6. Nginx ← ${REALITY_DEST}: Receive response
7. Browser ← Nginx: Return response (server appears as destination site)
```

**Flow 3: User Creation**

```
1. Admin: vless-user add username
2. Script: Generate UUID (uuidgen)
3. Script: Generate shortId (openssl rand -hex 8)
4. Script: Read /opt/vless/config/users.json
5. Script: Append new user: {"id": UUID, "shortId": shortId, "username": username}
6. Script: Write updated users.json
7. Script: Read /opt/vless/config/config.json
8. Script: Add to clients[] array in inbounds
9. Script: Write updated config.json
10. Script: docker-compose restart xray
11. Script: Generate client config (JSON format for v2rayN/v2rayNG)
12. Script: Generate VLESS URI: vless://UUID@SERVER_IP:PORT?...
13. Script: Generate QR code: qrencode -o qrcode.png < uri.txt
14. Script: Save all to /opt/vless/data/clients/username/
15. Script → Admin: Display config and QR code in terminal
```

**Flow 4: Installation**

```
1. Admin: curl -O install.sh && bash install.sh (or vless-install if reinstalling)
2. Script: Check privileges (if not root: exec sudo "$0" "$@")
3. Script: Detect OS (Ubuntu/Debian), versions, architecture
4. Script: Check Docker, Docker Compose versions (install if missing)
5. Script: Check UFW status (install/enable if missing)
6. Script: Scan for old installation (/opt/vless/ exists?)
7. Script: If old installation: Backup users.json, reality_keys.json
8. Script: Interactive prompts:
   - Dest site (default: google.com:443, validate SNI extraction)
   - Port (default: 443, check availability, suggest alternatives)
   - Docker subnet (scan existing, suggest unused)
9. Script: Generate Reality keys: xray x25519
10. Script: Create directory structure: mkdir -p /opt/vless/{config,data,logs,fake-site,scripts}
11. Script: Generate config.json (Xray inbound with Reality settings)
12. Script: Generate docker-compose.yml (Xray + Nginx services)
13. Script: Generate .env (environment variables)
14. Script: Generate Nginx default.conf (reverse proxy to dest)
15. Script: Configure UFW (/etc/ufw/after.rules, allow port)
16. Script: Create Docker network: docker network create vless_reality_net --subnet ${SUBNET}
17. Script: docker-compose up -d
18. Script: Wait for containers (health checks)
19. Script: Create first user 'admin'
20. Script: Create symlinks: ln -s /opt/vless/scripts/*.sh /usr/local/bin/vless-*
21. Script: chmod 755 /usr/local/bin/vless-* (sudo accessibility)
22. Script → Admin: Installation complete + admin config + QR code
```

### 3.6 Storage Architecture

**Filesystem Structure (after installation):**

**Note:** During development, files are in the project Git repository. The installer creates `/opt/vless/` and copies files during installation.

```
/opt/vless/                              # Created by installer
├── config/                          # Configuration files (700, sensitive)
│   ├── config.json                  # Xray main configuration (600)
│   ├── users.json                   # User database: UUID, shortId, metadata (600)
│   └── reality_keys.json            # Public/private X25519 keys (600)
├── data/                            # User data and backups (700)
│   ├── clients/                     # Client configurations per user
│   │   └── {username}/
│   │       ├── config.json          # v2rayN/v2rayNG client config
│   │       ├── uri.txt              # VLESS URI for import
│   │       └── qrcode.png           # QR code image
│   └── backups/                     # Backup files from updates
│       ├── users.json.backup.{timestamp}
│       └── reality_keys.json.backup.{timestamp}
├── logs/                            # Log files (755)
│   ├── access.log                   # Xray access log (644)
│   └── error.log                    # Xray error log (644)
├── fake-site/                       # Nginx configuration (755)
│   └── default.conf                 # Reverse proxy to dest (644)
├── scripts/                         # Management scripts (755)
│   ├── user-manager.sh              # User management functions (755)
│   ├── service-manager.sh           # Service control functions (755)
│   └── common-functions.sh          # Shared utilities (755)
├── docs/                            # Additional documentation (755)
│   ├── api.md                       # API documentation
│   └── troubleshooting.md           # Troubleshooting guide
├── tests/                           # Test files (755)
│   ├── unit/                        # Unit tests (bats framework)
│   └── integration/                 # Integration tests
├── .env                             # Environment variables (600)
└── docker-compose.yml               # Container orchestration (644)

/usr/local/bin/                      # Symlinks to scripts (755, sudo-accessible)
├── vless-install -> /opt/vless/scripts/install.sh
├── vless-user -> /opt/vless/scripts/user-manager.sh
├── vless-start -> /opt/vless/scripts/service-manager.sh start
├── vless-stop -> /opt/vless/scripts/service-manager.sh stop
├── vless-restart -> /opt/vless/scripts/service-manager.sh restart
├── vless-status -> /opt/vless/scripts/service-manager.sh status
├── vless-logs -> /opt/vless/scripts/service-manager.sh logs
└── vless-uninstall -> /opt/vless/scripts/uninstall.sh
```

**Project Development Structure:**

During development (before installation), files are organized in the project repository:

```
/home/ikeniborn/Documents/Project/vless/  # Project root
├── install.sh                       # Main installation script
├── PLAN.md                          # Implementation plan
├── PRD.md                           # Product requirements document
├── lib/                             # Installation modules
│   ├── os_detection.sh              # OS detection
│   ├── dependencies.sh              # Dependency management
│   ├── old_install_detect.sh        # Old installation detection
│   ├── interactive_params.sh        # Parameter collection
│   ├── sudoers_info.sh              # Sudoers instructions
│   ├── orchestrator.sh              # Installation orchestration
│   └── verification.sh              # Post-install verification
├── docs/                            # Additional documentation
│   ├── OLD_INSTALL_DETECT_REPORT.md
│   ├── INTERACTIVE_PARAMS_REPORT.md
│   └── SUDOERS_INFO_REPORT.md
├── tests/                           # Test files
│   ├── unit/                        # Unit tests (bats framework)
│   └── integration/                 # Integration tests
├── scripts/                         # Additional utility scripts
│   ├── dev-helpers/                 # Development helpers
│   └── ci/                          # CI/CD scripts
└── requests/                        # Task request templates
    └── request_implement.xml
```

**Permissions:**

- **config/**: 700 (root only), sensitive files 600
- **scripts/**: 755 (executable by all), files 755
- **logs/**: 755, log files 644 (readable by monitoring tools)
- **data/**: 700 (protect client configs)
- **docs/**: 755, documentation files 644 (readable by all)
- **tests/**: 755, test files 755 (executable)
- **Symlinks**: 755 (non-root users can execute via sudo)

**Volume Mounts:**

Docker containers access configuration via volume mounts:

```yaml
xray:
  volumes:
    - /opt/vless/config:/etc/xray:ro
    - /opt/vless/logs:/var/log/xray:rw

nginx:
  volumes:
    - /opt/vless/fake-site:/etc/nginx/conf.d:ro
```

### 3.7 Technology Stack

| Component | Technology | Version | Purpose |
|-----------|------------|---------|---------|
| **VPN Protocol** | VLESS + Reality | Latest (Xray-core) | DPI-resistant protocol with TLS masquerading |
| **Xray Core** | teddysun/xray | 24.11.30 | Protocol implementation, routing, fallback |
| **Web Proxy** | Nginx | alpine (latest) | Fake-site masquerading via reverse proxy |
| **Container Runtime** | Docker Engine | 20.10+ | Containerization and isolation |
| **Orchestration** | Docker Compose | v2.0+ | Multi-container management |
| **Firewall** | UFW | System default | Access control and Docker integration |
| **Scripting** | Bash | 4.0+ | CLI tools and automation |
| **JSON Processing** | jq | 1.5+ | Config file manipulation |
| **QR Generation** | qrencode | Latest | Client configuration QR codes |
| **Cryptography** | OpenSSL | System default | Key generation, SNI extraction, validation |
| **UUID Generation** | uuidgen | System default | User identifier generation |

**Table 3.2:** Complete technology stack with version requirements.

### 3.8 Architecture Diagrams

#### 3.8.1 Component Diagram

```mermaid
graph TB
    Admin[Administrator] --> InstallCLI[Installation CLI]
    Admin --> UserCLI[User Management CLI]
    Admin --> ServiceCLI[Service Management CLI]

    InstallCLI --> Configs[Configuration Storage]
    InstallCLI --> UFW[UFW Firewall]
    InstallCLI --> DockerNet[Docker Network]

    UserCLI --> Configs
    UserCLI --> Xray
    ServiceCLI --> Xray
    ServiceCLI --> Nginx

    Xray[Xray Container] --> DockerNet
    Nginx[Nginx Container] --> DockerNet

    Xray -.->|Volume Mounts| Configs
    Nginx -.->|Volume Mounts| Configs

    Client[VPN Client] --> UFW
    UFW --> Xray
    Xray -->|Fallback| Nginx

    style InstallCLI fill:#e3f2fd
    style UserCLI fill:#e3f2fd
    style ServiceCLI fill:#e3f2fd
    style Xray fill:#fff3e0
    style Nginx fill:#f3e5f5
    style Configs fill:#e8f5e9
    style DockerNet fill:#fce4ec
    style UFW fill:#fff9c4
```

**Figure 3.1:** Component diagram showing all 8 system components and their relationships. Solid lines indicate control flow, dotted lines indicate data dependencies.

#### 3.8.2 Authentication Sequence

```mermaid
sequenceDiagram
    participant C as VPN Client
    participant X as Xray Container
    participant U as users.json
    participant N as Nginx
    participant D as Dest (google.com)
    participant I as Internet

    C->>X: TLS Handshake (Reality)
    X->>X: Extract UUID, shortId, SNI
    X->>U: Read and validate UUID
    U-->>X: User found or not found
    X->>X: Verify publicKey, shortId, SNI

    alt Valid Authentication
        X-->>C: Tunnel Established
        C->>X: Encrypted VPN Traffic
        X->>I: Decrypted Traffic
        I-->>X: Response
        X-->>C: Encrypted Response
    else Invalid Authentication
        X->>N: Fallback to fake-site
        N->>D: Proxy Request
        D-->>N: Response
        N-->>C: Fake Site Content
    end
```

**Figure 3.2:** Authentication flow sequence showing both valid VPN connection and fake-site fallback scenarios.

#### 3.8.3 Network Topology

```mermaid
graph TB
    subgraph Host
        UFW[UFW Firewall<br/>Port 443 allowed<br/>Docker forwarding enabled]
    end

    subgraph "Docker: vless_reality_net<br/>172.20.0.0/16"
        Xray[Xray Container<br/>0.0.0.0:443<br/>VLESS + Reality]
        Nginx[Nginx Container<br/>8080 internal<br/>Reverse Proxy]
    end

    subgraph "Docker: outline_net<br/>172.18.0.0/16"
        Outline[Outline VPN<br/>Isolated]
    end

    Internet[Internet] -->|Port 443| UFW
    UFW --> Xray
    Xray -->|Valid Auth| Internet
    Xray -->|Fallback| Nginx
    Nginx -->|Proxy| Internet

    Xray -.->|Isolated| Outline

    style Xray fill:#fff3e0
    style Nginx fill:#f3e5f5
    style UFW fill:#fff9c4
    style Outline fill:#eceff1
```

**Figure 3.3:** Network topology showing Docker networks, port mappings, firewall, and isolation from other VPN services.

#### 3.8.4 Deployment Architecture

```mermaid
graph TB
    subgraph "Linux Server (Ubuntu 20.04+ / Debian 10+)"
        subgraph "Docker Engine 20.10+"
            subgraph "Network: vless_reality_net"
                Xray[Xray:24.11.30<br/>Port 443<br/>VLESS + Reality]
                Nginx[Nginx:alpine<br/>Port 8080<br/>Fake-site Proxy]
            end
        end

        subgraph "Host Filesystem"
            OptVless[/opt/vless/<br/>config/ data/ logs/<br/>scripts/ fake-site/]
            UsrBin[/usr/local/bin/<br/>vless-* commands<br/>sudo accessible]
        end

        UFW[UFW Firewall<br/>/etc/ufw/]
    end

    Xray -.->|Volume Mount| OptVless
    Nginx -.->|Volume Mount| OptVless
    UsrBin -.->|Controls via<br/>docker-compose| Xray
    UsrBin -.->|Controls via<br/>docker-compose| Nginx
    UFW -.->|Protects| Xray

    style Xray fill:#fff3e0
    style Nginx fill:#f3e5f5
    style OptVless fill:#e8f5e9
    style UsrBin fill:#e3f2fd
    style UFW fill:#fff9c4
```

**Figure 3.4:** Deployment architecture showing physical distribution across Linux server, Docker engine, and host filesystem.

---

**End of Section 3**

---

## 4. Functional Requirements

This section details all functional requirements organized by category. Each requirement includes: ID, priority, description, detailed specification, acceptance criteria, and component mapping.

### 4.1 Installation and Deployment

| ID | Requirement | Priority | Acceptance Criteria | Component |
|----|-------------|----------|---------------------|-----------|
| **FR-001** | **Interactive CLI Installation** | Critical | • All parameters prompted interactively<br/>• Validation before applying each parameter<br/>• Clear error messages with actionable guidance<br/>• Cancel and retry capability<br/>• Installation completes in < 5 minutes | Installation CLI |
| **FR-002** | **Existing Installation Detection** | Critical | • Check /opt/vless/ directory existence<br/>• Detect Docker containers named vless-*<br/>• Detect Docker networks prefixed vless_*<br/>• Options: delete/update/cancel<br/>• Backup users.json before any changes | Installation CLI |
| **FR-003** | **Deployment to /opt/vless** | High | • Directory created with 755 permissions<br/>• Subdirectories created automatically<br/>• Owner: root or specified user<br/>• Structure: config/, data/, logs/, scripts/, fake-site/ | Installation CLI, Config Storage |
| **FR-004** | **Dest Site Validation** | Critical | • Menu with defaults: google.com, microsoft.com, apple.com, cloudflare.com<br/>• Custom dest input option<br/>• Validation: TLS 1.3, HTTP/2 support, SNI extraction<br/>• Validation completes in < 10 seconds<br/>• Fallback to alternative dest on failure | Installation CLI |

**FR-001 Details:**
All installation parameters (dest, port, Docker subnet) are entered through an interactive terminal interface. Each parameter includes intelligent defaults based on environment detection, real-time validation, and clear feedback. The installer detects OS version, Docker installation, UFW status, existing VPN services, and recommends optimal configuration.

**FR-002 Details:**
Before installing, the system scans for:
- `/opt/vless/` directory and contents
- Running containers: `docker ps -a | grep vless-`
- Docker networks: `docker network ls | grep vless_`

If detected, user chooses:
1. **Delete completely** - Backup users.json to /tmp/, remove all resources
2. **Update** - Preserve users.json and reality_keys.json, update configs and containers
3. **Cancel** - Exit without changes

**FR-003 Details:**
Directory structure created:
```
/opt/vless/
├── config/         (700) - Xray and Reality configuration
├── data/           (700) - User data and backups
├── logs/           (755) - Access and error logs
├── fake-site/      (755) - Nginx reverse proxy configs
├── scripts/        (755) - Management scripts
├── .env            (600) - Environment variables
└── docker-compose.yml (644) - Container orchestration
```

**FR-004 Details:**
Destination validation process:
1. Present menu: [1] google.com:443 (default), [2] www.microsoft.com:443, [3] www.apple.com:443, [4] www.cloudflare.com:443, [5] Custom
2. For selected dest: `curl -vI https://${dest} 2>&1`
3. Extract: TLS version (must be 1.3), HTTP version (prefer HTTP/2)
4. Extract SNI from certificate: `openssl s_client -servername ${dest} -connect ${dest}:443 </dev/null 2>/dev/null | openssl x509 -noout -text | grep DNS`
5. Validate SNI extraction successful
6. On failure: offer alternative dest or retry

### 4.2 User Management

| ID | Requirement | Priority | Acceptance Criteria | Component |
|----|-------------|----------|---------------------|-----------|
| **FR-005** | **User Creation** | Critical | • User added in < 6 seconds (updated for proxy support)<br/>• UUID uniqueness guaranteed<br/>• ShortId uniqueness among users<br/>• Proxy password auto-generated (16 chars)<br/>• Xray container reloaded without downtime<br/>• 8 config files saved to data/clients/{username}/ | User Management CLI |
| **FR-006** | **User Deletion** | High | • Confirmation prompt before deletion<br/>• User removed from active list<br/>• Configs archived to data/clients/archived/<br/>• Xray reload without downtime | User Management CLI |
| **FR-007** | **User Listing and Details** | High | • List: table format (name, UUID, shortId, created date)<br/>• Show: full config + QR code display<br/>• Export: generate configs for v2rayN/v2rayNG | User Management CLI |
| **FR-008** | **Scalability for 10-50 Users** | Medium | • JSON file validation on read/write<br/>• Atomic write operations (lock mechanism)<br/>• Operations complete in < 1 second for 50 users | Config Storage |

**FR-005 Details:**
Command: `vless-user add <username>`

Workflow:
1. Generate UUID: `uuidgen` (v4 format)
2. Generate shortId: `openssl rand -hex 8` (8-16 hex characters)
3. Generate proxy password: `openssl rand -base64 16` (16-character password)
4. Read `/opt/vless/config/users.json`
5. Validate username not in use
6. Append new user: `{"username": "...", "uuid": "...", "shortId": "...", "proxy_password": "...", "created": "timestamp", "enabled": true}`
7. Write updated users.json atomically
8. Update `/opt/vless/config/config.json`:
   - Add to `inbounds[0].settings.clients[]` (VLESS Reality)
   - Add to `inbounds[1].settings.accounts[]` (SOCKS5 proxy)
   - Add to `inbounds[2].settings.accounts[]` (HTTP proxy)
9. Reload Xray: `docker-compose restart xray`
10. Generate 8 client config files (see FR-020 and FR-024):
    - vless_config.json, vless_uri.txt, qrcode.png
    - socks5_config.txt, http_config.txt
    - vscode_settings.json, docker_daemon.json, bash_exports.sh
11. Display VLESS QR code and proxy credentials in terminal

**FR-006 Details:**
Command: `vless-user remove <username|uuid>`

Workflow:
1. Prompt: "Remove user {username}? [y/N]"
2. Read users.json, find and remove user entry
3. Write updated users.json
4. Update config.json - remove from clients[]
5. Move `/opt/vless/data/clients/{username}/` to `/opt/vless/data/clients/archived/{username}_{timestamp}/`
6. Reload Xray: `docker-compose restart xray`
7. Confirm: "User {username} removed"

**FR-007 Details:**
Commands:
- `vless-user list`: Table output with columns: Username | UUID | ShortId | Created | Status
- `vless-user show <username>`: Display full VLESS URI, JSON config, and QR code (rendered in terminal if supported)
- `vless-user show <username> --proxy`: Display proxy credentials (SOCKS5 and HTTP connection strings with password)
- `vless-user proxy-reset <username>`: Regenerate proxy password, update config.json, reload Xray, display new credentials
- `vless-user export <username>`: Regenerate all 8 client config files in data/clients/{username}/

**FR-008 Details:**
users.json structure:
```json
{
  "users": [
    {
      "username": "admin",
      "uuid": "12345678-1234-1234-1234-123456789012",
      "shortId": "a1b2c3d4e5f67890",
      "proxy_password": "Xy9mK3pL2wN8vQ4r",
      "created": "2025-10-01T12:00:00Z",
      "enabled": true
    }
  ],
  "metadata": {
    "version": "1.1",
    "last_modified": "2025-10-03T12:00:00Z"
  }
}
```

Atomic writes using file locking:
```bash
(
  flock -x 200
  jq '.users += [new_user]' users.json > users.json.tmp
  mv users.json.tmp users.json
) 200>/var/lock/vless-users.lock
```

### 4.3 Network Configuration

| ID | Requirement | Priority | Acceptance Criteria | Component |
|----|-------------|----------|---------------------|-----------|
| **FR-009** | **Dynamic Subnet Detection** | High | • Correctly identifies occupied subnets<br/>• Suggestion doesn't conflict with existing networks<br/>• Validates custom CIDR format<br/>• Detects old vless_reality_net for reuse | Installation CLI, Docker Network |
| **FR-010** | **Dynamic Port Selection** | High | • Accurate port availability check<br/>• Identifies process occupying port<br/>• Suggests alternatives: 8443, 2053, 2083, 2087<br/>• Validates custom port range (1024-65535) | Installation CLI |
| **FR-011** | **UFW Integration** | Critical | • Detects UFW status (active/inactive)<br/>• Parses existing rules without duplication<br/>• Adds Docker forwarding to /etc/ufw/after.rules<br/>• Adds port allow rule with comment<br/>• Applies rules without dropping connections | Installation CLI, UFW Firewall |
| **FR-012** | **Network Isolation** | High | • Docker network vless_reality_net created<br/>• Both Xray and Nginx in same network<br/>• Internet access from containers functional<br/>• Isolated from other Docker networks | Docker Network |

**FR-009 Details:**
Subnet detection workflow:
1. List existing Docker networks: `docker network ls --format '{{.Name}}'`
2. For each network: `docker network inspect {network} | jq -r '.[0].IPAM.Config[0].Subnet'`
3. Build list of occupied subnets
4. Suggest free subnet from 172.16.0.0/16 - 172.31.0.0/16 range
5. If old vless_reality_net found: "Reuse subnet 172.20.0.0/16? [Y/n]"
6. Allow custom: "Enter custom subnet (CIDR): " - validate with `ipcalc` or regex

**FR-010 Details:**
Port checking workflow:
1. Default port: 443
2. Check availability: `ss -tuln | grep :443` or `netstat -tuln | grep :443`
3. If occupied:
   - Identify process: `lsof -i :443` or `ss -tulnp | grep :443`
   - Display: "Port 443 occupied by {process_name} (PID {pid})"
   - If process is old VLESS: "Reuse port 443? [Y/n]"
   - If other process: "Port 443 unavailable. Alternatives: [1] 8443 [2] 2053 [3] 2083 [4] Custom"
4. Validate custom port: 1024 ≤ port ≤ 65535

**FR-011 Details:**
UFW configuration workflow:
1. Check status: `ufw status | grep Status`
   - If inactive: "UFW is inactive. Activate now? [y/N]" → `ufw --force enable`
2. Check existing rules: `ufw status numbered`
3. Parse for VLESS port rule: avoid duplication
4. Add rule: `ufw allow ${VLESS_PORT}/tcp comment 'VLESS Reality VPN'`
5. Check /etc/ufw/after.rules for Docker chains:
```bash
*filter
:DOCKER-USER - [0:0]
-A DOCKER-USER -j RETURN
COMMIT
```
6. If missing, append and reload: `ufw reload`
7. Test connectivity: attempt connection to port from localhost

**FR-012 Details:**
Network creation:
```bash
docker network create vless_reality_net \
  --driver bridge \
  --subnet ${DOCKER_SUBNET} \
  --opt com.docker.network.bridge.name=br-vless
```

Verification:
- `docker network inspect vless_reality_net` - check subnet matches
- `docker exec vless-reality ping -c 1 8.8.8.8` - test Internet access
- `docker network ls` - confirm vless_reality_net separate from outline_net, wireguard_net

### 4.4 Fake-site Functionality

| ID | Requirement | Priority | Acceptance Criteria | Component |
|----|-------------|----------|---------------------|-----------|
| **FR-013** | **Nginx Reverse Proxy** | High | • Nginx container starts with Xray<br/>• Proxying to dest functions correctly<br/>• Fallback from Xray configured<br/>• Browser shows legitimate site on direct access | Nginx Container |
| **FR-014** | **Xray-Nginx Fallback Integration** | Medium | • Fallback configured in Xray config<br/>• Nginx accessible via Docker network<br/>• Invalid requests redirect correctly | Xray Container, Nginx Container |

**FR-013 Details:**
Nginx configuration (`/opt/vless/fake-site/default.conf`):
```nginx
server {
    listen 8080;
    server_name _;

    location / {
        proxy_pass https://${REALITY_DEST};
        proxy_ssl_server_name on;
        proxy_ssl_name ${REALITY_DEST};

        proxy_set_header Host ${REALITY_DEST};
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_ssl_verify off;
        proxy_buffering on;
        proxy_cache_valid 200 1h;
    }
}
```

Behavior:
- Browser accessing `https://server-ip:443` → Xray detects non-VPN → forwards to Nginx:8080 → Nginx proxies to google.com → browser sees Google homepage
- Port scanner accessing server → sees legitimate HTTPS site → no VPN fingerprint

**FR-014 Details:**
Xray fallback configuration (in config.json):
```json
{
  "inbounds": [{
    "protocol": "vless",
    "settings": {
      "clients": [...],
      "decryption": "none",
      "fallbacks": [
        {
          "dest": "nginx:8080"
        }
      ]
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {...}
    }
  }]
}
```

Testing:
- Valid VLESS client → establishes tunnel
- `curl https://server-ip:443` → receives proxied google.com response
- `nmap -p 443 server-ip` → sees HTTPS service, no VPN signature

### 4.5 Xray Configuration

| ID | Requirement | Priority | Acceptance Criteria | Component |
|----|-------------|----------|---------------------|-----------|
| **FR-015** | **VLESS + Reality Config Generation** | Critical | • config.json is valid JSON<br/>• Xray starts without errors<br/>• Reality handshake succeeds<br/>• Client can connect and tunnel traffic | Xray Container |
| **FR-016** | **Reality Key Generation** | Critical | • Keys generated via `xray x25519`<br/>• Private key permissions: 600<br/>• Public key available for export<br/>• Keys persisted to reality_keys.json | Installation CLI, Config Storage |

**FR-015 Details:**
config.json structure:
```json
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "inbounds": [{
    "port": 443,
    "protocol": "vless",
    "settings": {
      "clients": [],
      "decryption": "none",
      "fallbacks": [{"dest": "nginx:8080"}]
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "show": false,
        "dest": "google.com:443",
        "xver": 0,
        "serverNames": ["google.com", "www.google.com"],
        "privateKey": "...",
        "shortIds": ["", "a1b2c3d4"]
      }
    },
    "sniffing": {
      "enabled": true,
      "destOverride": ["http", "tls"]
    }
  }],
  "outbounds": [{
    "protocol": "freedom",
    "tag": "direct"
  }]
}
```

Validation:
- `jq . config.json` - verify JSON syntax
- `xray run -test -c config.json` - test configuration
- `docker logs vless-reality` - check for startup errors

**FR-016 Details:**
Key generation:
```bash
# Inside Xray container or using xray binary
xray x25519

# Output:
# Private key: SChVrmR...
# Public key: kLWZcz...
```

Stored in `/opt/vless/config/reality_keys.json`:
```json
{
  "private_key": "SChVrmR...",
  "public_key": "kLWZcz...",
  "generated": "2025-10-01T12:00:00Z"
}
```

Security:
- `chmod 600 /opt/vless/config/reality_keys.json`
- Private key NEVER shared with clients
- Public key distributed in client configs
- Keys backed up during updates

### 4.6 Docker Compose Orchestration

| ID | Requirement | Priority | Acceptance Criteria | Component |
|----|-------------|----------|---------------------|-----------|
| **FR-017** | **Multi-Container Setup** | Critical | • Both containers start successfully<br/>• Environment variables loaded from .env<br/>• Volumes mounted correctly<br/>• Network created automatically<br/>• Restart policy: unless-stopped | Docker Compose |

**FR-017 Details:**
docker-compose.yml:
```yaml
version: '3.8'

services:
  xray:
    image: teddysun/xray:24.11.30
    container_name: vless-reality
    restart: unless-stopped
    ports:
      - "${VLESS_PORT}:443"
    volumes:
      - ./config:/etc/xray:ro
      - ./logs:/var/log/xray:rw
    networks:
      - vless_reality_net
    environment:
      - TZ=UTC
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  nginx:
    image: nginx:alpine
    container_name: vless-fake-site
    restart: unless-stopped
    volumes:
      - ./fake-site:/etc/nginx/conf.d:ro
    networks:
      - vless_reality_net
    environment:
      - TZ=UTC
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

networks:
  vless_reality_net:
    external: true
```

.env file:
```bash
VLESS_PORT=443
DOCKER_SUBNET=172.20.0.0/16
REALITY_DEST=google.com
TZ=UTC
```

Operations:
- Start: `docker-compose -f /opt/vless/docker-compose.yml up -d`
- Stop: `docker-compose -f /opt/vless/docker-compose.yml down`
- Restart: `docker-compose -f /opt/vless/docker-compose.yml restart xray`
- Logs: `docker-compose -f /opt/vless/docker-compose.yml logs -f xray`

### 4.7 Operations and Management

| ID | Requirement | Priority | Acceptance Criteria | Component |
|----|-------------|----------|---------------------|-----------|
| **FR-018** | **Service Management Scripts** | High | • All commands work from any directory<br/>• Commands installed in /usr/local/bin/<br/>• Status shows container state<br/>• Logs with tail and follow options | Service Management CLI |
| **FR-019** | **Clean Uninstallation** | Medium | • Containers fully removed<br/>• User data backed up to /tmp/<br/>• /opt/vless/ directory cleaned<br/>• Confirmation before deletion | Service Management CLI |

**FR-018 Details:**
CLI Commands:

```bash
# Installation
vless-install          # Interactive installation wizard

# User Management
vless-user add <name>           # Create user (VLESS + SOCKS5 + HTTP configs)
vless-user remove <name>        # Delete user
vless-user list                 # List all users
vless-user show <name>          # Show user details + QR
vless-user show <name> --proxy  # Show proxy credentials and configs
vless-user proxy-reset <name>   # Regenerate proxy password
vless-user export <name>        # Export all configs (8 files)

# Service Control
vless-start            # Start containers
vless-stop             # Stop containers
vless-restart          # Restart containers
vless-status           # Show status
vless-logs [service]   # View logs (default: xray)
vless-update           # Update Docker images
vless-uninstall        # Remove system
```

Implementation:
- Symlinks in /usr/local/bin/ pointing to /opt/vless/scripts/
- All scripts check permissions and use sudo if needed
- Status output:
```
VLESS Reality VPN Status
========================
Xray Container:   RUNNING (uptime: 2d 5h)
Nginx Container:  RUNNING (uptime: 2d 5h)
Network:          vless_reality_net (172.20.0.0/16)
VLESS Port:       443 (LISTENING)
SOCKS5 Proxy:     127.0.0.1:1080 (ACTIVE)
HTTP Proxy:       127.0.0.1:8118 (ACTIVE)
Users:            5 active
```

**FR-019 Details:**
Uninstallation workflow:
```bash
vless-uninstall

# Prompt:
# This will remove VLESS Reality VPN system.
# User data will be backed up to /tmp/vless_backup_TIMESTAMP/
# Continue? [y/N]

# Actions:
1. docker-compose down (stop and remove containers)
2. mkdir -p /tmp/vless_backup_$(date +%s)/
3. cp -r /opt/vless/config/users.json /tmp/vless_backup_*/
4. cp -r /opt/vless/config/reality_keys.json /tmp/vless_backup_*/
5. cp -r /opt/vless/data/clients/ /tmp/vless_backup_*/
6. docker network rm vless_reality_net
7. rm -rf /opt/vless/
8. rm /usr/local/bin/vless-*
9. echo "Backup saved to /tmp/vless_backup_*/"
10. echo "UFW rules remain (manual removal: ufw delete allow ${VLESS_PORT}/tcp)"
```

### 4.8 Client Configuration Generation

| ID | Requirement | Priority | Acceptance Criteria | Component |
|----|-------------|----------|---------------------|-----------|
| **FR-020** | **Multi-Format Client Configs** | High | • JSON config valid for v2rayN/v2rayNG<br/>• VLESS URI correctly formatted<br/>• QR code scannable by mobile clients<br/>• Configs saved to data/clients/{username}/ | User Management CLI |

**FR-020 Details:**
Generated files for each user in `/opt/vless/data/clients/{username}/`:

**1. config.json** (v2rayN/v2rayNG format):
```json
{
  "outbounds": [{
    "protocol": "vless",
    "settings": {
      "vnext": [{
        "address": "SERVER_IP",
        "port": 443,
        "users": [{
          "id": "UUID",
          "encryption": "none",
          "flow": "xtls-rprx-vision"
        }]
      }]
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "show": false,
        "fingerprint": "chrome",
        "serverName": "google.com",
        "publicKey": "PUBLIC_KEY",
        "shortId": "SHORT_ID",
        "spiderX": "/"
      }
    }
  }]
}
```

**2. uri.txt** (VLESS URI):
```
vless://UUID@SERVER_IP:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=google.com&fp=chrome&pbk=PUBLIC_KEY&sid=SHORT_ID&type=tcp&headerType=none#username
```

**3. qrcode.png** (QR code):
```bash
qrencode -o qrcode.png -t PNG -s 10 < uri.txt
```

Terminal QR display (if supported):
```bash
qrencode -t ANSIUTF8 < uri.txt
```

### 4.9 Security and Accessibility

| ID | Requirement | Priority | Acceptance Criteria | Component |
|----|-------------|----------|---------------------|-----------|
| **FR-021** | **Sudo Accessibility for Non-Root Users** | High | • Symlinks created with 755 permissions<br/>• Scripts auto-escalate with sudo when needed<br/>• Non-root users can execute vless-* via sudo<br/>• Documentation includes sudo examples | Installation CLI, All CLI scripts |

**FR-021 Details:**
Implementation in all CLI scripts:

```bash
#!/bin/bash
# vless-user script

# Auto-escalate to sudo if not root
if [ "$EUID" -ne 0 ]; then
    exec sudo "$0" "$@"
fi

# Rest of script...
```

Symlink creation during installation:
```bash
chmod 755 /opt/vless/scripts/*.sh
ln -sf /opt/vless/scripts/install.sh /usr/local/bin/vless-install
ln -sf /opt/vless/scripts/user-manager.sh /usr/local/bin/vless-user
ln -sf /opt/vless/scripts/service-manager.sh /usr/local/bin/vless-start
chmod 755 /usr/local/bin/vless-*
```

Usage examples for non-root users:
```bash
# Regular user can run:
sudo vless-user add john
sudo vless-user list
sudo vless-start
sudo vless-status

# Or scripts auto-escalate:
vless-user add john  # Internally calls: exec sudo "$0" "$@"
```

Optional sudoers configuration for passwordless execution (installer offers):
```bash
# /etc/sudoers.d/vless
%sudo ALL=(ALL) NOPASSWD: /usr/local/bin/vless-*
```

Security considerations:
- Scripts validate inputs to prevent command injection
- Sensitive operations (key generation, config modification) logged
- File permissions enforced: configs 600, scripts 755

---

### 4.10 Proxy Server Support

| ID | Requirement | Priority | Acceptance Criteria | Component |
|----|-------------|----------|---------------------|-----------|
| **FR-022** | **SOCKS5 Proxy Inbound** | High | • Listen on 127.0.0.1:1080 only<br/>• Username/password authentication required<br/>• Credentials synced with users.json<br/>• TCP traffic proxied successfully<br/>• UDP disabled<br/>• Accessible only through VPN tunnel | Xray Container |
| **FR-023** | **HTTP Proxy Inbound** | High | • Listen on 127.0.0.1:8118 only<br/>• Username/password authentication required<br/>• Credentials synced with users.json<br/>• HTTP/HTTPS traffic proxied successfully<br/>• Compatible with VSCode, Docker, curl/wget<br/>• Accessible only through VPN tunnel | Xray Container |
| **FR-024** | **Proxy Configuration Management** | High | • Auto-generate proxy password on user creation<br/>• Export proxy configs (SOCKS5, HTTP, VSCode, Docker, Bash)<br/>• Proxy password reset command available<br/>• All 8 config files created per user<br/>• Credentials displayed in user output | User Management CLI |

**FR-022 Details: SOCKS5 Proxy**

Xray Configuration:
```json
{
  "tag": "socks5-proxy",
  "listen": "127.0.0.1",
  "port": 1080,
  "protocol": "socks",
  "settings": {
    "auth": "password",
    "accounts": [
      {
        "user": "username",
        "pass": "AUTO_GENERATED_16_CHAR_PASSWORD"
      }
    ],
    "udp": false,
    "ip": "127.0.0.1"
  },
  "sniffing": {
    "enabled": true,
    "destOverride": ["http", "tls"]
  }
}
```

Testing:
```bash
# After connecting to VLESS VPN:
curl --socks5 username:password@127.0.0.1:1080 https://ifconfig.me
# Should return server's public IP
```

**FR-023 Details: HTTP Proxy**

Xray Configuration:
```json
{
  "tag": "http-proxy",
  "listen": "127.0.0.1",
  "port": 8118,
  "protocol": "http",
  "settings": {
    "accounts": [
      {
        "user": "username",
        "pass": "AUTO_GENERATED_16_CHAR_PASSWORD"
      }
    ],
    "allowTransparent": false,
    "userLevel": 0
  },
  "sniffing": {
    "enabled": true,
    "destOverride": ["http", "tls"]
  }
}
```

Testing:
```bash
# After connecting to VLESS VPN:
export http_proxy="http://username:password@127.0.0.1:8118"
export https_proxy="http://username:password@127.0.0.1:8118"
curl https://ifconfig.me
# Should return server's public IP
```

**FR-024 Details: Configuration Management**

Enhanced User Creation Workflow:
```bash
sudo vless-user add john

# Generates:
# 1. UUID (for VLESS)
# 2. shortId (for VLESS)
# 3. proxy_password: openssl rand -base64 16 → "Kf8Lp2Mq9Xz3RtY5"
#
# Updates users.json:
# {
#   "username": "john",
#   "uuid": "...",
#   "shortId": "...",
#   "proxy_password": "Kf8Lp2Mq9Xz3RtY5",  ← NEW
#   ...
# }
#
# Updates config.json:
# - VLESS clients[] array
# - SOCKS5 accounts[] array  ← NEW
# - HTTP accounts[] array    ← NEW
#
# Creates 8 config files:
# 1. vless_config.json
# 2. vless_uri.txt
# 3. qrcode.png
# 4. socks5_config.txt       ← NEW
# 5. http_config.txt         ← NEW
# 6. vscode_settings.json    ← NEW
# 7. docker_daemon.json      ← NEW
# 8. bash_exports.sh         ← NEW
```

Generated File Examples:

**socks5_config.txt:**
```
SOCKS5 Proxy Configuration
Server: 127.0.0.1:1080
Username: john
Password: Kf8Lp2Mq9Xz3RtY5
URL: socks5://john:Kf8Lp2Mq9Xz3RtY5@127.0.0.1:1080

IMPORTANT: Only accessible through VLESS VPN tunnel
```

**http_config.txt:**
```
HTTP Proxy Configuration
Server: 127.0.0.1:8118
Username: john
Password: Kf8Lp2Mq9Xz3RtY5
URL: http://john:Kf8Lp2Mq9Xz3RtY5@127.0.0.1:8118

IMPORTANT: Only accessible through VLESS VPN tunnel
```

**vscode_settings.json:**
```json
{
  "http.proxy": "http://john:Kf8Lp2Mq9Xz3RtY5@127.0.0.1:8118",
  "http.proxyStrictSSL": false,
  "http.proxySupport": "on"
}
```

**docker_daemon.json:**
```json
{
  "proxies": {
    "default": {
      "httpProxy": "http://john:Kf8Lp2Mq9Xz3RtY5@127.0.0.1:8118",
      "httpsProxy": "http://john:Kf8Lp2Mq9Xz3RtY5@127.0.0.1:8118",
      "noProxy": "localhost,127.0.0.1"
    }
  }
}
```

**bash_exports.sh:**
```bash
#!/bin/bash
export http_proxy="http://john:Kf8Lp2Mq9Xz3RtY5@127.0.0.1:8118"
export https_proxy="http://john:Kf8Lp2Mq9Xz3RtY5@127.0.0.1:8118"
export HTTP_PROXY="$http_proxy"
export HTTPS_PROXY="$https_proxy"
export no_proxy="localhost,127.0.0.1,::1"
```

Proxy Password Reset:
```bash
sudo vless-user proxy-reset john
# Generates new password, updates users.json and config.json
# User must update proxy configs on client side
```

Security Considerations:
- Proxy passwords stored in plaintext in users.json (acceptable - file is 600 perms, root-only)
- Proxies bound to localhost only - no direct internet exposure
- Access requires VLESS VPN connection - provides encryption layer
- Individual credentials per user - access control and auditing
- UFW: Ports 1080, 8118 NOT exposed to internet (only port 443 for VLESS)

---

**End of Section 4**

---

## 5. Non-Functional Requirements

Non-functional requirements define the quality attributes and operational constraints of the system. These requirements are measurable and verifiable through specific metrics.

### 5.1 NFR Summary Table

| Category | Metric | Target | Measurement Method | Priority |
|----------|--------|--------|-------------------|----------|
| **Performance** | Installation time | < 5 minutes | Time from script start to first user ready | Critical |
| **Performance** | User creation time | < 5 seconds | Time from command to QR code display | Critical |
| **Performance** | Container startup | < 10 seconds | Time for both containers to reach healthy state | High |
| **Performance** | Config reload | < 3 seconds | Xray container restart time | High |
| **Reliability** | Service uptime | 99.9% | Container uptime monitoring | Critical |
| **Reliability** | Restart policy | unless-stopped | Docker restart policy configuration | Critical |
| **Reliability** | Config validation | 100% | Validate before applying changes | Critical |
| **Security** | File permissions (configs) | 600 | `ls -la /opt/vless/config/*.json` | Critical |
| **Security** | Directory permissions | 700 | `ls -la /opt/vless/config/` | Critical |
| **Security** | Script permissions | 755 | `ls -la /usr/local/bin/vless-*` | High |
| **Security** | Container user | non-root | Docker inspect user parameter | High |
| **Security** | Key storage security | Encrypted at rest (filesystem-level) | chmod 600, root ownership | Critical |
| **Security** | UFW integration | enabled | `ufw status` shows active | High |
| **Usability** | CLI intuitiveness | Self-explanatory commands | User testing, < 2 docs lookups per task | High |
| **Usability** | Error messages | Actionable guidance | Include fix suggestions in errors | High |
| **Usability** | Installation guidance | Step-by-step prompts | Interactive with validation | Critical |
| **Usability** | QR code display | Terminal rendering | qrencode ANSI output support | Medium |
| **Maintainability** | Code structure | Modular | Separate files for install/user/service mgmt | High |
| **Maintainability** | Logging | Structured | JSON logs with severity levels | Medium |
| **Maintainability** | Documentation | Comprehensive | All functions have docstrings | Medium |
| **Maintainability** | Script readability | Comments + clear naming | shellcheck score > 90% | Medium |
| **Compatibility** | OS support | Ubuntu 20.04+, Debian 10+ | Tested on LTS versions | Critical |
| **Compatibility** | Docker version | 20.10+ | Version check in installer | Critical |
| **Compatibility** | Docker Compose | v2.0+ | docker-compose --version check | Critical |
| **Compatibility** | Xray client | v1.8+ | v2rayN, v2rayNG, v2rayA | High |
| **Compatibility** | Architecture | x86_64, ARM64 | Docker multi-arch images | Medium |
| **Proxy Performance** | User creation with proxy | < 6 seconds | Time from command to proxy configs displayed | High |
| **Proxy Performance** | SOCKS5 connection handshake | < 200ms | Time to establish proxy connection | Medium |
| **Proxy Performance** | HTTP connection handshake | < 300ms | Time to establish proxy connection | Medium |
| **Proxy Security** | Proxy port binding | localhost only | `ss -tulnp \| grep -E '(1080\|8118)'` shows 127.0.0.1 | Critical |
| **Proxy Security** | Proxy authentication | required | Connection without credentials fails | Critical |
| **Proxy Security** | External proxy access | blocked | telnet from external host to 1080/8118 fails | Critical |
| **Proxy Usability** | Proxy config files generated | 8 files per user | All formats (SOCKS5, HTTP, VSCode, Docker, Bash) created | High |

**Table 5.1:** Complete non-functional requirements matrix with targets and verification methods (updated with proxy metrics).

### 5.2 Performance Requirements

**NFR-001: Operation Performance**

Performance targets ensure rapid deployment and responsive user management:

- **Installation Time: < 5 minutes**
  - Measurement: Time from `./vless-install.sh` start to "Installation complete" message
  - Includes: Environment detection, dependency installation, key generation, config creation, container deployment, first user creation
  - Baseline: Clean Ubuntu 22.04 LTS with internet connection (10 Mbps)
  - Excludes: Docker installation time if not present (add 2-3 minutes)

- **User Creation: < 6 seconds** (updated from < 5 seconds to include proxy setup)
  - Measurement: Time from `vless-user add username` to QR code and proxy configs display
  - Includes: UUID generation, shortId generation, proxy password generation, users.json update, config.json update (3 inbounds), Xray reload, client config generation (8 files)
  - Success criteria: Consistent performance up to 50 users
  - Note: +1 second overhead for proxy password generation and additional config file creation

- **Container Startup: < 10 seconds**
  - Measurement: `docker-compose up -d` to all containers showing "healthy" status
  - Includes: Image pull (if not cached), network creation, volume mounts, health checks
  - Verification: `docker ps` shows both containers running

- **Config Reload: < 3 seconds**
  - Measurement: `docker-compose restart xray` completion time
  - Impact: Brief interruption to active connections (graceful shutdown)
  - Verification: New clients can connect immediately after restart

### 5.3 Reliability Requirements

**NFR-002: Service Reliability**

Reliability targets ensure stable, uninterrupted VPN service:

- **Uptime: 99.9%**
  - Target: 99.9% availability (≈ 8.76 hours downtime per year, 43.8 minutes per month)
  - Measurement: Container uptime tracking via `docker ps` or monitoring tools
  - Excludes: Planned maintenance windows
  - Failure modes:
    - Container crash → Docker restart policy (unless-stopped) auto-recovers
    - Host reboot → Containers auto-start
    - Config error → Validation prevents deployment

- **Restart Policy: unless-stopped**
  - Configuration: `restart: unless-stopped` in docker-compose.yml
  - Behavior: Container restarts after crashes UNLESS manually stopped by admin
  - Verification: `docker inspect vless-reality | grep RestartPolicy`

- **Configuration Validation: 100%**
  - All config changes validated BEFORE application
  - Validation steps:
    1. JSON syntax check: `jq . config.json`
    2. Xray config test: `xray run -test -c config.json`
    3. Schema validation for users.json
    4. Port availability check before deployment
  - Rollback: Keep previous working config for automatic rollback on failure

**Failure Recovery:**
```
Config Change Requested
    → Backup current config
    → Validate new config
    → If VALID: Apply → Test connectivity → If OK: Commit
    → If INVALID: Reject → Keep current config → Log error + notify admin
```

### 5.4 Security Requirements

**NFR-003: Security Posture**

Security targets protect sensitive data and prevent unauthorized access:

- **File Permissions: 600 (configs), 700 (directories), 755 (scripts)**
  - `/opt/vless/config/`: 700 (owner: root)
  - `/opt/vless/config/config.json`: 600
  - `/opt/vless/config/users.json`: 600
  - `/opt/vless/config/reality_keys.json`: 600
  - `/opt/vless/scripts/*.sh`: 755 (executable by all, writable by root)
  - `/usr/local/bin/vless-*`: 755 (sudo accessible)
  - Verification: `find /opt/vless -type f -ls | awk '{print $3, $11}'`

- **Container User: non-root**
  - Xray container: runs as `nobody` user (UID 65534)
  - Nginx container: runs as `nginx` user
  - Verification: `docker exec vless-reality whoami`
  - Rationale: Limit blast radius of container compromise

- **Key Storage Security:**
  - Private key NEVER transmitted over network
  - Private key readable only by root
  - Public key can be distributed freely
  - Keys backed up during updates with same permissions
  - Optional: Encrypt /opt/vless/ partition with LUKS

- **UFW Integration:**
  - UFW active and enabled: `ufw status` shows "Status: active"
  - Only necessary ports exposed: ${VLESS_PORT}/tcp
  - Docker forwarding configured correctly
  - Default policy: deny incoming, allow outgoing
  - Verification: `ufw status numbered`

**Security Hardening Checklist:**
```
☐ File permissions enforced (600/700/755)
☐ UFW active with minimal rules
☐ Docker containers run as non-root
☐ Private keys never in client configs
☐ Sudo configuration for non-root access
☐ Input validation in all scripts
☐ Log all sensitive operations
☐ Regular security updates applied
```

### 5.5 Usability Requirements

**NFR-004: User Experience**

Usability targets ensure the system is approachable for system administrators:

- **CLI Intuitiveness: Self-explanatory commands**
  - Command naming: Clear, consistent prefix (`vless-*`)
  - Help text: Available for all commands (`vless-user --help`)
  - Examples: Included in help output
  - Success metric: Users complete common tasks without documentation in < 80% of cases
  - Testing: 5 system admins (varied Linux experience) attempt installation and user creation

- **Error Messages: Actionable guidance**
  - Bad example: "Error: Port unavailable"
  - Good example: "Error: Port 443 is occupied by nginx (PID 1234). Options: [1] Use alternative port 8443 [2] Stop nginx [3] Cancel"
  - All errors include:
    - Clear description of problem
    - Root cause (if determinable)
    - Suggested fixes with commands
    - Relevant troubleshooting commands
  - Example error output:
```
ERROR: Reality destination validation failed
Reason: Unable to extract SNI from google.com:443
Details: curl returned exit code 6 (Could not resolve host)

Possible causes:
  - DNS resolution issue
  - Firewall blocking outbound HTTPS
  - Dest site temporarily unavailable

Suggestions:
  1. Check DNS: dig google.com
  2. Test connectivity: curl -vI https://google.com
  3. Try alternative dest: [1] microsoft.com [2] apple.com
```

- **Installation Guidance: Step-by-step interactive prompts**
  - Progress indicator: "Step 3/7: Configuring UFW"
  - Current status: What's happening now
  - Next step preview: What will happen next
  - Validation results: Immediate feedback on input
  - Estimated time: "Installing Docker (2-3 minutes)..."

**Usability Metrics:**
- Time to first successful installation: < 10 minutes (including learning)
- Command memorability: Users recall vless-user add syntax after 1 use
- Error recovery: Users resolve 70% of errors without external help

### 5.6 Maintainability Requirements

**NFR-005: Code and Operational Maintainability**

Maintainability targets ensure long-term system health:

- **Code Structure: Modular design**
  - Separate scripts:
    - `install.sh` - Installation logic
    - `user-manager.sh` - User CRUD operations
    - `service-manager.sh` - Service control
    - `common-functions.sh` - Shared utilities (logging, validation, color output)
  - Function size: < 50 lines per function
  - Single Responsibility Principle: Each function does one thing
  - Verification: `wc -l` per function, code review

- **Logging: Structured and informative**
  - Log levels: DEBUG, INFO, WARN, ERROR, CRITICAL
  - Log format: `YYYY-MM-DD HH:MM:SS [LEVEL] component: message`
  - Rotation: Docker JSON logs (max 10MB, 3 files)
  - Sensitive data: Never log private keys, UUIDs in plain text (hash or mask)
  - Example:
```
2025-10-01 12:00:00 [INFO] install: Starting VLESS Reality installation
2025-10-01 12:00:05 [INFO] install: Detected OS: Ubuntu 22.04 LTS
2025-10-01 12:00:10 [WARN] install: Port 443 occupied by nginx (PID 1234)
2025-10-01 12:00:15 [INFO] install: User selected alternative port: 8443
2025-10-01 12:05:00 [INFO] install: Installation completed successfully
```

- **Documentation: Comprehensive inline and external**
  - All bash functions: Header comment with purpose, parameters, return values
  - Complex logic: Inline comments explaining WHY, not WHAT
  - README.md: Installation, usage, troubleshooting
  - ARCHITECTURE.md: System design, component interactions
  - Example function documentation:
```bash
#######################################
# Create new VPN user with automatic config generation
# Arguments:
#   $1 - username (alphanumeric, no spaces)
# Returns:
#   0 if successful, 1 on error
# Outputs:
#   VLESS URI and QR code to stdout
#   Error messages to stderr
#######################################
function user_create() {
  local username="$1"
  # Implementation...
}
```

- **Script Quality: Shellcheck compliance**
  - Target: Shellcheck score > 90% (minimal warnings)
  - Best practices: Quote variables, check exit codes, use local variables
  - Verification: `shellcheck -x *.sh`

**Maintainability Metrics:**
- New developer onboarding: Can add new user management feature in < 4 hours
- Bug fix time: Average < 2 hours from report to fix
- Code review: 100% of changes reviewed before merge

### 5.7 Compatibility Requirements

**NFR-006: Platform and Client Compatibility**

Compatibility targets ensure broad deployment and client support:

- **Operating System Support:**
  - **Primary:** Ubuntu 20.04 LTS, 22.04 LTS, 24.04 LTS
  - **Secondary:** Debian 10 (Buster), 11 (Bullseye), 12 (Bookworm)
  - **Testing:** Fresh installations on all supported versions
  - **Architecture:** x86_64 (primary), ARM64 (secondary)
  - **Not supported:** CentOS, RHEL, Fedora (different firewall: firewalld vs UFW)

- **Docker Requirements:**
  - **Docker Engine:** 20.10.0+ (required for compose v2 syntax)
  - **Docker Compose:** v2.0.0+ (required for `docker compose` subcommand)
  - **Verification:**
```bash
docker --version | grep -E "2[0-9]\.[0-9]+\.[0-9]+"  # Docker 20+
docker compose version | grep -E "v2\.[0-9]+\.[0-9]+"  # Compose v2+
```

- **Client Compatibility:**
  - **Windows:** v2rayN v6.0+
  - **Android:** v2rayNG v1.8+
  - **iOS:** Shadowrocket, Streisand (Reality support required)
  - **Linux:** v2rayA, Qv2ray with Reality plugin
  - **macOS:** V2Box, Qv2ray
  - **Config format:** VLESS URI (vless://) and JSON (Xray core format)
  - **Testing:** QR codes scan successfully on all platforms

- **Network Environment:**
  - **Firewall:** UFW required (iptables-based)
  - **IPv6:** Optional, system works with IPv4 only
  - **NAT:** Works behind NAT (port forwarding required)
  - **Cloud providers:** Tested on AWS EC2, DigitalOcean Droplets, Vultr VPS, Linode

**Compatibility Matrix:**

| Component | Minimum Version | Recommended Version | Verified |
|-----------|----------------|---------------------|----------|
| Ubuntu | 20.04 LTS | 22.04 LTS | ✓ |
| Debian | 10 (Buster) | 11 (Bullseye) | ✓ |
| Docker Engine | 20.10.0 | 24.0.0+ | ✓ |
| Docker Compose | v2.0.0 | v2.20.0+ | ✓ |
| Xray Core | 1.8.0 | 1.8.0+ (teddysun/xray:24.11.30) | ✓ |
| v2rayN (Windows) | 6.0 | Latest | ✓ |
| v2rayNG (Android) | 1.8.0 | Latest | ✓ |
| UFW | System default | System default | ✓ |

**Table 5.2:** Compatibility matrix showing minimum and recommended versions for all components.

### 5.8 Scalability Constraints

While this system is designed for **10-50 concurrent users**, scalability constraints are documented:

| Metric | 10 Users | 50 Users | 100+ Users |
|--------|----------|----------|------------|
| users.json file size | ~2 KB | ~10 KB | ~20 KB (Still manageable) |
| config.json file size | ~5 KB | ~20 KB | ~40 KB (Still manageable) |
| User add operation | < 1 sec | < 3 sec | < 5 sec (Slower, but acceptable) |
| Memory usage (Xray) | ~50 MB | ~80 MB | ~150 MB (Linear scaling) |
| File locking contention | None | Negligible | Possible delays (JSON-based limitation) |

**Beyond 50 users:**
- Consider database backend (SQLite, PostgreSQL) instead of JSON files
- Implement connection pooling
- Add caching layer for user lookups
- Monitor system resources and scale vertically (more RAM/CPU)

**Current design trade-offs:**
- ✅ Simplicity: JSON files easy to backup, inspect, edit manually
- ✅ No dependencies: No database server required
- ❌ Scalability: Limited to ~50 users before performance degrades
- ❌ Concurrency: File locking can cause brief delays under high concurrent user operations

---

**End of Section 5**

---

## 6. User Workflows

### 6.1 Initial Installation Workflow

**Prerequisites:** Fresh Ubuntu 20.04+ or Debian 10+ server, root/sudo access, internet connection

**Steps:**

1. Clone repository and run installer: `git clone <repo_url> && cd vless && sudo ./install.sh` (installer creates `/opt/vless` during installation)
2. Select destination site (google.com, microsoft.com, apple.com, cloudflare.com, or custom)
3. Validate destination (TLS 1.3, HTTP/2, SNI extraction)
4. Select port (default: 443, auto-detect conflicts)
5. Select Docker subnet (auto-detect existing networks)
6. System installs dependencies, generates Reality keys, creates configs, deploys containers
7. First admin user created automatically with QR code
8. Installation complete (3-5 minutes total)

**Installation Flowchart:**

```mermaid
flowchart TD
    Start([Clone repository & cd vless]) --> CheckRoot{Root/Sudo?}
    CheckRoot -->|No| Error1[Error: Requires root]
    CheckRoot -->|Yes| DetectOS[Detect OS]
    DetectOS --> CheckDocker{Docker Installed?}
    CheckDocker -->|No| InstallDocker[Install Docker]
    CheckDocker -->|Yes| CheckOld{Old Installation?}
    InstallDocker --> CheckOld
    CheckOld -->|Yes| Backup[Backup users.json]
    CheckOld -->|No| PromptDest[Select dest site]
    Backup --> PromptDest
    PromptDest --> ValidateDest{Valid?}
    ValidateDest -->|No| PromptDest
    ValidateDest -->|Yes| CheckPort[Check Port 443]
    CheckPort --> PromptPort[Confirm Port]
    PromptPort --> CheckSubnet[Scan Subnets]
    CheckSubnet --> PromptSubnet[Select Subnet]
    PromptSubnet --> GenKeys[Generate Keys]
    GenKeys --> CreateConfigs[Create Configs]
    CreateConfigs --> ConfigUFW[Configure UFW]
    ConfigUFW --> Deploy[Deploy Containers]
    Deploy --> CreateUser[Create Admin]
    CreateUser --> End([Display QR Code])
```

### 6.2 User Management Workflows

**Add User:** `sudo vless-user add <username>` → UUID + shortId + proxy password generated → Config updated (3 inbounds) → Xray reloaded → 8 config files created → QR code and proxy credentials displayed (< 6 sec)

**List Users:** `sudo vless-user list` → Table: username, UUID (first 8), shortId, created, status

**Show User:** `sudo vless-user show <username>` → Full VLESS config + QR code + file locations

**Show Proxy:** `sudo vless-user show <username> --proxy` → SOCKS5 and HTTP proxy credentials + connection strings

**Reset Proxy Password:** `sudo vless-user proxy-reset <username>` → New password generated → Config updated → New credentials displayed

**Remove User:** `sudo vless-user remove <username>` → Confirmation → User removed → Config archived

### 6.3 Service Management Workflows

**Check Status:** `sudo vless-status` → Container status, uptime, port, user count, recent logs

**Restart:** `sudo vless-restart` → Graceful restart of Xray and Nginx containers

**View Logs:** `sudo vless-logs [-f] [-n N] [nginx]` → Follow logs, tail N lines, specify service

**Update:** `sudo vless-update` → Pull new Docker images → Recreate containers → Preserve user data

**Uninstall:** `sudo vless-uninstall` → Backup to /tmp/ → Remove containers, network, files → UFW rules remain (manual removal)

---

## 7. Configuration Specifications

### 7.1 Xray config.json

**Complete configuration with VLESS Reality + SOCKS5 + HTTP proxy:**

```json
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "inbounds": [
    {
      "tag": "vless-reality",
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "UUID",
            "flow": "xtls-rprx-vision",
            "email": "username"
          }
        ],
        "decryption": "none",
        "fallbacks": [{"dest": "nginx:8080"}]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "google.com:443",
          "xver": 0,
          "serverNames": ["google.com", "www.google.com"],
          "privateKey": "PRIVATE_KEY",
          "shortIds": ["", "shortId1", "shortId2"]
        }
      },
      "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
    },
    {
      "tag": "socks5-proxy",
      "listen": "127.0.0.1",
      "port": 1080,
      "protocol": "socks",
      "settings": {
        "auth": "password",
        "accounts": [
          {
            "user": "username",
            "pass": "AUTO_GENERATED_16_CHAR_PASSWORD"
          }
        ],
        "udp": false,
        "ip": "127.0.0.1"
      },
      "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
    },
    {
      "tag": "http-proxy",
      "listen": "127.0.0.1",
      "port": 8118,
      "protocol": "http",
      "settings": {
        "accounts": [
          {
            "user": "username",
            "pass": "AUTO_GENERATED_16_CHAR_PASSWORD"
          }
        ],
        "allowTransparent": false,
        "userLevel": 0
      },
      "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
    }
  ],
  "outbounds": [
    {"protocol": "freedom", "tag": "direct"}
  ]
}
```

**Key Configuration Notes:**
- **VLESS Reality** (port 443): Public-facing, 0.0.0.0 binding (default), Reality protocol
- **SOCKS5 Proxy** (port 1080): Localhost only (127.0.0.1), password authentication, TCP only
- **HTTP Proxy** (port 8118): Localhost only (127.0.0.1), password authentication
- **Proxy Access**: Only accessible through established VLESS VPN tunnel
- **Authentication**: Same username, same password for both proxy protocols (synced from users.json)

### 7.2 docker-compose.yml

```yaml
services:
  xray:
    image: teddysun/xray:24.11.30
    container_name: vless-reality
    restart: unless-stopped
    ports: ["${VLESS_PORT}:443"]
    volumes:
      - ./config:/etc/xray:ro
      - ./logs:/var/log/xray:rw
    networks: [vless_reality_net]
    cap_drop: [ALL]
    cap_add: [NET_BIND_SERVICE]

  nginx:
    image: nginx:alpine
    container_name: vless-fake-site
    restart: unless-stopped
    volumes: ["./fake-site:/etc/nginx/conf.d:ro"]
    networks: [vless_reality_net]

networks:
  vless_reality_net:
    external: true
```

### 7.3 Nginx default.conf

```nginx
server {
    listen 8080;
    location / {
        proxy_pass https://google.com;
        proxy_ssl_server_name on;
        proxy_set_header Host google.com;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_ssl_verify off;
    }
}
```

### 7.4 users.json

```json
{
  "users": [
    {
      "username": "admin",
      "uuid": "UUID",
      "shortId": "shortId",
      "proxy_password": "Xy9mK3pL2wN8vQ4r",
      "created": "2025-10-01T12:00:00Z",
      "enabled": true
    }
  ],
  "metadata": {
    "version": "1.1",
    "last_modified": "2025-10-03T12:00:00Z"
  }
}
```

**Note:** `proxy_password` field added in version 1.1 for SOCKS5 and HTTP proxy authentication

---

## 8. Security Considerations

### 8.1 Reality Protocol Security

- **Forward Secrecy:** X25519 key exchange, ephemeral session keys
- **Anti-Fingerprinting:** Traffic indistinguishable from HTTPS to dest site
- **DPI Resistance:** No protocol-specific signatures detectable

### 8.2 Key Management

- Private key: 600 permissions, never transmitted, root-only
- Public key: Freely distributable in client configs
- Key rotation: Supported via regeneration + client config updates

### 8.3 Access Control

- Sudo accessibility for non-root users (FR-021)
- Input validation in all scripts
- Auto-escalation: `if [ "$EUID" -ne 0 ]; then exec sudo "$0" "$@"; fi`
- Optional sudoers entry: `%sudo ALL=(ALL) NOPASSWD: /usr/local/bin/vless-*`

### 8.4 Container Security

- Non-root containers (nobody, nginx users)
- Minimal capabilities: only NET_BIND_SERVICE
- Network isolation (vless_reality_net)
- Read-only config mounts

### 8.5 Threat Model

| Threat | Likelihood | Impact | Mitigation |
|--------|-----------|--------|------------|
| DPI Detection | Low | High | Reality protocol TLS masquerading |
| Private Key Compromise | Low | Critical | 600 permissions, never transmitted |
| Brute Force | Low | Medium | UUID + shortId required |
| Container Escape | Very Low | High | Non-root, minimal caps |
| Port Scanning | High | Low | Fake-site shows legitimate HTTPS |

---

## 9. Deployment and Operations

### 9.1 Production Deployment Checklist

**Pre-Deployment:**
```
☐ Fresh server (Ubuntu 20.04+, Debian 10+)
☐ Root/sudo access
☐ Clean IP (not blacklisted)
☐ Port 443 available
☐ Internet connectivity
```

**Deployment:**
```
☐ Download install.sh
☐ Run installer: sudo ./install.sh
☐ Select dest, port, subnet
☐ Wait 3-5 minutes
☐ Save admin credentials
☐ Test connection
```

**Post-Deployment:**
```
☐ Test VPN from client
☐ Verify UFW status
☐ Check logs: sudo vless-logs
☐ Create additional users
☐ Document server details
```

### 9.2 Monitoring and Maintenance

**Daily:** `sudo vless-status`, `sudo vless-logs -n 50`

**Weekly:** Check for updates (`sudo vless-update`), review user list

**Monthly:** Backup users.json and reality_keys.json, check disk space, review logs for anomalies

### 9.3 Troubleshooting

**Containers won't start:** Check Docker status, verify compose file, inspect logs (`docker logs vless-reality`)

**Client can't connect:** Verify port open (`ss -tulnp | grep :443`), check UFW, verify user UUID in config

**Fake-site not working:** Test Nginx (`docker exec vless-fake-site nginx -t`), verify dest reachable

**UFW blocking:** Check rules (`ufw status`), verify /etc/ufw/after.rules has Docker chains

---

## 10. Success Criteria

| Criterion | Target | Weight | Measurement |
|-----------|--------|--------|-------------|
| Installation Time | < 5 min | 18% | Time to first user ready |
| User Creation | < 6 sec | 22% | Command to QR + proxy configs display |
| DPI Masquerading | 100% | 18% | Traffic analysis |
| Proxy Functionality | 100% | 12% | SOCKS5/HTTP accessibility through VPN |
| Multi-VPN Compatibility | Zero conflicts | 12% | Coexistence verified |
| Update Preservation | 100% | 10% | Users + proxy passwords survive update |
| CLI Intuitiveness | 8/10 | 8% | User survey |

**Overall Success:** ≥ 85% weighted score

### Validation Tests

1. Fresh installation < 5 minutes
2. Conflict detection (Outline + VLESS coexist)
3. DPI resistance (Wireshark analysis)
4. 50 users < 6 sec average creation (with proxy configs)
5. Fake-site masquerading (browser + nmap)
6. Update preservation (10 users + proxy passwords survive update)
7. Proxy accessibility (SOCKS5 1080, HTTP 8118 work through VPN tunnel)
8. Proxy security (ports not exposed externally, authentication required)

---

## 11. Risks and Mitigations

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| UFW+Docker blocks traffic | Medium | High | Automated /etc/ufw/after.rules config |
| Port/subnet conflicts | Medium | High | Dynamic scanning, intelligent selection |
| Dest validation fails | Low | Medium | Multiple options, fallback strategy |
| Data loss on update | Low | High | Automatic backup, rollback capability |
| Private key compromise | Very Low | Critical | 600 permissions, never transmitted |
| Container crash | Low | Medium | unless-stopped policy, auto-recovery |
| DPI detection | Very Low | High | Reality protocol best practices |

---

## 12. Appendices

### 12.1 Glossary

- **VLESS:** VMess-Less lightweight VPN protocol
- **Reality:** TLS 1.3 masquerading technology
- **SOCKS5:** Socket Secure version 5 proxy protocol (RFC 1928) for TCP traffic proxying with authentication
- **HTTP Proxy:** Application-layer proxy server for HTTP/HTTPS traffic forwarding
- **X25519:** Elliptic curve Diffie-Hellman for forward secrecy
- **SNI:** Server Name Indication (TLS extension)
- **Dest:** Destination site for Reality masquerading
- **ShortId:** Additional client authentication identifier
- **Fake-site:** Nginx reverse proxy for traffic camouflage
- **DPI:** Deep Packet Inspection
- **UFW:** Uncomplicated Firewall
- **Localhost Binding:** Network service bound to 127.0.0.1 (accessible only from same machine)
- **Proxy Password:** Auto-generated 16-character password for SOCKS5/HTTP proxy authentication

### 12.2 References

- XTLS Xray-examples: https://github.com/XTLS/Xray-examples
- VLESS + Reality Guide: https://deepwiki.com/XTLS/Xray-examples/2.3-vless-+-tcp-+-reality
- Xray-core: https://xtls.github.io/
- Docker: https://docs.docker.com/
- v2rayN: https://github.com/2dust/v2rayN
- v2rayNG: https://github.com/2dust/v2rayNG

### 12.3 Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-10-01 | Initial PRD with VLESS + Reality VPN (21 functional requirements) |
| 1.1 | 2025-10-03 | Added integrated proxy server support (FR-022, FR-023, FR-024)<br/>• SOCKS5 proxy on 127.0.0.1:1080<br/>• HTTP proxy on 127.0.0.1:8118<br/>• Individual authentication per user<br/>• Localhost-only binding for security<br/>• 8 config files per user (added 5 proxy-related formats)<br/>• Updated users.json schema with proxy_password field<br/>• Updated CLI commands (vless-user show --proxy, proxy-reset)<br/>• Updated Xray config.json with 3 inbounds<br/>• Updated NFR with proxy performance metrics |

---

## Conclusion

This PRD defines a comprehensive VLESS + Reality VPN system with integrated proxy server functionality for 10-50 users, prioritizing ease of use (< 5 min install), security (Reality DPI resistance, X25519 forward secrecy), compatibility (Outline/Wireguard coexistence), application integration (SOCKS5/HTTP proxies), and reliability (99.9% uptime).

**Key Features:**
- VLESS + Reality Protocol for DPI-resistant VPN
- Integrated SOCKS5 (port 1080) and HTTP (port 8118) proxy servers
- Localhost-only proxy binding accessible through VPN tunnel
- Individual authentication for both VPN and proxy access
- 8 configuration files per user (VLESS + proxy configs + integration examples)

**Implementation Status:** Ready for development. All 24 functional requirements (FR-001 through FR-024), 6 NFR categories, and workflows specified with acceptance criteria.

---

**Document Control:**
- **Version:** 1.1
- **Status:** Final (Updated with Proxy Support)
- **Last Updated:** 2025-10-03
- **Word Count:** ~18,000

**END OF PRODUCT REQUIREMENTS DOCUMENT**

