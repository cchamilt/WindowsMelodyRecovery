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
$config = Get-WindowsMelodyRecovery
if (!$config.IsInitialized) {
    throw "Module not initialized. Please run Initialize-WindowsMelodyRecovery first."
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

function Test-PrintSpoolerService {
    param(
        [Parameter(Mandatory=$false)]
        [switch]$StartIfStopped
    )
    
    if ($script:TestMode) {
        Write-Verbose "Test mode: Would check print spooler service"
        return $true
    }
    
    try {
        $spoolerService = Get-Service -Name "Spooler" -ErrorAction SilentlyContinue
        if ($spoolerService) {
            if ($spoolerService.Status -ne "Running" -and $StartIfStopped) {
                Write-Host "Starting Print Spooler service..." -ForegroundColor Yellow
                Start-Service -Name "Spooler"
                Start-Sleep -Seconds 3
            }
            return $spoolerService.Status -eq "Running"
        }
        return $false
    } catch {
        Write-Warning "Could not check Print Spooler service status: $_"
        return $false
    }
}

function Restore-PrinterSettings {
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
            Feature = "Printer Settings"
            Timestamp = Get-Date
            ItemsRestored = @()
            ItemsSkipped = @()
            Errors = @()
        }
    }
    
    process {
        try {
            Write-Verbose "Starting restore of Printer Settings..."
            Write-Host "Restoring Printer Settings..." -ForegroundColor Blue
            
            # Validate inputs
            if (!(Test-Path $BackupRootPath)) {
                throw [System.IO.DirectoryNotFoundException]"Backup root path not found: $BackupRootPath"
            }
            
            $backupPath = Test-BackupPath -Path "Printer" -BackupType "Printer Settings"
            if (!$backupPath) {
                throw "No valid backup found for Printer Settings"
            }
            $result.RestorePath = $backupPath
            
            # Check and start print spooler service if needed
            if ($Force -or $PSCmdlet.ShouldProcess("Print Spooler Service", "Check and Start")) {
                $serviceRunning = Test-PrintSpoolerService -StartIfStopped
                if (!$serviceRunning -and !$Force) {
                    Write-Warning "Print Spooler service is not running. Printer restoration may not work properly."
                }
            }
            
            # Restore registry settings first
            $registryPath = Join-Path $backupPath "Registry"
            if (Test-Path $registryPath) {
                if ($Force -or $PSCmdlet.ShouldProcess("Printer Registry Settings", "Restore")) {
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

            # Note: Printer configurations, ports, drivers, and queues are informational only
            # They require specific printer management commands and driver installations
            
            $informationalFiles = @(
                "printers.json",
                "printer_ports.json", 
                "printer_drivers.json",
                "print_queues.json",
                "spooler_config.json"
            )
            
            foreach ($file in $informationalFiles) {
                $filePath = Join-Path $backupPath $file
                if (Test-Path $filePath) {
                    $result.ItemsSkipped += "$file (informational only - requires manual printer setup)"
                } else {
                    $result.ItemsSkipped += "$file (not found in backup)"
                }
            }

            # Restore printer preferences (default printer setting)
            $preferencesFile = Join-Path $backupPath "printer_preferences.json"
            if (Test-Path $preferencesFile) {
                if ($Force -or $PSCmdlet.ShouldProcess("Printer Preferences", "Restore")) {
                    try {
                        $preferences = Get-Content $preferencesFile | ConvertFrom-Json
                        
                        if (!$script:TestMode) {
                            # Restore default printer setting if the printer exists
                            if ($preferences.DefaultPrinter) {
                                try {
                                    $existingPrinter = Get-Printer -Name $preferences.DefaultPrinter -ErrorAction SilentlyContinue
                                    if ($existingPrinter) {
                                        # Set as default printer
                                        $existingPrinter | Set-Printer -Default
                                        Write-Verbose "Set default printer to: $($preferences.DefaultPrinter)"
                                    } else {
                                        Write-Verbose "Default printer '$($preferences.DefaultPrinter)' not found - skipping"
                                    }
                                } catch {
                                    Write-Verbose "Could not set default printer: $_"
                                }
                            }
                            
                            # Restore device setting in registry
                            if ($preferences.DeviceSetting) {
                                try {
                                    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Windows" -Name "Device" -Value $preferences.DeviceSetting -ErrorAction SilentlyContinue
                                    Write-Verbose "Restored device setting"
                                } catch {
                                    Write-Verbose "Could not restore device setting: $_"
                                }
                            }
                        }
                        
                        $result.ItemsRestored += "printer_preferences.json"
                    } catch {
                        $result.Errors += "Failed to restore printer preferences`: $_"
                        $result.ItemsSkipped += "printer_preferences.json"
                        if (!$Force) { throw }
                    }
                }
            } else {
                $result.ItemsSkipped += "printer_preferences.json (not found in backup)"
            }
                
            $result.Success = ($result.Errors.Count -eq 0)
            
            # Display summary
            Write-Host "`nPrinter Settings Restore Summary:" -ForegroundColor Green
            Write-Host "Items Restored: $($result.ItemsRestored.Count)" -ForegroundColor Yellow
            Write-Host "Items Skipped: $($result.ItemsSkipped.Count)" -ForegroundColor Yellow
            Write-Host "Errors: $($result.Errors.Count)" -ForegroundColor $(if ($result.Errors.Count -gt 0) { "Red" } else { "Yellow" })
            
            if ($result.Success) {
                Write-Host "Printer Settings restored successfully from: $backupPath" -ForegroundColor Green
                Write-Host "`nNote: Printers, drivers, and ports require manual reinstallation" -ForegroundColor Yellow
                Write-Host "Registry changes will take effect after Print Spooler service restart" -ForegroundColor Yellow
            } else {
                Write-Warning "Printer Settings restore completed with errors"
            }
            
            Write-Verbose "Restore completed successfully"
            return $result
        } catch {
            $errorRecord = $_
            $errorMessage = @(
                "Failed to restore Printer Settings"
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
    Export-ModuleMember -Function Restore-PrinterSettings
}

<#
.SYNOPSIS
Restores Windows Printer settings and configuration from backup.

.DESCRIPTION
Restores Windows Printer configuration and associated data from a previous backup, including registry settings
and printer preferences. Note that printers, drivers, ports, and queues are primarily informational and require 
manual reinstallation due to the complexity of printer driver management and hardware dependencies.

.PARAMETER BackupRootPath
The root path where the backup is located. The script will look for a "Printer" subdirectory within this path.

.PARAMETER Force
Forces the restore operation without prompting for confirmation and continues even if some items fail to restore.

.PARAMETER Include
Array of item names to include in the restore operation. If not specified, all available items are restored.

.PARAMETER Exclude
Array of item names to exclude from the restore operation.

.PARAMETER SkipVerification
Skips backup integrity verification (useful for testing).

.EXAMPLE
Restore-PrinterSettings -BackupRootPath "C:\Backups"

.EXAMPLE
Restore-PrinterSettings -BackupRootPath "C:\Backups" -Force

.EXAMPLE
Restore-PrinterSettings -BackupRootPath "C:\Backups" -WhatIf

.NOTES
Test cases to consider:
1. Valid backup with all files present
2. Partial backup (some files missing)
3. Corrupted backup
4. No backup found
5. Backup with invalid format
6. Permission issues during restore
7. Registry import failures
8. Print Spooler service availability
9. Administrative privileges scenarios
10. No printers installed scenario
11. Network printers scenario
12. Local printers scenario
13. Mixed printer types scenario
14. Print spooler service stopped
15. Driver installation requirements
16. Network connectivity issues
17. Default printer restoration
18. Printer preferences restoration
19. WhatIf scenario
20. Force parameter behavior
21. Include/Exclude filters
22. Service management scenarios

.TESTCASES
# Mock test examples:
Describe "Restore-PrinterSettings" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Test-BackupPath { return "TestPath" }
        Mock Test-PrintSpoolerService { return $true }
        Mock Get-ChildItem { 
            return @(
                [PSCustomObject]@{ Name = "Printers.reg"; FullName = "TestPath\Registry\Printers.reg" },
                [PSCustomObject]@{ Name = "Monitors.reg"; FullName = "TestPath\Registry\Monitors.reg" }
            )
        }
        Mock Get-Content { return '{"DefaultPrinter":"Test Printer","DeviceSetting":"Test Printer,winspool,Test Port"}' }
        Mock ConvertFrom-Json { return @{ DefaultPrinter = "Test Printer"; DeviceSetting = "Test Printer,winspool,Test Port" } }
        Mock Get-Printer { return @{
            Name = "Test Printer"
            IsDefault = $false
        }}
        Mock Set-Printer { }
        Mock Set-ItemProperty { }
        Mock reg { }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Restore-PrinterSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.RestorePath | Should -Be "TestPath"
        $result.Feature | Should -Be "Printer Settings"
        $result.ItemsRestored | Should -BeOfType [System.Array]
        $result.ItemsSkipped | Should -BeOfType [System.Array]
        $result.Errors | Should -BeOfType [System.Array]
    }

    It "Should handle WhatIf properly" {
        $result = Restore-PrinterSettings -BackupRootPath "TestPath" -WhatIf
        $result.ItemsRestored.Count | Should -BeGreaterOrEqual 0
    }

    It "Should handle registry import failure gracefully with Force" {
        Mock reg { throw "Registry import failed" }
        $result = Restore-PrinterSettings -BackupRootPath "TestPath" -Force
        $result.Errors.Count | Should -BeGreaterThan 0
        $result.ItemsSkipped.Count | Should -BeGreaterThan 0
    }

    It "Should handle missing backup gracefully" {
        Mock Test-BackupPath { return $null }
        { Restore-PrinterSettings -BackupRootPath "TestPath" } | Should -Throw
    }

    It "Should skip verification when specified" {
        $result = Restore-PrinterSettings -BackupRootPath "TestPath" -SkipVerification
        $result.Success | Should -Be $true
    }

    It "Should handle print spooler service check failure" {
        Mock Test-PrintSpoolerService { return $false }
        $result = Restore-PrinterSettings -BackupRootPath "TestPath" -Force
        $result.Success | Should -Be $true
    }

    It "Should handle printer preferences processing failure" {
        Mock ConvertFrom-Json { throw "JSON parsing failed" }
        $result = Restore-PrinterSettings -BackupRootPath "TestPath" -Force
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle missing default printer gracefully" {
        Mock Get-Printer { return $null }
        $result = Restore-PrinterSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Restore-PrinterSettings -BackupRootPath $BackupRootPath
} 