#!/bin/bash
# Mock Windows reg command for testing

REGISTRY_ROOT=${REGISTRY_ROOT:-/mock-registry}

case "$1" in
    "export")
        # reg export HKEY_LOCAL_MACHINE\SOFTWARE\Test output.reg
        KEY="$2"
        OUTPUT="$3"
        
        # Convert Windows registry path to mock path
        MOCK_PATH=$(echo "$KEY" | sed 's/HKEY_LOCAL_MACHINE/HKLM/g' | sed 's/HKEY_CURRENT_USER/HKCU/g' | sed 's/\\/\//g')
        FULL_PATH="$REGISTRY_ROOT/$MOCK_PATH"
        
        # Create mock registry export
        mkdir -p "$(dirname "$OUTPUT")"
        cat > "$OUTPUT" << EOF
Windows Registry Editor Version 5.00

[$KEY]
"MockValue"="MockData"
"TestValue"=dword:00000001
"StringValue"="Test String Data"

EOF
        echo "Registry export completed successfully"
        exit 0
        ;;
    "import")
        # reg import input.reg
        INPUT="$2"
        if [ -f "$INPUT" ]; then
            echo "Registry import completed successfully"
            exit 0
        else
            echo "Error: File not found"
            exit 1
        fi
        ;;
    "query")
        # reg query HKEY_LOCAL_MACHINE\SOFTWARE\Test
        KEY="$2"
        echo "Registry query for $KEY"
        echo "MockValue    REG_SZ    MockData"
        echo "TestValue    REG_DWORD    0x1"
        exit 0
        ;;
    "add")
        # reg add HKEY_LOCAL_MACHINE\SOFTWARE\Test /v TestValue /t REG_DWORD /d 1
        echo "Registry add operation completed"
        exit 0
        ;;
    "delete")
        # reg delete HKEY_LOCAL_MACHINE\SOFTWARE\Test /v TestValue
        echo "Registry delete operation completed"
        exit 0
        ;;
    *)
        echo "Mock reg command - Usage: reg [export|import|query|add|delete] ..."
        exit 1
        ;;
esac 