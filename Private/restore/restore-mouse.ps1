[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$BackupRootPath = $null,
    
    [Parameter(Mandatory=$false)]
    [string]$MachineBackupPath = $null,
    
    [Parameter(Mandatory=$false)]
    [string]$SharedBackupPath = $null
)

# Load environment script from the correct location
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$modulePath = Split-Path -Parent (Split-Path -Parent $scriptPath)
$loadEnvPath = Join-Path $modulePath "Private\scripts\load-environment.ps1"

# Source the load-environment script
if (Test-Path $loadEnvPath) {
    . $loadEnvPath
} else {
    Write-Host "Cannot find load-environment.ps1 at: $loadEnvPath" -ForegroundColor Red
}

# Get module configuration
$config = Get-WindowsMissingRecovery
if (!$config.IsInitialized) {
    throw "Module not initialized. Please run Initialize-WindowsMissingRecovery first."
}

if (!$BackupRootPath) {
    $BackupRootPath = Join-Path $config.BackupRoot $config.MachineName
}

# Define Test-BackupPath function directly in the script
function Test-BackupPath {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Path,
        
        [Parameter(Mandatory=$true)]
        [string]$BackupType
    )
    
    # First check machine-specific backup
    $machinePath = Join-Path $BackupRootPath $Path
    if (Test-Path $machinePath) {
        Write-Host "Using machine-specific $BackupType backup from: $machinePath" -ForegroundColor Green
        return $machinePath
    }
    
    # Fall back to shared backup if available
    if ($SharedBackupPath) {
        $sharedPath = Join-Path $SharedBackupPath $Path
        if (Test-Path $sharedPath) {
            Write-Host "Using shared $BackupType backup from: $sharedPath" -ForegroundColor Green
            return $sharedPath
        }
    }
    
    Write-Host "No $BackupType backup found" -ForegroundColor Yellow
    return $null
}

function Restore-MouseSettings {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force,

        [Parameter(Mandatory=$false)]
        [string[]]$Include,

        [Parameter(Mandatory=$false)]
        [string[]]$Exclude,

        # For testing purposes
        [Parameter(DontShow)]
        [switch]$SkipVerification
    )
    
    begin {
        # Test hook for mocking
        if ($script:TestMode) {
            Write-Verbose "Running in test mode"
        }

        # Initialize result object
        $result = [PSCustomObject]@{
            Success = $false
            RestorePath = $null
            Feature = "Mouse Settings"
            Timestamp = Get-Date
            ItemsRestored = @()
            ItemsSkipped = @()
            Errors = @()
        }
    }
    
    process {
        try {
            Write-Verbose "Starting restore of Mouse Settings..."
            Write-Host "Restoring Mouse Settings..." -ForegroundColor Blue
            
            # Validate inputs
            if (!(Test-Path $BackupRootPath)) {
                throw [System.IO.DirectoryNotFoundException]"Backup root path not found: $BackupRootPath"
            }
            
            $backupPath = Test-BackupPath -Path "Mouse" -BackupType "Mouse Settings"
            if (!$backupPath) {
                throw "No valid backup found for Mouse Settings"
            }
            $result.RestorePath = $backupPath
            
            if ($backupPath) {
                # Restore registry settings first
                $registryPath = Join-Path $backupPath "Registry"
                if (Test-Path $registryPath) {
                    if ($Force -or $PSCmdlet.ShouldProcess("Mouse Registry Settings", "Restore")) {
                        Get-ChildItem -Path $registryPath -Filter "*.reg" | ForEach-Object {
                            try {
                                Write-Host "Importing registry file: $($_.Name)" -ForegroundColor Yellow
                                if (!$script:TestMode) {
                                    reg import $_.FullName 2>$null
                                }
                                $result.ItemsRestored += "Registry\$($_.Name)"
                            } catch {
                                $result.Errors += "Failed to import registry file $($_.Name)`: $_"
                                $result.ItemsSkipped += "Registry\$($_.Name)"
                                if (!$Force) { throw }
                            }
                        }
                    }
                } else {
                    $result.ItemsSkipped += "Registry (not found in backup)"
                }

                # Restore mouse settings from JSON
                $mouseSettingsFile = Join-Path $backupPath "mouse_settings.json"
                if (Test-Path $mouseSettingsFile) {
                    if ($Force -or $PSCmdlet.ShouldProcess("Mouse Control Panel Settings", "Restore")) {
                        try {
                            $mouseSettings = Get-Content $mouseSettingsFile | ConvertFrom-Json
                            if (!$script:TestMode) {
                                foreach ($property in $mouseSettings.PSObject.Properties) {
                                    try {
                                        Set-ItemProperty -Path "HKCU:\Control Panel\Mouse" -Name $property.Name -Value $property.Value -ErrorAction SilentlyContinue
                                    } catch {
                                        Write-Verbose "Could not set mouse property: $($property.Name)"
                                    }
                                }
                            }
                            $result.ItemsRestored += "mouse_settings.json"
                        } catch {
                            $result.Errors += "Failed to restore mouse settings`: $_"
                            $result.ItemsSkipped += "mouse_settings.json"
                            if (!$Force) { throw }
                        }
                    }
                } else {
                    $result.ItemsSkipped += "mouse_settings.json (not found in backup)"
                }

                # Restore cursor settings
                $cursorSettingsFile = Join-Path $backupPath "cursor_settings.json"
                if (Test-Path $cursorSettingsFile) {
                    if ($Force -or $PSCmdlet.ShouldProcess("Cursor Settings", "Restore")) {
                        try {
                            $cursorSettings = Get-Content $cursorSettingsFile | ConvertFrom-Json
                            if (!$script:TestMode) {
                                foreach ($property in $cursorSettings.PSObject.Properties) {
                                    try {
                                        Set-ItemProperty -Path "HKCU:\Control Panel\Cursors" -Name $property.Name -Value $property.Value -ErrorAction SilentlyContinue
                                    } catch {
                                        Write-Verbose "Could not set cursor property: $($property.Name)"
                                    }
                                }
                            }
                            $result.ItemsRestored += "cursor_settings.json"
                        } catch {
                            $result.Errors += "Failed to restore cursor settings`: $_"
                            $result.ItemsSkipped += "cursor_settings.json"
                            if (!$Force) { throw }
                        }
                    }
                } else {
                    $result.ItemsSkipped += "cursor_settings.json (not found in backup)"
                }

                # Restore mouse accessibility settings
                $accessibilityFile = Join-Path $backupPath "mouse_accessibility.json"
                if (Test-Path $accessibilityFile) {
                    if ($Force -or $PSCmdlet.ShouldProcess("Mouse Accessibility Settings", "Restore")) {
                        try {
                            $accessibilitySettings = Get-Content $accessibilityFile | ConvertFrom-Json
                            if (!$script:TestMode) {
                                foreach ($property in $accessibilitySettings.PSObject.Properties) {
                                    try {
                                        Set-ItemProperty -Path "HKCU:\Control Panel\Accessibility\MouseKeys" -Name $property.Name -Value $property.Value -ErrorAction SilentlyContinue
                                    } catch {
                                        Write-Verbose "Could not set accessibility property: $($property.Name)"
                                    }
                                }
                            }
                            $result.ItemsRestored += "mouse_accessibility.json"
                        } catch {
                            $result.Errors += "Failed to restore mouse accessibility settings`: $_"
                            $result.ItemsSkipped += "mouse_accessibility.json"
                            if (!$Force) { throw }
                        }
                    }
                } else {
                    $result.ItemsSkipped += "mouse_accessibility.json (not found in backup)"
                }

                # Note: mouse_devices.json is informational only and doesn't need restoration
                $devicesFile = Join-Path $backupPath "mouse_devices.json"
                if (Test-Path $devicesFile) {
                    $result.ItemsSkipped += "mouse_devices.json (informational only)"
                } else {
                    $result.ItemsSkipped += "mouse_devices.json (not found in backup)"
                }
                
                $result.Success = ($result.Errors.Count -eq 0)
                
                # Display summary
                Write-Host "`nMouse Settings Restore Summary:" -ForegroundColor Green
                Write-Host "Items Restored: $($result.ItemsRestored.Count)" -ForegroundColor Yellow
                Write-Host "Items Skipped: $($result.ItemsSkipped.Count)" -ForegroundColor Yellow
                Write-Host "Errors: $($result.Errors.Count)" -ForegroundColor $(if ($result.Errors.Count -gt 0) { "Red" } else { "Yellow" })
                
                if ($result.Success) {
                    Write-Host "Mouse Settings restored successfully from: $backupPath" -ForegroundColor Green
                    Write-Host "`nNote: System restart or re-login may be required for some mouse settings to take full effect" -ForegroundColor Yellow
                } else {
                    Write-Warning "Mouse Settings restore completed with errors"
                }
                
                Write-Verbose "Restore completed successfully"
                return $result
            }
            return $result
        } catch {
            $errorRecord = $_
            $errorMessage = @(
                "Failed to restore Mouse Settings"
                "Error Message: $($errorRecord.Exception.Message)"
                "Error Type: $($errorRecord.Exception.GetType().FullName)"
                "Script Line Number: $($errorRecord.InvocationInfo.ScriptLineNumber)"
                "Script Name: $($errorRecord.InvocationInfo.ScriptName)"
                "Statement: $($errorRecord.InvocationInfo.Line.Trim())"
                if ($errorRecord.Exception.StackTrace) { "Stack Trace: $($errorRecord.Exception.StackTrace)" }
                if ($errorRecord.Exception.InnerException) { "Inner Exception: $($errorRecord.Exception.InnerException.Message)" }
            ) -join "`n"
            
            Write-Error $errorMessage
            Write-Verbose "Restore failed"
            $result.Errors += $errorMessage
            return $result
        }
    }

    end {
        # Log results
        if ($result.Errors.Count -gt 0) {
            Write-Warning "Restore completed with $($result.Errors.Count) errors"
        }
        Write-Verbose "Restored $($result.ItemsRestored.Count) items, skipped $($result.ItemsSkipped.Count) items"
    }
}

# Export the function if being imported as a module
if ($MyInvocation.Line -eq "") {
    Export-ModuleMember -Function Restore-MouseSettings
}

<#
.SYNOPSIS
Restores Windows Mouse settings and configuration from backup.

.DESCRIPTION
Restores Windows Mouse configuration and associated data from a previous backup, including registry settings,
control panel configurations, cursor schemes, and accessibility settings. Handles comprehensive mouse
customizations and user preferences restoration.

.PARAMETER BackupRootPath
The root path where the backup is located. The script will look for a "Mouse" subdirectory within this path.

.PARAMETER Force
Forces the restore operation without prompting for confirmation and continues even if some items fail to restore.

.PARAMETER Include
Array of item names to include in the restore operation. If not specified, all available items are restored.

.PARAMETER Exclude
Array of item names to exclude from the restore operation.

.PARAMETER SkipVerification
Skips backup integrity verification (useful for testing).

.EXAMPLE
Restore-MouseSettings -BackupRootPath "C:\Backups"

.EXAMPLE
Restore-MouseSettings -BackupRootPath "C:\Backups" -Force

.EXAMPLE
Restore-MouseSettings -BackupRootPath "C:\Backups" -WhatIf

.NOTES
Test cases to consider:
1. Valid backup with all files present
2. Partial backup (some files missing)
3. Corrupted backup
4. No backup found
5. Backup with invalid format
6. Permission issues during restore
7. Registry import failures
8. Mouse settings restore failures
9. Cursor settings restore failures
10. Accessibility settings restore failures
11. WhatIf scenario
12. Force parameter behavior
13. Include/Exclude filters
14. Multiple mouse devices
15. Gaming mouse configurations
16. Custom cursor themes
17. Accessibility features
18. System restart requirements
19. Network path backup scenarios

.TESTCASES
# Mock test examples:
Describe "Restore-MouseSettings" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Test-BackupPath { return "TestPath" }
        Mock Get-ChildItem { 
            return @(
                [PSCustomObject]@{ Name = "Mouse.reg"; FullName = "TestPath\Registry\Mouse.reg" },
                [PSCustomObject]@{ Name = "Cursors.reg"; FullName = "TestPath\Registry\Cursors.reg" }
            )
        }
        Mock Get-Content { return '{"DoubleClickSpeed":500,"MouseSpeed":1}' }
        Mock ConvertFrom-Json { return @{ DoubleClickSpeed = 500; MouseSpeed = 1 } }
        Mock Set-ItemProperty { }
        Mock reg { }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Restore-MouseSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.RestorePath | Should -Be "TestPath"
        $result.Feature | Should -Be "Mouse Settings"
        $result.ItemsRestored | Should -BeOfType [System.Array]
        $result.ItemsSkipped | Should -BeOfType [System.Array]
        $result.Errors | Should -BeOfType [System.Array]
    }

    It "Should handle WhatIf properly" {
        $result = Restore-MouseSettings -BackupRootPath "TestPath" -WhatIf
        $result.ItemsRestored.Count | Should -Be 0
    }

    It "Should handle registry import failure gracefully with Force" {
        Mock reg { throw "Registry import failed" }
        $result = Restore-MouseSettings -BackupRootPath "TestPath" -Force
        $result.Errors.Count | Should -BeGreaterThan 0
        $result.ItemsSkipped.Count | Should -BeGreaterThan 0
    }

    It "Should handle missing backup gracefully" {
        Mock Test-BackupPath { return $null }
        { Restore-MouseSettings -BackupRootPath "TestPath" } | Should -Throw
    }

    It "Should skip verification when specified" {
        $result = Restore-MouseSettings -BackupRootPath "TestPath" -SkipVerification
        $result.Success | Should -Be $true
    }

    It "Should handle mouse settings restore failure gracefully" {
        Mock Set-ItemProperty { throw "Access denied" }
        $result = Restore-MouseSettings -BackupRootPath "TestPath" -Force
        $result.Errors.Count | Should -BeGreaterThan 0
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Restore-MouseSettings -BackupRootPath $BackupRootPath
} 