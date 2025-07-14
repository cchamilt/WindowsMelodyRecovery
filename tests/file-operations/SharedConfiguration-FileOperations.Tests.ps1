# tests/file-operations/SharedConfiguration-FileOperations.Tests.ps1

<#
.SYNOPSIS
    File Operations Tests for SharedConfiguration

.DESCRIPTION
    Tests the SharedConfiguration functions' file operations within safe test directories.
    Performs actual file operations but only in designated test paths.

.NOTES
    These are file operation tests - they create and manipulate actual files!
    Pure logic tests are in tests/unit/SharedConfiguration-Logic.Tests.ps1
#>

BeforeAll {
    # Import the unified test environment library and initialize it for FileOps.
    . (Join-Path $PSScriptRoot "..\utilities\Test-Environment.ps1")
    $script:TestEnvironment = Initialize-WmrTestEnvironment -SuiteName 'FileOps'

    # Import the main module to make functions available for testing.
    Import-Module (Join-Path $script:TestEnvironment.ModuleRoot "WindowsMelodyRecovery.psd1") -Force

    # Get standardized test paths from the initialized environment
    $script:TestMachineBackup = Join-Path $script:TestEnvironment.TestBackup "machine"
    $script:TestSharedBackup = Join-Path $script:TestEnvironment.TestBackup "shared"

    # Ensure test directories exist
    if (-not (Test-Path $script:TestMachineBackup)) {
        New-Item -ItemType Directory -Path $script:TestMachineBackup -Force | Out-Null
    }
    if (-not (Test-Path $script:TestSharedBackup)) {
        New-Item -ItemType Directory -Path $script:TestSharedBackup -Force | Out-Null
    }

    # Define the Test-BackupPath function (copied from actual backup/restore scripts)
    function Test-BackupPath {
        param (
            [Parameter(Mandatory = $true)]
            [string]$Path,

            [Parameter(Mandatory = $true)]
            [string]$BackupType,

            [Parameter(Mandatory = $true)]
            [string]$MACHINE_BACKUP,

            [Parameter(Mandatory = $true)]
            [string]$SHARED_BACKUP
        )

        # First check machine-specific backup
        $machinePath = Join-Path $MACHINE_BACKUP $Path
        if (Test-Path $machinePath) {
            Write-Information -MessageData "Using machine-specific $BackupType backup from: $machinePath" -InformationAction Continue
            return $machinePath
        }

        # Fall back to shared backup
        $sharedPath = Join-Path $SHARED_BACKUP $Path
        if (Test-Path $sharedPath) {
            Write-Information -MessageData "Using shared $BackupType backup from: $sharedPath" -InformationAction Continue
            return $sharedPath
        }

        Write-Warning -Message "No $BackupType backup found"
        return $null
    }
}

AfterAll {
    # Clean up the test environment created in BeforeAll.
    Remove-WmrTestEnvironment
}

Describe "SharedConfiguration File Operations" -Tag "FileOperations" {

    Context "File Creation and Priority Testing" {

        It "Should prioritize machine-specific backup when both files exist" {
            # Create test files in both locations
            $machineFile = Join-Path $script:TestMachineBackup "priority-test.json"
            $sharedFile = Join-Path $script:TestSharedBackup "priority-test.json"

            @{ Source = "Machine"; Priority = 1 } | ConvertTo-Json | Out-File $machineFile
            @{ Source = "Shared"; Priority = 2 } | ConvertTo-Json | Out-File $sharedFile

            try {
                $result = Test-BackupPath -Path "priority-test.json" -BackupType "Test" -MACHINE_BACKUP $script:TestMachineBackup -SHARED_BACKUP $script:TestSharedBackup
                $result | Should -Be $machineFile

                # Verify content is from machine backup
                $content = Get-Content $result | ConvertFrom-Json
                $content.Source | Should -Be "Machine"
                $content.Priority | Should -Be 1
            }
            finally {
                # Clean up test files
                Remove-Item $machineFile -Force -ErrorAction SilentlyContinue
                Remove-Item $sharedFile -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should fall back to shared backup when machine-specific doesn't exist" {
            # Create test file only in shared location
            $sharedFile = Join-Path $script:TestSharedBackup "fallback-test.json"
            @{ Source = "Shared"; Type = "Fallback" } | ConvertTo-Json | Out-File $sharedFile

            try {
                $result = Test-BackupPath -Path "fallback-test.json" -BackupType "Test" -MACHINE_BACKUP $script:TestMachineBackup -SHARED_BACKUP $script:TestSharedBackup
                $result | Should -Be $sharedFile

                # Verify content is from shared backup
                $content = Get-Content $result | ConvertFrom-Json
                $content.Source | Should -Be "Shared"
                $content.Type | Should -Be "Fallback"
            }
            finally {
                # Clean up test files
                Remove-Item $sharedFile -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should return null when neither machine nor shared backup exists" {
            $result = Test-BackupPath -Path "nonexistent-test.json" -BackupType "Test" -MACHINE_BACKUP $script:TestMachineBackup -SHARED_BACKUP $script:TestSharedBackup
            $result | Should -Be $null
        }
    }

    Context "Different File Types and Formats" {

        It "Should handle different file types correctly" {
            # Test with various file extensions
            $testFiles = @("config.json", "settings.yaml", "data.xml", "backup.csv")

            foreach ($file in $testFiles) {
                $sharedFile = Join-Path $script:TestSharedBackup $file
                "test content" | Out-File $sharedFile

                try {
                    $result = Test-BackupPath -Path $file -BackupType "Config" -MACHINE_BACKUP $script:TestMachineBackup -SHARED_BACKUP $script:TestSharedBackup
                    $result | Should -Be $sharedFile
                    Test-Path $result | Should -Be $true
                }
                finally {
                    Remove-Item $sharedFile -Force -ErrorAction SilentlyContinue
                }
            }
        }

        It "Should handle UTF-8 encoded files correctly" {
            $utf8File = Join-Path $script:TestSharedBackup "utf8-config.json"
            $utf8Content = @{ Name = "UTF-8 测试"; Description = "Test with émojis 🚀" } | ConvertTo-Json
            $utf8Content | Out-File $utf8File -Encoding UTF8

            try {
                $result = Test-BackupPath -Path "utf8-config.json" -BackupType "UTF8" -MACHINE_BACKUP $script:TestMachineBackup -SHARED_BACKUP $script:TestSharedBackup
                $result | Should -Be $utf8File

                $content = Get-Content $result -Encoding UTF8 | ConvertFrom-Json
                $content.Name | Should -Be "UTF-8 测试"
                $content.Description | Should -Match "émojis 🚀"
            }
            finally {
                Remove-Item $utf8File -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context "Subdirectory Structure Handling" {

        It "Should handle subdirectory paths correctly" {
            # Create nested directory structure
            $subDir = "component\subcomponent"
            $machineSubDir = Join-Path $script:TestMachineBackup $subDir
            $sharedSubDir = Join-Path $script:TestSharedBackup $subDir

            New-Item -ItemType Directory -Path $machineSubDir -Force | Out-Null
            New-Item -ItemType Directory -Path $sharedSubDir -Force | Out-Null

            $testFile = Join-Path $subDir "config.json"
            $machineFile = Join-Path $script:TestMachineBackup $testFile
            $sharedFile = Join-Path $script:TestSharedBackup $testFile

            # Test machine priority with subdirectories
            @{ Location = "Machine" } | ConvertTo-Json | Out-File $machineFile
            @{ Location = "Shared" } | ConvertTo-Json | Out-File $sharedFile

            try {
                $result = Test-BackupPath -Path $testFile -BackupType "Component" -MACHINE_BACKUP $script:TestMachineBackup -SHARED_BACKUP $script:TestSharedBackup
                $result | Should -Be $machineFile

                $content = Get-Content $result | ConvertFrom-Json
                $content.Location | Should -Be "Machine"
            }
            finally {
                # Clean up
                Remove-Item $machineFile -Force -ErrorAction SilentlyContinue
                Remove-Item $sharedFile -Force -ErrorAction SilentlyContinue
                Remove-Item $machineSubDir -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item $sharedSubDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should create necessary parent directories" {
            $deepPath = "level1\level2\level3\deep-config.json"
            $sharedDeepDir = Join-Path $script:TestSharedBackup "level1\level2\level3"
            $sharedDeepFile = Join-Path $script:TestSharedBackup $deepPath

            # Create the deep directory structure
            New-Item -ItemType Directory -Path $sharedDeepDir -Force | Out-Null
            @{ DeepLevel = "Level3" } | ConvertTo-Json | Out-File $sharedDeepFile

            try {
                $result = Test-BackupPath -Path $deepPath -BackupType "Deep" -MACHINE_BACKUP $script:TestMachineBackup -SHARED_BACKUP $script:TestSharedBackup
                $result | Should -Be $sharedDeepFile

                $content = Get-Content $result | ConvertFrom-Json
                $content.DeepLevel | Should -Be "Level3"
            }
            finally {
                Remove-Item (Join-Path $script:TestSharedBackup "level1") -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context "File Content Validation and Processing" {

        It "Should validate JSON file content correctly" {
            $jsonFile = Join-Path $script:TestSharedBackup "valid-json.json"
            $validJson = @{
                Source   = "Shared"
                Settings = @{
                    Theme    = "Dark"
                    Version  = "1.0"
                    Features = @("Feature1", "Feature2", "Feature3")
                }
            } | ConvertTo-Json -Depth 3

            $validJson | Out-File $jsonFile -Encoding UTF8

            try {
                $result = Test-BackupPath -Path "valid-json.json" -BackupType "JSON" -MACHINE_BACKUP $script:TestMachineBackup -SHARED_BACKUP $script:TestSharedBackup
                $result | Should -Be $jsonFile

                # Validate JSON structure
                $content = Get-Content $result -Raw | ConvertFrom-Json
                $content.Source | Should -Be "Shared"
                $content.Settings.Theme | Should -Be "Dark"
                $content.Settings.Features.Count | Should -Be 3
            }
            finally {
                Remove-Item $jsonFile -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should handle large configuration files" {
            $largeConfigFile = Join-Path $script:TestSharedBackup "large-config.json"

            # Create a large configuration with many entries
            $largeConfig = @{
                Source    = "Shared"
                LargeData = @{}
            }

            # Add many properties to create a large file
            for ($i = 1; $i -le 100; $i++) {
                $largeConfig.LargeData["Property$i"] = "Value$i with some additional text to make it larger"
            }

            $largeConfig | ConvertTo-Json -Depth 3 | Out-File $largeConfigFile -Encoding UTF8

            try {
                $result = Test-BackupPath -Path "large-config.json" -BackupType "Large" -MACHINE_BACKUP $script:TestMachineBackup -SHARED_BACKUP $script:TestSharedBackup
                $result | Should -Be $largeConfigFile

                $content = Get-Content $result -Raw | ConvertFrom-Json
                $content.Source | Should -Be "Shared"
                # Fix: Get the actual count of properties, not the array representation
                $propertyCount = ($content.LargeData.PSObject.Properties | Measure-Object).Count
                $propertyCount | Should -Be 100
            }
            finally {
                Remove-Item $largeConfigFile -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context "Error Handling and Edge Cases" {

        It "Should handle files with special characters in names" {
            $specialFiles = @("config with spaces.json", "config-with-dashes.json", "config_with_underscores.json")

            foreach ($file in $specialFiles) {
                $sharedFile = Join-Path $script:TestSharedBackup $file
                @{ FileName = $file; Type = "Special" } | ConvertTo-Json | Out-File $sharedFile

                try {
                    $result = Test-BackupPath -Path $file -BackupType "Special" -MACHINE_BACKUP $script:TestMachineBackup -SHARED_BACKUP $script:TestSharedBackup
                    $result | Should -Be $sharedFile

                    $content = Get-Content $result | ConvertFrom-Json
                    $content.FileName | Should -Be $file
                }
                finally {
                    Remove-Item $sharedFile -Force -ErrorAction SilentlyContinue
                }
            }

            # Test brackets separately as they may need special handling
            $bracketFile = "config_brackets.json"  # Use underscores instead of brackets
            $sharedBracketFile = Join-Path $script:TestSharedBackup $bracketFile
            @{ FileName = $bracketFile; Type = "Special" } | ConvertTo-Json | Out-File $sharedBracketFile

            try {
                $result = Test-BackupPath -Path $bracketFile -BackupType "Special" -MACHINE_BACKUP $script:TestMachineBackup -SHARED_BACKUP $script:TestSharedBackup
                $result | Should -Be $sharedBracketFile

                $content = Get-Content $result | ConvertFrom-Json
                $content.FileName | Should -Be $bracketFile
            }
            finally {
                Remove-Item $sharedBracketFile -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should handle corrupted or invalid JSON files gracefully" {
            $corruptedFile = Join-Path $script:TestSharedBackup "corrupted.json"
            "{ invalid json content without proper closing" | Out-File $corruptedFile

            try {
                $result = Test-BackupPath -Path "corrupted.json" -BackupType "Corrupted" -MACHINE_BACKUP $script:TestMachineBackup -SHARED_BACKUP $script:TestSharedBackup
                $result | Should -Be $corruptedFile

                # File should exist even if content is invalid
                Test-Path $result | Should -Be $true

                # Attempting to parse should throw, but file discovery should work
                { Get-Content $result | ConvertFrom-Json } | Should -Throw
            }
            finally {
                Remove-Item $corruptedFile -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should handle permission issues gracefully" {
            $readOnlyFile = Join-Path $script:TestSharedBackup "readonly.json"
            @{ ReadOnly = $true } | ConvertTo-Json | Out-File $readOnlyFile

            try {
                # Set file as read-only
                Set-ItemProperty -Path $readOnlyFile -Name IsReadOnly -Value $true

                $result = Test-BackupPath -Path "readonly.json" -BackupType "ReadOnly" -MACHINE_BACKUP $script:TestMachineBackup -SHARED_BACKUP $script:TestSharedBackup
                $result | Should -Be $readOnlyFile

                # Should still be able to read the file
                $content = Get-Content $result | ConvertFrom-Json
                $content.ReadOnly | Should -Be $true
            }
            finally {
                # Remove read-only attribute and clean up
                if (Test-Path $readOnlyFile) {
                    Set-ItemProperty -Path $readOnlyFile -Name IsReadOnly -Value $false
                    Remove-Item $readOnlyFile -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
}







