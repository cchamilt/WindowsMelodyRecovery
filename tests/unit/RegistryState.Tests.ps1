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
        return [System.Convert]::ToBase64String($DataBytes) # Simply Base64 encode for mock
    }
    
    function Unprotect-WmrData {
        param([string]$EncodedData)
        return [System.Text.Encoding]::UTF8.GetBytes([System.Convert]::FromBase64String($EncodedData)) # Simply Base64 decode for mock
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
        
        # Ensure clean state for each test
        if (Test-Path $script:TempStateDir) {
            Get-ChildItem $script:TempStateDir | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "should capture a specific registry value and save to dynamic_state_path" {
        $registryConfig = @{
            name = "Test Reg Value Capture"
            path = "HKCU:\SOFTWARE\WmrRegTest"
            type = "value"
            key_name = "TestValue"
            dynamic_state_path = "test_reg_value.json"
        }

        $result = Get-WmrRegistryState -RegistryConfig $registryConfig -StateFilesDirectory $script:TempStateDir

        $result | Should -Not -BeNullOrEmpty
        $result.Name | Should -Be "Test Reg Value Capture"
        $result.Path | Should -Be "HKCU:\SOFTWARE\WmrRegTest"
        $result.Type | Should -Be "value"
        $result.KeyName | Should -Be "TestValue"
        $result.Value | Should -Be "OriginalData"
        $result.Encrypted | Should -Be $false

        # Verify state file was created
        $stateFilePath = Join-Path $script:TempStateDir "test_reg_value.json"
        Test-Path $stateFilePath | Should -Be $true
        
        # Verify state file content
        $stateContent = Get-Content $stateFilePath -Raw | ConvertFrom-Json
        $stateContent.Name | Should -Be "Test Reg Value Capture"
        $stateContent.Value | Should -Be "OriginalData"
    }

    It "should capture a specific registry value and simulate encryption" {
        $registryConfig = @{
            name = "Encrypted Reg Value Capture"
            path = "HKCU:\SOFTWARE\WmrRegTest"
            type = "value"
            key_name = "EncryptedValue"
            dynamic_state_path = "test_encrypted_reg_value.json"
            encrypt = $true
        }

        $result = Get-WmrRegistryState -RegistryConfig $registryConfig -StateFilesDirectory $script:TempStateDir

        $result | Should -Not -BeNullOrEmpty
        $result.Name | Should -Be "Encrypted Reg Value Capture"
        $result.Encrypted | Should -Be $true
        $result.EncryptedValue | Should -Not -BeNullOrEmpty
        $result.Value | Should -BeNullOrEmpty # Should be removed after encryption

        # Verify state file was created
        $stateFilePath = Join-Path $script:TempStateDir "test_encrypted_reg_value.json"
        Test-Path $stateFilePath | Should -Be $true
        
        # Verify state file content
        $stateContent = Get-Content $stateFilePath -Raw | ConvertFrom-Json
        $stateContent.Encrypted | Should -Be $true
        $stateContent.EncryptedValue | Should -Not -BeNullOrEmpty
    }

    It "should capture all values under a registry key" {
        $registryConfig = @{
            name = "Test Reg Key Capture"
            path = "HKCU:\SOFTWARE\WmrRegTest"
            type = "key"
            dynamic_state_path = "test_reg_key.json"
        }

        $result = Get-WmrRegistryState -RegistryConfig $registryConfig -StateFilesDirectory $script:TempStateDir

        $result | Should -Not -BeNullOrEmpty
        $result.Name | Should -Be "Test Reg Key Capture"
        $result.Path | Should -Be "HKCU:\SOFTWARE\WmrRegTest"
        $result.Type | Should -Be "key"
        $result.Values | Should -Not -BeNullOrEmpty
        $result.Values.TestValue | Should -Be "OriginalData"
        $result.Values.NumericValue | Should -Be 12345

        # Verify state file was created
        $stateFilePath = Join-Path $script:TempStateDir "test_reg_key.json"
        Test-Path $stateFilePath | Should -Be $true
        
        # Verify state file content
        $stateContent = Get-Content $stateFilePath -Raw | ConvertFrom-Json
        $stateContent.Values.TestValue | Should -Be "OriginalData"
        $stateContent.Values.NumericValue | Should -Be 12345
    }

    It "should warn and return null if registry path does not exist" {
        $registryConfig = @{
            name = "Non Existent Reg Key"
            path = "HKCU:\SOFTWARE\NonExistent"
            type = "key"
            dynamic_state_path = "test_nonexistent_reg_key.json"
        }

        $result = Get-WmrRegistryState -RegistryConfig $registryConfig -StateFilesDirectory $script:TempStateDir

        $result | Should -BeNullOrEmpty
    }
}

Describe "Set-WmrRegistryState" {

    BeforeEach {
        # Reset mock registry for each test
        Initialize-MockRegistry
        
        # Ensure clean state for each test
        if (Test-Path $script:TempStateDir) {
            Get-ChildItem $script:TempStateDir | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "should restore a specific registry value from dynamic_state_path" {
        # Create a state file first
        $stateData = @{
            Name = "Test Reg Value Restore"
            Path = "HKCU:\SOFTWARE\WmrRegTestDest"
            Type = "value"
            KeyName = "TestValue"
            Value = "RestoredData"
            Encrypted = $false
        }
        $stateFilePath = Join-Path $script:TempStateDir "test_reg_value_restore.json"
        New-Item -Path (Split-Path $stateFilePath) -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
        $stateData | ConvertTo-Json | Set-Content -Path $stateFilePath -Encoding UTF8

        $registryConfig = @{
            name = "Test Reg Value Restore"
            path = "HKCU:\SOFTWARE\WmrRegTestDest"
            type = "value"
            key_name = "TestValue"
            dynamic_state_path = "test_reg_value_restore.json"
        }

        { Set-WmrRegistryState -RegistryConfig $registryConfig -StateFilesDirectory $script:TempStateDir } | Should -Not -Throw

        # Verify the value was set in mock registry
        $mockRegistry = Get-MockRegistryState
        $mockRegistry['HKCU:\SOFTWARE\WmrRegTestDest']['TestValue'] | Should -Be "RestoredData"
    }

    It "should restore a specific registry value and simulate decryption" {
        # Create an encrypted state file
        $encryptedValue = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("DecryptedData"))
        $stateData = @{
            Name = "Test Encrypted Reg Value Restore"
            Path = "HKCU:\SOFTWARE\WmrRegTestDest"
            Type = "value"
            KeyName = "EncryptedValue"
            EncryptedValue = $encryptedValue
            Encrypted = $true
        }
        $stateFilePath = Join-Path $script:TempStateDir "test_encrypted_reg_value_restore.json"
        New-Item -Path (Split-Path $stateFilePath) -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
        $stateData | ConvertTo-Json | Set-Content -Path $stateFilePath -Encoding UTF8

        $registryConfig = @{
            name = "Test Encrypted Reg Value Restore"
            path = "HKCU:\SOFTWARE\WmrRegTestDest"
            type = "value"
            key_name = "EncryptedValue"
            dynamic_state_path = "test_encrypted_reg_value_restore.json"
        }

        { Set-WmrRegistryState -RegistryConfig $registryConfig -StateFilesDirectory $script:TempStateDir } | Should -Not -Throw

        # Verify the decrypted value was set in mock registry
        $mockRegistry = Get-MockRegistryState
        $mockRegistry['HKCU:\SOFTWARE\WmrRegTestDest']['EncryptedValue'] | Should -Be "DecryptedData"
    }

    It "should restore registry key values from dynamic_state_path" {
        # Create a state file with multiple values
        $stateData = @{
            Name = "Test Reg Key Restore"
            Path = "HKCU:\SOFTWARE\WmrRegTestDest"
            Type = "key"
            Values = @{
                TestValue = "RestoredData"
                NumericValue = 54321
                StringValue = "AnotherValue"
            }
        }
        $stateFilePath = Join-Path $script:TempStateDir "test_reg_key_restore.json"
        New-Item -Path (Split-Path $stateFilePath) -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
        $stateData | ConvertTo-Json | Set-Content -Path $stateFilePath -Encoding UTF8

        $registryConfig = @{
            name = "Test Reg Key Restore"
            path = "HKCU:\SOFTWARE\WmrRegTestDest"
            type = "key"
            dynamic_state_path = "test_reg_key_restore.json"
        }

        { Set-WmrRegistryState -RegistryConfig $registryConfig -StateFilesDirectory $script:TempStateDir } | Should -Not -Throw

        # Verify all values were set in mock registry
        $mockRegistry = Get-MockRegistryState
        $mockRegistry['HKCU:\SOFTWARE\WmrRegTestDest']['TestValue'] | Should -Be "RestoredData"
        $mockRegistry['HKCU:\SOFTWARE\WmrRegTestDest']['NumericValue'] | Should -Be 54321
        $mockRegistry['HKCU:\SOFTWARE\WmrRegTestDest']['StringValue'] | Should -Be "AnotherValue"
    }

    It "should use default value_data if state file is missing for a value type" {
        $registryConfig = @{
            name = "Test Default Value"
            path = "HKCU:\SOFTWARE\WmrRegTestDest"
            type = "value"
            key_name = "DefaultValue"
            value_data = "DefaultData"
            dynamic_state_path = "non_existent_file.json"
        }

        { Set-WmrRegistryState -RegistryConfig $registryConfig -StateFilesDirectory $script:TempStateDir } | Should -Not -Throw

        # Verify the default value was set in mock registry
        $mockRegistry = Get-MockRegistryState
        $mockRegistry['HKCU:\SOFTWARE\WmrRegTestDest']['DefaultValue'] | Should -Be "DefaultData"
    }

    It "should warn if state file is missing and no default value_data for a value type" {
        $registryConfig = @{
            name = "Test Missing Value"
            path = "HKCU:\SOFTWARE\WmrRegTestDest"
            type = "value"
            key_name = "MissingValue"
            dynamic_state_path = "non_existent_file.json"
        }

        { Set-WmrRegistryState -RegistryConfig $registryConfig -StateFilesDirectory $script:TempStateDir } | Should -Not -Throw

        # Verify no value was set in mock registry
        $mockRegistry = Get-MockRegistryState
        $mockRegistry['HKCU:\SOFTWARE\WmrRegTestDest'].ContainsKey('MissingValue') | Should -Be $false
    }

    It "should warn if state file is missing for a key type" {
        $registryConfig = @{
            name = "Test Missing Key"
            path = "HKCU:\SOFTWARE\WmrRegTestDest"
            type = "key"
            dynamic_state_path = "non_existent_file.json"
        }

        { Set-WmrRegistryState -RegistryConfig $registryConfig -StateFilesDirectory $script:TempStateDir } | Should -Not -Throw

        # Verify no values were set in mock registry (key should remain empty)
        $mockRegistry = Get-MockRegistryState
        $mockRegistry['HKCU:\SOFTWARE\WmrRegTestDest'].Count | Should -Be 0
    }
}