#!/bin/bash
# WSL Container Startup Script
# This script ensures the WSL container is properly initialized and ready for testing

set -e

# Logging function
log() {
    echo "[WSL-STARTUP] $(date '+%Y-%m-%d %H:%M:%S') - $*"
}

# Function to check if service is ready
wait_for_service() {
    local service_name="$1"
    local max_attempts=30
    local attempt=1
    
    log "Waiting for $service_name to be ready..."
    
    while [ $attempt -le $max_attempts ]; do
        if systemctl is-active --quiet "$service_name" 2>/dev/null || pgrep -f "$service_name" >/dev/null 2>&1; then
            log "$service_name is ready"
            return 0
        fi
        
        log "Attempt $attempt/$max_attempts: $service_name not ready yet, waiting..."
        sleep 2
        attempt=$((attempt + 1))
    done
    
    log "Warning: $service_name may not be fully ready after $max_attempts attempts"
    return 1
}

# Function to initialize user environment
init_user_environment() {
    log "Initializing user environment for testuser..."
    
    # Ensure user home directory exists and has proper permissions
    if [ ! -d "/home/testuser" ]; then
        log "Creating testuser home directory"
        mkdir -p /home/testuser
        chown testuser:testuser /home/testuser
    fi
    
    # Ensure .bashrc exists
    if [ ! -f "/home/testuser/.bashrc" ]; then
        log "Creating .bashrc for testuser"
        cat > /home/testuser/.bashrc << 'EOF'
# .bashrc for testuser
export PATH="$HOME/.local/bin:$PATH"
alias ll="ls -la"
alias la="ls -A"
alias l="ls -CF"

# Chezmoi aliases
alias cm="chezmoi"
alias cma="chezmoi apply"
alias cme="chezmoi edit"
alias cms="chezmoi status"
alias cmd="chezmoi diff"
alias cmu="chezmoi update"
alias cmcd="cd $(chezmoi source-path)"
EOF
        chown testuser:testuser /home/testuser/.bashrc
    fi
    
    # Ensure chezmoi configuration exists
    if [ ! -f "/home/testuser/.config/chezmoi/chezmoi.toml" ]; then
        log "Creating chezmoi configuration"
        mkdir -p /home/testuser/.config/chezmoi
        cat > /home/testuser/.config/chezmoi/chezmoi.toml << 'EOF'
[chezmoi]
sourceDir = "~/.local/share/chezmoi"
destDir = "~"
configFile = "~/.config/chezmoi/chezmoi.toml"
EOF
        chown -R testuser:testuser /home/testuser/.config
    fi
    
    # Ensure chezmoi source directory exists
    if [ ! -d "/home/testuser/.local/share/chezmoi" ]; then
        log "Creating chezmoi source directory"
        mkdir -p /home/testuser/.local/share/chezmoi
        chown -R testuser:testuser /home/testuser/.local
    fi
    
    log "User environment initialization complete"
}

# Function to verify development tools
verify_development_tools() {
    log "Verifying development tools..."
    
    local tools=("python3" "node" "git" "chezmoi" "apt" "pip3" "npm")
    local missing_tools=()
    
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -eq 0 ]; then
        log "All development tools are available"
    else
        log "Warning: Missing tools: ${missing_tools[*]}"
    fi
}

# Function to start required services
start_services() {
    log "Starting required services..."
    
    # Start SSH service if available
    if command -v sshd >/dev/null 2>&1; then
        log "Starting SSH service..."
        service ssh start || log "Warning: Could not start SSH service"
    fi
    
    # Start cron service if available
    if command -v cron >/dev/null 2>&1; then
        log "Starting cron service..."
        service cron start || log "Warning: Could not start cron service"
    fi
}

# Function to create test data directories
create_test_directories() {
    log "Creating test data directories..."
    
    local test_dirs=(
        "/tmp/wsl-test"
        "/home/testuser/test-projects"
        "/home/testuser/test-scripts"
    )
    
    for dir in "${test_dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
            if [[ "$dir" == /home/testuser/* ]]; then
                chown testuser:testuser "$dir"
            fi
        fi
    done
    
    log "Test directories created"
}

# Function to verify container health
verify_container_health() {
    log "Verifying container health..."
    
    # Check if we can execute basic commands
    if ! whoami >/dev/null 2>&1; then
        log "Error: Cannot determine current user"
        return 1
    fi
    
    # Check if we can access user home directory
    if [ ! -d "/home/testuser" ]; then
        log "Error: testuser home directory not found"
        return 1
    fi
    
    # Check if we can execute commands as testuser
    if ! su -c "echo 'test'" testuser >/dev/null 2>&1; then
        log "Error: Cannot execute commands as testuser"
        return 1
    fi
    
    log "Container health check passed"
    return 0
}

# Main startup sequence
main() {
    log "Starting WSL container initialization..."
    
    # Initialize user environment
    init_user_environment
    
    # Start required services
    start_services
    
    # Create test directories
    create_test_directories
    
    # Verify development tools
    verify_development_tools
    
    # Verify container health
    if ! verify_container_health; then
        log "Error: Container health check failed"
        exit 1
    fi
    
    log "WSL container initialization complete"
    log "Container is ready for testing"
    
    # Keep container running
    log "Container is now running and ready for connections"
    exec tail -f /dev/null
}

# Run main function
main "$@" 