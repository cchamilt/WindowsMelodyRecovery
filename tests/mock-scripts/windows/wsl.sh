#!/bin/bash
# Mock WSL command for testing - routes commands to wmr-wsl-mock container

WSL_CONTAINER="wmr-wsl-mock"
WSL_USER="testuser"

# Function to execute command in WSL container
exec_in_wsl() {
    local cmd="$1"
    local user="${2:-$WSL_USER}"
    
    if [ "$user" = "root" ]; then
        docker exec "$WSL_CONTAINER" bash -c "$cmd"
    else
        docker exec -u "$user" "$WSL_CONTAINER" bash -c "$cmd"
    fi
}

# Parse WSL command line arguments
case "$1" in
    "--list"|"-l")
        if [ "$2" = "--verbose" ] || [ "$2" = "-v" ]; then
            echo "  NAME                   STATE           VERSION"
            echo "* Ubuntu-22.04          Running         2"
            echo "  Debian                Stopped         2"
            echo "  openSUSE-Leap-15.5    Stopped         2"
        elif [ "$2" = "--quiet" ] || [ "$2" = "-q" ]; then
            echo "Ubuntu-22.04"
            echo "Debian"
            echo "openSUSE-Leap-15.5"
        else
            echo "Ubuntu-22.04 (Default)"
            echo "Debian"
            echo "openSUSE-Leap-15.5"
        fi
        ;;
    "--distribution"|"-d")
        # wsl -d Ubuntu-22.04 [command]
        DISTRO="$2"
        shift 2
        
        if [ "$1" = "--" ]; then
            shift
            # Execute the remaining command in WSL container
            exec_in_wsl "$*"
        elif [ "$1" = "--exec" ]; then
            shift
            # Execute with exec flag
            exec_in_wsl "$*"
        else
            # No command, just start interactive session
            docker exec -it -u "$WSL_USER" "$WSL_CONTAINER" bash
        fi
        ;;
    "--exec")
        # wsl --exec command
        shift
        exec_in_wsl "$*"
        ;;
    "--user"|"-u")
        # wsl --user username [command]
        USER="$2"
        shift 2
        if [ "$1" = "--" ]; then
            shift
        fi
        exec_in_wsl "$*" "$USER"
        ;;
    "--shutdown")
        echo "Shutting down all WSL distributions..."
        # In our mock, we don't actually shut down the container
        echo "WSL shutdown complete."
        ;;
    "--status")
        echo "Default distribution: Ubuntu-22.04"
        echo "Default version: 2"
        ;;
    "--version")
        echo "WSL version: 2.0.0.0"
        echo "Kernel version: 5.15.68.1"
        echo "WSLg version: 1.0.47"
        ;;
    "--help"|"-h"|"")
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
EOF
        ;;
    *)
        # Default: execute command in default distribution
        if [ $# -gt 0 ]; then
            exec_in_wsl "$*"
        else
            # No arguments, start interactive session
            docker exec -it -u "$WSL_USER" "$WSL_CONTAINER" bash
        fi
        ;;
esac 