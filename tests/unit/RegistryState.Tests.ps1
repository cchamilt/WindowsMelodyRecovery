# tests/unit/RegistryState.Tests.ps1

BeforeAll {
    # Import the WindowsMelodyRecovery module to make functions available
    Import-Module WindowsMelodyRecovery -Force # For mocked encryption

    # Setup a temporary directory for state files
    $script:TempStateDir = Join-Path $PSScriptRoot "..\..\Temp\RegistryStateTests"
    if (-not (Test-Path $script:TempStateDir -PathType Container)) {
        New-Item -ItemType Directory -Path $script:TempStateDir -Force | Out-Null
    }

    # Mock encryption functions for testing purposes
    Mock Protect-WmrData {
        param([byte[]]$DataBytes)
        return [System.Convert]::ToBase64String($DataBytes) # Simply Base64 encode for mock
    }
    Mock Unprotect-WmrData {
        param([string]$EncodedData)
        return [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($EncodedData)) # Simply Base64 decode for mock
    }
}

AfterAll {
    # Clean up temporary directories
    Remove-Item -Path $script:TempStateDir -Recurse -Force -ErrorAction SilentlyContinue
    # Unmock functions
# Note: In Pester 5+, mocks are automatically cleaned up
}

Describe "Get-WmrRegistryState" {

    BeforeEach {
        # Ensure test key is clean before each test
        Remove-Item -Path "HKCU:\SOFTWARE\WmrRegTest" -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -Path "HKCU:\SOFTWARE\WmrRegTest" -Force | Out-Null
        Set-ItemProperty -Path "HKCU:\SOFTWARE\WmrRegTest" -Name "TestValue" -Value "OriginalData" -Force | Out-Null
        Set-ItemProperty -Path "HKCU:\SOFTWARE\WmrRegTest" -Name "NumericValue" -Value 12345 -Force | Out-Null
    }

    It "should capture a specific registry value and save to dynamic_state_path" {
        $regConfig = @{
            name = "Test Reg Value Capture"
            path = "HKCU:\SOFTWARE\WmrRegTest"
            key_name = "TestValue"
            type = "value"
            action = "backup"
            dynamic_state_path = "registry/test_value.json"
            encrypt = $false
        }

        $result = Get-WmrRegistryState -RegistryConfig $regConfig -StateFilesDirectory $script:TempStateDir
        $result | Should Not BeNull
        $result.Name | Should Be "Test Reg Value Capture"
        $result.Path | Should Be "HKCU:\SOFTWARE\WmrRegTest"
        $result.KeyName | Should Be "TestValue"
        $result.Value | Should Be "OriginalData"

        $stateFilePath = Join-Path $script:TempStateDir "registry/test_value.json"
        (Test-Path $stateFilePath) | Should Be $true
        $stateContent = (Get-Content -Path $stateFilePath -Raw -Encoding Utf8) | ConvertFrom-Json
        $stateContent.Value | Should Be "OriginalData"
    }

    It "should capture a specific registry value and simulate encryption" {
        $regConfig = @{
            name = "Encrypted Reg Value Capture"
            path = "HKCU:\SOFTWARE\WmrRegTest"
            key_name = "TestValue"
            type = "value"
            action = "backup"
            dynamic_state_path = "registry/encrypted_value.json"
            encrypt = $true
        }

        $result = Get-WmrRegistryState -RegistryConfig $regConfig -StateFilesDirectory $script:TempStateDir
        $result | Should Not BeNull
        $result.Value | Should Not Be "OriginalData" # Should be Base64 encoded

        $stateFilePath = Join-Path $script:TempStateDir "registry/encrypted_value.json"
        (Test-Path $stateFilePath) | Should Be $true
        $stateContent = (Get-Content -Path $stateFilePath -Raw -Encoding Utf8) | ConvertFrom-Json
        # In Get-WmrRegistryState, the value stored in the state file is already Base64 encoded if encrypt is true
        $stateContent.Value | Should Not Be "OriginalData"
        [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($stateContent.Value)) | Should Be "OriginalData"
    }

    It "should capture all values under a registry key" {
        $regConfig = @{
            name = "Test Reg Key Capture"
            path = "HKCU:\SOFTWARE\WmrRegTest"
            type = "key"
            action = "backup"
            dynamic_state_path = "registry/test_key.json"
        }

        $result = Get-WmrRegistryState -RegistryConfig $regConfig -StateFilesDirectory $script:TempStateDir
        $result | Should Not BeNull
        $result.Name | Should Be "Test Reg Key Capture"
        $result.Path | Should Be "HKCU:\SOFTWARE\WmrRegTest"
        $result.Type | Should Be "key"
        $result.Values | Should Not BeNullOrEmpty
        $result.Values.TestValue | Should Be "OriginalData"
        $result.Values.NumericValue | Should Be 12345

        $stateFilePath = Join-Path $script:TempStateDir "registry/test_key.json"
        (Test-Path $stateFilePath) | Should Be $true
        $stateContent = (Get-Content -Path $stateFilePath -Raw -Encoding Utf8) | ConvertFrom-Json
        $stateContent.Values.TestValue | Should Be "OriginalData"
    }

    It "should warn and return null if registry path does not exist" {
        $regConfig = @{
            name = "Non Existent Reg Key"
            path = "HKCU:\SOFTWARE\NonExistentRegKey"
            type = "key"
            action = "backup"
            dynamic_state_path = "registry/non_existent.json"
        }
        $result = Get-WmrRegistryState -RegistryConfig $regConfig -StateFilesDirectory $script:TempStateDir
        $result | Should BeNull
    }
}

Describe "Set-WmrRegistryState" {

    BeforeEach {
        # Ensure test key is clean before each test
        Remove-Item -Path "HKCU:\SOFTWARE\WmrRegTestDest" -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -Path "HKCU:\SOFTWARE\WmrRegTestDest" -Force | Out-Null
    }

    It "should restore a specific registry value from dynamic_state_path" {
        $stateData = @{
            Name = "Restore Value"
            Path = "HKCU:\SOFTWARE\WmrRegTestDest"
            KeyName = "RestoredValue"
            Value = "RestoredData"
        }
        $stateFilePath = Join-Path $script:TempStateDir "registry/restore_value.json"
        $stateData | ConvertTo-Json -Compress | Set-Content -Path $stateFilePath -Encoding Utf8

        $regConfig = @{
            name = "Restore Value Item"
            path = "HKCU:\SOFTWARE\WmrRegTestDest"
            key_name = "RestoredValue"
            type = "value"
            action = "restore"
            dynamic_state_path = "registry/restore_value.json"
            encrypt = $false
        }

        Set-WmrRegistryState -RegistryConfig $regConfig -StateFilesDirectory $script:TempStateDir

        (Get-ItemProperty -Path "HKCU:\SOFTWARE\WmrRegTestDest" -Name "RestoredValue").RestoredValue | Should Be "RestoredData"
    }

    It "should restore a specific registry value and simulate decryption" {
        $originalValue = "EncryptedDataToRestore"
        # Simulate encrypted data (Base64 encoded string)
        $encryptedOriginalValue = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($originalValue))

        $stateData = @{
            Name = "Restore Encrypted Value"
            Path = "HKCU:\SOFTWARE\WmrRegTestDest"
            KeyName = "EncryptedRestoredValue"
            Value = $encryptedOriginalValue
        }
        $stateFilePath = Join-Path $script:TempStateDir "registry/restore_encrypted_value.json"
        $stateData | ConvertTo-Json -Compress | Set-Content -Path $stateFilePath -Encoding Utf8

        $regConfig = @{
            name = "Restore Encrypted Value Item"
            path = "HKCU:\SOFTWARE\WmrRegTestDest"
            key_name = "EncryptedRestoredValue"
            type = "value"
            action = "restore"
            dynamic_state_path = "registry/restore_encrypted_value.json"
            encrypt = $true
        }

        Set-WmrRegistryState -RegistryConfig $regConfig -StateFilesDirectory $script:TempStateDir

        (Get-ItemProperty -Path "HKCU:\SOFTWARE\WmrRegTestDest" -Name "EncryptedRestoredValue").EncryptedRestoredValue | Should Be $originalValue
    }

    It "should restore registry key values from dynamic_state_path" {
        $stateData = @{
            Name = "Restore Key"
            Path = "HKCU:\SOFTWARE\WmrRegTestDest"
            Values = @{
                ValueA = "DataA"
                ValueB = 456
            }
        }
        $stateFilePath = Join-Path $script:TempStateDir "registry/restore_key.json"
        $stateData | ConvertTo-Json -Compress | Set-Content -Path $stateFilePath -Encoding Utf8

        $regConfig = @{
            name = "Restore Key Item"
            path = "HKCU:\SOFTWARE\WmrRegTestDest"
            type = "key"
            action = "restore"
            dynamic_state_path = "registry/restore_key.json"
        }

        Set-WmrRegistryState -RegistryConfig $regConfig -StateFilesDirectory $script:TempStateDir

        (Get-ItemProperty -Path "HKCU:\SOFTWARE\WmrRegTestDest").ValueA | Should Be "DataA"
        (Get-ItemProperty -Path "HKCU:\SOFTWARE\WmrRegTestDest").ValueB | Should Be 456
    }

    It "should use default value_data if state file is missing for a value type" {
        $regConfig = @{
            name = "Default Value Test"
            path = "HKCU:\SOFTWARE\WmrRegTestDest"
            key_name = "DefaultedValue"
            type = "value"
            action = "restore"
            dynamic_state_path = "registry/non_existent_state_for_default.json"
            value_data = "DefaultValue"
        }

        Set-WmrRegistryState -RegistryConfig $regConfig -StateFilesDirectory $script:TempStateDir

        (Get-ItemProperty -Path "HKCU:\SOFTWARE\WmrRegTestDest" -Name "DefaultedValue").DefaultedValue | Should Be "DefaultValue"
    }

    It "should warn if state file is missing and no default value_data for a value type" {
        $regConfig = @{
            name = "Missing State and No Default Value Test"
            path = "HKCU:\SOFTWARE\WmrRegTestDest"
            key_name = "NoDataValue"
            type = "value"
            action = "restore"
            dynamic_state_path = "registry/non_existent_state_no_default.json"
        }

        Set-WmrRegistryState -RegistryConfig $regConfig -StateFilesDirectory $script:TempStateDir

        (Test-Path -Path "HKCU:\SOFTWARE\WmrRegTestDest\NoDataValue") | Should Be $false # Ensure value was not created
    }

    It "should warn if state file is missing for a key type" {
        $regConfig = @{
            name = "Missing State Key Test"
            path = "HKCU:\SOFTWARE\WmrRegTestDest\MissingKey"
            type = "key"
            action = "restore"
            dynamic_state_path = "registry/non_existent_state_key.json"
        }

        Set-WmrRegistryState -RegistryConfig $regConfig -StateFilesDirectory $script:TempStateDir

        (Test-Path -Path "HKCU:\SOFTWARE\WmrRegTestDest\MissingKey") | Should Be $false # Ensure key was not created with values
    }
} 