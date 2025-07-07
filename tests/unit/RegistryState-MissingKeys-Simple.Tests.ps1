# tests/unit/RegistryState-MissingKeys-Simple.Tests.ps1

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
        "/tmp/RegistryMissingKeysSimpleTests"
    } else {
        Join-Path $env:TEMP "RegistryMissingKeysSimpleTests"
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

Describe "Registry Missing Keys - Simple Tests" {

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

    Context "Basic Missing Key Tests" {
        It "should handle completely missing registry key" {
            $registryConfig = @{
                name = "Missing Registry Key"
                path = "HKCU:\SOFTWARE\NonExistentKey"
                type = "key"
                dynamic_state_path = "missing_key.json"
            }

            # This should not throw an exception
            $result = Get-WmrRegistryState -RegistryConfig $registryConfig -StateFilesDirectory $script:TempStateDir

            # Should return null gracefully
            $result | Should -BeNullOrEmpty
            
            # State file should NOT be created for missing keys
            $stateFilePath = Join-Path $script:TempStateDir "missing_key.json"
            Test-Path $stateFilePath | Should -Be $false
        }

        It "should handle missing registry value in existing key" {
            $registryConfig = @{
                name = "Missing Registry Value"
                path = "HKCU:\SOFTWARE\WmrRegTest"  # This key exists
                type = "value"
                key_name = "NonExistentValue"      # This value doesn't exist
                dynamic_state_path = "missing_value.json"
            }

            # This should not throw an exception
            $result = Get-WmrRegistryState -RegistryConfig $registryConfig -StateFilesDirectory $script:TempStateDir

            # Should return null gracefully
            $result | Should -BeNullOrEmpty
            
            # State file should NOT be created for missing values
            $stateFilePath = Join-Path $script:TempStateDir "missing_value.json"
            Test-Path $stateFilePath | Should -Be $false
        }

        It "should handle existing key successfully" {
            $registryConfig = @{
                name = "Existing Registry Key"
                path = "HKCU:\SOFTWARE\WmrRegTest"  # This key exists
                type = "key"
                dynamic_state_path = "existing_key.json"
            }

            # This should work
            $result = Get-WmrRegistryState -RegistryConfig $registryConfig -StateFilesDirectory $script:TempStateDir

            # Should have a result
            $result | Should -Not -BeNullOrEmpty
            $result.Name | Should -Be "Existing Registry Key"
            $result.Path | Should -Be "HKCU:\SOFTWARE\WmrRegTest"
            
            # State file should be created
            $stateFilePath = Join-Path $script:TempStateDir "existing_key.json"
            Test-Path $stateFilePath | Should -Be $true
        }

        It "should handle existing value successfully" {
            $registryConfig = @{
                name = "Existing Registry Value"
                path = "HKCU:\SOFTWARE\WmrRegTest"  # This key exists
                type = "value"
                key_name = "TestValue"             # This value exists
                dynamic_state_path = "existing_value.json"
            }

            # This should work
            $result = Get-WmrRegistryState -RegistryConfig $registryConfig -StateFilesDirectory $script:TempStateDir

            # Should have a result
            $result | Should -Not -BeNullOrEmpty
            $result.Name | Should -Be "Existing Registry Value"
            $result.Value | Should -Be "OriginalData"
            
            # State file should be created
            $stateFilePath = Join-Path $script:TempStateDir "existing_value.json"
            Test-Path $stateFilePath | Should -Be $true
        }
    }
}