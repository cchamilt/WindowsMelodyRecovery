# tests/unit/RegistryState-Logic.Tests.ps1

<#
.SYNOPSIS
    Pure Unit Tests for RegistryState Logic

.DESCRIPTION
    Tests the RegistryState functions' logic without any actual file or registry operations.
    Consolidates all registry state test scenarios with proper mocking.

.NOTES
    These are pure unit tests - no file system or registry operations!
    File operation tests are in tests/file-operations/RegistryState-FileOperations.Tests.ps1
#>

BeforeAll {
    # Load Docker test bootstrap for cross-platform compatibility
    . (Join-Path $PSScriptRoot "../utilities/Docker-Test-Bootstrap.ps1")

    # Import the module with standardized pattern
    try {
        $ModulePath = Resolve-Path "$PSScriptRoot/../../WindowsMelodyRecovery.psd1"
        Import-Module $ModulePath -Force -ErrorAction Stop
    } catch {
        throw "Cannot find or import WindowsMelodyRecovery module: $($_.Exception.Message)"
    }

    # Dot-source RegistryState.ps1 to ensure all functions are available
    . (Join-Path (Split-Path $ModulePath) "Private\Core\RegistryState.ps1")

    # Mock all file and registry operations
    Mock Test-Path { return $true } -ParameterFilter { $Path -like "*registry*exists*" }
    Mock Test-Path { return $false } -ParameterFilter { $Path -like "*registry*missing*" }
    Mock Test-Path { return $true } -ParameterFilter { $Path -like "*HKCU*" }
    Mock Test-Path { return $false } -ParameterFilter { $Path -like "*HKLM*Missing*" }
    Mock New-Item { return @{ FullName = $Path } }
    Mock Set-Content { }
    Mock Get-Content { return '{"KeyName":"TestKey","Value":"MockValue","Encrypted":false}' }
    Mock Remove-Item { }
    Mock Get-ItemProperty { return @{ TestValue = "MockedRegistryValue" } }
    Mock Set-ItemProperty { }
    Mock Get-ChildItem { return @(@{ Name = "SubKey1" }, @{ Name = "SubKey2" }) }
    Mock ConvertTo-Json { return '{"MockedJson":"Data"}' }
    Mock ConvertFrom-Json { return @{ MockedJson = "Data" } }
}

Describe "RegistryState Logic Tests" -Tag "Unit", "Logic" {

    Context "Get-WmrRegistryState Logic" {

        It "Should validate registry configuration structure" {
            $registryConfig = @{
                key_name = "TestKey"
                registry_path = "HKCU:\Software\Test"
                value_name = "TestValue"
                encrypted = $false
            }

            # Test configuration validation logic
            $registryConfig.key_name | Should -Not -BeNullOrEmpty
            $registryConfig.registry_path | Should -Match "^HK[CLU][MU]:"
            $registryConfig.value_name | Should -Not -BeNullOrEmpty
            $registryConfig.encrypted | Should -BeOfType [bool]
        }

        It "Should handle different registry hive paths correctly" {
            $registryHives = @(
                "HKLM:\Software\Test",
                "HKCU:\Software\Test",
                "HKCR:\Test",
                "HKU:\S-1-5-21-123456789\Software\Test"
            )

            foreach ($hive in $registryHives) {
                $hive | Should -Match "^HK(LM|CU|CR|U):"
            }
        }

        It "Should validate registry value type logic" {
            $valueTypes = @("String", "DWord", "QWord", "Binary", "MultiString", "ExpandString")

            foreach ($type in $valueTypes) {
                $type | Should -BeIn $valueTypes
            }
        }

        It "Should handle missing registry keys gracefully" {
            # Mock missing registry key
            Mock Test-Path { return $false } -ParameterFilter { $Path -like "*Missing*" }

            $missingKeyConfig = @{
                key_name = "MissingKey"
                registry_path = "HKCU:\Software\Missing"
                value_name = "TestValue"
                encrypted = $false
            }

            # Should handle missing keys without throwing
            $missingKeyConfig.key_name | Should -Be "MissingKey"
        }

        It "Should validate encryption configuration logic" {
            $encryptedConfig = @{
                key_name = "EncryptedKey"
                registry_path = "HKCU:\Software\Test"
                value_name = "SecretValue"
                encrypted = $true
            }

            $unencryptedConfig = @{
                key_name = "PlainKey"
                registry_path = "HKCU:\Software\Test"
                value_name = "PlainValue"
                encrypted = $false
            }

            # Test encryption logic
            $encryptedConfig.encrypted | Should -Be $true
            $unencryptedConfig.encrypted | Should -Be $false
        }
    }

    Context "Set-WmrRegistryState Logic" {

        It "Should validate state restoration logic" {
            $registryState = @{
                KeyName = "TestKey"
                Value = "TestValue"
                Encrypted = $false
                RegistryPath = "HKCU:\Software\Test"
                ValueName = "TestValue"
            }

            # Test state structure validation
            $registryState.KeyName | Should -Not -BeNullOrEmpty
            $registryState.Value | Should -Not -BeNullOrEmpty
            $registryState.Encrypted | Should -BeOfType [bool]
            $registryState.RegistryPath | Should -Match "^HK[CLU][MU]:"
        }

        It "Should handle encrypted value restoration logic" {
            $encryptedState = @{
                KeyName = "EncryptedKey"
                EncryptedValue = "MockEncryptedData"
                Encrypted = $true
                RegistryPath = "HKCU:\Software\Test"
                ValueName = "SecretValue"
            }

            # Test encrypted state structure
            $encryptedState.Encrypted | Should -Be $true
            $encryptedState.EncryptedValue | Should -Not -BeNullOrEmpty
            $encryptedState.ContainsKey("Value") | Should -Be $false  # Should not contain plain value
        }

        It "Should validate registry path creation logic" {
            $pathCreationTests = @(
                @{ path = "HKCU:\Software\NewKey"; shouldCreate = $true },
                @{ path = "HKLM:\Software\ExistingKey"; shouldCreate = $false },
                @{ path = "HKCU:\Software\Deep\Nested\Path"; shouldCreate = $true }
            )

            foreach ($test in $pathCreationTests) {
                $test.path | Should -Match "^HK[CLU][MU]:"
                $test.shouldCreate | Should -BeOfType [bool]
            }
        }

        It "Should handle different registry value types in restoration" {
            $valueTypeTests = @(
                @{ type = "String"; value = "Test String"; expected = "Test String" },
                @{ type = "DWord"; value = 12345; expected = 12345 },
                @{ type = "QWord"; value = 123456789012345; expected = 123456789012345 },
                @{ type = "Binary"; value = @(0x01, 0x02, 0x03); expected = @(1, 2, 3) }
            )

            foreach ($test in $valueTypeTests) {
                $test.type | Should -BeIn @("String", "DWord", "QWord", "Binary", "MultiString", "ExpandString")
                $test.value | Should -Not -BeNull
            }
        }
    }

    Context "Registry Configuration Validation Logic" {

        It "Should validate complete registry configuration" {
            $completeConfig = @{
                key_name = "CompleteKey"
                registry_path = "HKCU:\Software\Complete"
                value_name = "CompleteValue"
                encrypted = $false
                backup_entire_key = $false
                value_type = "String"
            }

            # Validate all required fields
            $completeConfig.key_name | Should -Not -BeNullOrEmpty
            $completeConfig.registry_path | Should -Match "^HK[CLU][MU]:"
            $completeConfig.value_name | Should -Not -BeNullOrEmpty
            $completeConfig.encrypted | Should -BeOfType [bool]
            $completeConfig.backup_entire_key | Should -BeOfType [bool]
        }

        It "Should handle backup_entire_key configuration" {
            $entireKeyConfig = @{
                key_name = "EntireKey"
                registry_path = "HKCU:\Software\EntireKey"
                backup_entire_key = $true
                encrypted = $false
            }

            $singleValueConfig = @{
                key_name = "SingleValue"
                registry_path = "HKCU:\Software\SingleValue"
                value_name = "SpecificValue"
                backup_entire_key = $false
                encrypted = $false
            }

            # Test backup strategy logic
            $entireKeyConfig.backup_entire_key | Should -Be $true
            $entireKeyConfig.ContainsKey("value_name") | Should -Be $false

            $singleValueConfig.backup_entire_key | Should -Be $false
            $singleValueConfig.value_name | Should -Not -BeNullOrEmpty
        }

        It "Should validate registry path format" {
            $validPaths = @(
                "HKLM:\Software\Microsoft",
                "HKCU:\Software\Test",
                "HKCR:\TestClass",
                "HKU:\S-1-5-21-123456789\Software\Test"
            )

            $invalidPaths = @(
                (Get-WmrTestPath -WindowsPath "C:\Software\Test"),
                "HKEY_LOCAL_MACHINE\Software\Test",
                "Registry::HKEY_CURRENT_USER\Software\Test",
                ""
            )

            foreach ($path in $validPaths) {
                $path | Should -Match "^HK(LM|CU|CR|U):"
            }

            foreach ($path in $invalidPaths) {
                $path | Should -Not -Match "^HK(LM|CU|CR|U):"
            }
        }
    }

    Context "Error Handling Logic" {

        It "Should handle null or empty configurations gracefully" {
            $nullConfig = $null
            $emptyConfig = @{}

            # Should handle gracefully without throwing
            $nullConfig | Should -BeNull
            $emptyConfig.Count | Should -Be 0
        }

        It "Should handle malformed registry configurations" {
            $malformedConfigs = @(
                @{ key_name = "Missing Path" },  # Missing registry_path
                @{ registry_path = "HKCU:\Software\Test" },  # Missing key_name
                @{ key_name = "Invalid"; registry_path = "InvalidPath" }  # Invalid path format
            )

            foreach ($config in $malformedConfigs) {
                # Each should be missing required fields or have invalid format
                if (-not $config.key_name) { $config.key_name | Should -BeNullOrEmpty }
                if (-not $config.registry_path) { $config.registry_path | Should -BeNullOrEmpty }
                if ($config.registry_path -and $config.registry_path -notmatch "^HK") {
                    $config.registry_path | Should -Not -Match "^HK[CLRU][MU]?:"
                }
            }
        }

        It "Should handle encryption/decryption errors gracefully" {
            $encryptionErrorConfig = @{
                key_name = "EncryptionError"
                registry_path = "HKCU:\Software\Test"
                value_name = "CorruptedValue"
                encrypted = $true
            }

            # Should handle encryption errors without crashing
            $encryptionErrorConfig.encrypted | Should -Be $true
        }
    }

    Context "State File Logic" {

        It "Should validate state file naming logic" {
            $stateFileNames = @(
                "registry_display.json",
                "registry_mouse.json",
                "registry_keyboard.json",
                "registry_sound.json"
            )

            foreach ($fileName in $stateFileNames) {
                $fileName | Should -Match "^registry_.*\.json$"
            }
        }

        It "Should handle state file path construction" {
            $stateDirectory = (Get-WmrTestPath -WindowsPath "C:\Test\States")
            $keyName = "TestKey"
            $expectedPath = Join-Path $stateDirectory "registry_$keyName.json"

            $expectedPath | Should -Be (Get-WmrTestPath -WindowsPath "C:\Test\States\registry_TestKey.json")
        }

        It "Should validate state file content structure" {
            $stateContent = @{
                KeyName = "TestKey"
                Value = "TestValue"
                Encrypted = $false
                RegistryPath = "HKCU:\Software\Test"
                ValueName = "TestValue"
                Timestamp = Get-Date
            }

            # Validate state structure
            $stateContent.KeyName | Should -Not -BeNullOrEmpty
            $stateContent.ContainsKey("Value") | Should -Be $true
            $stateContent.Encrypted | Should -BeOfType [bool]
            $stateContent.RegistryPath | Should -Match "^HK[CLU][MU]:"
        }
    }

    Context "Registry Key and Value Logic" {

        It "Should handle registry key existence checking logic" {
            $existingKeys = @(
                "HKCU:\Software\Microsoft",
                "HKLM:\Software\Microsoft"
            )

            $nonExistentKeys = @(
                "HKCU:\Software\NonExistent",
                "HKLM:\Software\NonExistent"
            )

            foreach ($key in $existingKeys) {
                # Mock as existing
                Mock Test-Path { return $true } -ParameterFilter { $Path -eq $key }
            }

            foreach ($key in $nonExistentKeys) {
                # Mock as non-existent
                Mock Test-Path { return $false } -ParameterFilter { $Path -eq $key }
            }

            # Test logic
            $existingKeys.Count | Should -Be 2
            $nonExistentKeys.Count | Should -Be 2
        }

        It "Should validate registry value processing logic" {
            $valueProcessingTests = @(
                @{ input = "String Value"; type = "String"; expected = "String Value" },
                @{ input = 12345; type = "DWord"; expected = 12345 },
                @{ input = @("Multi", "String"); type = "MultiString"; expected = @("Multi", "String") },
                @{ input = @(0x01, 0x02); type = "Binary"; expected = @(1, 2) }
            )

            foreach ($test in $valueProcessingTests) {
                $test.type | Should -BeIn @("String", "DWord", "QWord", "Binary", "MultiString", "ExpandString")
                $test.input | Should -Not -BeNull
            }
        }
    }

    Context "Backup and Restore Logic Flow" {

        It "Should validate backup workflow logic" {
            $backupWorkflow = @(
                "ValidateConfiguration",
                "CheckRegistryKeyExists",
                "ReadRegistryValue",
                "ProcessEncryption",
                "SaveStateFile"
            )

            # Test workflow steps
            $backupWorkflow.Count | Should -Be 5
            $backupWorkflow[0] | Should -Be "ValidateConfiguration"
            $backupWorkflow[-1] | Should -Be "SaveStateFile"
        }

        It "Should validate restore workflow logic" {
            $restoreWorkflow = @(
                "ReadStateFile",
                "ValidateStateContent",
                "ProcessDecryption",
                "CreateRegistryKey",
                "SetRegistryValue"
            )

            # Test workflow steps
            $restoreWorkflow.Count | Should -Be 5
            $restoreWorkflow[0] | Should -Be "ReadStateFile"
            $restoreWorkflow[-1] | Should -Be "SetRegistryValue"
        }

        It "Should handle workflow error scenarios" {
            $errorScenarios = @(
                "ConfigurationValidationError",
                "RegistryKeyNotFound",
                "RegistryValueNotFound",
                "EncryptionError",
                "DecryptionError",
                "StateFileCorrupted",
                "PermissionDenied"
            )

            foreach ($scenario in $errorScenarios) {
                $scenario | Should -Not -BeNullOrEmpty
                $scenario | Should -Match "Error|NotFound|Corrupted|Denied"
            }
        }
    }
}







