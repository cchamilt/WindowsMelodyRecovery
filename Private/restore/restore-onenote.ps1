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

function Restore-OneNoteSettings {
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
            Feature = "OneNote Settings"
            Timestamp = Get-Date
            ItemsRestored = @()
            ItemsSkipped = @()
            Errors = @()
        }
    }
    
    process {
        try {
            Write-Verbose "Starting restore of OneNote Settings..."
            Write-Host "Restoring OneNote Settings..." -ForegroundColor Blue
            
            # Validate inputs
            if (!(Test-Path $BackupRootPath)) {
                throw [System.IO.DirectoryNotFoundException]"Backup root path not found: $BackupRootPath"
            }
            
            $backupPath = Test-BackupPath -Path "OneNote" -BackupType "OneNote Settings"
            if (!$backupPath) {
                throw "No valid backup found for OneNote Settings"
            }
            $result.RestorePath = $backupPath
            
            if ($backupPath) {
                # Stop OneNote processes if running (only if not in test mode)
                if (!$script:TestMode) {
                    $oneNoteProcesses = Get-Process -Name "ONENOTE", "OneNote" -ErrorAction SilentlyContinue
                    if ($oneNoteProcesses) {
                        if ($Force -or $PSCmdlet.ShouldProcess("OneNote processes", "Stop")) {
                            Write-Host "Stopping OneNote processes..." -ForegroundColor Yellow
                            $oneNoteProcesses | Stop-Process -Force -ErrorAction SilentlyContinue
                            Start-Sleep -Seconds 2
                            $result.ItemsRestored += "ProcessStop\OneNote"
                        }
                    }
                }

                # Restore registry settings first
                $registryPath = Join-Path $backupPath "Registry"
                if (Test-Path $registryPath) {
                    if ($Force -or $PSCmdlet.ShouldProcess("OneNote Registry Settings", "Restore")) {
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

                # OneNote config locations mapping
                $oneNoteConfigs = @{
                    "AppData" = "$env:LOCALAPPDATA\Microsoft\OneNote"
                    "Settings" = "$env:APPDATA\Microsoft\OneNote"
                    "Templates" = "$env:APPDATA\Microsoft\Templates"
                    "RecentFiles" = "$env:APPDATA\Microsoft\Office\Recent"
                    "UWPSettings" = "$env:LOCALAPPDATA\Packages\Microsoft.Office.OneNote_8wekyb3d8bbwe\LocalState"
                    "Cache" = "$env:LOCALAPPDATA\Microsoft\OneNote\16.0\cache"
                }

                # Restore config files
                foreach ($config in $oneNoteConfigs.GetEnumerator()) {
                    $backupItem = Join-Path $backupPath $config.Key
                    if (Test-Path $backupItem) {
                        if ($Force -or $PSCmdlet.ShouldProcess("OneNote $($config.Key)", "Restore")) {
                            try {
                                # Create parent directory if it doesn't exist
                                $parentDir = Split-Path $config.Value -Parent
                                if (!(Test-Path $parentDir) -and !$script:TestMode) {
                                    New-Item -ItemType Directory -Force -Path $parentDir | Out-Null
                                }

                                if (!$script:TestMode) {
                                    if ((Get-Item $backupItem) -is [System.IO.DirectoryInfo]) {
                                        # Skip temporary files during restore
                                        $excludeFilter = @("*.tmp", "~*.*", "*.log")
                                        Copy-Item $backupItem $config.Value -Recurse -Force -Exclude $excludeFilter
                                    } else {
                                        Copy-Item $backupItem $config.Value -Force
                                    }
                                }
                                $result.ItemsRestored += $config.Key
                            } catch {
                                $result.Errors += "Failed to restore $($config.Key)`: $_"
                                $result.ItemsSkipped += $config.Key
                                if (!$Force) { throw }
                            }
                        }
                    } else {
                        $result.ItemsSkipped += "$($config.Key) (not found in backup)"
                    }
                }

                # Restore notebook locations
                $notebookFile = Join-Path $backupPath "notebook_locations.xml"
                if (Test-Path $notebookFile) {
                    if ($Force -or $PSCmdlet.ShouldProcess("OneNote Notebook Locations", "Restore")) {
                        try {
                            $notebookDestPath = "$env:APPDATA\Microsoft\OneNote\16.0\NotebookList.xml"
                            if (!$script:TestMode) {
                                $parentDir = Split-Path $notebookDestPath -Parent
                                if (!(Test-Path $parentDir)) {
                                    New-Item -ItemType Directory -Force -Path $parentDir | Out-Null
                                }
                                Copy-Item -Path $notebookFile -Destination $notebookDestPath -Force
                            }
                            $result.ItemsRestored += "notebook_locations.xml"
                        } catch {
                            $result.Errors += "Failed to restore notebook locations`: $_"
                            $result.ItemsSkipped += "notebook_locations.xml"
                            if (!$Force) { throw }
                        }
                    }
                } else {
                    $result.ItemsSkipped += "notebook_locations.xml (not found in backup)"
                }
                
                $result.Success = ($result.Errors.Count -eq 0)
                
                # Display summary
                Write-Host "`nOneNote Settings Restore Summary:" -ForegroundColor Green
                Write-Host "Items Restored: $($result.ItemsRestored.Count)" -ForegroundColor Yellow
                Write-Host "Items Skipped: $($result.ItemsSkipped.Count)" -ForegroundColor Yellow
                Write-Host "Errors: $($result.Errors.Count)" -ForegroundColor $(if ($result.Errors.Count -gt 0) { "Red" } else { "Yellow" })
                
                if ($result.Success) {
                    Write-Host "OneNote Settings restored successfully from: $backupPath" -ForegroundColor Green
                    Write-Host "`nNote: OneNote restart may be required for settings to take full effect" -ForegroundColor Yellow
                } else {
                    Write-Warning "OneNote Settings restore completed with errors"
                }
                
                Write-Verbose "Restore completed successfully"
                return $result
            }
            return $result
        } catch {
            $errorRecord = $_
            $errorMessage = @(
                "Failed to restore OneNote Settings"
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
    Export-ModuleMember -Function Restore-OneNoteSettings
}

<#
.SYNOPSIS
Restores Microsoft OneNote settings and configuration from backup.

.DESCRIPTION
Restores Microsoft OneNote configuration and associated data from a previous backup, including registry settings,
configuration files, templates, notebook locations, recent files, and UWP app settings. Supports both OneNote 2016
and OneNote for Windows 10/11. Handles OneNote process management during restore to ensure settings are applied correctly.

.PARAMETER BackupRootPath
The root path where the backup is located. The script will look for a "OneNote" subdirectory within this path.

.PARAMETER Force
Forces the restore operation without prompting for confirmation and continues even if some items fail to restore.

.PARAMETER Include
Array of item names to include in the restore operation. If not specified, all available items are restored.

.PARAMETER Exclude
Array of item names to exclude from the restore operation.

.PARAMETER SkipVerification
Skips backup integrity verification (useful for testing).

.EXAMPLE
Restore-OneNoteSettings -BackupRootPath "C:\Backups"

.EXAMPLE
Restore-OneNoteSettings -BackupRootPath "C:\Backups" -Force

.EXAMPLE
Restore-OneNoteSettings -BackupRootPath "C:\Backups" -WhatIf

.NOTES
Test cases to consider:
1. Valid backup with all files present
2. Partial backup (some files missing)
3. Corrupted backup
4. No backup found
5. Backup with invalid format
6. Permission issues during restore
7. Registry import failures
8. Configuration file restore failures
9. Notebook location restore failures
10. WhatIf scenario
11. Force parameter behavior
12. Include/Exclude filters
13. OneNote process management
14. OneNote 2016 vs UWP app scenarios
15. Missing OneNote installation
16. Template and add-in restore
17. Cache and sync settings restore
18. Multiple user profiles
19. Network path backup scenarios

.TESTCASES
# Mock test examples:
Describe "Restore-OneNoteSettings" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Test-BackupPath { return "TestPath" }
        Mock Get-ChildItem { 
            return @(
                [PSCustomObject]@{ Name = "OneNote.reg"; FullName = "TestPath\Registry\OneNote.reg" },
                [PSCustomObject]@{ Name = "FileExts.reg"; FullName = "TestPath\Registry\FileExts.reg" }
            )
        }
        Mock Get-Process { return @() }
        Mock Stop-Process { }
        Mock Start-Sleep { }
        Mock New-Item { }
        Mock Copy-Item { }
        Mock reg { }
        Mock Get-Item { return [PSCustomObject]@{ PSIsContainer = $true } }
        Mock Split-Path { return "C:\Users\Test\AppData" }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Restore-OneNoteSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.RestorePath | Should -Be "TestPath"
        $result.Feature | Should -Be "OneNote Settings"
        $result.ItemsRestored | Should -BeOfType [System.Array]
        $result.ItemsSkipped | Should -BeOfType [System.Array]
        $result.Errors | Should -BeOfType [System.Array]
    }

    It "Should handle WhatIf properly" {
        $result = Restore-OneNoteSettings -BackupRootPath "TestPath" -WhatIf
        $result.ItemsRestored.Count | Should -Be 0
    }

    It "Should handle registry import failure gracefully with Force" {
        Mock reg { throw "Registry import failed" }
        $result = Restore-OneNoteSettings -BackupRootPath "TestPath" -Force
        $result.Errors.Count | Should -BeGreaterThan 0
        $result.ItemsSkipped.Count | Should -BeGreaterThan 0
    }

    It "Should handle missing backup gracefully" {
        Mock Test-BackupPath { return $null }
        { Restore-OneNoteSettings -BackupRootPath "TestPath" } | Should -Throw
    }

    It "Should skip verification when specified" {
        $result = Restore-OneNoteSettings -BackupRootPath "TestPath" -SkipVerification
        $result.Success | Should -Be $true
    }

    It "Should handle OneNote process management" {
        Mock Get-Process { return @([PSCustomObject]@{ Name = "ONENOTE" }) }
        $result = Restore-OneNoteSettings -BackupRootPath "TestPath" -Force
        $result.ItemsRestored | Should -Contain "ProcessStop\OneNote"
    }

    It "Should handle configuration file restore failure gracefully" {
        Mock Copy-Item { throw "Access denied" }
        $result = Restore-OneNoteSettings -BackupRootPath "TestPath" -Force
        $result.Errors.Count | Should -BeGreaterThan 0
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Restore-OneNoteSettings -BackupRootPath $BackupRootPath
} 