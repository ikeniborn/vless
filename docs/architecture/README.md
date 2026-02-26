# familyTraffic VPN - Architecture Documentation

**Version:** v5.33
**Last Updated:** 2026-02-26
**Status:** ✅ COMPREHENSIVE (Core documentation complete)

---

## Overview

This directory contains **comprehensive, machine-readable architecture documentation** for the familyTraffic VPN project. The documentation is structured in modular YAML files and visualized with Mermaid diagrams.

**Target Audience:**
- Developers (understanding code structure)
- DevOps Engineers (deployment and operations)
- AI Assistants (structured data processing)
- Technical Documentation Consumers

**Documentation Format:**
- **YAML Files:** Machine-readable structured specifications
- **Mermaid Diagrams:** Visual representations (GitHub-native rendering)
- **JSON Schemas:** Validation support for YAML files

---

## Quick Navigation by Use Case

### 🔍 For Developers: Understanding the System

**Start Here:**
1. [yaml/docker.yaml](yaml/docker.yaml) - Container architecture (single `familytraffic` container + optional MTProxy)
2. [yaml/data-flows.yaml](yaml/data-flows.yaml) - How data moves through the system
3. [yaml/lib-modules.yaml](yaml/lib-modules.yaml) - Code structure (44 modules, ~26,500 lines)

**Then Explore:**
- [yaml/cli.yaml](yaml/cli.yaml) - All CLI commands and usage
- [diagrams/data-flows/vless-reality-flow.md](diagrams/data-flows/vless-reality-flow.md) - Visual VLESS flow

### 🚀 For DevOps: Deployment & Operations

**Start Here:**
1. [yaml/docker.yaml](yaml/docker.yaml) - Infrastructure specifications
2. [yaml/dependencies.yaml](yaml/dependencies.yaml) - Initialization order & critical paths
3. [yaml/config.yaml](yaml/config.yaml) - Configuration architecture

**Then Explore:**
- Installation critical path: ~5-7 minutes (15 steps documented)
- Service dependencies and startup order
- Failure recovery strategies

### 🤖 For AI Assistants: Structured Information

**Load All YAML Files:**
1. [yaml/docker.yaml](yaml/docker.yaml) - Container specs
2. [yaml/config.yaml](yaml/config.yaml) - Configuration relationships
3. [yaml/cli.yaml](yaml/cli.yaml) - CLI interface
4. [yaml/lib-modules.yaml](yaml/lib-modules.yaml) - Code modules
5. [yaml/data-flows.yaml](yaml/data-flows.yaml) - Data flow patterns
6. [yaml/dependencies.yaml](yaml/dependencies.yaml) - Dependencies

**Visualize with Mermaid Diagrams** (rendered in markdown)

---

## File Index

### YAML Documentation Files

| File | Purpose | Size | Priority | Status |
|------|---------|------|----------|--------|
| [yaml/docker.yaml](yaml/docker.yaml) | Docker containers, networks, volumes, port mappings | ~1,900 lines | **HIGHEST** | ✅ Complete |
| [yaml/config.yaml](yaml/config.yaml) | Configuration files, relationships, propagation paths | ~2,800 lines | **HIGH** | ✅ Complete |
| [yaml/data-flows.yaml](yaml/data-flows.yaml) | Traffic flows, state transitions, routing patterns | ~2,100 lines | **HIGH** | ✅ Complete |
| [yaml/cli.yaml](yaml/cli.yaml) | CLI tools, commands, parameters, usage patterns | ~1,650 lines | **HIGH** | ✅ Complete |
| [yaml/lib-modules.yaml](yaml/lib-modules.yaml) | Shell modules, functions, dependencies, call chains | ~4,200 lines | **MEDIUM** | ✅ Complete |
| [yaml/dependencies.yaml](yaml/dependencies.yaml) | Initialization order, runtime deps, critical paths | ~1,100 lines | **MEDIUM** | ✅ Complete |

**Total:** ~13,750 lines of structured YAML documentation

---

### Mermaid Diagrams

#### Data Flow Diagrams (5 diagrams)

Visualize how traffic flows through the system:

| Diagram | Description | File | Status |
|---------|-------------|------|--------|
| **VLESS Reality Flow** | Main VPN protocol (DPI-resistant) | [vless-reality-flow.md](diagrams/data-flows/vless-reality-flow.md) | ✅ Complete |
| **SOCKS5 Proxy Flow** | SOCKS5 over TLS traffic flow | socks5-proxy-flow.md | 📝 Planned |
| **HTTP Proxy Flow** | HTTP proxy over TLS flow | http-proxy-flow.md | 📝 Planned |
| **Reverse Proxy Flow** | Subdomain-based reverse proxy | reverse-proxy-flow.md | 📝 Planned |
| **External Proxy Flow** | Per-user upstream proxy routing (v5.24+) | external-proxy-flow.md | 📝 Planned |

#### Sequence Diagrams (5 diagrams)

Visualize step-by-step workflows:

| Diagram | Description | File | Status |
|---------|-------------|------|--------|
| **User Management** | Add/remove user sequence | user-management.md | 📝 Planned |
| **Proxy Assignment** | Per-user proxy assignment (v5.24+) | proxy-assignment.md | 📝 Planned |
| **Certificate Renewal** | Automated Let's Encrypt renewal | cert-renewal.md | 📝 Planned |
| **Config Update** | Configuration propagation flow | config-update.md | 📝 Planned |
| **Reverse Proxy Setup** | Domain setup workflow | reverse-proxy-setup.md | 📝 Planned |

#### Deployment Diagrams (3 diagrams)

Visualize infrastructure and deployment:

| Diagram | Description | File | Status |
|---------|-------------|------|--------|
| **Docker Topology** | Container network, volumes, ports | docker-topology.md | 📝 Planned |
| **Port Mapping** | Public/internal port allocation | port-mapping.md | 📝 Planned |
| **Filesystem Layout** | /opt/familytraffic/ directory structure | filesystem-layout.md | 📝 Planned |

#### Dependency Diagrams (3 diagrams)

Visualize module relationships:

| Diagram | Description | File | Status |
|---------|-------------|------|--------|
| **Module Dependencies** | lib/ module dependency graph | module-dependencies.md | 📝 Planned |
| **Initialization Order** | Installation flow (15 steps) | initialization-order.md | 📝 Planned |
| **Runtime Call Chains** | Function call graphs | runtime-call-chains.md | 📝 Planned |

---

### JSON Schemas (Validation Support)

Schemas for automated validation of YAML files:

| Schema | Purpose | File | Status |
|--------|---------|------|--------|
| **docker-schema.json** | Validate docker.yaml structure | schemas/docker-schema.json | 📝 Planned |
| **config-schema.json** | Validate config.yaml structure | schemas/config-schema.json | 📝 Planned |
| **cli-schema.json** | Validate cli.yaml structure | schemas/cli-schema.json | 📝 Planned |
| **lib-modules-schema.json** | Validate lib-modules.yaml | schemas/lib-modules-schema.json | 📝 Planned |
| **data-flows-schema.json** | Validate data-flows.yaml | schemas/data-flows-schema.json | 📝 Planned |
| **dependencies-schema.json** | Validate dependencies.yaml | schemas/dependencies-schema.json | 📝 Planned |

---

## Key Concepts Documented

### Docker Architecture (yaml/docker.yaml)
- **Single-Container Architecture (v5.33):**
  - `familytraffic` - Main container: nginx + xray + certbot-cron + supervisord (all-in-one, `network_mode: host`)
  - `familytraffic-mtproxy` - Telegram MTProxy (optional, separate container)
- **Removed in v5.33:** `familytraffic-haproxy`, `familytraffic-nginx` (separate), `familytraffic-certbot` (separate), `familytraffic-fake-site`
- **Network:** `network_mode: host` (main container shares host network stack)
- **Port Allocation:**
  - `443` - nginx ssl_preread SNI routing (VLESS + Tier 2)
  - `1080` - nginx TLS termination (SOCKS5)
  - `8118` - nginx TLS termination (HTTP proxy)
  - `8448` - Tier 2 transports (WS/XHTTP/gRPC, loopback only)
  - `80` - nginx webroot for certbot HTTP-01 renewal
  - `8443` - MTProxy (optional, familytraffic-mtproxy container)

### Configuration Architecture (yaml/config.yaml)
- **users.json** - Single source of truth for user data
- **xray_config.json** - Generated from users.json + external_proxy.json
- **nginx.conf** - nginx stream+http config (SNI routing, TLS termination)
- **Atomic Operations** - File locking (flock) for concurrency control
- **Graceful Reloads** - Zero downtime config updates (`nginx -s reload`, Xray HUP)

### Data Flows (yaml/data-flows.yaml)
- **VLESS Reality:** TLS 1.3 masquerading (DPI-resistant), port 443 via nginx ssl_preread
- **SOCKS5/HTTP:** TLS termination at nginx (inside `familytraffic` container)
- **Tier 2 Transports:** WS/XHTTP/gRPC via nginx http block (port 8448)
- **External Proxy:** Per-user upstream routing (v5.24+)

### CLI Interface (yaml/cli.yaml)
- **familytraffic** - Main CLI (user management, system status)
- **familytraffic-external-proxy** - Upstream proxy management (v5.24+)
- **familytraffic-proxy** - Reverse proxy domain management
- **mtproxy** - MTProxy management (v6.0+ planned)

### Library Modules (yaml/lib-modules.yaml)
- **44 Modules** - ~26,500 lines of shell code
- **orchestrator.sh** - Installation coordinator (1,881 lines)
- **user_management.sh** - User CRUD + proxy assignment (3,000 lines)
- **nginx_config_generator.sh** - nginx stream+http config generation
- **Modular Design** - Clear separation of concerns

### Dependencies (yaml/dependencies.yaml)
- **Installation:** 15-step sequential process (~5-7 min)
- **Runtime Dependencies:** File locks, atomic operations
- **Critical Paths:** Installation, user add, proxy assignment
- **Failure Recovery:** Rollback strategies for common scenarios

---

## Relationship with Existing Documentation

This architecture documentation **COMPLEMENTS** existing project docs:

| Existing Documentation | Architecture Docs | Relationship |
|------------------------|-------------------|--------------|
| [docs/prd/](../prd/) | `yaml/*.yaml` | **PRD:** Human-readable prose<br/>**Architecture:** Machine-readable data |
| [docs/prd/00_summary.md](../prd/00_summary.md) | [README.md](README.md) | **Summary:** Quick start & overview<br/>**README:** Detailed navigation |
| [docs/prd/04_architecture.md](../prd/04_architecture.md) | [yaml/docker.yaml](yaml/docker.yaml) | **PRD:** Narrative architecture<br/>**YAML:** Structured specifications |
| [CLAUDE.md](../../CLAUDE.md) | [yaml/lib-modules.yaml](yaml/lib-modules.yaml) | **CLAUDE.md:** Project memory<br/>**YAML:** Detailed code structure |

**When to Use Which:**
- **Human Learning:** Start with [docs/prd/00_summary.md](../prd/00_summary.md)
- **AI Processing:** Use `docs/architecture/yaml/*.yaml`
- **Quick Reference:** Use [CLAUDE.md](../../CLAUDE.md)
- **Visual Understanding:** Use `docs/architecture/diagrams/`

---

## Validation

### Validate YAML Files Against Schemas

```bash
# Install validator
npm install -g ajv-cli

# Navigate to architecture directory
cd /home/ikeniborn/Documents/Project/familyTraffic/docs/architecture

# Validate all YAML files (when schemas are available)
ajv validate -s schemas/docker-schema.json -d yaml/docker.yaml
ajv validate -s schemas/config-schema.json -d yaml/config.yaml
ajv validate -s schemas/cli-schema.json -d yaml/cli.yaml
ajv validate -s schemas/lib-modules-schema.json -d yaml/lib-modules.yaml
ajv validate -s schemas/data-flows-schema.json -d yaml/data-flows.yaml
ajv validate -s schemas/dependencies-schema.json -d yaml/dependencies.yaml
```

### Validate Mermaid Diagrams

Mermaid diagrams can be validated by:
1. **GitHub Preview:** Push to GitHub and view rendered markdown
2. **Mermaid Live Editor:** https://mermaid.live (paste code)
3. **VS Code Extension:** Mermaid Preview extension

---

## Tools & Technologies

**Required:**
- **YAML Editor:** VS Code with YAML extension
- **Mermaid Live Editor:** https://mermaid.live (diagram testing)
- **ajv-cli:** `npm install -g ajv-cli` (validation)
- **jq:** For parsing JSON configs
- **GitHub Markdown Renderer:** Final validation

**Optional:**
- **yq:** YAML processor (`brew install yq` or `snap install yq`)
- **yamllint:** YAML linter (`pip install yamllint`)

---

## Development Workflow

### Adding New Architecture Documentation

1. **Identify Component:**
   - New Docker container → Update `yaml/docker.yaml`
   - New CLI command → Update `yaml/cli.yaml`
   - New module → Update `yaml/lib-modules.yaml`
   - New data flow → Update `yaml/data-flows.yaml`

2. **Update YAML File:**
   - Follow existing structure
   - Use consistent naming conventions
   - Add comprehensive metadata

3. **Create/Update Diagram (if applicable):**
   - Add Mermaid diagram to `diagrams/` directory
   - Test rendering on Mermaid Live Editor
   - Link from YAML file

4. **Validate Changes:**
   - YAML syntax: `yamllint yaml/<file>.yaml`
   - Schema validation: `ajv validate -s schemas/<schema>.json -d yaml/<file>.yaml`
   - Diagram rendering: GitHub preview

5. **Update This README:**
   - Add new files to index
   - Update status indicators
   - Update quick navigation if needed

---

## Skills System Integration

**Location:** `../../.claude/skills/` (in familyTraffic project root)
**Purpose:** Automated workflows leveraging this architecture documentation

### How Skills Use YAML Documentation

Skills automatically load YAML files as **execution context** before performing tasks:

| Skill Category | Primary YAML Files | Usage |
|----------------|-------------------|-------|
| **Troubleshooting** | docker.yaml, data-flows.yaml, dependencies.yaml | Container specs, traffic flows, diagnostic workflows |
| **Development** | lib-modules.yaml, cli.yaml, dependencies.yaml | Module structure, function locations, dependency chains |
| **Documentation** | All YAML files | Sync detection, diagram generation, stale entry identification |
| **Testing** | docker.yaml, dependencies.yaml | Test dependencies, container validation |

### Example: add-feature Skill

```yaml
# Skill workflow
Phase 1: Load Context
  Read docs/architecture/yaml/lib-modules.yaml  # Find module structure
  Read docs/architecture/yaml/cli.yaml          # Find CLI commands

Phase 2: Analysis
  Search lib-modules.yaml for affected modules
  Example: user_management.sh line 156 (add_user_to_json function)

Phase 3: Implementation
  Modify code based on YAML-provided locations
  Add mandatory logging

Phase 4: Update YAML
  Add new function to lib-modules.yaml:
    - name: "set_user_quota"
      line: 1245  # Auto-detected
      purpose: "Set user bandwidth quota"
```

### Benefits

1. **YAML-Driven Intelligence:**
   - Skills know exact file paths and line numbers from lib-modules.yaml
   - Skills understand data flows from data-flows.yaml
   - Skills validate against docker.yaml container specs

2. **Automatic Sync:**
   - `sync-yaml-with-code` skill detects stale YAML entries
   - `update-architecture-docs` skill proposes YAML updates
   - `generate-mermaid-diagram` skill creates diagrams from YAML

3. **Safety:**
   - All skills validate YAML schema before updates
   - Mandatory approval gates for YAML modifications
   - YAML changes committed separately from code changes

### Skill-YAML Relationship

```
Code Change
    ↓
Skills Execute (using YAML as context)
    ↓
YAML Updated (by skill)
    ↓
Validation (schemas/validate_architecture_docs.py)
    ↓
Git Commit (docs: sync YAML with code changes)
```

**Result:** Architecture documentation stays in sync with codebase automatically.

🔗 **Skills Documentation:** `../../.claude/skills/` (12 skills in 4 categories)

---

## Documentation Statistics

**Current Status (2026-01-07):**

### YAML Files
- **Total Files:** 6
- **Total Lines:** ~13,750
- **Status:** ✅ All core files complete

### Mermaid Diagrams
- **Total Planned:** 16 diagrams
- **Completed:** 1 (VLESS Reality Flow)
- **Status:** 🚧 In Progress

### JSON Schemas
- **Total Planned:** 6 schemas
- **Completed:** 0
- **Status:** 📝 Planned

---

## Version History

| Date | Version | Changes |
|------|---------|---------|
| 2026-01-07 | 1.0 | Initial creation of architecture documentation |
|  |  | - Created 6 YAML files (~13,750 lines) |
|  |  | - Created VLESS Reality flow diagram |
|  |  | - Created README navigation guide |
| TBD | 1.1 | Complete remaining diagrams (15 diagrams) |
| TBD | 1.2 | Add JSON schemas for validation |
| TBD | 2.0 | MTProxy v6.0+ documentation (when implemented) |

---

## Contributing

### Guidelines for Architecture Documentation

1. **Accuracy:** All information must match actual codebase
2. **Completeness:** Cover all aspects of components
3. **Clarity:** Use clear, concise language
4. **Consistency:** Follow existing patterns and naming
5. **Machine-Readable:** Structure data for automated processing
6. **Visual:** Provide diagrams where helpful

### Reporting Issues

If you find inaccuracies or missing information:
1. Check latest codebase version matches documentation version
2. Verify issue persists in current implementation
3. Create GitHub issue with:
   - File affected (e.g., `yaml/docker.yaml`)
   - Section affected
   - Expected vs. actual information
   - Suggested fix

---

## Future Enhancements

### Planned (v1.1)
- ✅ Complete remaining 15 Mermaid diagrams
- ✅ Create 6 JSON validation schemas
- ✅ Add automated validation CI/CD pipeline
- ✅ Interactive HTML visualization (optional)

### Future (v2.0 - MTProxy v6.0+)
- 📝 MTProxy v6.0 container specifications
- 📝 MTProxy secret management documentation
- 📝 MTProxy data flow diagrams
- 📝 MTProxy v6.1 multi-user specifications

---

## Contact & Feedback

**Questions:**
- Create issue in GitHub repository
- Reference specific file/section in architecture docs

**Suggestions:**
- Propose improvements via pull request
- Follow existing structure and conventions

---

**Maintained By:** familyTraffic VPN Project Team
**Documentation Status:** ✅ COMPREHENSIVE (Core complete, diagrams in progress)
**Last Updated:** 2026-02-26

---

## Quick Links Summary

### Essential YAML Files
1. [docker.yaml](yaml/docker.yaml) - Containers, networks, volumes
2. [config.yaml](yaml/config.yaml) - Configuration architecture
3. [data-flows.yaml](yaml/data-flows.yaml) - Traffic flows
4. [cli.yaml](yaml/cli.yaml) - CLI interface

### Essential Diagrams
1. [VLESS Reality Flow](diagrams/data-flows/vless-reality-flow.md) - Main protocol flow

### Related Documentation
1. [Project README](../../README.md) - User guide
2. [PRD Summary](../prd/00_summary.md) - Executive summary
3. [CLAUDE.md](../../CLAUDE.md) - Project memory
4. [CHANGELOG.md](../../CHANGELOG.md) - Version history

---

**End of README**
