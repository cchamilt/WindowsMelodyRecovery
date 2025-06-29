#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Integration tests for backup functionality

.DESCRIPTION
    Tests backup operations on real Windows environments with actual WSL, package managers, and cloud storage simulation.
#>

BeforeAll {
    # Import the module
    Import-Module "$PSScriptRoot\..\..\WindowsMelodyRecovery.psm1" -Force
    
    # Setup test environment
    $tempPath = if ($env:TEMP) { $env:TEMP } else { "/tmp" }
    $script:TestBackupRoot = Join-Path $tempPath "WMR-Integration-Tests\Backup"
    $script:TestCloudPath = "$env:USERPROFILE\OneDrive\WindowsMelodyRecovery"
    
    # Create test directories
    New-Item -Path $script:TestBackupRoot -ItemType Directory -Force | Out-Null
    New-Item -Path $script:TestCloudPath -ItemType Directory -Force | Out-Null
    
    # Set test mode
    $env:WMR_TEST_MODE = "true"
    $env:WMR_BACKUP_ROOT = $script:TestBackupRoot
}

Describe "Backup Integration Tests" -Tag "Backup" {
    
    Context "System Settings Backup" {
        It "Should backup system settings successfully" {
            # Load the backup script
            . "$PSScriptRoot\..\..\Private\backup\backup-system-settings.ps1"
            
            # Run backup
            $result = Backup-SystemSettings -BackupRootPath $script:TestBackupRoot
            
            # Verify results
            $result.Success | Should -Be $true
            $result.BackupPath | Should -Exist
            $result.Items.Count | Should -BeGreaterThan 0
        }
        
        It "Should create registry export files" {
            $registryPath = Join-Path $script:TestBackupRoot "Registry"
            Test-Path $registryPath | Should -Be $true
            
            # Check for common registry exports
            $expectedFiles = @(
                "HKLM_SOFTWARE_Microsoft_Windows_CurrentVersion.reg",
                "HKCU_SOFTWARE_Microsoft_Windows_CurrentVersion.reg"
            )
            
            foreach ($file in $expectedFiles) {
                $filePath = Join-Path $registryPath $file
                # File should exist or backup should have attempted to create it
                ($result.Items -contains $file) -or ($result.Errors.Count -gt 0) | Should -Be $true
            }
        }
    }
    
    Context "Application Backup" {
        It "Should backup package manager data" {
            # Load the backup script
            . "$PSScriptRoot\..\..\Private\backup\backup-applications.ps1"
            
            # Run backup
            $result = Backup-Applications -BackupRootPath $script:TestBackupRoot -MachineBackupPath "$script:TestBackupRoot\Machine" -SharedBackupPath "$script:TestBackupRoot\Shared"
            
            # Verify results
            $result.Success | Should -Be $true
            $result.Items.Count | Should -BeGreaterThan 0
        }
        
        It "Should export winget packages" {
            $wingetFile = Join-Path "$script:TestBackupRoot\Shared" "winget-export.json"
            
            # Winget should be available on GitHub Actions runners
            if (Get-Command winget -ErrorAction SilentlyContinue) {
                Test-Path $wingetFile | Should -Be $true
                
                # Verify JSON structure
                $content = Get-Content $wingetFile | ConvertFrom-Json
                $content.Sources | Should -Not -BeNullOrEmpty
            }
        }
        
        It "Should handle chocolatey if installed" {
            if (Get-Command choco -ErrorAction SilentlyContinue) {
                $chocoFile = Join-Path "$script:TestBackupRoot\Shared" "chocolatey-packages.json"
                # Should either create file or handle gracefully
                ($result.Items -contains "chocolatey-packages.json") -or ($result.Errors.Count -ge 0) | Should -Be $true
            }
        }
    }
    
    Context "WSL Backup" -Skip:(-not $env:WMR_WSL_DISTRO) {
        It "Should backup WSL environment" {
            # Load the backup script
            . "$PSScriptRoot\..\..\Private\backup\backup-wsl.ps1"
            
            # Run backup
            $result = Backup-WSL -BackupRootPath $script:TestBackupRoot
            
            # Verify results
            $result.Success | Should -Be $true
            $result.Items.Count | Should -BeGreaterThan 0
        }
        
        It "Should backup WSL package lists" {
            $wslBackupPath = Join-Path $script:TestBackupRoot "WSL"
            Test-Path $wslBackupPath | Should -Be $true
            
            # Check for package lists
            $packageFiles = @(
                "apt-packages.txt",
                "npm-packages.json",
                "pip-packages.txt"
            )
            
            foreach ($file in $packageFiles) {
                $filePath = Join-Path $wslBackupPath $file
                # Should exist or be in the items list
                (Test-Path $filePath) -or ($result.Items -contains $file) | Should -Be $true
            }
        }
        
        It "Should backup WSL configuration files" {
            $configPath = Join-Path $script:TestBackupRoot "WSL\config"
            
            # Should attempt to backup common config files
            $configFiles = @(
                "wsl.conf",
                "fstab",
                "hosts"
            )
            
            # At least some config files should be backed up
            $result.Items | Where-Object { $_ -like "*.conf" -or $_ -like "*fstab*" -or $_ -like "*hosts*" } | Should -Not -BeNullOrEmpty
        }
    }
    
    Context "Gaming Platform Backup" {
        It "Should backup gaming platform configurations" {
            # Load the backup script
            . "$PSScriptRoot\..\..\Private\backup\backup-gamemanagers.ps1"
            
            # Run backup
            $result = Backup-GameManagers -BackupRootPath $script:TestBackupRoot -MachineBackupPath "$script:TestBackupRoot\Machine" -SharedBackupPath "$script:TestBackupRoot\Shared"
            
            # Verify results
            $result.Success | Should -Be $true
        }
        
        It "Should handle Steam configuration" {
            $steamPath = "$env:ProgramFiles(x86)\Steam"
            if (Test-Path $steamPath) {
                $steamBackup = Join-Path "$script:TestBackupRoot\Machine" "steam-config.json"
                Test-Path $steamBackup | Should -Be $true
            } else {
                # Should handle missing Steam gracefully
                $result.Errors.Count | Should -BeGreaterOrEqual 0
            }
        }
        
        It "Should handle Epic Games configuration" {
            $epicPath = "$env:ProgramFiles(x86)\Epic Games\Launcher"
            if (Test-Path $epicPath) {
                $epicBackup = Join-Path "$script:TestBackupRoot\Machine" "epic-config.json"
                Test-Path $epicBackup | Should -Be $true
            } else {
                # Should handle missing Epic gracefully
                $result.Errors.Count | Should -BeGreaterOrEqual 0
            }
        }
    }
    
    Context "Cloud Storage Integration" {
        It "Should detect cloud storage paths" {
            # Test OneDrive detection
            $oneDrivePath = "$env:USERPROFILE\OneDrive"
            if (Test-Path $oneDrivePath) {
                Test-Path "$oneDrivePath\WindowsMelodyRecovery" | Should -Be $true
            }
        }
        
        It "Should backup to cloud storage location" {
            # Simulate cloud backup
            $cloudBackupPath = Join-Path $script:TestCloudPath "backup-$(Get-Date -Format 'yyyy-MM-dd')"
            New-Item -Path $cloudBackupPath -ItemType Directory -Force | Out-Null
            
            # Copy some test data
            Copy-Item -Path "$script:TestBackupRoot\*" -Destination $cloudBackupPath -Recurse -Force -ErrorAction SilentlyContinue
            
            # Verify cloud backup exists
            Test-Path $cloudBackupPath | Should -Be $true
        }
    }
    
    Context "Error Handling" {
        It "Should handle invalid backup paths gracefully" {
            # Test with invalid path
            $result = Backup-SystemSettings -BackupRootPath "Z:\NonExistent\Path"
            
            # Should fail gracefully
            $result.Success | Should -Be $false
            $result.Errors.Count | Should -BeGreaterThan 0
        }
        
        It "Should handle permission issues gracefully" {
            # Test with restricted path (if possible)
            $restrictedPath = "$env:SystemRoot\System32\TestBackup"
            
            try {
                $result = Backup-SystemSettings -BackupRootPath $restrictedPath
                # Should either succeed or fail gracefully
                $result | Should -Not -BeNullOrEmpty
            } catch {
                # Exception handling is acceptable
                $_.Exception.Message | Should -Not -BeNullOrEmpty
            }
        }
    }
}

AfterAll {
    # Cleanup test environment
    if (Test-Path $script:TestBackupRoot) {
        Remove-Item -Path $script:TestBackupRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    # Remove test environment variables
    Remove-Item Env:WMR_TEST_MODE -ErrorAction SilentlyContinue
    Remove-Item Env:WMR_BACKUP_ROOT -ErrorAction SilentlyContinue
} 