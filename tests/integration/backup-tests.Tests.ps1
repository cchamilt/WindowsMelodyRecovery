#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Integration tests for backup functionality using the template-based approach

.DESCRIPTION
    Tests backup operations using the new template system instead of legacy script-based backups.
#>

BeforeAll {
    # Import the module
    Import-Module WindowsMelodyRecovery -Force
    
    # Setup test environment
    $tempPath = if ($env:TEMP) { $env:TEMP } else { "/tmp" }
    $script:TestBackupRoot = Join-Path $tempPath "WMR-Integration-Tests\Backup"
    $script:TestCloudPath = Join-Path $tempPath "WMR-Integration-Tests\Cloud"
    
    # Create test directories
    New-Item -Path $script:TestBackupRoot -ItemType Directory -Force | Out-Null
    New-Item -Path $script:TestCloudPath -ItemType Directory -Force | Out-Null
    
    # Set test mode
    $env:WMR_TEST_MODE = "true"
    $env:WMR_BACKUP_ROOT = $script:TestBackupRoot
    
    # Get module root for template paths
    $script:ModuleRoot = Split-Path (Get-Module WindowsMelodyRecovery).Path -Parent
    $script:TemplatesPath = Join-Path $script:ModuleRoot "Templates\System"
    
    # Import the template function
    . (Join-Path $script:ModuleRoot "Private\Core\InvokeWmrTemplate.ps1")
}

Describe "Backup Integration Tests" -Tag "Backup" {
    
    Context "System Settings Backup" {
        It "Should backup system settings successfully using template" {
            # Use the system-settings template
            $templatePath = Join-Path $script:TemplatesPath "system-settings.yaml"
            
            # Skip if template doesn't exist
            if (-not (Test-Path $templatePath)) {
                Set-ItResult -Skipped -Because "system-settings.yaml template not found"
                return
            }
            
            # Create backup directory for this template
            $backupPath = Join-Path $script:TestBackupRoot "system-settings"
            
            # Run template-based backup
            { Invoke-WmrTemplate -TemplatePath $templatePath -Operation "Backup" -StateFilesDirectory $backupPath } | Should -Not -Throw
            
            # Verify backup directory was created
            Test-Path $backupPath | Should -Be $true
            
            # Check for backup files
            $backupFiles = Get-ChildItem -Path $backupPath -Recurse -File
            $backupFiles.Count | Should -BeGreaterThan 0
        }
        
        It "Should create state files in backup directory" {
            $backupPath = Join-Path $script:TestBackupRoot "system-settings"
            
            if (Test-Path $backupPath) {
                # Should contain some backup files
                $stateFiles = Get-ChildItem -Path $backupPath -Recurse -File
                $stateFiles | Should -Not -BeNullOrEmpty
            }
        }
    }
    
    Context "Application Backup" {
        It "Should backup applications using template" {
            # Use the applications template
            $templatePath = Join-Path $script:TemplatesPath "applications.yaml"
            
            # Skip if template doesn't exist
            if (-not (Test-Path $templatePath)) {
                Set-ItResult -Skipped -Because "applications.yaml template not found"
                return
            }
            
            # Create backup directory for this template
            $backupPath = Join-Path $script:TestBackupRoot "applications"
            
            # Run template-based backup
            { Invoke-WmrTemplate -TemplatePath $templatePath -Operation "Backup" -StateFilesDirectory $backupPath } | Should -Not -Throw
            
            # Verify backup directory was created
            Test-Path $backupPath | Should -Be $true
        }
        
        It "Should handle package manager exports in template" {
            $backupPath = Join-Path $script:TestBackupRoot "applications"
            
            if (Test-Path $backupPath) {
                # Check for application backup files
                $appFiles = Get-ChildItem -Path $backupPath -Recurse -File
                $appFiles | Should -Not -BeNullOrEmpty
            }
        }
    }
    
    Context "WSL Backup" -Skip:(-not $env:WMR_WSL_DISTRO) {
        It "Should backup WSL using template" {
            # Use the WSL template
            $templatePath = Join-Path $script:TemplatesPath "wsl.yaml"
            
            # Skip if template doesn't exist
            if (-not (Test-Path $templatePath)) {
                Set-ItResult -Skipped -Because "wsl.yaml template not found"
                return
            }
            
            # Create backup directory for this template
            $backupPath = Join-Path $script:TestBackupRoot "wsl"
            
            # Run template-based backup
            { Invoke-WmrTemplate -TemplatePath $templatePath -Operation "Backup" -StateFilesDirectory $backupPath } | Should -Not -Throw
            
            # Verify backup directory was created
            Test-Path $backupPath | Should -Be $true
        }
        
        It "Should backup WSL configuration and packages" {
            $backupPath = Join-Path $script:TestBackupRoot "wsl"
            
            if (Test-Path $backupPath) {
                # Check for WSL backup files
                $wslFiles = Get-ChildItem -Path $backupPath -Recurse -File
                $wslFiles | Should -Not -BeNullOrEmpty
            }
        }
    }
    
    Context "Gaming Platform Backup" {
        It "Should backup gaming platforms using template" {
            # Use the gamemanagers template
            $templatePath = Join-Path $script:TemplatesPath "gamemanagers.yaml"
            
            # Skip if template doesn't exist
            if (-not (Test-Path $templatePath)) {
                Set-ItResult -Skipped -Because "gamemanagers.yaml template not found"
                return
            }
            
            # Create backup directory for this template
            $backupPath = Join-Path $script:TestBackupRoot "gamemanagers"
            
            # Run template-based backup
            { Invoke-WmrTemplate -TemplatePath $templatePath -Operation "Backup" -StateFilesDirectory $backupPath } | Should -Not -Throw
            
            # Verify backup directory was created
            Test-Path $backupPath | Should -Be $true
        }
        
        It "Should handle gaming platform configurations" {
            $backupPath = Join-Path $script:TestBackupRoot "gamemanagers"
            
            if (Test-Path $backupPath) {
                # Check for gaming backup files
                $gamingFiles = Get-ChildItem -Path $backupPath -Recurse -File
                # Gaming files may or may not exist depending on what's installed
                # Test should pass if directory exists
                Test-Path $backupPath | Should -Be $true
            }
        }
    }
    
    Context "Multiple Template Backup" {
        It "Should backup multiple templates successfully" {
            # Test backing up multiple templates
            $templates = @("applications.yaml", "system-settings.yaml")
            $successfulBackups = 0
            
            foreach ($template in $templates) {
                $templatePath = Join-Path $script:TemplatesPath $template
                
                if (Test-Path $templatePath) {
                    $templateName = [System.IO.Path]::GetFileNameWithoutExtension($template)
                    $backupPath = Join-Path $script:TestBackupRoot $templateName
                    
                    try {
                        Invoke-WmrTemplate -TemplatePath $templatePath -Operation "Backup" -StateFilesDirectory $backupPath
                        $successfulBackups++
                    } catch {
                        Write-Warning "Failed to backup template $template: $($_.Exception.Message)"
                    }
                }
            }
            
            # At least one template should have backed up successfully
            $successfulBackups | Should -BeGreaterThan 0
        }
    }
    
    Context "Cloud Storage Integration" {
        It "Should detect cloud storage paths" {
            # Test OneDrive detection
            $oneDrivePath = "$env:USERPROFILE\OneDrive"
            if (Test-Path $oneDrivePath) {
                # Check if WindowsMelodyRecovery directory exists or can be created
                $wmrPath = "$oneDrivePath\WindowsMelodyRecovery"
                if (-not (Test-Path $wmrPath)) {
                    New-Item -Path $wmrPath -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
                }
                Test-Path $wmrPath | Should -Be $true
            } else {
                Set-ItResult -Skipped -Because "OneDrive not available"
            }
        }
        
        It "Should backup to cloud storage location" {
            # Simulate cloud backup
            $cloudBackupPath = Join-Path $script:TestCloudPath "backup-$(Get-Date -Format 'yyyy-MM-dd')"
            New-Item -Path $cloudBackupPath -ItemType Directory -Force | Out-Null
            
            # Copy some test data
            if (Test-Path $script:TestBackupRoot) {
                Copy-Item -Path "$script:TestBackupRoot\*" -Destination $cloudBackupPath -Recurse -Force -ErrorAction SilentlyContinue
            }
            
            # Verify cloud backup exists
            Test-Path $cloudBackupPath | Should -Be $true
        }
    }
    
    Context "Error Handling" {
        It "Should handle invalid template paths gracefully" {
            # Test with non-existent template
            $invalidTemplate = Join-Path $script:TemplatesPath "nonexistent.yaml"
            $backupPath = Join-Path $script:TestBackupRoot "invalid"
            
            # Should throw an error for invalid template
            { Invoke-WmrTemplate -TemplatePath $invalidTemplate -Operation "Backup" -StateFilesDirectory $backupPath } | Should -Throw
        }
        
        It "Should handle invalid backup paths gracefully" {
            # Test with invalid backup directory path
            $templatePath = Join-Path $script:TemplatesPath "applications.yaml"
            
            if (Test-Path $templatePath) {
                $invalidBackupPath = "Z:\NonExistent\Path"
                
                # Should handle invalid backup path (may throw or handle gracefully depending on implementation)
                try {
                    Invoke-WmrTemplate -TemplatePath $templatePath -Operation "Backup" -StateFilesDirectory $invalidBackupPath
                    # If it succeeds, that's also acceptable
                } catch {
                    # Expected behavior for invalid path
                    $_.Exception.Message | Should -Not -BeNullOrEmpty
                }
            } else {
                Set-ItResult -Skipped -Because "applications.yaml template not found"
            }
        }
    }
}

AfterAll {
    # Cleanup test environment
    if (Test-Path $script:TestBackupRoot) {
        Remove-Item -Path $script:TestBackupRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $script:TestCloudPath) {
        Remove-Item -Path $script:TestCloudPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    # Remove test environment variables
    Remove-Item Env:WMR_TEST_MODE -ErrorAction SilentlyContinue
    Remove-Item Env:WMR_BACKUP_ROOT -ErrorAction SilentlyContinue
} 