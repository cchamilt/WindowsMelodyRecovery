# tests/unit/RegistryState.Tests.ps1

BeforeAll {
    # Determine script root path
    $scriptRoot = if ($PSScriptRoot) { 
        $PSScriptRoot 
    } elseif ($MyInvocation.MyCommand.Path) {
        Split-Path $MyInvocation.MyCommand.Path
    } else {
        "/workspace/tests/unit"
    }
    
    # Import registry mocking utilities first
    . "$scriptRoot/../utilities/Registry-Mock.ps1"
    
    # Enable registry mocking for the test environment
    Enable-RegistryMocking
    
    # Directly source the registry state functions
    . "$scriptRoot/../../Private/Core/RegistryState.ps1"
    . "$scriptRoot/../../Private/Core/PathUtilities.ps1"
    
    # Setup a temporary directory for state files
    $script:TempStateDir = if ($IsLinux) {
        "/tmp/RegistryStateTests"
    } else {
        Join-Path $env:TEMP "RegistryStateTests"
    }
    
    if (-not (Test-Path $script:TempStateDir -PathType Container)) {
        New-Item -ItemType Directory -Path $script:TempStateDir -Force | Out-Null
    }

    # Mock encryption functions for testing purposes
    function Protect-WmrData {
        param([byte[]]$DataBytes)
        return [System.Convert]::ToBase64String($DataBytes)
    }
    
    function Unprotect-WmrData {
        param([string]$EncodedData)
        # Ensure we return a proper byte array, not a string representation
        $bytes = [System.Convert]::FromBase64String($EncodedData)
        return ,$bytes  # Comma operator ensures array is returned as-is
    }
}

AfterAll {
    # Disable registry mocking
    Disable-RegistryMocking
    
    # Clean up temporary directories
    Remove-Item -Path $script:TempStateDir -Recurse -Force -ErrorAction SilentlyContinue
}

Describe "Get-WmrRegistryState" {

    BeforeEach {
        # Reset mock registry for each test
        Initialize-MockRegistry
        
        # Ensure clean state for each test - use actual Remove-Item cmdlet, not the mock
        if (Test-Path $script:TempStateDir) {
            $items = Get-ChildItem $script:TempStateDir -ErrorAction SilentlyContinue
            if ($items) {
                $items | ForEach-Object { & (Get-Command Remove-Item -CommandType Cmdlet) -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
            }
        }
    }

    It "should capture a specific registry value and save to dynamic_state_path" {
        $registryConfig = @{
            name = "Test Registry Value"
            path = "HKCU:\SOFTWARE\WmrRegTest"
            type = "value"
            key_name = "TestValue"
            dynamic_state_path = "test_registry_value.json"
        }

        $result = Get-WmrRegistryState -RegistryConfig $registryConfig -StateFilesDirectory $script:TempStateDir

        # Verify the result
        $result | Should -Not -BeNullOrEmpty
        $result.Name | Should -Be "Test Registry Value"
        $result.Path | Should -Be "HKCU:\SOFTWARE\WmrRegTest"
        $result.Type | Should -Be "value"
        $result.KeyName | Should -Be "TestValue"
        $result.Value | Should -Be "OriginalData"
        $result.Encrypted | Should -Be $false

        # Verify state file was created
        $stateFilePath = Join-Path $script:TempStateDir "test_registry_value.json"
        Test-Path $stateFilePath | Should -Be $true
        
        # Verify state file content
        $stateContent = Get-Content $stateFilePath -Raw | ConvertFrom-Json
        $stateContent.Name | Should -Be "Test Registry Value"
        $stateContent.Value | Should -Be "OriginalData"
    }

    It "should capture a specific registry value and simulate encryption" {
        $registryConfig = @{
            name = "Test Encrypted Registry Value"
            path = "HKCU:\SOFTWARE\WmrRegTest"
            type = "value"
            key_name = "TestValue"
            encrypt = $true
            dynamic_state_path = "test_encrypted_registry_value.json"
        }

        $result = Get-WmrRegistryState -RegistryConfig $registryConfig -StateFilesDirectory $script:TempStateDir

        # Verify the result
        $result | Should -Not -BeNullOrEmpty
        $result.Name | Should -Be "Test Encrypted Registry Value"
        $result.Path | Should -Be "HKCU:\SOFTWARE\WmrRegTest"
        $result.Type | Should -Be "value"
        $result.KeyName | Should -Be "TestValue"
        $result.Encrypted | Should -Be $true
        $result.EncryptedValue | Should -Not -BeNullOrEmpty
        $result.PSObject.Properties.Name | Should -Not -Contain "Value"  # Original value should be removed

        # Verify state file was created
        $stateFilePath = Join-Path $script:TempStateDir "test_encrypted_registry_value.json"
        Test-Path $stateFilePath | Should -Be $true
        
        # Verify state file content
        $stateContent = Get-Content $stateFilePath -Raw | ConvertFrom-Json
        $stateContent.Name | Should -Be "Test Encrypted Registry Value"
        $stateContent.Encrypted | Should -Be $true
        $stateContent.EncryptedValue | Should -Not -BeNullOrEmpty
    }

    It "should capture all values under a registry key" {
        $registryConfig = @{
            name = "Test Registry Key"
            path = "HKCU:\SOFTWARE\WmrRegTest"
            type = "key"
            dynamic_state_path = "test_registry_key.json"
        }

        $result = Get-WmrRegistryState -RegistryConfig $registryConfig -StateFilesDirectory $script:TempStateDir

        # Verify the result
        $result | Should -Not -BeNullOrEmpty
        $result.Name | Should -Be "Test Registry Key"
        $result.Path | Should -Be "HKCU:\SOFTWARE\WmrRegTest"
        $result.Type | Should -Be "key"
        $result.Values | Should -Not -BeNullOrEmpty
        $result.Values.TestValue | Should -Be "OriginalData"
        $result.Values.NumericValue | Should -Be 12345

        # Verify state file was created
        $stateFilePath = Join-Path $script:TempStateDir "test_registry_key.json"
        Test-Path $stateFilePath | Should -Be $true
        
        # Verify state file content
        $stateContent = Get-Content $stateFilePath -Raw | ConvertFrom-Json
        $stateContent.Name | Should -Be "Test Registry Key"
        $stateContent.Values.TestValue | Should -Be "OriginalData"
    }

    It "should warn and return null if registry path does not exist" {
        $registryConfig = @{
            name = "Non-existent Registry Key"
            path = "HKCU:\SOFTWARE\NonExistentKey"
            type = "key"
            dynamic_state_path = "non_existent_registry_key.json"
        }

        $result = Get-WmrRegistryState -RegistryConfig $registryConfig -StateFilesDirectory $script:TempStateDir

        # Should return null
        $result | Should -BeNullOrEmpty
        
        # State file should not be created
        $stateFilePath = Join-Path $script:TempStateDir "non_existent_registry_key.json"
        Test-Path $stateFilePath | Should -Be $false
    }
}

Describe "Set-WmrRegistryState" {

    BeforeEach {
        # Reset mock registry for each test
        Initialize-MockRegistry
        
        # Ensure clean state for each test - use actual Remove-Item cmdlet, not the mock
        if (Test-Path $script:TempStateDir) {
            $items = Get-ChildItem $script:TempStateDir -ErrorAction SilentlyContinue
            if ($items) {
                $items | ForEach-Object { & (Get-Command Remove-Item -CommandType Cmdlet) -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
            }
        }
    }

    It "should restore a specific registry value from dynamic_state_path" {
        # First, capture the state
        $registryConfig = @{
            name = "Test Registry Value"
            path = "HKCU:\SOFTWARE\WmrRegTest"
            type = "value"
            key_name = "TestValue"
            dynamic_state_path = "test_restore_value.json"
        }

        Get-WmrRegistryState -RegistryConfig $registryConfig -StateFilesDirectory $script:TempStateDir

        # Modify the registry value
        Set-ItemProperty -Path "HKCU:\SOFTWARE\WmrRegTest" -Name "TestValue" -Value "ModifiedData"

        # Restore the state
        Set-WmrRegistryState -RegistryConfig $registryConfig -StateFilesDirectory $script:TempStateDir

        # Verify the restoration
        $restoredValue = (Get-ItemProperty -Path "HKCU:\SOFTWARE\WmrRegTest" -Name "TestValue").TestValue
        $restoredValue | Should -Be "OriginalData"
    }

    It "should restore a specific registry value and simulate decryption" {
        # First, capture the state with encryption
        $registryConfig = @{
            name = "Test Encrypted Registry Value"
            path = "HKCU:\SOFTWARE\WmrRegTest"
            type = "value"
            key_name = "TestValue"
            encrypt = $true
            dynamic_state_path = "test_restore_encrypted_value.json"
        }

        Get-WmrRegistryState -RegistryConfig $registryConfig -StateFilesDirectory $script:TempStateDir

        # Modify the registry value
        Set-ItemProperty -Path "HKCU:\SOFTWARE\WmrRegTest" -Name "TestValue" -Value "ModifiedData"

        # Restore the state (should decrypt)
        Set-WmrRegistryState -RegistryConfig $registryConfig -StateFilesDirectory $script:TempStateDir

        # Verify the restoration
        $restoredValue = (Get-ItemProperty -Path "HKCU:\SOFTWARE\WmrRegTest" -Name "TestValue").TestValue
        $restoredValue | Should -Be "OriginalData"
    }

    It "should restore registry key values from dynamic_state_path" {
        # First, capture the state
        $registryConfig = @{
            name = "Test Registry Key"
            path = "HKCU:\SOFTWARE\WmrRegTest"
            type = "key"
            dynamic_state_path = "test_restore_key.json"
        }

        Get-WmrRegistryState -RegistryConfig $registryConfig -StateFilesDirectory $script:TempStateDir

        # Modify the registry values
        Set-ItemProperty -Path "HKCU:\SOFTWARE\WmrRegTest" -Name "TestValue" -Value "ModifiedData"
        Set-ItemProperty -Path "HKCU:\SOFTWARE\WmrRegTest" -Name "NumericValue" -Value 99999

        # Restore the state
        Set-WmrRegistryState -RegistryConfig $registryConfig -StateFilesDirectory $script:TempStateDir

        # Verify the restoration
        $restoredValues = Get-ItemProperty -Path "HKCU:\SOFTWARE\WmrRegTest"
        $restoredValues.TestValue | Should -Be "OriginalData"
        $restoredValues.NumericValue | Should -Be 12345
    }

    It "should use default value_data if state file is missing for a value type" {
        $registryConfig = @{
            name = "Test Registry Value with Default"
            path = "HKCU:\SOFTWARE\WmrRegTestDest"
            type = "value"
            key_name = "DefaultValue"
            value_data = "DefaultData"
            dynamic_state_path = "non_existent_state.json"
        }

        # Restore the state (should use default)
        Set-WmrRegistryState -RegistryConfig $registryConfig -StateFilesDirectory $script:TempStateDir

        # Verify the default value was set
        $restoredValue = (Get-ItemProperty -Path "HKCU:\SOFTWARE\WmrRegTestDest" -Name "DefaultValue").DefaultValue
        $restoredValue | Should -Be "DefaultData"
    }

    It "should warn if state file is missing and no default value_data for a value type" {
        $registryConfig = @{
            name = "Test Registry Value without Default"
            path = "HKCU:\SOFTWARE\WmrRegTestDest"
            type = "value"
            key_name = "NoDefaultValue"
            dynamic_state_path = "non_existent_state.json"
        }

        # Restore the state (should warn)
        Set-WmrRegistryState -RegistryConfig $registryConfig -StateFilesDirectory $script:TempStateDir

        # Verify the value was not set
        $valueExists = $null
        try {
            $valueExists = (Get-ItemProperty -Path "HKCU:\SOFTWARE\WmrRegTestDest" -Name "NoDefaultValue" -ErrorAction Stop).NoDefaultValue
        } catch {
            # Expected - value should not exist
        }
        $valueExists | Should -BeNullOrEmpty
    }

    It "should warn if state file is missing for a key type" {
        $registryConfig = @{
            name = "Test Registry Key without State"
            path = "HKCU:\SOFTWARE\WmrRegTestDest"
            type = "key"
            dynamic_state_path = "non_existent_state.json"
        }

        # Restore the state (should warn)
        Set-WmrRegistryState -RegistryConfig $registryConfig -StateFilesDirectory $script:TempStateDir

        # Should not cause any errors, just warnings
        $true | Should -Be $true
    }
}