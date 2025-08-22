#!/bin/bash

# Claude Code Setup for Arch Linux - Simple & Secure
# Version: 0.1

set -euo pipefail

# Security: Secure umask and cleanup
umask 077
TEMP_DIR="$(mktemp -d -t claude-setup-XXXXXX)"
trap 'cleanup_and_exit' EXIT INT TERM

# Configuration
SCRIPT_VERSION="0.1"
MIN_DISK_SPACE_MB=1000
NETWORK_TIMEOUT=15
DOCKER_WAIT_TIMEOUT=30

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Global state
NEED_RELOGIN=false

# Cleanup function
cleanup_and_exit() {
    local exit_code=$?
    rm -rf "$TEMP_DIR"
    
    if [[ $exit_code -ne 0 ]]; then
        log_warning "Setup failed. Check for partially created project directory if needed."
    fi
    
    exit $exit_code
}

# Logging functions
log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; exit 1; }

# Execute command with error handling
exec_cmd() {
    local error_msg="$1"
    shift
    
    if ! "$@"; then
        log_error "$error_msg"
    fi
}

# Input validation
validate_project_name() {
    local name="$1"
    [[ ${#name} -ge 3 && ${#name} -le 39 && "$name" =~ ^[a-zA-Z0-9_-]+$ && ! "$name" =~ ^[-_] && ! "$name" =~ [-_]$ ]]
}

validate_github_username() {
    local username="$1"
    [[ ${#username} -ge 1 && ${#username} -le 39 && "$username" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]]
}

validate_email() {
    local email="$1"
    [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]
}

sanitize_input() {
    local input="$1"
    # Remove all dangerous shell characters
    echo "$input" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed 's/[;<>&|`$(){}[\]!\\]//g'
}

# System checks
check_system() {
    log_info "Checking system requirements..."
    
    # Check if running as root
    if [[ $EUID -eq 0 ]]; then
        log_error "Do not run as root. Use a regular user with sudo privileges."
    fi
    
    # Check curl availability first
    if ! command -v curl &>/dev/null; then
        log_error "curl is required but not installed. Please install curl first: sudo pacman -S curl"
    fi
    
    # Check if running on Arch Linux
    if [[ ! -f /etc/arch-release ]]; then
        log_error "This script is designed for Arch Linux only."
    fi
    
    # Check disk space early
    local available_mb
    available_mb=$(df "$HOME" --output=avail | tail -1 | awk '{print int($1/1024)}')
    if [[ $available_mb -lt $MIN_DISK_SPACE_MB ]]; then
        log_error "Insufficient disk space in $HOME. Need ${MIN_DISK_SPACE_MB}MB, have ${available_mb}MB"
    fi
    
    # Check network connectivity
    if ! curl -sf --connect-timeout "$NETWORK_TIMEOUT" https://github.com >/dev/null; then
        log_error "Network connectivity check failed - cannot reach GitHub"
    fi
    
    # Check sudo access early
    if ! sudo -v; then
        log_error "Sudo access required for package installation and Docker setup"
    fi
    
    # Check docker group membership
    if ! groups "$USER" | grep -q docker; then
        log_warning "User not in docker group. Will add to docker group during setup."
        log_warning "You will need to log out and back in after setup completes."
        NEED_RELOGIN=true
    fi
    
    log_success "System requirements met"
}

# Get project name
get_project_name() {
    while true; do
        read -p "Project name (3-39 chars, letters/numbers/hyphens/underscores): " PROJECT_NAME
        PROJECT_NAME="$(sanitize_input "$PROJECT_NAME")"
        if [[ -n "$PROJECT_NAME" ]] && validate_project_name "$PROJECT_NAME"; then
            break
        fi
        log_warning "Invalid project name. Use 3-39 characters: letters, numbers, hyphens, underscores"
    done
}

# Get GitHub details
get_github_details() {
    # GitHub username
    while true; do
        read -p "GitHub username: " GITHUB_USERNAME
        GITHUB_USERNAME="$(sanitize_input "$GITHUB_USERNAME")"
        if [[ -n "$GITHUB_USERNAME" ]] && validate_github_username "$GITHUB_USERNAME"; then
            break
        fi
        log_warning "Invalid GitHub username (1-39 chars, alphanumeric/hyphens, no leading/trailing hyphens)"
    done
    
    # Repository name (default to project name)
    read -p "Repository name (default: $PROJECT_NAME): " GITHUB_REPO_NAME
    GITHUB_REPO_NAME="${GITHUB_REPO_NAME:-$PROJECT_NAME}"
    GITHUB_REPO_NAME="$(sanitize_input "$GITHUB_REPO_NAME")"
    
    # Use project name if repo name is invalid
    if [[ -z "$GITHUB_REPO_NAME" ]]; then
        GITHUB_REPO_NAME="$PROJECT_NAME"
    fi
}

# Get project description
get_project_description() {
    read -p "Project description (optional): " PROJECT_DESCRIPTION
    PROJECT_DESCRIPTION="${PROJECT_DESCRIPTION:-A project built with Claude Code}"
    PROJECT_DESCRIPTION="$(sanitize_input "$PROJECT_DESCRIPTION")"
}

# Setup project directories
setup_project_directories() {
    DEV_BASE_DIR="$HOME/Development"
    
    if [[ ! -d "$DEV_BASE_DIR" ]]; then
        exec_cmd "Cannot create Development directory" mkdir -p "$DEV_BASE_DIR"
    fi
    
    # Set derived variables
    GITHUB_REPO="$GITHUB_USERNAME/$GITHUB_REPO_NAME"
    PROJECT_DIR="$DEV_BASE_DIR/$PROJECT_NAME"
    GITHUB_URL="https://github.com/$GITHUB_REPO.git"
    
    # Check if project directory already exists
    if [[ -d "$PROJECT_DIR" ]]; then
        log_error "Project directory already exists: $PROJECT_DIR"
    fi
}

# Get project details with validation
get_project_details() {
    log_info "Project Configuration"
    
    get_project_name
    get_github_details
    get_project_description
    setup_project_directories
    
    log_info "Project: $PROJECT_NAME at $PROJECT_DIR"
    log_info "GitHub: $GITHUB_REPO"
}



# Install dependencies
install_dependencies() {
    log_info "Installing dependencies..."
    
    # Update package database
    exec_cmd "Failed to update package database" sudo pacman -Syu --noconfirm
    
    # Install required packages
    REQUIRED_PACKAGES=("docker" "github-cli" "git" "curl")
    exec_cmd "Package installation failed" sudo pacman -S --needed --noconfirm "${REQUIRED_PACKAGES[@]}"
    
    # Setup Docker
    setup_docker
    
    
    log_success "Dependencies installed"
}

# Setup Docker service and user permissions
setup_docker() {
    log_info "Setting up Docker..."
    
    # Start and enable Docker service
    if ! systemctl is-active --quiet docker; then
        exec_cmd "Failed to start Docker service" sudo systemctl start docker
        exec_cmd "Failed to enable Docker service" sudo systemctl enable docker
        
        # Wait for Docker to be ready
        local retries=0
        while [[ $retries -lt $DOCKER_WAIT_TIMEOUT ]]; do
            if sudo docker info &>/dev/null; then
                break
            fi
            sleep 1
            ((retries++))
        done
        
        if [[ $retries -eq $DOCKER_WAIT_TIMEOUT ]]; then
            log_error "Docker failed to start within ${DOCKER_WAIT_TIMEOUT} seconds"
        fi
    fi
    
    # Add user to docker group if needed
    if ! groups "$USER" | grep -q docker; then
        exec_cmd "Failed to add user to docker group" sudo usermod -aG docker "$USER"
        NEED_RELOGIN=true
    fi
    
    log_success "Docker configured"
}

# Git configuration
setup_git() {
    log_info "Configuring Git..."
    
    # Check if already configured
    local current_name current_email
    current_name="$(git config --global user.name 2>/dev/null || true)"
    current_email="$(git config --global user.email 2>/dev/null || true)"
    
    if [[ -n "$current_name" && -n "$current_email" ]]; then
        log_success "Git already configured: $current_name <$current_email>"
        return 0
    fi
    
    # Get user details
    local git_name git_email
    while true; do
        read -p "Your full name for Git: " git_name
        git_name="$(echo "$git_name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        if [[ -n "$git_name" && ${#git_name} -ge 2 ]]; then
            break
        fi
        log_warning "Please enter a valid name"
    done
    
    while true; do
        read -p "Your email for Git: " git_email
        git_email="$(echo "$git_email" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        if validate_email "$git_email"; then
            break
        fi
        log_warning "Please enter a valid email"
    done
    
    # Configure Git
    exec_cmd "Failed to configure Git name" git config --global user.name "$git_name"
    exec_cmd "Failed to configure Git email" git config --global user.email "$git_email"
    
    # Set default branch to main
    read -p "Set default branch to 'main'? (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        exec_cmd "Failed to set default branch" git config --global init.defaultBranch main
    fi
    
    log_success "Git configured"
}

# GitHub authentication and repository setup
setup_github() {
    log_info "Setting up GitHub..."
    
    # GitHub CLI authentication
    if ! gh auth status &>/dev/null; then
        log_info "GitHub CLI authentication required"
        exec_cmd "GitHub CLI authentication failed" gh auth login --web --scopes "repo,read:org,workflow"
    fi
    
    # Validate GitHub CLI can access token
    log_info "Validating GitHub CLI authentication..."
    if ! gh auth token &>/dev/null; then
        log_error "GitHub CLI authentication failed. Please run 'gh auth login' manually."
    fi
    
    # Test token permissions by trying to access user info
    if ! gh api user &>/dev/null; then
        log_error "GitHub token lacks required permissions. Please re-authenticate with 'gh auth login --scopes repo,read:org,workflow'"
    fi
    
    log_success "GitHub CLI authentication validated"
    
    # Create repository if it doesn't exist
    if ! gh repo view "$GITHUB_REPO" &>/dev/null; then
        local visibility="--public"
        read -p "Make repository private? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            visibility="--private"
        fi
        
        exec_cmd "Repository creation failed" gh repo create "$GITHUB_REPO" $visibility --description "$PROJECT_DESCRIPTION" --clone=false
        log_success "Repository created: https://github.com/$GITHUB_REPO"
    fi
    
    log_success "GitHub configured"
}

# Create project structure
create_project() {
    log_info "Creating project structure..."
    
    # Create directories
    exec_cmd "Cannot create project directory" mkdir -p "$PROJECT_DIR"
    cd "$PROJECT_DIR"
    
    exec_cmd "Cannot create .devcontainer directory" mkdir -p .devcontainer
    chmod 700 .devcontainer
    
    # Create environment file
    cat > .env << EOF
PROJECT_NAME=$PROJECT_NAME
GITHUB_REPO=$GITHUB_REPO
GITHUB_URL=$GITHUB_URL
PROJECT_DESCRIPTION=$PROJECT_DESCRIPTION
USER_ID=$(id -u)
GID=$(id -g)
EOF
    chmod 600 .env
    
    # Create Dockerfile that builds Claude Code from npm
    cat > Dockerfile << EOF
FROM node:20-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \\
    git \\
    curl \\
    && rm -rf /var/lib/apt/lists/*

# Install Claude Code from npm
RUN npm install -g @anthropic-ai/claude-code

# Create workspace directory
WORKDIR /workspace

# Use node user (already exists in base image)
USER node

# Set up Claude Code directory
RUN mkdir -p /home/node/.claude

CMD ["claude"]
EOF
    
    # Create devcontainer configuration
    cat > .devcontainer/devcontainer.json << EOF
{
    "name": "Claude Code",
    "build": {
        "dockerfile": "../Dockerfile"
    },
    "customizations": {
        "vscode": {
            "extensions": ["ms-vscode.vscode-json"]
        }
    },
    "remoteUser": "node",
    "workspaceMount": "source=\${localWorkspaceFolder},target=/workspace,type=bind",
    "workspaceFolder": "/workspace",
    "mounts": [
        "source=claude-code-auth-$PROJECT_NAME,target=/home/node/.claude,type=volume"
    ],
    "runArgs": [
        "--security-opt=no-new-privileges:true",
        "--cap-drop=ALL",
        "--read-only=false"
    ]
}
EOF
    
    # Create Docker Compose file with environment-based token
    cat > docker-compose.yml << EOF
services:
  claude-code:
    build: .
    container_name: claude-code-$PROJECT_NAME
    stdin_open: true
    tty: true
    working_dir: /workspace
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true
    read_only: false
    environment:
      - HOME=/home/node
      - PROJECT_NAME=$PROJECT_NAME
      - GITHUB_TOKEN=\${GITHUB_TOKEN}
    volumes:
      - ./:/workspace
      - claude-code-auth-$PROJECT_NAME:/home/node/.claude
      - ~/.gitconfig:/home/claude/.gitconfig:ro
    restart: unless-stopped

volumes:
  claude-code-auth-$PROJECT_NAME:
    name: claude-code-auth-$PROJECT_NAME
EOF
    
    # Create management script
    cat > claude.sh << 'SCRIPT_EOF'
#!/bin/bash
set -euo pipefail

# Load environment
if [[ -f .env ]]; then
    set -a; source .env; set +a
fi

# Configuration
DOCKER_WAIT_TIMEOUT=30

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; exit 1; }

wait_for_container() {
    local count=0
    while [[ $count -lt $DOCKER_WAIT_TIMEOUT ]]; do
        if docker compose exec -T claude-code echo "ready" &>/dev/null; then
            return 0
        fi
        sleep 1
        ((count++))
    done
    return 1
}

check_github_auth() {
    if ! gh auth status &>/dev/null; then
        log_error "GitHub CLI not authenticated. Run 'gh auth login' first."
    fi
    
    if ! gh auth token &>/dev/null; then
        log_error "Cannot access GitHub token from CLI. Re-authenticate with 'gh auth login'."
    fi
}

case "${1:-run}" in
    run|start)
        check_github_auth
        log_info "Building and starting Claude Code..."
        export GITHUB_TOKEN=$(gh auth token)
        docker compose up --build -d claude-code
        if wait_for_container; then
            docker compose exec claude-code claude --dangerously-skip-permissions
        else
            log_error "Container failed to start"
        fi
        ;;
    shell)
        check_github_auth
        log_info "Building and opening shell..."
        export GITHUB_TOKEN=$(gh auth token)
        docker compose up --build -d claude-code
        if wait_for_container; then
            docker compose exec claude-code bash
        else
            log_error "Container failed to start"
        fi
        ;;
    stop)
        log_info "Stopping..."
        docker compose down
        ;;
    logs)
        docker compose logs -f claude-code
        ;;
    clean)
        read -p "Remove all containers and data? (y/N): " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            docker compose down -v --remove-orphans
            docker volume prune -f
            docker image prune -f
            log_success "Cleaned up"
        fi
        ;;
    setup-mcp)
        check_github_auth
        log_info "Setting up MCP servers..."
        
        # Start container if not running
        if ! docker compose ps -q claude-code | grep -q .; then
            log_info "Building and starting container for MCP setup..."
            export GITHUB_TOKEN=$(gh auth token)
            docker compose up --build -d claude-code
            if ! wait_for_container; then
                log_error "Container failed to start"
            fi
        fi
        
        # Get GitHub token securely
        GITHUB_TOKEN="$(gh auth token)"
        
        # Setup MCP servers
        log_info "Installing GitHub MCP server..."
        if docker compose exec -T claude-code claude --dangerously-skip-permissions mcp add github \
            -e "GITHUB_PERSONAL_ACCESS_TOKEN=$GITHUB_TOKEN" \
            -- docker run -i --rm -e GITHUB_PERSONAL_ACCESS_TOKEN \
            ghcr.io/github/github-mcp-server &>/dev/null; then
            log_success "GitHub MCP server installed"
        else
            log_warning "GitHub MCP server installation failed"
        fi
        
        log_info "Installing Git MCP server..."
        if docker compose exec -T claude-code claude --dangerously-skip-permissions mcp add git \
            -- npx -y mcp-server-git --repository /workspace &>/dev/null; then
            log_success "Git MCP server installed"
        else
            log_warning "Git MCP server installation failed"
        fi
        
        log_info "Installing shadcn/ui MCP server..."
        if docker compose exec -T claude-code claude --dangerously-skip-permissions mcp add shadcn-ui-server \
            -- npx -y shadcn-ui-mcp-server &>/dev/null; then
            log_success "shadcn/ui MCP server installed"
        else
            log_warning "shadcn/ui MCP server installation failed"
        fi
        
        # Verify installation
        log_info "Verifying MCP servers..."
        docker compose exec claude-code claude --dangerously-skip-permissions mcp list
        ;;
    *)
        echo "Claude Code Manager"
        echo "Commands: run, shell, stop, logs, clean, setup-mcp"
        echo
        echo "Note: Authenticate with 'gh auth login' before running."
        echo "No manual token exports needed!"
        ;;
esac
SCRIPT_EOF
    chmod +x claude.sh
    
    # Create .gitignore
    cat > .gitignore << 'EOF'
.env
.env.*
node_modules/
.next/
build/
dist/
*.log
.DS_Store
*.tmp
EOF
    
    # Create README
    cat > README.md << EOF
# $PROJECT_NAME

$PROJECT_DESCRIPTION

## Setup

Authentication is handled automatically via GitHub CLI. No manual token exports needed!

1. Ensure you're authenticated (done during setup):
   \`\`\`bash
   gh auth status
   \`\`\`

2. Start Claude Code:
   \`\`\`bash
   ./claude.sh
   \`\`\`

## Commands

- \`./claude.sh\` - Start Claude Code
- \`./claude.sh shell\` - Open shell
- \`./claude.sh stop\` - Stop container
- \`./claude.sh logs\` - View logs
- \`./claude.sh setup-mcp\` - Setup MCP servers
- \`./claude.sh clean\` - Remove all data

## Authentication

This project uses GitHub CLI's secure token storage. The setup script automatically:
- Authenticates you with GitHub CLI
- Securely stores credentials in GitHub CLI's credential manager
- Automatically retrieves tokens when starting containers

No manual token management required!

## MCP Servers

The setup automatically installs these MCP servers for enhanced Claude Code functionality:
- **GitHub MCP Server**: Direct GitHub repository access and operations
- **Git MCP Server**: Local Git repository management within the workspace
- **shadcn/ui MCP Server**: Access to shadcn/ui component library and documentation

MCP servers are configured during initial setup. To reconfigure, use: \`./claude.sh setup-mcp\`

## Configuration

This setup configures Claude Code to run with \`--dangerously-skip-permissions\` by default for a smoother workflow. All commands bypass permission prompts automatically.

## Links

- Repository: [$GITHUB_REPO](https://github.com/$GITHUB_REPO)
- Claude Code: Official Anthropic development environment
EOF
    
    log_success "Project structure created"
}

# Initialize Git repository
setup_git_repo() {
    log_info "Setting up Git repository..."
    
    cd "$PROJECT_DIR"
    
    if [[ ! -d ".git" ]]; then
        exec_cmd "Failed to initialize Git repository" git init
        if [[ -n "$GITHUB_URL" ]]; then
            exec_cmd "Failed to add remote origin" git remote add origin "$GITHUB_URL"
        fi
    fi
    
    # Initial commit
    git add .
    if ! git diff --cached --quiet; then
        exec_cmd "Failed to create initial commit" git commit -m "Initial commit from Claude Code setup v$SCRIPT_VERSION"
        log_success "Initial commit created"
    fi
    
    log_success "Git repository initialized"
}

# Setup MCP servers
setup_mcp_servers() {
    log_info "Setting up MCP servers..."
    
    cd "$PROJECT_DIR"
    
    # Use sudo if user not in docker group yet
    local docker_cmd="docker"
    if [[ "$NEED_RELOGIN" == "true" ]]; then
        docker_cmd="sudo docker"
    fi
    
    # Start container if not running
    if ! $docker_cmd compose ps -q claude-code | grep -q .; then
        log_info "Building and starting container for MCP setup..."
        export GITHUB_TOKEN=$(gh auth token)
        $docker_cmd compose up --build -d claude-code
        
        # Wait for container to be ready
        local retries=0
        while [[ $retries -lt $DOCKER_WAIT_TIMEOUT ]]; do
            if $docker_cmd compose exec -T claude-code echo "ready" &>/dev/null; then
                break
            fi
            sleep 1
            ((retries++))
        done
        
        if [[ $retries -eq $DOCKER_WAIT_TIMEOUT ]]; then
            log_warning "Container startup timeout - MCP setup may fail"
        fi
    fi
    
    # Get GitHub token securely
    local github_token
    github_token="$(gh auth token)"
    
    # Setup GitHub MCP server
    log_info "Installing GitHub MCP server..."
    if $docker_cmd compose exec -T claude-code claude --dangerously-skip-permissions mcp add github \
        -e "GITHUB_PERSONAL_ACCESS_TOKEN=$github_token" \
        -- docker run -i --rm -e GITHUB_PERSONAL_ACCESS_TOKEN \
        ghcr.io/github/github-mcp-server &>/dev/null; then
        log_success "GitHub MCP server installed"
    else
        log_warning "GitHub MCP server installation failed - continuing"
    fi
    
    # Setup Git MCP server
    log_info "Installing Git MCP server..."
    if $docker_cmd compose exec -T claude-code claude --dangerously-skip-permissions mcp add git \
        -- npx -y mcp-server-git --repository /workspace &>/dev/null; then
        log_success "Git MCP server installed"
    else
        log_warning "Git MCP server installation failed - continuing"
    fi
    
    # Setup shadcn/ui MCP server
    log_info "Installing shadcn/ui MCP server..."
    if $docker_cmd compose exec -T claude-code claude --dangerously-skip-permissions mcp add shadcn-ui-server \
        -- npx -y shadcn-ui-mcp-server &>/dev/null; then
        log_success "shadcn/ui MCP server installed"
    else
        log_warning "shadcn/ui MCP server installation failed - continuing"
    fi
    
    # Verify MCP server installation
    log_info "Verifying MCP server installation..."
    if $docker_cmd compose exec -T claude-code claude --dangerously-skip-permissions mcp list &>/dev/null; then
        log_success "MCP servers configured successfully"
    else
        log_warning "MCP server verification failed - check manually with 'claude --dangerously-skip-permissions mcp list'"
    fi
}

# Main execution
main() {
    echo "Claude Code Setup v$SCRIPT_VERSION"
    echo "=================================="
    echo
    
    check_system
    get_project_details
    install_dependencies
    setup_git
    setup_github
    create_project
    setup_git_repo
    setup_mcp_servers
    
    echo
    log_success "Setup complete!"
    echo
    echo "Next steps:"
    echo "1. cd '$PROJECT_DIR'"
    if [[ "$NEED_RELOGIN" == "true" ]]; then
        echo "2. Log out and log back in to activate Docker group membership"
        echo "3. ./claude.sh"
    else
        echo "2. ./claude.sh"
    fi
    echo
    echo "✅ GitHub authentication is already configured via GitHub CLI"
    echo "✅ No manual token exports needed!"
    echo "Happy coding! 🚀"
}

# Argument handling
case "${1:-}" in
    -h|--help)
        echo "Claude Code Setup v$SCRIPT_VERSION"
        echo "Usage: $0 [--help|--version]"
        echo
        echo "Interactive setup for Claude Code development environment"
        exit 0
        ;;
    --version)
        echo "v$SCRIPT_VERSION"
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac
