#!/bin/bash

# Mock explorer.exe for Windows Melody Recovery Docker testing
# This script simulates Windows Explorer behavior in Linux environment

# Function to log mock explorer actions
log_explorer_action() {
    local action="$1"
    local target="$2"
    echo "[MOCK EXPLORER] Action: $action, Target: $target" >&2
}

# Parse command line arguments
FILEPATH=""
OPERATION=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -FilePath)
            FILEPATH="$2"
            shift 2
            ;;
        /select,*)
            OPERATION="select"
            FILEPATH="${1#/select,}"
            shift
            ;;
        /e,*)
            OPERATION="explore"
            FILEPATH="${1#/e,}"
            shift
            ;;
        /root,*)
            OPERATION="root"
            FILEPATH="${1#/root,}"
            shift
            ;;
        *)
            if [[ -z "$FILEPATH" ]]; then
                FILEPATH="$1"
            fi
            shift
            ;;
    esac
done

# Default to current directory if no path specified
if [[ -z "$FILEPATH" ]]; then
    FILEPATH="."
fi

# Convert Windows paths to Linux paths for testing
LINUX_PATH="$FILEPATH"
if [[ "$FILEPATH" =~ ^[A-Za-z]: ]]; then
    # Convert C:\ style paths to /mnt/c/ style
    DRIVE_LETTER=$(echo "$FILEPATH" | cut -c1 | tr '[:upper:]' '[:lower:]')
    REST_PATH=$(echo "$FILEPATH" | cut -c4- | tr '\\' '/')
    LINUX_PATH="/mnt/$DRIVE_LETTER/$REST_PATH"
fi

# Mock different explorer operations
case "$OPERATION" in
    "select")
        log_explorer_action "Select file/folder" "$FILEPATH"
        echo "Mock: Would select '$FILEPATH' in Windows Explorer"
        exit 0
        ;;
    "explore")
        log_explorer_action "Explore folder" "$FILEPATH"
        echo "Mock: Would open '$FILEPATH' in Windows Explorer"
        exit 0
        ;;
    "root")
        log_explorer_action "Open with root" "$FILEPATH"
        echo "Mock: Would open '$FILEPATH' as root folder in Windows Explorer"
        exit 0
        ;;
    *)
        log_explorer_action "Open" "$FILEPATH"
        echo "Mock: Would open '$FILEPATH' in Windows Explorer"

        # For directories, simulate listing contents
        if [[ -d "$LINUX_PATH" ]]; then
            echo "Mock: Directory contents would be displayed in Explorer"
            ls -la "$LINUX_PATH" 2>/dev/null || echo "Mock: Directory listing simulation"
        elif [[ -f "$LINUX_PATH" ]]; then
            echo "Mock: File would be opened or selected in Explorer"
        else
            echo "Mock: Path does not exist, Explorer would show error"
        fi
        exit 0
        ;;
esac
