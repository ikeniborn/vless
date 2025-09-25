# VLESS+Reality VPN Service

A minimalistic, secure VPN service implementation using VLESS protocol with Reality transport for up to 10 users.

## Features

- **VLESS Protocol** with Reality transport for enhanced security
- **Docker-based** deployment for easy management
- **CLI-only** interface for server administration
- Support for **up to 10 concurrent users**
- **Minimal logging** for privacy
- **Cross-architecture support** (x86_64, ARM64)

## System Requirements

- **OS**: Ubuntu 20.04+ or Debian 11+
- **Architecture**: x86_64 or ARM64
- **RAM**: Minimum 512 MB
- **Disk**: Minimum 1 GB free space
- **Network**: Port 443 must be available
- **Permissions**: Root or sudo access required

## Quick Start

### Installation

1. Clone the repository:
```bash
git clone https://github.com/yourusername/vless.git
cd vless
```

2. Make the script executable:
```bash
chmod +x vless-manager.sh
```

3. Run the installation:
```bash
sudo ./vless-manager.sh install
```

The installation will:
- Verify system requirements
- Install Docker and Docker Compose
- Create the necessary directory structure
- Generate environment configuration
- Generate X25519 key pairs for Reality transport
- Create Xray server configuration
- Generate Docker Compose configuration

### Usage

Available commands:

```bash
# Show help and available commands
./vless-manager.sh help

# Install the service
sudo ./vless-manager.sh install

# User Management Commands
sudo ./vless-manager.sh add-user <username>     # Add a new VPN user
sudo ./vless-manager.sh remove-user <username>  # Remove existing VPN user
./vless-manager.sh list-users                   # List all VPN users
./vless-manager.sh show-user <username>         # Show detailed user info

# Service Management Commands
sudo ./vless-manager.sh start                   # Start VPN service
sudo ./vless-manager.sh stop                    # Stop VPN service
sudo ./vless-manager.sh restart                 # Restart VPN service
./vless-manager.sh status                       # Check service status
./vless-manager.sh logs [--follow] [--lines N]  # View service logs

# System Commands (coming in Stage 5)
sudo ./vless-manager.sh uninstall               # Uninstall the service
```

## Project Structure

```
vless/
├── vless-manager.sh      # Main management script
├── docker-compose.yml    # Docker container configuration (generated)
├── .env                  # Environment configuration
├── config/
│   ├── server.json       # Server configuration (generated)
│   └── users/            # Client configurations (Stage 3)
├── data/
│   ├── users.db          # User database
│   └── keys/             # X25519 key storage (generated)
│       ├── private.key   # Server private key
│       └── public.key    # Server public key
├── logs/
│   └── xray.log          # Service logs
└── tests/                # Comprehensive test suites
    └── test_configuration.sh  # Stage 2 configuration tests
```

## Configuration

The service uses environment variables defined in `.env` file. Copy the example configuration:

```bash
cp .env.example .env
```

Edit `.env` to customize:
- `SERVER_IP`: Your server's public IP address
- `XRAY_PORT`: Service port (default: 443)
- `LOG_LEVEL`: Logging level (default: warning)

## Testing

Run the test suite to verify installation:

```bash
cd tests
./run_all_tests.sh run
```

For detailed testing options:
```bash
./run_all_tests.sh help
```

## Security Considerations

- All sensitive files are created with restrictive permissions (600)
- Directories containing sensitive data use 700 permissions
- No credentials or keys are hardcoded
- Official Docker repositories and GPG keys are used for installation
- Minimal logging to protect user privacy

## Development Roadmap

###  Stage 1: Basic Infrastructure (Complete)
- Main management script
- System requirements checking
- Docker and Docker Compose installation
- Directory structure creation

### = Stage 2: Configuration Generation (In Progress)
- X25519 key generation
- UUID generation for users
- Xray server configuration

### =� Stage 3: User Management (Planned)
- Add/remove users
- List active users
- Generate client configurations

### =� Stage 4: Docker Integration (Planned)
- Docker Compose configuration
- Container auto-start
- Health checks

### =� Stage 5: Service Functions (Planned)
- Status checking
- Service restart
- Log viewing
- Uninstallation

### =� Stage 6: Testing & Documentation (Planned)
- Comprehensive testing
- Complete documentation
- Usage examples

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Please feel free to submit pull requests or open issues for bugs and feature requests.

## Support

For issues and questions, please open an issue on GitHub.

## Acknowledgments

- [XTLS/Xray-core](https://github.com/XTLS/Xray-core) - The core proxy implementation
- [Docker](https://www.docker.com/) - Container platform
- The VLESS and Reality protocol developers