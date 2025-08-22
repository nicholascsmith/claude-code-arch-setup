# Claude Code Setup for Arch Linux

Automated setup for [Claude Code](https://claude.ai/code) development environment on Arch Linux.

[![Version](https://img.shields.io/badge/version-0.1-blue)](https://github.com/nicholascsmith/claude-code-arch-setup)
[![Arch Linux](https://img.shields.io/badge/platform-Arch%20Linux-1793d1)](https://archlinux.org/)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

## Features

- Secure token handling and sandboxed containers
- Complete setup: Docker, GitHub CLI, Git configuration, and MCP servers
- Fully automated with intelligent defaults
- Optimized for Arch Linux
- Claude Code runs with `--dangerously-skip-permissions` by default

## Quick Start

**Recommended**

```bash
curl -sSL https://raw.githubusercontent.com/nicholascsmith/claude-code-arch-setup/main/setup.sh -o setup.sh
chmod +x setup.sh
./setup.sh
```

**Alternative**

```bash
git clone https://github.com/nicholascsmith/claude-code-arch-setup.git
cd claude-code-arch-setup
./setup.sh
```

## Prerequisites

- Arch Linux (fresh install supported)
- Internet connection 
- User with sudo privileges (must be in `wheel` group)
- 1GB+ free disk space

For very fresh Arch installs, ensure time sync and updated keyring:

```bash
sudo timedatectl set-ntp true
sudo pacman-key --refresh-keys
sudo usermod -aG wheel $USER
```

## What Gets Installed

### System Packages
- Docker - Container runtime for Claude Code
- GitHub CLI - Secure GitHub authentication
- Git - Version control (configured during setup)
- curl - Network utilities

### Claude Code Environment
- Latest Claude Code Docker image (automatically fetched)
- Project structure in `~/Development`
- Docker Compose configuration
- Management scripts for easy container control

### MCP Servers (Automatically Configured)
- GitHub MCP Server - Direct GitHub integration
- Git MCP Server - Local repository management  
- shadcn/ui MCP Server - Component library access

## Usage

The setup creates a project structure in `~/Development/your-project/`:

```
├── .devcontainer/          # VS Code dev container config
├── .env                    # Environment variables
├── docker-compose.yml      # Container configuration
├── claude.sh              # Management script
├── .gitignore             # Git ignore rules
└── README.md              # Project documentation
```

### Management Commands

```bash
cd ~/Development/your-project
./claude.sh                # Start Claude Code (default)
./claude.sh shell          # Open shell in container
./claude.sh stop           # Stop container
./claude.sh logs           # View logs
./claude.sh setup-mcp      # Reconfigure MCP servers
./claude.sh clean          # Remove all data
```

## Security Features

- Secure token storage - No credentials in process arguments
- Container sandboxing - Read-only filesystem, dropped capabilities
- GitHub CLI integration - Secure OAuth flow, no manual token management
- Root prevention - Blocks dangerous root execution
- Automatic cleanup - Secure temporary file handling

## Project Structure

- `.env` - Project environment variables (not committed)
- `docker-compose.yml` - Container configuration
- `.devcontainer/` - VS Code dev container setup
- `claude.sh` - Project management script
- GitHub authentication handled via GitHub CLI
- Docker volumes for persistent Claude Code settings

## Advanced Usage

### Custom MCP Servers

```bash
./claude.sh shell
claude --dangerously-skip-permissions mcp add my-server -- npx my-mcp-server
```

### Multiple Projects

Each project gets isolated environments:

```bash
cd ~/Development/project-one && ./claude.sh
cd ~/Development/project-two && ./claude.sh
```

### Docker Customization

Edit `docker-compose.yml` for custom port mappings, volume mounts, environment variables, or resource limits.

## Troubleshooting

**Docker Permission Denied**
```bash
sudo usermod -aG docker $USER
sudo reboot
```

**GitHub Authentication Failed**
```bash
gh auth login --web --scopes "repo,read:org,workflow"
```

**Container Won't Start**
```bash
sudo systemctl restart docker
cd your-project && ./claude.sh logs
```

**MCP Servers Not Working**
```bash
./claude.sh setup-mcp
```

For additional help, run `./claude.sh logs` to check container logs or `./claude.sh shell` to debug interactively.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
