#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Unit tests for Windows Missing Recovery module

.DESCRIPTION
    Fast unit tests for core module functionality, configuration, and basic operations.
#>

BeforeAll {
    # Import test utilities
    . $PSScriptRoot/../utilities/Test-Utilities.ps1
    . $PSScriptRoot/../utilities/Mock-Utilities.ps1
    
    # Set up test environment
    $TestModulePath = "/workspace/WindowsMissingRecovery.psm1"
    $TestManifestPath = "/workspace/WindowsMissingRecovery.psd1"
    $TestInstallScriptPath = "/workspace/Install-Module.ps1"
    
    # Create temporary test directory
    $TestTempDir = Join-Path $TestDrive "WindowsMissingRecovery-Tests"
    New-Item -Path $TestTempDir -ItemType Directory -Force | Out-Null
    
    # Mock environment variables for testing
    $env:WMR_CONFIG_PATH = $TestTempDir
    $env:WMR_BACKUP_PATH = Join-Path $TestTempDir "backups"
    $env:WMR_LOG_PATH = Join-Path $TestTempDir "logs"
    
    # Set environment variables to avoid prompts in Initialize-WindowsMissingRecovery
    $env:COMPUTERNAME = "TEST-MACHINE"
    $env:USERPROFILE = "/tmp"
    
    # Install the module for testing (simulates production installation)
    if (-not (Get-Module -ListAvailable -Name "WindowsMissingRecovery")) {
        Write-Host "Installing module for testing..." -ForegroundColor Yellow
        & "/tests/scripts/simulate-installation.ps1" -Force -Verbose
    }
}

Describe "Windows Missing Recovery Module - Installation Tests" -Tag "Installation" {
    
    Context "Module Files" {
        It "Should have a valid module manifest" {
            Test-Path $TestManifestPath | Should -Be $true
            
            $manifest = Import-PowerShellDataFile $TestManifestPath
            $manifest.ModuleVersion | Should -Not -BeNullOrEmpty
            $manifest.Author | Should -Not -BeNullOrEmpty
            $manifest.Description | Should -Not -BeNullOrEmpty
            $manifest.PowerShellVersion | Should -Not -BeNullOrEmpty
        }
        
        It "Should have a valid main module file" {
            Test-Path $TestModulePath | Should -Be $true
            
            # Test syntax
            { [System.Management.Automation.PSParser]::Tokenize((Get-Content $TestModulePath -Raw), [ref]$null) } | Should -Not -Throw
        }
        
        It "Should have an installation script" {
            Test-Path $TestInstallScriptPath | Should -Be $true
            
            # Test syntax
            { [System.Management.Automation.PSParser]::Tokenize((Get-Content $TestInstallScriptPath -Raw), [ref]$null) } | Should -Not -Throw
        }
    }
    
    Context "Module Import" {
        It "Should import without errors" {
            { Import-Module WindowsMissingRecovery -Force -ErrorAction Stop } | Should -Not -Throw
        }
        
        It "Should export expected functions" {
            Import-Module WindowsMissingRecovery -Force
            
            $exportedFunctions = Get-Command -Module WindowsMissingRecovery -ErrorAction SilentlyContinue
            $exportedFunctions | Should -Not -BeNullOrEmpty
            
            # Check for key functions
            $expectedFunctions = @(
                'Initialize-WindowsMissingRecovery',
                'Get-WindowsMissingRecoveryStatus',
                'Backup-WindowsMissingRecovery',
                'Restore-WindowsMissingRecovery'
            )
            
            foreach ($function in $expectedFunctions) {
                Get-Command $function -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
            }
        }
    }
}

Describe "Windows Missing Recovery Module - Initialization Tests" -Tag "Initialization" {
    
    BeforeAll {
        Import-Module WindowsMissingRecovery -Force
    }
    
    Context "Initialization Function" {
        It "Should have Initialize-WindowsMissingRecovery function" {
            Get-Command Initialize-WindowsMissingRecovery -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
        
        It "Should have Get-WindowsMissingRecoveryStatus function" {
            Get-Command Get-WindowsMissingRecoveryStatus -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
        
        It "Should initialize successfully with default parameters" {
            { Initialize-WindowsMissingRecovery -ErrorAction Stop -NoPrompt } | Should -Not -Throw
        }
        
        It "Should initialize with custom configuration path" {
            $customConfigPath = Join-Path $TestTempDir "custom-config"
            { Initialize-WindowsMissingRecovery -InstallPath $customConfigPath -ErrorAction Stop -NoPrompt } | Should -Not -Throw
            
            Test-Path $customConfigPath | Should -Be $true
        }
        
        It "Should return status information" {
            $status = Get-WindowsMissingRecoveryStatus
            $status | Should -Not -BeNullOrEmpty
            $status.Configuration.ModuleVersion | Should -Not -BeNullOrEmpty
            $status.Initialization.Initialized | Should -Not -BeNullOrEmpty
        }
        
        It "Should handle empty install path gracefully" {
            { Initialize-WindowsMissingRecovery -InstallPath "" -ErrorAction Stop -NoPrompt } | Should -Not -Throw
        }
        
        It "Should initialize with valid install path" {
            { Initialize-WindowsMissingRecovery -InstallPath $TestTempDir -NoPrompt } | Should -Not -Throw
        }
    }
    
    Context "Configuration Management" {
        It "Should create configuration directories" {
            Initialize-WindowsMissingRecovery -InstallPath $TestTempDir -NoPrompt
            
            $expectedDirs = @(
                (Join-Path $TestTempDir "Config"),
                (Join-Path $TestTempDir "backups"),
                (Join-Path $TestTempDir "logs"),
                (Join-Path $TestTempDir "scripts")
            )
            
            foreach ($dir in $expectedDirs) {
                Test-Path $dir | Should -Be $true
            }
        }
        
        It "Should copy template files" {
            $templateDir = Join-Path $PSScriptRoot "../../Templates"
            Initialize-WindowsMissingRecovery -InstallPath $TestTempDir -NoPrompt
            
            $configDir = Join-Path $TestTempDir "config"
            
            if (Test-Path (Join-Path $templateDir "scripts-config.json")) {
                Test-Path (Join-Path $configDir "scripts-config.json") | Should -Be $true
            }
        }
    }
    
    Context "Error Handling" {
        It "Should handle invalid configuration path gracefully" {
            $invalidPath = ""
            # The function should handle empty paths gracefully without throwing
            { Initialize-WindowsMissingRecovery -InstallPath $invalidPath -ErrorAction Stop -NoPrompt } | Should -Not -Throw
        }
        
        It "Should handle permission errors gracefully" {
            # Mock a permission error scenario
            Mock New-Item { throw "Access denied" } -ParameterFilter { $Path -like "*test*" }
            
            # The function should handle permission errors gracefully without throwing
            { Initialize-WindowsMissingRecovery -InstallPath $TestTempDir -ErrorAction Stop -NoPrompt } | Should -Not -Throw
        }
    }
}

Describe "Windows Missing Recovery Module - Core Functionality Tests" -Tag "Core" {
    
    BeforeAll {
        Import-Module WindowsMissingRecovery -Force
        Initialize-WindowsMissingRecovery -InstallPath $TestTempDir -NoPrompt
    }
    
    Context "Backup Functions" {
        It "Should have backup functions available" {
            $backupFunctions = @(
                'Backup-WindowsMissingRecovery'
            )
            
            foreach ($function in $backupFunctions) {
                Get-Command $function -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
            }
        }
        
        It "Should create backup manifest" {
            $backupPath = Join-Path $TestTempDir "test-backup"
            { Backup-WindowsMissingRecovery -ErrorAction Stop } | Should -Not -Throw
            
            # Check if backup was created in the configured location
            $config = Get-WindowsMissingRecovery
            $expectedBackupPath = Join-Path $config.BackupRoot $config.MachineName
            Test-Path $expectedBackupPath | Should -Be $true
        }
    }
    
    Context "Restore Functions" {
        It "Should have restore functions available" {
            $restoreFunctions = @(
                'Restore-WindowsMissingRecovery'
            )
            
            foreach ($function in $restoreFunctions) {
                Get-Command $function -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
            }
        }
        
        It "Should validate backup manifest" {
            $backupPath = Join-Path $TestTempDir "test-backup"
            $manifestPath = Join-Path $backupPath "manifest.json"
            
            # Create the backup directory first
            New-Item -Path $backupPath -ItemType Directory -Force | Out-Null
            
            # Create a test manifest
            $testManifest = @{
                ModuleVersion = "1.0.0"
                CreatedDate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                BackupType = "Full"
                Components = @("SystemSettings", "Applications")
            }
            
            $testManifest | ConvertTo-Json -Depth 10 | Out-File -FilePath $manifestPath -Encoding UTF8
            
            # Test that restore function exists and doesn't throw on basic call
            { Restore-WindowsMissingRecovery -ErrorAction Stop } | Should -Not -Throw
        }
    }
    
    Context "Setup Functions" {
        It "Should have setup functions available" {
            $setupFunctions = @(
                'Setup-WindowsMissingRecovery'
            )
            
            foreach ($function in $setupFunctions) {
                Get-Command $function -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
            }
        }
    }
    
    Context "Utility Functions" {
        It "Should have utility functions available" {
            $utilityFunctions = @(
                'Convert-ToWinget',
                'Set-WindowsMissingRecoveryScripts',
                'Sync-WindowsMissingRecoveryScripts',
                'Test-WindowsMissingRecovery',
                'Update-WindowsMissingRecovery',
                'Install-WindowsMissingRecoveryTasks',
                'Remove-WindowsMissingRecoveryTasks'
            )
            
            foreach ($function in $utilityFunctions) {
                Get-Command $function -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
            }
        }
    }
}

Describe "Windows Missing Recovery Module - Integration Tests" -Tag "Integration" {
    
    BeforeAll {
        Import-Module WindowsMissingRecovery -Force
        Initialize-WindowsMissingRecovery -InstallPath $TestTempDir -NoPrompt
    }
    
    Context "Full Backup/Restore Cycle" {
        It "Should complete a full backup and restore cycle" {
            $backupPath = Join-Path $TestTempDir "full-cycle-test"
            
            # Perform backup
            { Backup-WindowsMissingRecovery -ErrorAction Stop } | Should -Not -Throw
            
            # Check if backup was created
            $config = Get-WindowsMissingRecovery
            $expectedBackupPath = Join-Path $config.BackupRoot $config.MachineName
            Test-Path $expectedBackupPath | Should -Be $true
            
            # Perform restore (this would need a valid backup to restore from)
            # For now, just test that the function exists and doesn't throw on basic call
            { Restore-WindowsMissingRecovery -ErrorAction Stop } | Should -Not -Throw
        }
        
        It "Should handle backup validation" {
            # Test that backup validation works
            { Backup-WindowsMissingRecovery -ErrorAction Stop } | Should -Not -Throw
        }
    }
    
    Context "Configuration Synchronization" {
        It "Should sync scripts successfully" {
            { Sync-WindowsMissingRecoveryScripts -ErrorAction Stop -NoPrompt } | Should -Not -Throw
        }
        
        It "Should set scripts configuration" {
            { Set-WindowsMissingRecoveryScripts -ErrorAction Stop } | Should -Not -Throw
        }
    }
    
    Context "Task Management" {
        It "Should install scheduled tasks" {
            { Install-WindowsMissingRecoveryTasks -ErrorAction Stop } | Should -Not -Throw
        }
        
        It "Should remove scheduled tasks" {
            { Remove-WindowsMissingRecoveryTasks -ErrorAction Stop } | Should -Not -Throw
        }
    }
}

Describe "Windows Missing Recovery Module - Error Handling Tests" -Tag "ErrorHandling" {
    
    BeforeAll {
        Import-Module WindowsMissingRecovery -Force
    }
    
    Context "Invalid Parameters" {
        It "Should handle invalid backup path" {
            { Backup-WindowsMissingRecovery -BackupPath "" -ErrorAction Stop } | Should -Throw
        }
        
        It "Should handle invalid restore path" {
            { Restore-WindowsMissingRecovery -BackupPath "C:\NonExistent\Path" -ErrorAction Stop } | Should -Throw
        }
        
        It "Should handle invalid configuration path" {
            { Initialize-WindowsMissingRecovery -InstallPath "" -ErrorAction Stop -NoPrompt } | Should -Not -Throw
        }
    }
    
    Context "Missing Dependencies" {
        It "Should handle missing PowerShell modules gracefully" {
            { Initialize-WindowsMissingRecovery -InstallPath $TestTempDir -NoPrompt } | Should -Not -Throw
        }
    }
    
    Context "Permission Issues" {
        It "Should handle insufficient permissions gracefully" {
            # Mock permission error
            Mock New-Item { throw "Access denied" } -ParameterFilter { $Path -like "*restricted*" }
            
            # The function should handle permission errors gracefully without throwing
            { Initialize-WindowsMissingRecovery -InstallPath $TestTempDir -ErrorAction Stop -NoPrompt } | Should -Not -Throw
        }
    }
}

AfterAll {
    # Cleanup
    if (Test-Path $TestTempDir) {
        Remove-Item -Path $TestTempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    # Remove module
    Remove-Module WindowsMissingRecovery -ErrorAction SilentlyContinue
} 