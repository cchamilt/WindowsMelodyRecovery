#!/bin/bash
# WSL Container Startup Script
# This script ensures the WSL container is properly initialized and ready for testing

set -e

# Logging function
log() {
    echo "[WSL-STARTUP] $(date '+%Y-%m-%d %H:%M:%S') - $*"
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

# Function to start SSH daemon
start_sshd() {
    log "Starting SSH daemon..."
    
    # Ensure SSH directory exists
    mkdir -p /var/run/sshd
    
    # Start SSH daemon directly
    if command -v sshd >/dev/null 2>&1; then
        log "Starting sshd daemon..."
        /usr/sbin/sshd -D &
        log "SSH daemon started in background"
    else
        log "Warning: SSH daemon not available"
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
    
    # Start SSH daemon
    start_sshd
    
    # Create test directories
    create_test_directories
    
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