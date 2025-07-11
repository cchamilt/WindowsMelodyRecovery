#!/bin/bash
# Mock WSL command for testing - routes commands to wmr-wsl-mock container

WSL_CONTAINER="wmr-wsl-mock"
WSL_USER="testuser"
DEBUG_MODE="${WSL_DEBUG:-false}"

# Logging function
log_debug() {
    if [ "$DEBUG_MODE" = "true" ]; then
        echo "[WSL-MOCK-DEBUG] $*" >&2
    fi
}

# Function to check if WSL container is running
check_wsl_container() {
    if ! docker ps --format "table {{.Names}}" | grep -q "^${WSL_CONTAINER}$"; then
        echo "Error: WSL container '${WSL_CONTAINER}' is not running" >&2
        log_debug "Available containers: $(docker ps --format "table {{.Names}}")"
        return 1
    fi
    return 0
}

# Function to execute command in WSL container with better error handling
exec_in_wsl() {
    local cmd="$1"
    local user="${2:-$WSL_USER}"

    log_debug "Executing command in WSL container: '$cmd' as user '$user'"

    # Check if container is running
    if ! check_wsl_container; then
        return 1
    fi

    # Execute command with proper error handling
    if [ "$user" = "root" ]; then
        log_debug "Running as root: docker exec $WSL_CONTAINER bash -c '$cmd'"
        docker exec "$WSL_CONTAINER" bash -c "$cmd"
        local exit_code=$?
    else
        log_debug "Running as user: docker exec -u $user $WSL_CONTAINER bash -c '$cmd'"
        docker exec -u "$user" "$WSL_CONTAINER" bash -c "$cmd"
        local exit_code=$?
    fi

    log_debug "Command completed with exit code: $exit_code"
    return $exit_code
}

# Function to test container connectivity
test_connectivity() {
    log_debug "Testing connectivity to WSL container..."

    if ! check_wsl_container; then
        return 1
    fi

    # Test basic connectivity
    if docker exec "$WSL_CONTAINER" echo "connectivity test" >/dev/null 2>&1; then
        log_debug "Basic connectivity test passed"
        return 0
    else
        log_debug "Basic connectivity test failed"
        return 1
    fi
}

# Check for test-connectivity argument first
if [ "$1" = "--test-connectivity" ]; then
    log_debug "Testing WSL container connectivity"
    if test_connectivity; then
        echo "WSL container connectivity test: PASSED"
        exit 0
    else
        echo "WSL container connectivity test: FAILED"
        exit 1
    fi
fi

# Parse WSL command line arguments
# We need to handle arguments properly to avoid bash interpreting them
while [[ $# -gt 0 ]]; do
    case $1 in
        --list|-l)
            log_debug "Handling --list command"
            shift
            if [ "$1" = "--verbose" ] || [ "$1" = "-v" ]; then
                echo "  NAME                   STATE           VERSION"
                echo "* Ubuntu-22.04          Running         2"
                echo "  Debian                Stopped         2"
                echo "  openSUSE-Leap-15.5    Stopped         2"
                shift
            elif [ "$1" = "--quiet" ] || [ "$1" = "-q" ]; then
                echo "Ubuntu-22.04"
                echo "Debian"
                echo "openSUSE-Leap-15.5"
                shift
            else
                echo "Ubuntu-22.04 (Default)"
                echo "Debian"
                echo "openSUSE-Leap-15.5"
            fi
            exit 0
            ;;
        --distribution|-d)
            log_debug "Handling --distribution command with distro: $2"
            DISTRO="$2"
            shift 2

            if [ "$1" = "--" ]; then
                shift
                # Execute the remaining command in WSL container
                exec_in_wsl "$*"
                exit $?
            elif [ "$1" = "--exec" ]; then
                shift
                # Execute with exec flag
                exec_in_wsl "$*"
                exit $?
            else
                # No command, just start interactive session
                log_debug "Starting interactive session for distribution: $DISTRO"
                docker exec -it -u "$WSL_USER" "$WSL_CONTAINER" bash
                exit $?
            fi
            ;;
        --exec)
            log_debug "Handling --exec command"
            shift
            exec_in_wsl "$*"
            exit $?
            ;;
        --user|-u)
            log_debug "Handling --user command with user: $2"
            USER="$2"
            shift 2
            if [ "$1" = "--" ]; then
                shift
            fi
            # Continue parsing for additional commands
            if [ "$1" = "--exec" ]; then
                shift
                exec_in_wsl "$*" "$USER"
                exit $?
            else
                exec_in_wsl "$*" "$USER"
                exit $?
            fi
            ;;
        --shutdown)
            log_debug "Handling --shutdown command"
            echo "Shutting down all WSL distributions..."
            # In our mock, we don't actually shut down the container
            echo "WSL shutdown complete."
            exit 0
            ;;
        --status)
            log_debug "Handling --status command"
            echo "Default distribution: Ubuntu-22.04"
            echo "Default version: 2"
            exit 0
            ;;
        --version)
            log_debug "Handling --version command"
            echo "WSL version: 2.0.0.0"
            echo "Kernel version: 5.15.68.1"
            echo "WSLg version: 1.0.47"
            exit 0
            ;;
        --help|-h)
            cat << 'EOF'
Usage: wsl [Argument] [Options...] [CommandLine]

Arguments for running Linux binaries:

    If no command line is provided, wsl.exe launches the default shell.

    --exec, -e <CommandLine>
        Execute the specified command without using the default Linux shell.

    --
        Pass the remaining command line as-is.

Options:
    --cd <Directory>
        Sets the specified directory as the current working directory.
        If ~ is used the Linux user's home path will be used. If the path begins
        with a / character, it will be interpreted as an absolute Linux path.
        Otherwise, the value must be an absolute Windows path and it will be
        converted to the corresponding Linux path.

    --distribution, -d <DistributionName>
        Run the specified distribution.

    --user, -u <UserName>
        Run as the specified user.

Arguments for managing Windows Subsystem for Linux:

    --help
        Display usage information.

    --list, -l [Options]
        Lists distributions.

        --verbose, -v
            Show detailed information about all distributions.

        --quiet, -q
            Only show distribution names.

    --shutdown
        Immediately terminates all running distributions and the WSL 2
        lightweight utility virtual machine.

    --status
        Show the status of Windows Subsystem for Linux.

    --version
        Display version information.

    --test-connectivity
        Test connectivity to WSL container (testing only).
EOF
            exit 0
            ;;
        *)
            # Default: execute command in default distribution
            if [ $# -gt 0 ]; then
                exec_in_wsl "$*"
                exit $?
            else
                # No arguments, start interactive session
                docker exec -it -u "$WSL_USER" "$WSL_CONTAINER" bash
                exit $?
            fi
            ;;
    esac
done

# If we get here with no arguments, start interactive session
docker exec -it -u "$WSL_USER" "$WSL_CONTAINER" bash