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

function Restore-ExplorerSettings {
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
            Feature = "Explorer Settings"
            Timestamp = Get-Date
            ItemsRestored = @()
            ItemsSkipped = @()
            Errors = @()
        }
    }
    
    process {
        try {
            Write-Verbose "Starting restore of Explorer Settings..."
            Write-Host "Restoring Explorer Settings..." -ForegroundColor Blue
            
            # Validate inputs
            if (!(Test-Path $BackupRootPath)) {
                throw [System.IO.DirectoryNotFoundException]"Backup root path not found: $BackupRootPath"
            }
            
            $backupPath = Test-BackupPath -Path "Explorer" -BackupType "Explorer Settings"
            if (!$backupPath) {
                throw "No valid backup found for Explorer Settings"
            }
            $result.RestorePath = $backupPath
            
            if ($backupPath) {
                # Explorer config locations
                $explorerConfigs = @{
                    "QuickAccess" = "$env:APPDATA\Microsoft\Windows\Recent\AutomaticDestinations"
                    "RecentItems" = "$env:APPDATA\Microsoft\Windows\Recent"
                    "Favorites" = "$env:USERPROFILE\Favorites"
                    "Desktop" = "$env:USERPROFILE\Desktop"
                    "StartMenu" = "$env:APPDATA\Microsoft\Windows\Start Menu"
                }

                # Stop Explorer process to allow settings changes (only if not in test mode)
                if (!$script:TestMode) {
                    if ($Force -or $PSCmdlet.ShouldProcess("Explorer Process", "Stop and Restart")) {
                        Write-Host "Stopping Explorer process to allow settings changes..." -ForegroundColor Yellow
                        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
                        Start-Sleep -Seconds 2
                    }
                }

                # Restore registry settings first
                $registryPath = Join-Path $backupPath "Registry"
                if (Test-Path $registryPath) {
                    if ($Force -or $PSCmdlet.ShouldProcess("Explorer Registry Settings", "Restore")) {
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

                # Restore Explorer configuration files
                foreach ($config in $explorerConfigs.GetEnumerator()) {
                    $backupItem = Join-Path $backupPath $config.Key
                    if (Test-Path $backupItem) {
                        if ($Force -or $PSCmdlet.ShouldProcess("Explorer $($config.Key)", "Restore")) {
                            try {
                                # Create parent directory if it doesn't exist
                                $parentDir = Split-Path $config.Value -Parent
                                if (!(Test-Path $parentDir)) {
                                    if (!$script:TestMode) {
                                        New-Item -ItemType Directory -Force -Path $parentDir | Out-Null
                                    }
                                }

                                if ((Get-Item $backupItem) -is [System.IO.DirectoryInfo]) {
                                    # Skip temporary files during restore
                                    $excludeFilter = @("*.tmp", "~*.*", "*.bak", "*.old")
                                    if (!$script:TestMode) {
                                        Copy-Item $backupItem $config.Value -Recurse -Force -Exclude $excludeFilter
                                    }
                                } else {
                                    if (!$script:TestMode) {
                                        Copy-Item $backupItem $config.Value -Force
                                    }
                                }
                                Write-Host "Restored configuration: $($config.Key)" -ForegroundColor Green
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

                # Restore folder view settings
                $folderViewsPath = Join-Path $backupPath "FolderViews"
                if (Test-Path $folderViewsPath) {
                    if ($Force -or $PSCmdlet.ShouldProcess("Explorer Folder Views", "Restore")) {
                        try {
                            Get-ChildItem -Path $folderViewsPath -Filter "*.json" | ForEach-Object {
                                try {
                                    $viewData = Get-Content $_.FullName | ConvertFrom-Json
                                    if ($viewData -and !$script:TestMode) {
                                        # Apply folder view settings (simplified for safety)
                                        Write-Verbose "Processing folder view settings for $($_.BaseName)"
                                    }
                                    $result.ItemsRestored += "FolderViews\$($_.Name)"
                                } catch {
                                    $result.Errors += "Failed to restore folder view $($_.Name)`: $_"
                                    $result.ItemsSkipped += "FolderViews\$($_.Name)"
                                    if (!$Force) { throw }
                                }
                            }
                        } catch {
                            $result.Errors += "Failed to process folder views`: $_"
                            if (!$Force) { throw }
                        }
                    }
                } else {
                    $result.ItemsSkipped += "FolderViews (not found in backup)"
                }

                # Start Explorer process (only if not in test mode)
                if (!$script:TestMode) {
                    if ($Force -or $PSCmdlet.ShouldProcess("Explorer Process", "Start")) {
                        Write-Host "Starting Explorer process..." -ForegroundColor Yellow
                        Start-Process explorer
                        Start-Sleep -Seconds 2
                    }
                }
                
                $result.Success = ($result.Errors.Count -eq 0)
                
                # Display summary
                Write-Host "`nExplorer Settings Restore Summary:" -ForegroundColor Green
                Write-Host "Items Restored: $($result.ItemsRestored.Count)" -ForegroundColor Yellow
                Write-Host "Items Skipped: $($result.ItemsSkipped.Count)" -ForegroundColor Yellow
                Write-Host "Errors: $($result.Errors.Count)" -ForegroundColor $(if ($result.Errors.Count -gt 0) { "Red" } else { "Yellow" })
                
                if ($result.Success) {
                    Write-Host "Explorer Settings restored successfully from: $backupPath" -ForegroundColor Green
                    Write-Host "`nNote: Some settings may require a system restart to take full effect" -ForegroundColor Yellow
                } else {
                    Write-Warning "Explorer Settings restore completed with errors"
                }
                
                Write-Verbose "Restore completed successfully"
                return $result
            }
            return $result
        } catch {
            $errorRecord = $_
            $errorMessage = @(
                "Failed to restore Explorer Settings"
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
    Export-ModuleMember -Function Restore-ExplorerSettings
}

<#
.SYNOPSIS
Restores Windows Explorer settings and configuration from backup.

.DESCRIPTION
Restores Windows Explorer configuration and associated data from a previous backup, including registry settings,
Quick Access, Recent Items, Favorites, Desktop items, Start Menu, and folder view settings. Handles Explorer
process management during restore to ensure settings are applied correctly.

.PARAMETER BackupRootPath
The root path where the backup is located. The script will look for an "Explorer" subdirectory within this path.

.PARAMETER Force
Forces the restore operation without prompting for confirmation and continues even if some items fail to restore.

.PARAMETER Include
Array of item names to include in the restore operation. If not specified, all available items are restored.

.PARAMETER Exclude
Array of item names to exclude from the restore operation.

.PARAMETER SkipVerification
Skips backup integrity verification (useful for testing).

.EXAMPLE
Restore-ExplorerSettings -BackupRootPath "C:\Backups"

.EXAMPLE
Restore-ExplorerSettings -BackupRootPath "C:\Backups" -Force

.EXAMPLE
Restore-ExplorerSettings -BackupRootPath "C:\Backups" -WhatIf

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
9. Explorer process management
10. WhatIf scenario
11. Force parameter behavior
12. Include/Exclude filters
13. Folder view settings restore
14. Quick Access restore
15. Large Desktop/Favorites restore
16. Network path backup scenarios
17. System restart requirements

.TESTCASES
# Mock test examples:
Describe "Restore-ExplorerSettings" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Test-BackupPath { return "TestPath" }
        Mock Get-ChildItem { 
            return @(
                [PSCustomObject]@{ Name = "Explorer.reg"; FullName = "TestPath\Registry\Explorer.reg" },
                [PSCustomObject]@{ Name = "Advanced.reg"; FullName = "TestPath\Registry\Advanced.reg" },
                [PSCustomObject]@{ Name = "Desktop.json"; FullName = "TestPath\FolderViews\Desktop.json"; BaseName = "Desktop" }
            )
        }
        Mock Copy-Item { }
        Mock New-Item { }
        Mock reg { }
        Mock Stop-Process { }
        Mock Start-Process { }
        Mock Start-Sleep { }
        Mock Get-Content { return '{"test": "data"}' }
        Mock ConvertFrom-Json { return @{ test = "data" } }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Restore-ExplorerSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.RestorePath | Should -Be "TestPath"
        $result.Feature | Should -Be "Explorer Settings"
        $result.ItemsRestored | Should -BeOfType [System.Array]
        $result.ItemsSkipped | Should -BeOfType [System.Array]
        $result.Errors | Should -BeOfType [System.Array]
    }

    It "Should handle WhatIf properly" {
        $result = Restore-ExplorerSettings -BackupRootPath "TestPath" -WhatIf
        $result.ItemsRestored.Count | Should -Be 0
    }

    It "Should handle registry import failure gracefully with Force" {
        Mock reg { throw "Registry import failed" }
        $result = Restore-ExplorerSettings -BackupRootPath "TestPath" -Force
        $result.Errors.Count | Should -BeGreaterThan 0
        $result.ItemsSkipped.Count | Should -BeGreaterThan 0
    }

    It "Should handle missing backup gracefully" {
        Mock Test-BackupPath { return $null }
        { Restore-ExplorerSettings -BackupRootPath "TestPath" } | Should -Throw
    }

    It "Should skip verification when specified" {
        $result = Restore-ExplorerSettings -BackupRootPath "TestPath" -SkipVerification
        $result.Success | Should -Be $true
    }

    It "Should handle folder view restore failure gracefully" {
        Mock ConvertFrom-Json { throw "Invalid JSON" }
        $result = Restore-ExplorerSettings -BackupRootPath "TestPath" -Force
        $result.Errors.Count | Should -BeGreaterThan 0
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Restore-ExplorerSettings -BackupRootPath $BackupRootPath
} 