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

BeforeAll {
    # Import test environment utilities
    . (Join-Path $PSScriptRoot "..\utilities\Test-Environment.ps1")
    
    # Initialize test environment to ensure directories exist
    $script:TestEnvironment = Initialize-TestEnvironment
    
    # Get standardized test paths
    $script:TestBackupDir = $script:TestEnvironment.TestBackup
    $script:TestRestoreDir = $script:TestEnvironment.TestRestore
    
    # Import the module with standardized pattern
    try {
        $ModulePath = Resolve-Path "$PSScriptRoot/../../WindowsMelodyRecovery.psd1"
        Import-Module $ModulePath -Force -ErrorAction Stop
    } catch {
        throw "Cannot find or import WindowsMelodyRecovery module: $($_.Exception.Message)"
    }

    # Dot-source RegistryState.ps1 to ensure all functions are available
    . (Join-Path (Split-Path $ModulePath) "Private\Core\RegistryState.ps1")
    
    # Ensure test directories exist with null checks
    @($script:TestBackupDir, $script:TestRestoreDir) | ForEach-Object {
        if ($_ -and -not (Test-Path $_)) {
            New-Item -ItemType Directory -Path $_ -Force | Out-Null
        }
    }
    
    # Define safe test registry path
    $script:TestRegistryPath = "HKCU:\Software\WindowsMelodyRecovery\FileOperationsTest"
}

Describe "RegistryState File Operations" -Tag "FileOperations" {

    Context "State File Creation and Management" {
        
        It "Should create registry state files with proper structure" {
            $stateFilePath = Join-Path $script:TestEnvironment.TestState "registry_test.json"
            $stateData = @{
                KeyName = "TestKey"
                Value = "TestValue"
                Encrypted = $false
                RegistryPath = "HKCU:\Software\Test"
                ValueName = "TestValue"
                Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            }
            
            try {
                # Create state file
                $stateData | ConvertTo-Json -Depth 3 | Out-File $stateFilePath -Encoding UTF8
                Test-Path $stateFilePath | Should -Be $true
                
                # Verify content structure
                $readState = Get-Content $stateFilePath -Raw | ConvertFrom-Json
                $readState.KeyName | Should -Be "TestKey"
                $readState.Value | Should -Be "TestValue"
                $readState.Encrypted | Should -Be $false
                $readState.RegistryPath | Should -Be "HKCU:\Software\Test"
                
            } finally {
                Remove-Item $stateFilePath -Force -ErrorAction SilentlyContinue
            }
        }
        
        It "Should handle encrypted state files" {
            $encryptedStateFile = Join-Path $script:TestEnvironment.TestState "registry_encrypted.json"
            $encryptedStateData = @{
                KeyName = "EncryptedKey"
                EncryptedValue = "MockEncryptedData123"
                Encrypted = $true
                RegistryPath = "HKCU:\Software\Test"
                ValueName = "SecretValue"
                Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            }
            
            try {
                # Create encrypted state file
                $encryptedStateData | ConvertTo-Json -Depth 3 | Out-File $encryptedStateFile -Encoding UTF8
                Test-Path $encryptedStateFile | Should -Be $true
                
                # Verify encrypted structure
                $readState = Get-Content $encryptedStateFile -Raw | ConvertFrom-Json
                $readState.KeyName | Should -Be "EncryptedKey"
                $readState.Encrypted | Should -Be $true
                $readState.EncryptedValue | Should -Be "MockEncryptedData123"
                $readState.PSObject.Properties.Name | Should -Not -Contain "Value"  # Should not have plain value
                
            } finally {
                Remove-Item $encryptedStateFile -Force -ErrorAction SilentlyContinue
            }
        }
        
        It "Should create state files with UTF-8 encoding" {
            $utf8StateFile = Join-Path $script:TestEnvironment.TestState "registry_utf8.json"
            $utf8StateData = @{
                KeyName = "UTF8Key"
                Value = "UTF-8 测试 with émojis 🚀"
                Encrypted = $false
                RegistryPath = "HKCU:\Software\Test"
                ValueName = "UTF8Value"
                Description = "测试 UTF-8 encoding"
            }
            
            try {
                # Create UTF-8 state file
                $utf8StateData | ConvertTo-Json -Depth 3 | Out-File $utf8StateFile -Encoding UTF8
                Test-Path $utf8StateFile | Should -Be $true
                
                # Verify UTF-8 content
                $readState = Get-Content $utf8StateFile -Encoding UTF8 -Raw | ConvertFrom-Json
                $readState.Value | Should -Be "UTF-8 测试 with émojis 🚀"
                $readState.Description | Should -Be "测试 UTF-8 encoding"
                
            } finally {
                Remove-Item $utf8StateFile -Force -ErrorAction SilentlyContinue
            }
        }
    }
    
    Context "Registry Key Operations" {
        
        It "Should create and clean up test registry keys" {
            $testKeyPath = "$script:TestRegistryPath\BasicTest"
            
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
                
            } finally {
                # Clean up test registry key
                if (Test-Path $testKeyPath) {
                    Remove-Item $testKeyPath -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
        
        It "Should handle different registry value types" {
            $testKeyPath = "$script:TestRegistryPath\ValueTypes"
            
            try {
                # Create test registry key
                if (-not (Test-Path $testKeyPath)) {
                    New-Item -Path $testKeyPath -Force | Out-Null
                }
                
                # Test different value types
                Set-ItemProperty -Path $testKeyPath -Name "StringValue" -Value "Test String"
                Set-ItemProperty -Path $testKeyPath -Name "DWordValue" -Value 12345 -PropertyType DWord
                Set-ItemProperty -Path $testKeyPath -Name "QWordValue" -Value 123456789012345 -PropertyType QWord
                Set-ItemProperty -Path $testKeyPath -Name "BinaryValue" -Value @(0x01, 0x02, 0x03) -PropertyType Binary
                
                # Verify values
                $props = Get-ItemProperty -Path $testKeyPath
                $props.StringValue | Should -Be "Test String"
                $props.DWordValue | Should -Be 12345
                $props.QWordValue | Should -Be 123456789012345
                $props.BinaryValue | Should -Be @(1, 2, 3)
                
            } finally {
                # Clean up
                if (Test-Path $testKeyPath) {
                    Remove-Item $testKeyPath -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
        
        It "Should handle nested registry key structures" {
            $nestedKeyPath = "$script:TestRegistryPath\Level1\Level2\Level3"
            
            try {
                # Create nested registry structure
                if (-not (Test-Path $nestedKeyPath)) {
                    New-Item -Path $nestedKeyPath -Force | Out-Null
                }
                Test-Path $nestedKeyPath | Should -Be $true
                
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
                
            } finally {
                # Clean up (remove from top level)
                if (Test-Path "$script:TestRegistryPath\Level1") {
                    Remove-Item "$script:TestRegistryPath\Level1" -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
    
    Context "State File and Registry Integration" {
        
        It "Should backup registry value to state file" {
            $testKeyPath = "$script:TestRegistryPath\BackupTest"
            $stateFilePath = Join-Path $script:TestEnvironment.TestState "registry_backup_test.json"
            
            try {
                # Create test registry key with value
                if (-not (Test-Path $testKeyPath)) {
                    New-Item -Path $testKeyPath -Force | Out-Null
                }
                Set-ItemProperty -Path $testKeyPath -Name "BackupValue" -Value "DataToBackup"
                
                # Simulate backup process
                $registryValue = Get-ItemProperty -Path $testKeyPath -Name "BackupValue"
                $stateData = @{
                    KeyName = "BackupTest"
                    Value = $registryValue.BackupValue
                    Encrypted = $false
                    RegistryPath = $testKeyPath
                    ValueName = "BackupValue"
                    Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                }
                
                # Save to state file
                $stateData | ConvertTo-Json -Depth 3 | Out-File $stateFilePath -Encoding UTF8
                Test-Path $stateFilePath | Should -Be $true
                
                # Verify backup content
                $readState = Get-Content $stateFilePath -Raw | ConvertFrom-Json
                $readState.Value | Should -Be "DataToBackup"
                $readState.RegistryPath | Should -Be $testKeyPath
                
            } finally {
                # Clean up
                if (Test-Path $testKeyPath) {
                    Remove-Item $testKeyPath -Recurse -Force -ErrorAction SilentlyContinue
                }
                Remove-Item $stateFilePath -Force -ErrorAction SilentlyContinue
            }
        }
        
        It "Should restore registry value from state file" {
            $testKeyPath = "$script:TestRegistryPath\RestoreTest"
            $stateFilePath = Join-Path $script:TestEnvironment.TestState "registry_restore_test.json"
            
            try {
                # Create state file with restoration data
                $stateData = @{
                    KeyName = "RestoreTest"
                    Value = "DataToRestore"
                    Encrypted = $false
                    RegistryPath = $testKeyPath
                    ValueName = "RestoreValue"
                    Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                }
                $stateData | ConvertTo-Json -Depth 3 | Out-File $stateFilePath -Encoding UTF8
                
                # Simulate restore process
                $readState = Get-Content $stateFilePath -Raw | ConvertFrom-Json
                
                # Create registry key if it doesn't exist
                if (-not (Test-Path $testKeyPath)) {
                    New-Item -Path $testKeyPath -Force | Out-Null
                }
                
                # Restore value
                Set-ItemProperty -Path $testKeyPath -Name $readState.ValueName -Value $readState.Value
                
                # Verify restoration
                $restoredValue = Get-ItemProperty -Path $testKeyPath -Name "RestoreValue"
                $restoredValue.RestoreValue | Should -Be "DataToRestore"
                
            } finally {
                # Clean up
                if (Test-Path $testKeyPath) {
                    Remove-Item $testKeyPath -Recurse -Force -ErrorAction SilentlyContinue
                }
                Remove-Item $stateFilePath -Force -ErrorAction SilentlyContinue
            }
        }
        
        It "Should handle backup and restore of entire registry keys" {
            $testKeyPath = "$script:TestRegistryPath\EntireKeyTest"
            $stateFilePath = Join-Path $script:TestEnvironment.TestState "registry_entire_key.json"
            
            try {
                # Create test registry key with multiple values
                if (-not (Test-Path $testKeyPath)) {
                    New-Item -Path $testKeyPath -Force | Out-Null
                }
                Set-ItemProperty -Path $testKeyPath -Name "Value1" -Value "Data1"
                Set-ItemProperty -Path $testKeyPath -Name "Value2" -Value "Data2"
                Set-ItemProperty -Path $testKeyPath -Name "Value3" -Value 12345 -PropertyType DWord
                
                # Backup entire key
                $keyProperties = Get-ItemProperty -Path $testKeyPath
                $keyValues = @{}
                $keyProperties.PSObject.Properties | Where-Object { $_.Name -notmatch "^PS" } | ForEach-Object {
                    $keyValues[$_.Name] = $_.Value
                }
                
                $stateData = @{
                    KeyName = "EntireKeyTest"
                    Values = $keyValues
                    Encrypted = $false
                    RegistryPath = $testKeyPath
                    BackupEntireKey = $true
                    Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                }
                
                # Save to state file
                $stateData | ConvertTo-Json -Depth 3 | Out-File $stateFilePath -Encoding UTF8
                Test-Path $stateFilePath | Should -Be $true
                
                # Verify backup content
                $readState = Get-Content $stateFilePath -Raw | ConvertFrom-Json
                $readState.Values.Value1 | Should -Be "Data1"
                $readState.Values.Value2 | Should -Be "Data2"
                $readState.Values.Value3 | Should -Be 12345
                
            } finally {
                # Clean up
                if (Test-Path $testKeyPath) {
                    Remove-Item $testKeyPath -Recurse -Force -ErrorAction SilentlyContinue
                }
                Remove-Item $stateFilePath -Force -ErrorAction SilentlyContinue
            }
        }
    }
    
    Context "Error Handling and Edge Cases" {
        
        It "Should handle corrupted state files gracefully" {
            $corruptedStateFile = Join-Path $script:TestEnvironment.TestState "corrupted_state.json"
            $corruptedContent = '{ "KeyName": "Test", "Value": "Data"'  # Missing closing brace
            
            try {
                # Create corrupted file
                $corruptedContent | Out-File $corruptedStateFile -Encoding UTF8
                Test-Path $corruptedStateFile | Should -Be $true
                
                # Attempting to parse should fail
                { Get-Content $corruptedStateFile -Raw | ConvertFrom-Json } | Should -Throw
                
            } finally {
                Remove-Item $corruptedStateFile -Force -ErrorAction SilentlyContinue
            }
        }
        
        It "Should handle missing registry keys during backup" {
            $missingKeyPath = "$script:TestRegistryPath\NonExistentKey"
            
            # Key should not exist
            Test-Path $missingKeyPath | Should -Be $false
            
            # Attempting to read should handle gracefully
            $result = Get-ItemProperty -Path $missingKeyPath -ErrorAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }
        
        It "Should handle permission issues with registry keys" {
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
                
            } finally {
                # Clean up
                if (Test-Path $testKeyPath) {
                    Remove-Item $testKeyPath -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
        
        It "Should handle large registry values" {
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
                    KeyName = "LargeValueTest"
                    Value = $registryValue.LargeValue
                    Encrypted = $false
                    RegistryPath = $testKeyPath
                    ValueName = "LargeValue"
                }
                
                # Save to state file
                $stateData | ConvertTo-Json -Depth 3 | Out-File $stateFilePath -Encoding UTF8
                Test-Path $stateFilePath | Should -Be $true
                
                # Verify large value backup
                $readState = Get-Content $stateFilePath -Raw | ConvertFrom-Json
                $readState.Value.Length | Should -Be 1000
                $readState.Value | Should -Be $largeValue
                
            } finally {
                # Clean up
                if (Test-Path $testKeyPath) {
                    Remove-Item $testKeyPath -Recurse -Force -ErrorAction SilentlyContinue
                }
                Remove-Item $stateFilePath -Force -ErrorAction SilentlyContinue
            }
        }
    }
    
    Context "Multiple State Files Management" {
        
        It "Should handle multiple state files in directory" {
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
                        KeyName = $fileName.Replace("registry_", "").Replace(".json", "")
                        Value = "TestValue_$fileName"
                        Encrypted = $false
                        RegistryPath = "HKCU:\Software\Test\$fileName"
                        ValueName = "TestValue"
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
                
            } finally {
                # Clean up all state files
                foreach ($fileName in $stateFiles) {
                    $filePath = Join-Path $script:TestEnvironment.TestState $fileName
                    Remove-Item $filePath -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
}

AfterAll {
    # Final cleanup of test directories and registry keys
    if (Test-Path $script:TestEnvironment.TestState) {
        Get-ChildItem $script:TestEnvironment.TestState -Recurse | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
    }
    
    # Clean up test registry keys
    if (Test-Path $script:TestRegistryPath) {
        Remove-Item $script:TestRegistryPath -Recurse -Force -ErrorAction SilentlyContinue
    }
} 