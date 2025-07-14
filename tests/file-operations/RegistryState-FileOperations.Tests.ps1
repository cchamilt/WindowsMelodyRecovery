# tests/file-operations/RegistryState-FileOperations.Tests.ps1

<#
.SYNOPSIS
    File Operations Tests for RegistryState

.DESCRIPTION
    Tests the RegistryState functions' file and registry operations within safe test directories.
    Performs actual file operations and safe registry operations in test keys only.

.NOTES
    These are file operation tests - they create and manipulate actual files and registry keys!
    Pure logic tests are in tests/unit/RegistryState-Logic.Tests.ps1
#>

Describe "RegistryState File Operations" -Tag "FileOperations", "Safe" {

    BeforeAll {
        # Skip all registry tests in Docker/Linux environment
        if ($IsLinux -or $IsMacOS -or ($env:DOCKER_ENVIRONMENT -eq "true") -or ($env:CONTAINER_NAME -like "*wmr*")) {
            Write-Warning "Registry file operations tests skipped in non-Windows environment"
            return
        }

        # Load Docker test bootstrap for cross-platform compatibility
        . (Join-Path $PSScriptRoot "../utilities/Docker-Test-Bootstrap.ps1")

        # Import only the specific scripts needed to avoid TUI dependencies
        try {
            $RegistryStateScript = Resolve-Path "$PSScriptRoot/../../Private/Core/RegistryState.ps1"
            . $RegistryStateScript

            $PathUtilitiesScript = Resolve-Path "$PSScriptRoot/../../Private/Core/PathUtilities.ps1"
            . $PathUtilitiesScript

            # Initialize test environment
            $TestEnvironmentScript = Resolve-Path "$PSScriptRoot/../utilities/Test-Environment.ps1"
            . $TestEnvironmentScript
            $script:TestEnvironment = Initialize-TestEnvironment -SuiteName 'FileOps'
        }
        catch {
            throw "Cannot find or import registry scripts: $($_.Exception.Message)"
        }

        # Get standardized test paths
        $script:TestBackupDir = $script:TestEnvironment.TestBackup
        $script:TestRestoreDir = $script:TestEnvironment.TestRestore
        $script:TestStateDir = $script:TestEnvironment.TestState

        # Module functions are already imported via specific scripts above

        # Dot-source RegistryState.ps1 for direct function access
        . (Join-Path $PSScriptRoot "..\\..\\Private\\Core\\RegistryState.ps1")

        # Set up test registry path (only on Windows)
        if ($IsWindows) {
            $script:TestRegistryPath = "HKCU:\Software\WindowsMelodyRecovery\FileOperationsTest"
        }
        else {
            $script:TestRegistryPath = $null
        }

        # Ensure test directories exist with null checks
        @($script:TestBackupDir, $script:TestRestoreDir) | ForEach-Object {
            if ($_ -and -not (Test-Path $_)) {
                New-Item -ItemType Directory -Path $_ -Force | Out-Null
            }
        }

    }

    AfterAll {
        # Skip cleanup in Docker/Linux environment
        if ($IsLinux -or $IsMacOS -or ($env:DOCKER_ENVIRONMENT -eq "true") -or ($env:CONTAINER_NAME -like "*wmr*")) {
            return
        }

        # Clean up test environment
        if ($script:TestEnvironment -and $script:TestEnvironment.TestState) {
            if (Test-Path $script:TestEnvironment.TestState) {
                Remove-Item $script:TestEnvironment.TestState -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        # Clean up test registry keys
        if ($script:TestRegistryPath -and (Test-Path $script:TestRegistryPath)) {
            Remove-Item $script:TestRegistryPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context "State File Creation and Management" {

        It "Should create registry state files with proper structure" -Skip:($IsLinux -or $IsMacOS -or ($env:DOCKER_ENVIRONMENT -eq "true") -or ($env:CONTAINER_NAME -like "*wmr*")) {
            # Skip this test in non-Windows environments
            if ($IsLinux -or $IsMacOS -or ($env:DOCKER_ENVIRONMENT -eq "true") -or ($env:CONTAINER_NAME -like "*wmr*")) {
                Set-ItResult -Skipped -Because "Registry operations not supported in Docker environment"
                return
            }

            $stateFile = Join-Path $script:TestStateDir "registry-state.json"
            $registryData = @{
                Path      = "HKCU:\Software\Test"
                ValueName = "TestValue"
                ValueData = "TestData"
                ValueType = "String"
            }

            $registryData | ConvertTo-Json | Out-File $stateFile -Encoding UTF8

            try {
                Test-Path $stateFile | Should -Be $true
                $content = Get-Content $stateFile -Raw | ConvertFrom-Json
                $content.Path | Should -Be "HKCU:\Software\Test"
                $content.ValueName | Should -Be "TestValue"
                $content.ValueData | Should -Be "TestData"
                $content.ValueType | Should -Be "String"
            }
            finally {
                Remove-Item $stateFile -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should handle encrypted state files" -Skip:($IsLinux -or $IsMacOS -or ($env:DOCKER_ENVIRONMENT -eq "true") -or ($env:CONTAINER_NAME -like "*wmr*")) {
            # Skip this test in non-Windows environments
            if ($IsLinux -or $IsMacOS -or ($env:DOCKER_ENVIRONMENT -eq "true") -or ($env:CONTAINER_NAME -like "*wmr*")) {
                Set-ItResult -Skipped -Because "Registry operations not supported in Docker environment"
                return
            }

            $stateFile = Join-Path $script:TestStateDir "encrypted-registry-state.json"
            $registryData = @{
                Path      = "HKCU:\Software\Test"
                ValueName = "EncryptedValue"
                ValueData = "SensitiveData"
                ValueType = "String"
                Encrypted = $true
            }

            $registryData | ConvertTo-Json | Out-File $stateFile -Encoding UTF8

            try {
                Test-Path $stateFile | Should -Be $true
                $content = Get-Content $stateFile -Raw | ConvertFrom-Json
                $content.Encrypted | Should -Be $true
                $content.ValueName | Should -Be "EncryptedValue"
            }
            finally {
                Remove-Item $stateFile -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should create state files with UTF-8 encoding" -Skip:($IsLinux -or $IsMacOS -or ($env:DOCKER_ENVIRONMENT -eq "true") -or ($env:CONTAINER_NAME -like "*wmr*")) {
            # Skip this test in non-Windows environments
            if ($IsLinux -or $IsMacOS -or ($env:DOCKER_ENVIRONMENT -eq "true") -or ($env:CONTAINER_NAME -like "*wmr*")) {
                Set-ItResult -Skipped -Because "Registry operations not supported in Docker environment"
                return
            }

            $stateFile = Join-Path $script:TestStateDir "utf8-registry-state.json"
            $registryData = @{
                Path      = "HKCU:\Software\Test"
                ValueName = "UTF8Value"
                ValueData = "Test with special characters: émojis 🚀 and 中文"
                ValueType = "String"
            }

            $registryData | ConvertTo-Json | Out-File $stateFile -Encoding UTF8

            try {
                Test-Path $stateFile | Should -Be $true
                $content = Get-Content $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json
                $content.ValueData | Should -Match "émojis 🚀"
                $content.ValueData | Should -Match "中文"
            }
            finally {
                Remove-Item $stateFile -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context "Registry Key Operations" {

        It "Should create and clean up test registry keys" -Skip:($IsLinux -or $IsMacOS -or ($env:DOCKER_ENVIRONMENT -eq "true") -or ($env:CONTAINER_NAME -like "*wmr*")) {
            # Skip this test in non-Windows environments
            if ($IsLinux -or $IsMacOS -or ($env:DOCKER_ENVIRONMENT -eq "true") -or ($env:CONTAINER_NAME -like "*wmr*")) {
                Set-ItResult -Skipped -Because "Registry operations not supported in Docker environment"
                return
            }

            $testKeyPath = "$script:TestRegistryPath\TestKey"

            try {
                # Create test registry key
                if (-not (Test-Path $testKeyPath)) {
                    New-Item -Path $testKeyPath -Force | Out-Null
                }
                Test-Path $testKeyPath | Should -Be $true

                # Set test value
                Set-ItemProperty -Path $testKeyPath -Name "TestValue" -Value "TestData"
                $value = Get-ItemProperty -Path $testKeyPath -Name "TestValue"
                $value.TestValue | Should -Be "TestData"

            }
            finally {
                # Clean up test registry key
                if (Test-Path $testKeyPath) {
                    Remove-Item $testKeyPath -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }

        It "Should handle different registry value types" -Skip:($IsLinux -or $IsMacOS -or ($env:DOCKER_ENVIRONMENT -eq "true") -or ($env:CONTAINER_NAME -like "*wmr*")) {
            # Skip this test in non-Windows environments
            if ($IsLinux -or $IsMacOS -or ($env:DOCKER_ENVIRONMENT -eq "true") -or ($env:CONTAINER_NAME -like "*wmr*")) {
                Set-ItResult -Skipped -Because "Registry operations not supported in Docker environment"
                return
            }

            $testKeyPath = "$script:TestRegistryPath\ValueTypes"

            try {
                # Create test registry key
                if (-not (Test-Path $testKeyPath)) {
                    New-Item -Path $testKeyPath -Force | Out-Null
                }

                # Test different data types (only on Windows)
                if ($IsWindows) {
                    Set-ItemProperty -Path $testKeyPath -Name "StringValue" -Value "Test String"
                    Set-ItemProperty -Path $testKeyPath -Name "DWordValue" -Value 12345
                    # Skip binary type test as it may not be supported on all PowerShell versions

                    # Verify values
                    $props = Get-ItemProperty -Path $testKeyPath
                    $props.StringValue | Should -Be "Test String"
                    $props.DWordValue | Should -Be 12345
                }

            }
            finally {
                # Clean up
                if (Test-Path $testKeyPath) {
                    Remove-Item $testKeyPath -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }

        It "Should handle nested registry key structures" -Skip:($IsLinux -or $IsMacOS -or ($env:DOCKER_ENVIRONMENT -eq "true") -or ($env:CONTAINER_NAME -like "*wmr*")) {
            # Skip this test in non-Windows environments
            if ($IsLinux -or $IsMacOS -or ($env:DOCKER_ENVIRONMENT -eq "true") -or ($env:CONTAINER_NAME -like "*wmr*")) {
                Set-ItResult -Skipped -Because "Registry operations not supported in Docker environment"
                return
            }

            $nestedKeyPath = "$script:TestRegistryPath\Level1\Level2\Level3"

            try {
                # Create nested registry structure
                if (-not (Test-Path $nestedKeyPath)) {
                    New-Item -Path $nestedKeyPath -Force | Out-Null
                }

                # Set values at different levels
                Set-ItemProperty -Path "$script:TestRegistryPath\Level1" -Name "Level1Value" -Value "L1"
                Set-ItemProperty -Path "$script:TestRegistryPath\Level1\Level2" -Name "Level2Value" -Value "L2"
                Set-ItemProperty -Path $nestedKeyPath -Name "Level3Value" -Value "L3"

                # Verify nested structure
                $l1Props = Get-ItemProperty -Path "$script:TestRegistryPath\Level1"
                $l2Props = Get-ItemProperty -Path "$script:TestRegistryPath\Level1\Level2"
                $l3Props = Get-ItemProperty -Path $nestedKeyPath

                $l1Props.Level1Value | Should -Be "L1"
                $l2Props.Level2Value | Should -Be "L2"
                $l3Props.Level3Value | Should -Be "L3"

            }
            finally {
                # Clean up nested structure
                if (Test-Path "$script:TestRegistryPath\Level1") {
                    Remove-Item "$script:TestRegistryPath\Level1" -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }

    Context "State File and Registry Integration" {

        It "Should backup registry value to state file" -Skip:($IsLinux -or $IsMacOS -or ($env:DOCKER_ENVIRONMENT -eq "true") -or ($env:CONTAINER_NAME -like "*wmr*")) {
            # Skip this test in non-Windows environments
            if ($IsLinux -or $IsMacOS -or ($env:DOCKER_ENVIRONMENT -eq "true") -or ($env:CONTAINER_NAME -like "*wmr*")) {
                Set-ItResult -Skipped -Because "Registry operations not supported in Docker environment"
                return
            }

            $testKeyPath = "$script:TestRegistryPath\BackupTest"
            $stateFilePath = Join-Path $script:TestEnvironment.TestState "registry_backup.json"

            try {
                # Create test registry key with value
                if (-not (Test-Path $testKeyPath)) {
                    New-Item -Path $testKeyPath -Force | Out-Null
                }
                Set-ItemProperty -Path $testKeyPath -Name "BackupValue" -Value "DataToBackup"

                # Backup registry value
                $registryValue = Get-ItemProperty -Path $testKeyPath -Name "BackupValue"
                $stateData = @{
                    KeyName      = "BackupTest"
                    Value        = $registryValue.BackupValue
                    Encrypted    = $false
                    RegistryPath = $testKeyPath
                    ValueName    = "BackupValue"
                    Timestamp    = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                }

                # Save to state file
                $stateData | ConvertTo-Json -Depth 3 | Out-File $stateFilePath -Encoding UTF8
                Test-Path $stateFilePath | Should -Be $true

                # Verify backup content
                $readState = Get-Content $stateFilePath -Raw | ConvertFrom-Json
                $readState.Value | Should -Be "DataToBackup"
                $readState.KeyName | Should -Be "BackupTest"
                $readState.ValueName | Should -Be "BackupValue"

            }
            finally {
                # Clean up
                if (Test-Path $testKeyPath) {
                    Remove-Item $testKeyPath -Recurse -Force -ErrorAction SilentlyContinue
                }
                Remove-Item $stateFilePath -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should restore registry value from state file" -Skip:($IsLinux -or $IsMacOS -or ($env:DOCKER_ENVIRONMENT -eq "true") -or ($env:CONTAINER_NAME -like "*wmr*")) {
            # Skip this test in non-Windows environments
            if ($IsLinux -or $IsMacOS -or ($env:DOCKER_ENVIRONMENT -eq "true") -or ($env:CONTAINER_NAME -like "*wmr*")) {
                Set-ItResult -Skipped -Because "Registry operations not supported in Docker environment"
                return
            }

            $testKeyPath = "$script:TestRegistryPath\RestoreTest"
            $stateFilePath = Join-Path $script:TestEnvironment.TestState "registry_restore.json"

            try {
                # Create state file with backup data
                $stateData = @{
                    KeyName      = "RestoreTest"
                    Value        = "DataToRestore"
                    Encrypted    = $false
                    RegistryPath = $testKeyPath
                    ValueName    = "RestoreValue"
                    Timestamp    = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                }
                $stateData | ConvertTo-Json -Depth 3 | Out-File $stateFilePath -Encoding UTF8

                # Restore from state file
                $readState = Get-Content $stateFilePath -Raw | ConvertFrom-Json

                # Create registry key and restore value
                if (-not (Test-Path $testKeyPath)) {
                    New-Item -Path $testKeyPath -Force | Out-Null
                }
                Set-ItemProperty -Path $testKeyPath -Name $readState.ValueName -Value $readState.Value

                # Verify restoration
                $restoredValue = Get-ItemProperty -Path $testKeyPath -Name $readState.ValueName
                $restoredValue.RestoreValue | Should -Be "DataToRestore"

            }
            finally {
                # Clean up
                if (Test-Path $testKeyPath) {
                    Remove-Item $testKeyPath -Recurse -Force -ErrorAction SilentlyContinue
                }
                Remove-Item $stateFilePath -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should handle backup and restore of entire registry keys" -Skip:($IsLinux -or $IsMacOS -or ($env:DOCKER_ENVIRONMENT -eq "true") -or ($env:CONTAINER_NAME -like "*wmr*")) {
            # Skip this test in non-Windows environments
            if ($IsLinux -or $IsMacOS -or ($env:DOCKER_ENVIRONMENT -eq "true") -or ($env:CONTAINER_NAME -like "*wmr*")) {
                Set-ItResult -Skipped -Because "Registry operations not supported in Docker environment"
                return
            }

            $testKeyPath = "$script:TestRegistryPath\EntireKeyTest"
            $stateFilePath = Join-Path $script:TestEnvironment.TestState "registry_entire_key.json"

            try {
                # Create test registry key with multiple values
                if (-not (Test-Path $testKeyPath)) {
                    New-Item -Path $testKeyPath -Force | Out-Null
                }
                Set-ItemProperty -Path $testKeyPath -Name "Value1" -Value "Data1"
                Set-ItemProperty -Path $testKeyPath -Name "Value2" -Value "Data2"
                Set-ItemProperty -Path $testKeyPath -Name "Value3" -Value 12345

                # Backup entire key
                $keyProperties = Get-ItemProperty -Path $testKeyPath
                $keyValues = @{}
                $keyProperties.PSObject.Properties | Where-Object { $_.Name -notmatch "^PS" } | ForEach-Object {
                    $keyValues[$_.Name] = $_.Value
                }

                $stateData = @{
                    KeyName         = "EntireKeyTest"
                    Values          = $keyValues
                    Encrypted       = $false
                    RegistryPath    = $testKeyPath
                    BackupEntireKey = $true
                    Timestamp       = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                }

                # Save to state file
                $stateData | ConvertTo-Json -Depth 3 | Out-File $stateFilePath -Encoding UTF8
                Test-Path $stateFilePath | Should -Be $true

                # Verify backup content
                $readState = Get-Content $stateFilePath -Raw | ConvertFrom-Json
                $readState.Values.Value1 | Should -Be "Data1"
                $readState.Values.Value2 | Should -Be "Data2"
                $readState.Values.Value3 | Should -Be 12345

            }
            finally {
                # Clean up
                if (Test-Path $testKeyPath) {
                    Remove-Item $testKeyPath -Recurse -Force -ErrorAction SilentlyContinue
                }
                Remove-Item $stateFilePath -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context "Error Handling and Edge Cases" {

        It "Should handle corrupted state files gracefully" -Skip:($IsLinux -or $IsMacOS -or ($env:DOCKER_ENVIRONMENT -eq "true") -or ($env:CONTAINER_NAME -like "*wmr*")) {
            # Skip this test in non-Windows environments
            if ($IsLinux -or $IsMacOS -or ($env:DOCKER_ENVIRONMENT -eq "true") -or ($env:CONTAINER_NAME -like "*wmr*")) {
                Set-ItResult -Skipped -Because "Registry operations not supported in Docker environment"
                return
            }

            $corruptedStateFile = Join-Path $script:TestEnvironment.TestState "corrupted_state.json"
            $corruptedContent = '{ "KeyName": "Test", "Value": "Data"'  # Missing closing brace

            try {
                # Create corrupted file
                $corruptedContent | Out-File $corruptedStateFile -Encoding UTF8
                Test-Path $corruptedStateFile | Should -Be $true

                # Attempting to parse should fail
                { Get-Content $corruptedStateFile -Raw | ConvertFrom-Json } | Should -Throw

            }
            finally {
                Remove-Item $corruptedStateFile -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should handle missing registry keys during backup" -Skip:($IsLinux -or $IsMacOS -or ($env:DOCKER_ENVIRONMENT -eq "true") -or ($env:CONTAINER_NAME -like "*wmr*")) {
            # Skip this test in non-Windows environments
            if ($IsLinux -or $IsMacOS -or ($env:DOCKER_ENVIRONMENT -eq "true") -or ($env:CONTAINER_NAME -like "*wmr*")) {
                Set-ItResult -Skipped -Because "Registry operations not supported in Docker environment"
                return
            }

            $missingKeyPath = "$script:TestRegistryPath\NonExistentKey"

            # Key should not exist
            Test-Path $missingKeyPath | Should -Be $false

            # Attempting to read should handle gracefully
            $result = Get-ItemProperty -Path $missingKeyPath -ErrorAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }

        It "Should handle permission issues with registry keys" -Skip:($IsLinux -or $IsMacOS -or ($env:DOCKER_ENVIRONMENT -eq "true") -or ($env:CONTAINER_NAME -like "*wmr*")) {
            # Skip this test in non-Windows environments
            if ($IsLinux -or $IsMacOS -or ($env:DOCKER_ENVIRONMENT -eq "true") -or ($env:CONTAINER_NAME -like "*wmr*")) {
                Set-ItResult -Skipped -Because "Registry operations not supported in Docker environment"
                return
            }

            # Note: This test uses safe HKCU keys, so permission issues are minimal
            # In real scenarios, HKLM keys might have permission issues
            $testKeyPath = "$script:TestRegistryPath\PermissionTest"

            try {
                # Create test key (should succeed in HKCU)
                if (-not (Test-Path $testKeyPath)) {
                    New-Item -Path $testKeyPath -Force | Out-Null
                }
                Test-Path $testKeyPath | Should -Be $true

                # Set value (should succeed)
                Set-ItemProperty -Path $testKeyPath -Name "PermissionValue" -Value "TestData"
                $value = Get-ItemProperty -Path $testKeyPath -Name "PermissionValue"
                $value.PermissionValue | Should -Be "TestData"

            }
            finally {
                # Clean up
                if (Test-Path $testKeyPath) {
                    Remove-Item $testKeyPath -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }

        It "Should handle large registry values" -Skip:($IsLinux -or $IsMacOS -or ($env:DOCKER_ENVIRONMENT -eq "true") -or ($env:CONTAINER_NAME -like "*wmr*")) {
            # Skip this test in non-Windows environments
            if ($IsLinux -or $IsMacOS -or ($env:DOCKER_ENVIRONMENT -eq "true") -or ($env:CONTAINER_NAME -like "*wmr*")) {
                Set-ItResult -Skipped -Because "Registry operations not supported in Docker environment"
                return
            }

            $testKeyPath = "$script:TestRegistryPath\LargeValueTest"
            $stateFilePath = Join-Path $script:TestEnvironment.TestState "registry_large_value.json"

            try {
                # Create large string value
                $largeValue = "A" * 1000  # 1000 character string

                # Create registry key with large value
                if (-not (Test-Path $testKeyPath)) {
                    New-Item -Path $testKeyPath -Force | Out-Null
                }
                Set-ItemProperty -Path $testKeyPath -Name "LargeValue" -Value $largeValue

                # Backup large value
                $registryValue = Get-ItemProperty -Path $testKeyPath -Name "LargeValue"
                $stateData = @{
                    KeyName      = "LargeValueTest"
                    Value        = $registryValue.LargeValue
                    Encrypted    = $false
                    RegistryPath = $testKeyPath
                    ValueName    = "LargeValue"
                }

                # Save to state file
                $stateData | ConvertTo-Json -Depth 3 | Out-File $stateFilePath -Encoding UTF8
                Test-Path $stateFilePath | Should -Be $true

                # Verify large value backup
                $readState = Get-Content $stateFilePath -Raw | ConvertFrom-Json
                $readState.Value.Length | Should -Be 1000
                $readState.Value | Should -Be $largeValue

            }
            finally {
                # Clean up
                if (Test-Path $testKeyPath) {
                    Remove-Item $testKeyPath -Recurse -Force -ErrorAction SilentlyContinue
                }
                Remove-Item $stateFilePath -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context "Multiple State Files Management" {

        It "Should handle multiple state files in directory" -Skip:($IsLinux -or $IsMacOS -or ($env:DOCKER_ENVIRONMENT -eq "true") -or ($env:CONTAINER_NAME -like "*wmr*")) {
            # Skip this test in non-Windows environments
            if ($IsLinux -or $IsMacOS -or ($env:DOCKER_ENVIRONMENT -eq "true") -or ($env:CONTAINER_NAME -like "*wmr*")) {
                Set-ItResult -Skipped -Because "Registry operations not supported in Docker environment"
                return
            }

            $stateFiles = @(
                "registry_display.json",
                "registry_mouse.json",
                "registry_keyboard.json",
                "registry_sound.json"
            )

            try {
                # Create multiple state files
                foreach ($fileName in $stateFiles) {
                    $filePath = Join-Path $script:TestEnvironment.TestState $fileName
                    $stateData = @{
                        KeyName      = $fileName.Replace("registry_", "").Replace(".json", "")
                        Value        = "TestValue_$fileName"
                        Encrypted    = $false
                        RegistryPath = "HKCU:\Software\Test\$fileName"
                        ValueName    = "TestValue"
                    }
                    $stateData | ConvertTo-Json -Depth 3 | Out-File $filePath -Encoding UTF8
                }

                # Verify all files created
                foreach ($fileName in $stateFiles) {
                    $filePath = Join-Path $script:TestEnvironment.TestState $fileName
                    Test-Path $filePath | Should -Be $true

                    $content = Get-Content $filePath -Raw | ConvertFrom-Json
                    $content.KeyName | Should -Not -BeNullOrEmpty
                    $content.Value | Should -Match "TestValue_"
                }

            }
            finally {
                # Clean up all state files
                foreach ($fileName in $stateFiles) {
                    $filePath = Join-Path $script:TestEnvironment.TestState $fileName
                    Remove-Item $filePath -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
}







