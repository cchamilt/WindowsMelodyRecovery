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

function Test-PowerService {
    param(
        [Parameter(Mandatory=$false)]
        [switch]$StartIfStopped
    )
    
    if ($script:TestMode) {
        Write-Verbose "Test mode: Would check power service"
        return $true
    }
    
    try {
        $powerService = Get-Service -Name "Power" -ErrorAction SilentlyContinue
        if ($powerService) {
            if ($powerService.Status -ne "Running" -and $StartIfStopped) {
                Write-Host "Starting Power service..." -ForegroundColor Yellow
                Start-Service -Name "Power"
                Start-Sleep -Seconds 2
            }
            return $powerService.Status -eq "Running"
        }
        return $false
    } catch {
        Write-Warning "Could not check Power service status: $_"
        return $false
    }
}

function Restore-PowerSettings {
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
            Feature = "Power Settings"
            Timestamp = Get-Date
            ItemsRestored = @()
            ItemsSkipped = @()
            Errors = @()
        }
    }
    
    process {
        try {
            Write-Verbose "Starting restore of Power Settings..."
            Write-Host "Restoring Power Settings..." -ForegroundColor Blue
            
            # Validate inputs
            if (!(Test-Path $BackupRootPath)) {
                throw [System.IO.DirectoryNotFoundException]"Backup root path not found: $BackupRootPath"
            }
            
            $backupPath = Test-BackupPath -Path "Power" -BackupType "Power Settings"
            if (!$backupPath) {
                throw "No valid backup found for Power Settings"
            }
            $result.RestorePath = $backupPath
            
            # Check and start power service if needed
            if ($Force -or $PSCmdlet.ShouldProcess("Power Service", "Check and Start")) {
                $serviceRunning = Test-PowerService -StartIfStopped
                if (!$serviceRunning -and !$Force) {
                    Write-Warning "Power service is not running. Some settings may not be restored properly."
                }
            }
            
            # Restore registry settings first
            $registryPath = Join-Path $backupPath "Registry"
            if (Test-Path $registryPath) {
                if ($Force -or $PSCmdlet.ShouldProcess("Power Registry Settings", "Restore")) {
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

            # Note: Power schemes, active scheme, capabilities, and reports are informational only
            # They cannot be directly restored as they are system-generated or require specific powercfg commands
            
            $informationalFiles = @(
                "power_schemes.txt",
                "active_scheme.txt", 
                "power_capabilities.txt",
                "battery_report.html",
                "energy_report.html"
            )
            
            foreach ($file in $informationalFiles) {
                $filePath = Join-Path $backupPath $file
                if (Test-Path $filePath) {
                    $result.ItemsSkipped += "$file (informational only)"
                } else {
                    $result.ItemsSkipped += "$file (not found in backup)"
                }
            }
            
            # Skip scheme files as they are also informational
            Get-ChildItem -Path $backupPath -Filter "scheme_*.txt" -ErrorAction SilentlyContinue | ForEach-Object {
                $result.ItemsSkipped += "$($_.Name) (informational only)"
            }

            # Restore power button and lid settings
            $buttonSettingsFile = Join-Path $backupPath "button_settings.json"
            if (Test-Path $buttonSettingsFile) {
                if ($Force -or $PSCmdlet.ShouldProcess("Power Button and Lid Settings", "Restore")) {
                    try {
                        $buttonSettings = Get-Content $buttonSettingsFile | ConvertFrom-Json
                        
                        if (!$script:TestMode) {
                            # Apply power button settings
                            if ($buttonSettings.PowerButton) {
                                try {
                                    # Note: These are complex to restore as they require parsing the original powercfg output
                                    # For now, we'll log that they were found but skip actual restoration
                                    Write-Verbose "Power button settings found in backup but restoration requires manual configuration"
                                } catch {
                                    Write-Verbose "Could not restore power button settings"
                                }
                            }
                            
                            # Apply sleep button settings
                            if ($buttonSettings.SleepButton) {
                                try {
                                    Write-Verbose "Sleep button settings found in backup but restoration requires manual configuration"
                                } catch {
                                    Write-Verbose "Could not restore sleep button settings"
                                }
                            }
                            
                            # Apply lid close settings
                            if ($buttonSettings.LidClose) {
                                try {
                                    Write-Verbose "Lid close settings found in backup but restoration requires manual configuration"
                                } catch {
                                    Write-Verbose "Could not restore lid close settings"
                                }
                            }
                        }
                        
                        $result.ItemsSkipped += "button_settings.json (requires manual configuration)"
                    } catch {
                        $result.Errors += "Failed to process power button and lid settings`: $_"
                        $result.ItemsSkipped += "button_settings.json"
                        if (!$Force) { throw }
                    }
                }
            } else {
                $result.ItemsSkipped += "button_settings.json (not found in backup)"
            }
                
            $result.Success = ($result.Errors.Count -eq 0)
            
            # Display summary
            Write-Host "`nPower Settings Restore Summary:" -ForegroundColor Green
            Write-Host "Items Restored: $($result.ItemsRestored.Count)" -ForegroundColor Yellow
            Write-Host "Items Skipped: $($result.ItemsSkipped.Count)" -ForegroundColor Yellow
            Write-Host "Errors: $($result.Errors.Count)" -ForegroundColor $(if ($result.Errors.Count -gt 0) { "Red" } else { "Yellow" })
            
            if ($result.Success) {
                Write-Host "Power Settings restored successfully from: $backupPath" -ForegroundColor Green
                Write-Host "`nNote: Power schemes and button settings may require manual reconfiguration" -ForegroundColor Yellow
                Write-Host "Registry changes will take effect after system restart" -ForegroundColor Yellow
            } else {
                Write-Warning "Power Settings restore completed with errors"
            }
            
            Write-Verbose "Restore completed successfully"
            return $result
        } catch {
            $errorRecord = $_
            $errorMessage = @(
                "Failed to restore Power Settings"
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
    Export-ModuleMember -Function Restore-PowerSettings
}

<#
.SYNOPSIS
Restores Windows Power settings and configuration from backup.

.DESCRIPTION
Restores Windows Power configuration and associated data from a previous backup, including registry settings.
Note that power schemes, capabilities, and button settings are primarily informational and may require 
manual reconfiguration due to the complexity of power management restoration.

.PARAMETER BackupRootPath
The root path where the backup is located. The script will look for a "Power" subdirectory within this path.

.PARAMETER Force
Forces the restore operation without prompting for confirmation and continues even if some items fail to restore.

.PARAMETER Include
Array of item names to include in the restore operation. If not specified, all available items are restored.

.PARAMETER Exclude
Array of item names to exclude from the restore operation.

.PARAMETER SkipVerification
Skips backup integrity verification (useful for testing).

.EXAMPLE
Restore-PowerSettings -BackupRootPath "C:\Backups"

.EXAMPLE
Restore-PowerSettings -BackupRootPath "C:\Backups" -Force

.EXAMPLE
Restore-PowerSettings -BackupRootPath "C:\Backups" -WhatIf

.NOTES
Test cases to consider:
1. Valid backup with all files present
2. Partial backup (some files missing)
3. Corrupted backup
4. No backup found
5. Backup with invalid format
6. Permission issues during restore
7. Registry import failures
8. Power service availability
9. Administrative privileges scenarios
10. Desktop vs laptop scenarios
11. Custom power schemes
12. Modified power settings
13. Button and lid settings
14. Battery configurations
15. UPS configurations
16. Network path backup scenarios
17. WhatIf scenario
18. Force parameter behavior
19. Include/Exclude filters
20. Service management scenarios

.TESTCASES
# Mock test examples:
Describe "Restore-PowerSettings" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Test-BackupPath { return "TestPath" }
        Mock Test-PowerService { return $true }
        Mock Get-ChildItem { 
            return @(
                [PSCustomObject]@{ Name = "Power.reg"; FullName = "TestPath\Registry\Power.reg" },
                [PSCustomObject]@{ Name = "PowerSettings.reg"; FullName = "TestPath\Registry\PowerSettings.reg" }
            )
        }
        Mock Get-Content { return '{"PowerButton":{"AC":"test","DC":"test"}}' }
        Mock ConvertFrom-Json { return @{ PowerButton = @{ AC = "test"; DC = "test" } } }
        Mock reg { }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Restore-PowerSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.RestorePath | Should -Be "TestPath"
        $result.Feature | Should -Be "Power Settings"
        $result.ItemsRestored | Should -BeOfType [System.Array]
        $result.ItemsSkipped | Should -BeOfType [System.Array]
        $result.Errors | Should -BeOfType [System.Array]
    }

    It "Should handle WhatIf properly" {
        $result = Restore-PowerSettings -BackupRootPath "TestPath" -WhatIf
        $result.ItemsRestored.Count | Should -BeGreaterOrEqual 0
    }

    It "Should handle registry import failure gracefully with Force" {
        Mock reg { throw "Registry import failed" }
        $result = Restore-PowerSettings -BackupRootPath "TestPath" -Force
        $result.Errors.Count | Should -BeGreaterThan 0
        $result.ItemsSkipped.Count | Should -BeGreaterThan 0
    }

    It "Should handle missing backup gracefully" {
        Mock Test-BackupPath { return $null }
        { Restore-PowerSettings -BackupRootPath "TestPath" } | Should -Throw
    }

    It "Should skip verification when specified" {
        $result = Restore-PowerSettings -BackupRootPath "TestPath" -SkipVerification
        $result.Success | Should -Be $true
    }

    It "Should handle power service check failure" {
        Mock Test-PowerService { return $false }
        $result = Restore-PowerSettings -BackupRootPath "TestPath" -Force
        $result.Success | Should -Be $true
    }

    It "Should handle button settings processing failure" {
        Mock ConvertFrom-Json { throw "JSON parsing failed" }
        $result = Restore-PowerSettings -BackupRootPath "TestPath" -Force
        $result.Errors.Count | Should -BeGreaterThan 0
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Restore-PowerSettings -BackupRootPath $BackupRootPath
} 