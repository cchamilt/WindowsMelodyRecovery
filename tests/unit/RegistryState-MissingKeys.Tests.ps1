# tests/unit/RegistryState-MissingKeys.Tests.ps1

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
        "/tmp/RegistryMissingKeysTests"
    } else {
        Join-Path $env:TEMP "RegistryMissingKeysTests"
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

Describe "Registry Missing Keys Handling During Backup" {

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

    Context "Missing Registry Keys" {
        It "should gracefully handle completely missing registry key" {
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

        It "should gracefully handle missing registry value in existing key" {
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

        It "should handle partially missing registry path structure" {
            $registryConfig = @{
                name = "Deep Missing Path"
                path = "HKCU:\SOFTWARE\NonExistent\Deep\Path\Structure"
                type = "key"
                dynamic_state_path = "deep_missing_path.json"
            }

            # This should not throw an exception
            $result = Get-WmrRegistryState -RegistryConfig $registryConfig -StateFilesDirectory $script:TempStateDir

            # Should return null gracefully
            $result | Should -BeNullOrEmpty
            
            # State file should NOT be created
            $stateFilePath = Join-Path $script:TempStateDir "deep_missing_path.json"
            Test-Path $stateFilePath | Should -Be $false
        }

        It "should handle missing HKLM system registry keys" {
            $registryConfig = @{
                name = "Missing System Key"
                path = "HKLM:\SOFTWARE\NonExistentSystemKey"
                type = "key"
                dynamic_state_path = "missing_system_key.json"
            }

            # This should not throw an exception
            $result = Get-WmrRegistryState -RegistryConfig $registryConfig -StateFilesDirectory $script:TempStateDir

            # Should return null gracefully
            $result | Should -BeNullOrEmpty
            
            # State file should NOT be created
            $stateFilePath = Join-Path $script:TempStateDir "missing_system_key.json"
            Test-Path $stateFilePath | Should -Be $false
        }
    }

    Context "Mixed Scenarios - Some Keys Exist, Some Don't" {
        It "should handle backup when some registry keys exist and others don't" {
            # Test multiple registry configs - some exist, some don't
            $registryConfigs = @(
                @{
                    name = "Existing Key"
                    path = "HKCU:\SOFTWARE\WmrRegTest"
                    type = "key"
                    dynamic_state_path = "existing_key.json"
                },
                @{
                    name = "Missing Key"
                    path = "HKCU:\SOFTWARE\NonExistentKey"
                    type = "key"
                    dynamic_state_path = "missing_key.json"
                },
                @{
                    name = "Another Existing Key"
                    path = "HKCU:\Control Panel\Desktop"
                    type = "key"
                    dynamic_state_path = "another_existing_key.json"
                }
            )

            $results = @()
            foreach ($config in $registryConfigs) {
                $result = Get-WmrRegistryState -RegistryConfig $config -StateFilesDirectory $script:TempStateDir
                $results += @{ Config = $config; Result = $result }
            }

            # Existing keys should have results
            $results[0].Result | Should -Not -BeNullOrEmpty
            $results[2].Result | Should -Not -BeNullOrEmpty
            
            # Missing key should be null
            $results[1].Result | Should -BeNullOrEmpty

            # State files should only exist for successful backups
            Test-Path (Join-Path $script:TempStateDir "existing_key.json") | Should -Be $true
            Test-Path (Join-Path $script:TempStateDir "missing_key.json") | Should -Be $false
            Test-Path (Join-Path $script:TempStateDir "another_existing_key.json") | Should -Be $true
        }

        It "should handle mixed value scenarios in same key" {
            $registryConfigs = @(
                @{
                    name = "Existing Value"
                    path = "HKCU:\SOFTWARE\WmrRegTest"
                    type = "value"
                    key_name = "TestValue"  # This exists
                    dynamic_state_path = "existing_value.json"
                },
                @{
                    name = "Missing Value"
                    path = "HKCU:\SOFTWARE\WmrRegTest"
                    type = "value"
                    key_name = "NonExistentValue"  # This doesn't exist
                    dynamic_state_path = "missing_value.json"
                }
            )

            $results = @()
            foreach ($config in $registryConfigs) {
                $result = Get-WmrRegistryState -RegistryConfig $config -StateFilesDirectory $script:TempStateDir
                $results += @{ Config = $config; Result = $result }
            }

            # Existing value should have result
            $results[0].Result | Should -Not -BeNullOrEmpty
            $results[0].Result.Value | Should -Be "OriginalData"
            
            # Missing value should be null
            $results[1].Result | Should -BeNullOrEmpty

            # State files should only exist for successful backups
            Test-Path (Join-Path $script:TempStateDir "existing_value.json") | Should -Be $true
            Test-Path (Join-Path $script:TempStateDir "missing_value.json") | Should -Be $false
        }
    }

    Context "Error Handling and Logging" {
        It "should log appropriate warnings for missing keys" {
            $registryConfig = @{
                name = "Missing Key for Warning Test"
                path = "HKCU:\SOFTWARE\NonExistentKeyForWarning"
                type = "key"
                dynamic_state_path = "missing_key_warning.json"
            }

            # Capture warning output
            $warningMessages = @()
            $originalWarningPreference = $WarningPreference
            $WarningPreference = "Continue"
            
            try {
                $result = Get-WmrRegistryState -RegistryConfig $registryConfig -StateFilesDirectory $script:TempStateDir -WarningVariable warningMessages
                
                # Should return null
                $result | Should -BeNullOrEmpty
                
                # Should have generated warning messages
                $warningMessages | Should -Not -BeNullOrEmpty
                $warningMessages -join " " | Should -Match "Failed to get registry state"
                
            } finally {
                $WarningPreference = $originalWarningPreference
            }
        }

        It "should handle invalid registry paths gracefully" {
            $registryConfig = @{
                name = "Invalid Registry Path"
                path = "INVALID:\NotAValidRegistryPath"
                type = "key"
                dynamic_state_path = "invalid_path.json"
            }

            # This should not throw an exception
            $result = Get-WmrRegistryState -RegistryConfig $registryConfig -StateFilesDirectory $script:TempStateDir

            # Should return null gracefully
            $result | Should -BeNullOrEmpty
        }

        It "should handle empty or null registry paths" {
            $registryConfigs = @(
                @{
                    name = "Empty Path"
                    path = ""
                    type = "key"
                    dynamic_state_path = "empty_path.json"
                },
                @{
                    name = "Null Path"
                    path = $null
                    type = "key"
                    dynamic_state_path = "null_path.json"
                }
            )

            foreach ($config in $registryConfigs) {
                # This should handle validation errors gracefully
                $result = $null
                try {
                    $result = Get-WmrRegistryState -RegistryConfig $config -StateFilesDirectory $script:TempStateDir
                } catch {
                    # Validation errors are expected for empty/null paths
                    Write-Verbose "Expected validation error for empty/null path: $($_.Exception.Message)"
                }

                # Should return null gracefully (either from validation or from the function)
                $result | Should -BeNullOrEmpty
            }
        }
    }

    Context "Registry Prerequisites and Dependencies" {
        It "should handle missing prerequisite registry keys" {
            # Simulate a scenario where a template depends on a registry key that doesn't exist
            $registryConfig = @{
                name = "Prerequisite Registry Key"
                path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\NonExistentPrereq"
                type = "key"
                dynamic_state_path = "missing_prereq.json"
            }

            # This should not throw an exception
            $result = Get-WmrRegistryState -RegistryConfig $registryConfig -StateFilesDirectory $script:TempStateDir

            # Should return null gracefully
            $result | Should -BeNullOrEmpty
            
            # Should not create state file
            $stateFilePath = Join-Path $script:TempStateDir "missing_prereq.json"
            Test-Path $stateFilePath | Should -Be $false
        }

        It "should handle missing encrypted registry values gracefully" {
            $registryConfig = @{
                name = "Missing Encrypted Value"
                path = "HKCU:\SOFTWARE\WmrRegTest"
                type = "value"
                key_name = "NonExistentEncryptedValue"
                encrypt = $true
                dynamic_state_path = "missing_encrypted_value.json"
            }

            # This should not throw an exception
            $result = Get-WmrRegistryState -RegistryConfig $registryConfig -StateFilesDirectory $script:TempStateDir

            # Should return null gracefully
            $result | Should -BeNullOrEmpty
            
            # Should not create state file
            $stateFilePath = Join-Path $script:TempStateDir "missing_encrypted_value.json"
            Test-Path $stateFilePath | Should -Be $false
        }
    }

    Context "Template Integration Scenarios" {
        It "should handle realistic template scenarios with missing Office registry keys" {
            # Simulate Office template scenario where Office might not be installed
            $officeRegistryConfigs = @(
                @{
                    name = "Office 2021 Main Settings"
                    path = "HKCU:\SOFTWARE\Microsoft\Office\16.0\Common"
                    type = "key"
                    dynamic_state_path = "office_2021_main.json"
                },
                @{
                    name = "Office 2019 Main Settings"
                    path = "HKCU:\SOFTWARE\Microsoft\Office\19.0\Common"
                    type = "key"
                    dynamic_state_path = "office_2019_main.json"
                },
                @{
                    name = "Office 365 Settings"
                    path = "HKCU:\SOFTWARE\Microsoft\Office\365\Common"
                    type = "key"
                    dynamic_state_path = "office_365_main.json"
                }
            )

            $results = @()
            foreach ($config in $officeRegistryConfigs) {
                $result = Get-WmrRegistryState -RegistryConfig $config -StateFilesDirectory $script:TempStateDir
                $results += @{ Config = $config; Result = $result }
            }

            # All should return null gracefully (Office not installed in test environment)
            foreach ($result in $results) {
                $result.Result | Should -BeNullOrEmpty
            }

            # No state files should be created
            Test-Path (Join-Path $script:TempStateDir "office_2021_main.json") | Should -Be $false
            Test-Path (Join-Path $script:TempStateDir "office_2019_main.json") | Should -Be $false
            Test-Path (Join-Path $script:TempStateDir "office_365_main.json") | Should -Be $false
        }

        It "should handle gaming platform registry keys that might not exist" {
            # Simulate gaming platform scenarios
            $gamingRegistryConfigs = @(
                @{
                    name = "Steam Settings"
                    path = "HKCU:\SOFTWARE\Valve\Steam"
                    type = "key"
                    dynamic_state_path = "steam_settings.json"
                },
                @{
                    name = "Epic Games Settings"
                    path = "HKCU:\SOFTWARE\Epic Games\EOS"
                    type = "key"
                    dynamic_state_path = "epic_settings.json"
                },
                @{
                    name = "GOG Galaxy Settings"
                    path = "HKCU:\SOFTWARE\GOG.com\GalaxyClient"
                    type = "key"
                    dynamic_state_path = "gog_settings.json"
                }
            )

            $results = @()
            foreach ($config in $gamingRegistryConfigs) {
                $result = Get-WmrRegistryState -RegistryConfig $config -StateFilesDirectory $script:TempStateDir
                $results += @{ Config = $config; Result = $result }
            }

            # All should return null gracefully (gaming platforms not installed in test environment)
            foreach ($result in $results) {
                $result.Result | Should -BeNullOrEmpty
            }

            # No state files should be created
            Test-Path (Join-Path $script:TempStateDir "steam_settings.json") | Should -Be $false
            Test-Path (Join-Path $script:TempStateDir "epic_settings.json") | Should -Be $false
            Test-Path (Join-Path $script:TempStateDir "gog_settings.json") | Should -Be $false
        }
    }
}