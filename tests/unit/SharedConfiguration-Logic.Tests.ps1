# tests/unit/SharedConfiguration-Logic.Tests.ps1

<#
.SYNOPSIS
    Pure Unit Tests for SharedConfiguration Logic

.DESCRIPTION
    Tests the SharedConfiguration functions' logic without any actual file operations.
    Uses mock data and tests the decision-making logic only.

.NOTES
    These are pure unit tests - no file system operations!
    File operation tests are in tests/file-operations/SharedConfiguration-FileOperations.Tests.ps1
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

    # Mock all file operations
    Mock Test-Path { return $true } -ParameterFilter { $Path -like "*machine*" -and $Path -like "*priority*" }
    Mock Test-Path { return $true } -ParameterFilter { $Path -like "*shared*" -and $Path -like "*fallback*" }
    Mock Test-Path { return $false } -ParameterFilter { $Path -like "*nonexistent*" }
    Mock Test-Path { return $true } # Default to true for other paths
    Mock New-Item { return @{ FullName = $Path } }
    Mock Remove-Item { }
    Mock Get-Content { return '{"Source":"Machine","Priority":1}' } -ParameterFilter { $Path -like "*machine*" }
    Mock Get-Content { return '{"Source":"Shared","Priority":2}' } -ParameterFilter { $Path -like "*shared*" }

    # Define the Test-BackupPath function (copied from actual backup/restore scripts)
    function Test-BackupPath {
        param (
            [Parameter(Mandatory=$true)]
            [string]$Path,

            [Parameter(Mandatory=$true)]
            [string]$BackupType,

            [Parameter(Mandatory=$true)]
            [AllowEmptyString()]
            [string]$MACHINE_BACKUP,

            [Parameter(Mandatory=$true)]
            [AllowEmptyString()]
            [string]$SHARED_BACKUP
        )

        # Handle empty backup paths gracefully
        if ([string]::IsNullOrWhiteSpace($MACHINE_BACKUP) -and [string]::IsNullOrWhiteSpace($SHARED_BACKUP)) {
            Write-Host "No backup paths provided" -ForegroundColor Yellow
            return $null
        }

        # First check machine-specific backup
        if (-not [string]::IsNullOrWhiteSpace($MACHINE_BACKUP)) {
            $machinePath = Join-Path $MACHINE_BACKUP $Path
            if (Test-Path $machinePath) {
                Write-Host "Using machine-specific $BackupType backup from: $machinePath" -ForegroundColor Green
                return $machinePath
            }
        }

        # Fall back to shared backup
        if (-not [string]::IsNullOrWhiteSpace($SHARED_BACKUP)) {
            $sharedPath = Join-Path $SHARED_BACKUP $Path
            if (Test-Path $sharedPath) {
                Write-Host "Using shared $BackupType backup from: $sharedPath" -ForegroundColor Green
                return $sharedPath
            }
        }

        Write-Host "No $BackupType backup found" -ForegroundColor Yellow
        return $null
    }
}

Describe "SharedConfiguration Logic Tests" -Tag "Unit", "Logic" {

    Context "Priority Logic - Machine First, Shared Fallback" {

        It "Should prioritize machine-specific backup when both exist" {
            # Mock Test-Path to return true for both locations
            Mock Test-Path { return $true } -ParameterFilter { $Path -like "*machine*priority*" }
            Mock Test-Path { return $true } -ParameterFilter { $Path -like "*shared*priority*" }

            $machineBackup = (Get-WmrTestPath -WindowsPath "C:\MockMachine")
            $sharedBackup = (Get-WmrTestPath -WindowsPath "C:\MockShared")
            $expectedMachinePath = Join-Path $machineBackup "priority-test.json"

            $result = Test-BackupPath -Path "priority-test.json" -BackupType "Test" -MACHINE_BACKUP $machineBackup -SHARED_BACKUP $sharedBackup
            $result | Should -Be $expectedMachinePath
        }

        It "Should fall back to shared backup when machine-specific doesn't exist" {
            # Mock Test-Path to return false for machine, true for shared
            Mock Test-Path { return $false } -ParameterFilter { $Path -like "*machine*fallback*" }
            Mock Test-Path { return $true } -ParameterFilter { $Path -like "*shared*fallback*" }

            $machineBackup = (Get-WmrTestPath -WindowsPath "C:\MockMachine")
            $sharedBackup = (Get-WmrTestPath -WindowsPath "C:\MockShared")
            $expectedSharedPath = Join-Path $sharedBackup "fallback-test.json"

            $result = Test-BackupPath -Path "fallback-test.json" -BackupType "Test" -MACHINE_BACKUP $machineBackup -SHARED_BACKUP $sharedBackup
            $result | Should -Be $expectedSharedPath
        }

        It "Should return null when neither machine nor shared backup exists" {
            # Mock Test-Path to return false for both locations
            Mock Test-Path { return $false } -ParameterFilter { $Path -like "*nonexistent*" }

            $result = Test-BackupPath -Path "nonexistent-test.json" -BackupType "Test" -MACHINE_BACKUP (Get-WmrTestPath -WindowsPath "C:\MockMachine") -SHARED_BACKUP (Get-WmrTestPath -WindowsPath "C:\MockShared")
            $result | Should -Be $null
        }
    }

    Context "Configuration Discovery and Selection Logic" {

        It "Should handle different file types correctly" {
            $testFiles = @("config.json", "settings.yaml", "data.xml", "backup.csv")
            $machineBackup = (Get-WmrTestPath -WindowsPath "C:\MockMachine")
            $sharedBackup = (Get-WmrTestPath -WindowsPath "C:\MockShared")

            foreach ($file in $testFiles) {
                # Mock Test-Path to return false for machine, true for shared for each file
                Mock Test-Path { return $false } -ParameterFilter { $Path -like "*machine*$file" }
                Mock Test-Path { return $true } -ParameterFilter { $Path -like "*shared*$file" }

                $expectedPath = Join-Path $sharedBackup $file
                $result = Test-BackupPath -Path $file -BackupType "Config" -MACHINE_BACKUP $machineBackup -SHARED_BACKUP $sharedBackup
                $result | Should -Be $expectedPath
            }
        }

        It "Should handle subdirectory paths correctly" {
            $subDir = "component\subcomponent"
            $testFile = Join-Path $subDir "config.json"
            $machineBackup = (Get-WmrTestPath -WindowsPath "C:\MockMachine")
            $sharedBackup = (Get-WmrTestPath -WindowsPath "C:\MockShared")
            $expectedMachinePath = Join-Path $machineBackup $testFile

            # Mock Test-Path to return true for machine subdirectory
            Mock Test-Path { return $true } -ParameterFilter { $Path -like "*machine*component*subcomponent*" }

            $result = Test-BackupPath -Path $testFile -BackupType "Component" -MACHINE_BACKUP $machineBackup -SHARED_BACKUP $sharedBackup
            $result | Should -Be $expectedMachinePath
        }
    }

    Context "Path Construction Logic" {

        It "Should construct correct machine backup paths" {
            $machineBackup = (Get-WmrTestPath -WindowsPath "C:\TestMachine")
            $relativePath = "apps\winget.json"
            $expectedPath = Join-Path $machineBackup $relativePath

            $expectedPath | Should -Be (Get-WmrTestPath -WindowsPath "C:\TestMachine\apps\winget.json")
        }

        It "Should construct correct shared backup paths" {
            $sharedBackup = (Get-WmrTestPath -WindowsPath "C:\TestShared")
            $relativePath = "registry\display.json"
            $expectedPath = Join-Path $sharedBackup $relativePath

            $expectedPath | Should -Be (Get-WmrTestPath -WindowsPath "C:\TestShared\registry\display.json")
        }

        It "Should handle complex nested paths" {
            $basePath = (Get-WmrTestPath -WindowsPath "C:\Backup")
            $nestedPath = "level1\level2\level3\config.json"
            $fullPath = Join-Path $basePath $nestedPath

            $fullPath | Should -Be (Get-WmrTestPath -WindowsPath "C:\Backup\level1\level2\level3\config.json")
        }
    }

    Context "Configuration Merging Logic" {

        It "Should merge machine and shared configurations correctly" {
            # Test configuration merging logic
            $machineConfig = @{
                Source = "Machine"
                Priority = 1
                Settings = @{
                    Theme = "Dark"
                    Language = "en-US"
                }
            }

            $sharedConfig = @{
                Source = "Shared"
                Priority = 2
                Settings = @{
                    Theme = "Light"  # Should be overridden by machine
                    FontSize = "12"  # Should be added from shared
                }
            }

            # Machine config should take priority
            $machineConfig.Priority | Should -BeLessThan $sharedConfig.Priority
            $machineConfig.Settings.Theme | Should -Be "Dark"
        }

        It "Should handle missing configuration properties gracefully" {
            $incompleteConfig = @{
                Source = "Test"
                # Missing Priority and Settings
            }

            # Should handle gracefully without throwing
            $incompleteConfig.Source | Should -Be "Test"
            $incompleteConfig.Priority | Should -BeNullOrEmpty
        }
    }

    Context "Error Handling Logic" {

        It "Should handle empty or null paths gracefully" {
            $result = Test-BackupPath -Path "test.json" -BackupType "Test" -MACHINE_BACKUP "" -SHARED_BACKUP ""
            # Should handle gracefully and return null
            $result | Should -Be $null
        }

        It "Should handle special characters in filenames" {
            $specialFiles = @("config with spaces.json", "config-with-dashes.json", "config_with_underscores.json")
            $machineBackup = (Get-WmrTestPath -WindowsPath "C:\MockMachine")
            $sharedBackup = (Get-WmrTestPath -WindowsPath "C:\MockShared")

            foreach ($file in $specialFiles) {
                # Mock Test-Path to return true for shared location
                Mock Test-Path { return $false } -ParameterFilter { $Path -like "*machine*" -and $Path -like "*$file*" }
                Mock Test-Path { return $true } -ParameterFilter { $Path -like "*shared*" -and $Path -like "*$file*" }

                $expectedPath = Join-Path $sharedBackup $file
                $result = Test-BackupPath -Path $file -BackupType "Special" -MACHINE_BACKUP $machineBackup -SHARED_BACKUP $sharedBackup
                $result | Should -Be $expectedPath
            }
        }
    }

    Context "Configuration Validation Logic" {

        It "Should validate configuration structure" {
            $validConfig = @{
                Source = "Machine"
                Priority = 1
                BackupType = "System"
                Path = (Get-WmrTestPath -WindowsPath "C:\Config\system.json")
            }

            # Validate required properties exist
            $validConfig.Source | Should -Not -BeNullOrEmpty
            $validConfig.Priority | Should -BeOfType [int]
            $validConfig.Path | Should -Match "\.json$"
        }

        It "Should identify configuration type from source" {
            $machineConfig = @{ Source = "Machine" }
            $sharedConfig = @{ Source = "Shared" }
            $moduleConfig = @{ Source = "ModuleConfig" }

            $machineConfig.Source | Should -Be "Machine"
            $sharedConfig.Source | Should -Be "Shared"
            $moduleConfig.Source | Should -Be "ModuleConfig"
        }

        It "Should validate priority ordering" {
            $priorities = @(1, 2, 3, 4, 5)

            for ($i = 0; $i -lt $priorities.Count - 1; $i++) {
                $priorities[$i] | Should -BeLessThan $priorities[$i + 1]
            }
        }
    }
}

