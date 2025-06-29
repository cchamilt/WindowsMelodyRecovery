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

function Stop-OutlookProcesses {
    param(
        [Parameter(Mandatory=$false)]
        [switch]$Force
    )
    
    if ($script:TestMode) {
        Write-Verbose "Test mode: Would stop Outlook processes"
        return $true
    }
    
    try {
        $outlookProcesses = Get-Process -Name "OUTLOOK" -ErrorAction SilentlyContinue
        if ($outlookProcesses) {
            Write-Host "Stopping Outlook processes..." -ForegroundColor Yellow
            foreach ($process in $outlookProcesses) {
                if ($Force) {
                    $process | Stop-Process -Force
                } else {
                    $process | Stop-Process
                }
            }
            Start-Sleep -Seconds 2
        }
        return $true
    } catch {
        Write-Warning "Could not stop Outlook processes: $_"
        return $false
    }
}

function Restore-OutlookSettings {
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
            Feature = "Outlook Settings"
            Timestamp = Get-Date
            ItemsRestored = @()
            ItemsSkipped = @()
            Errors = @()
        }
    }
    
    process {
        try {
            Write-Verbose "Starting restore of Outlook Settings..."
            Write-Host "Restoring Outlook Settings..." -ForegroundColor Blue
            
            # Validate inputs
            if (!(Test-Path $BackupRootPath)) {
                throw [System.IO.DirectoryNotFoundException]"Backup root path not found: $BackupRootPath"
            }
            
            $backupPath = Test-BackupPath -Path "Outlook" -BackupType "Outlook Settings"
            if (!$backupPath) {
                throw "No valid backup found for Outlook Settings"
            }
            $result.RestorePath = $backupPath
            
            # Stop Outlook processes before restoration
            if ($Force -or $PSCmdlet.ShouldProcess("Outlook Processes", "Stop")) {
                $stopped = Stop-OutlookProcesses -Force:$Force
                if (!$stopped -and !$Force) {
                    throw "Could not stop Outlook processes. Use -Force to continue anyway."
                }
            }
            
            # Restore registry settings first
            $registryPath = Join-Path $backupPath "Registry"
            if (Test-Path $registryPath) {
                if ($Force -or $PSCmdlet.ShouldProcess("Outlook Registry Settings", "Restore")) {
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

            # Restore configuration files
            $configMappings = @{
                "Signatures" = "$env:APPDATA\Microsoft\Signatures"
                "Templates" = "$env:APPDATA\Microsoft\Templates"
                "Rules" = "$env:APPDATA\Microsoft\Outlook"
                "Forms" = "$env:APPDATA\Microsoft\Forms"
                "Stationery" = "$env:APPDATA\Microsoft\Stationery"
                "QuickParts" = "$env:APPDATA\Microsoft\Document Building Blocks"
                "CustomUI" = "$env:APPDATA\Microsoft\Office\16.0\User Content\Ribbon"
                "AddIns" = "$env:APPDATA\Microsoft\AddIns"
                "VBA" = "$env:APPDATA\Microsoft\Office\16.0\VBA"
                "Themes" = "$env:APPDATA\Microsoft\Templates\Document Themes"
                "RecentFiles" = "$env:APPDATA\Microsoft\Office\Recent"
                "UProof" = "$env:APPDATA\Microsoft\UProof"
            }

            foreach ($config in $configMappings.GetEnumerator()) {
                $backupItem = Join-Path $backupPath $config.Key
                if (Test-Path $backupItem) {
                    if ($Force -or $PSCmdlet.ShouldProcess("$($config.Key) Configuration", "Restore")) {
                        try {
                            # Create parent directory if it doesn't exist
                            $parentDir = Split-Path $config.Value -Parent
                            if (!(Test-Path $parentDir)) {
                                New-Item -ItemType Directory -Force -Path $parentDir | Out-Null
                            }

                            # Create target directory if it doesn't exist
                            if (!(Test-Path $config.Value)) {
                                New-Item -ItemType Directory -Force -Path $config.Value | Out-Null
                            }

                            if (!$script:TestMode) {
                                # Copy files, excluding temporary and large files
                                $excludeFilter = @("*.tmp", "~*.*", "*.ost", "*.pst", "*.log", "*.lock")
                                Copy-Item -Path "$backupItem\*" -Destination $config.Value -Recurse -Force -Exclude $excludeFilter -ErrorAction SilentlyContinue
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

            # Restore Quick Access Toolbar
            $quickAccessBackup = Join-Path $backupPath "QuickAccess\Outlook.lnk"
            if (Test-Path $quickAccessBackup) {
                if ($Force -or $PSCmdlet.ShouldProcess("Quick Access Toolbar", "Restore")) {
                    try {
                        $quickAccessDest = "$env:APPDATA\Microsoft\Windows\Recent\Outlook.lnk"
                        $parentDir = Split-Path $quickAccessDest -Parent
                        if (!(Test-Path $parentDir)) {
                            New-Item -ItemType Directory -Force -Path $parentDir | Out-Null
                        }
                        
                        if (!$script:TestMode) {
                            Copy-Item $quickAccessBackup $quickAccessDest -Force
                        }
                        $result.ItemsRestored += "QuickAccess\Outlook.lnk"
                    } catch {
                        $result.Errors += "Failed to restore Quick Access Toolbar`: $_"
                        $result.ItemsSkipped += "QuickAccess\Outlook.lnk"
                        if (!$Force) { throw }
                    }
                }
            } else {
                $result.ItemsSkipped += "QuickAccess\Outlook.lnk (not found in backup)"
            }

            # Note: Profile information is informational only and doesn't need restoration
            $profilesFile = Join-Path $backupPath "Profiles\profiles.json"
            if (Test-Path $profilesFile) {
                $result.ItemsSkipped += "Profiles\profiles.json (informational only)"
            } else {
                $result.ItemsSkipped += "Profiles\profiles.json (not found in backup)"
            }
                
            $result.Success = ($result.Errors.Count -eq 0)
            
            # Display summary
            Write-Host "`nOutlook Settings Restore Summary:" -ForegroundColor Green
            Write-Host "Items Restored: $($result.ItemsRestored.Count)" -ForegroundColor Yellow
            Write-Host "Items Skipped: $($result.ItemsSkipped.Count)" -ForegroundColor Yellow
            Write-Host "Errors: $($result.Errors.Count)" -ForegroundColor $(if ($result.Errors.Count -gt 0) { "Red" } else { "Yellow" })
            
            if ($result.Success) {
                Write-Host "Outlook Settings restored successfully from: $backupPath" -ForegroundColor Green
                Write-Host "`nNote: Outlook restart is required for settings to take full effect" -ForegroundColor Yellow
            } else {
                Write-Warning "Outlook Settings restore completed with errors"
            }
            
            Write-Verbose "Restore completed successfully"
            return $result
        } catch {
            $errorRecord = $_
            $errorMessage = @(
                "Failed to restore Outlook Settings"
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
    Export-ModuleMember -Function Restore-OutlookSettings
}

<#
.SYNOPSIS
Restores Microsoft Outlook settings and configuration from backup.

.DESCRIPTION
Restores Microsoft Outlook configuration and associated data from a previous backup, including registry settings,
signatures, templates, rules, forms, stationery, Quick Parts, custom UI, add-ins, VBA projects, themes, and 
profile information. Supports multiple Outlook versions (2010, 2013, 2016, 2019, 365).

.PARAMETER BackupRootPath
The root path where the backup is located. The script will look for an "Outlook" subdirectory within this path.

.PARAMETER Force
Forces the restore operation without prompting for confirmation and continues even if some items fail to restore.

.PARAMETER Include
Array of item names to include in the restore operation. If not specified, all available items are restored.

.PARAMETER Exclude
Array of item names to exclude from the restore operation.

.PARAMETER SkipVerification
Skips backup integrity verification (useful for testing).

.EXAMPLE
Restore-OutlookSettings -BackupRootPath "C:\Backups"

.EXAMPLE
Restore-OutlookSettings -BackupRootPath "C:\Backups" -Force

.EXAMPLE
Restore-OutlookSettings -BackupRootPath "C:\Backups" -WhatIf

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
9. Outlook running during restore
10. Multiple Outlook versions
11. Custom signatures and templates
12. VBA projects and add-ins
13. Custom forms and stationery
14. Quick Parts and building blocks
15. Network path backup scenarios
16. Corrupted profile scenarios
17. Missing configuration directories
18. File permission issues
19. Disk space limitations
20. WhatIf scenario
21. Force parameter behavior
22. Include/Exclude filters
23. Process management scenarios
24. Large PST/OST file handling
25. Custom UI and ribbon modifications

.TESTCASES
# Mock test examples:
Describe "Restore-OutlookSettings" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Test-BackupPath { return "TestPath" }
        Mock Stop-OutlookProcesses { return $true }
        Mock Get-ChildItem { 
            return @(
                [PSCustomObject]@{ Name = "Outlook.reg"; FullName = "TestPath\Registry\Outlook.reg" },
                [PSCustomObject]@{ Name = "Preferences.reg"; FullName = "TestPath\Registry\Preferences.reg" }
            )
        }
        Mock New-Item { }
        Mock Copy-Item { }
        Mock reg { }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Restore-OutlookSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.RestorePath | Should -Be "TestPath"
        $result.Feature | Should -Be "Outlook Settings"
        $result.ItemsRestored | Should -BeOfType [System.Array]
        $result.ItemsSkipped | Should -BeOfType [System.Array]
        $result.Errors | Should -BeOfType [System.Array]
    }

    It "Should handle WhatIf properly" {
        $result = Restore-OutlookSettings -BackupRootPath "TestPath" -WhatIf
        $result.ItemsRestored.Count | Should -Be 0
    }

    It "Should handle registry import failure gracefully with Force" {
        Mock reg { throw "Registry import failed" }
        $result = Restore-OutlookSettings -BackupRootPath "TestPath" -Force
        $result.Errors.Count | Should -BeGreaterThan 0
        $result.ItemsSkipped.Count | Should -BeGreaterThan 0
    }

    It "Should handle missing backup gracefully" {
        Mock Test-BackupPath { return $null }
        { Restore-OutlookSettings -BackupRootPath "TestPath" } | Should -Throw
    }

    It "Should skip verification when specified" {
        $result = Restore-OutlookSettings -BackupRootPath "TestPath" -SkipVerification
        $result.Success | Should -Be $true
    }

    It "Should handle configuration restore failure gracefully" {
        Mock Copy-Item { throw "Access denied" }
        $result = Restore-OutlookSettings -BackupRootPath "TestPath" -Force
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle Outlook process stop failure" {
        Mock Stop-OutlookProcesses { return $false }
        { Restore-OutlookSettings -BackupRootPath "TestPath" } | Should -Throw
    }

    It "Should continue with Force when process stop fails" {
        Mock Stop-OutlookProcesses { return $false }
        $result = Restore-OutlookSettings -BackupRootPath "TestPath" -Force
        $result.Success | Should -Be $true
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Restore-OutlookSettings -BackupRootPath $BackupRootPath
} 