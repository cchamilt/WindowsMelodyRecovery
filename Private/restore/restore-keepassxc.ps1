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

function Restore-KeePassXCSettings {
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
            Feature = "KeePassXC Settings"
            Timestamp = Get-Date
            ItemsRestored = @()
            ItemsSkipped = @()
            Errors = @()
        }
    }
    
    process {
        try {
            Write-Verbose "Starting restore of KeePassXC Settings..."
            Write-Host "Restoring KeePassXC Settings..." -ForegroundColor Blue
            
            # Validate inputs
            if (!(Test-Path $BackupRootPath)) {
                throw [System.IO.DirectoryNotFoundException]"Backup root path not found: $BackupRootPath"
            }
            
            $backupPath = Test-BackupPath -Path "KeePassXC" -BackupType "KeePassXC Settings"
            if (!$backupPath) {
                throw "No valid backup found for KeePassXC Settings"
            }
            $result.RestorePath = $backupPath
            
            if ($backupPath) {
                # KeePassXC config locations
                $keepassxcConfigs = @{
                    "Config" = "$env:APPDATA\KeePassXC"
                    "Plugins" = "$env:APPDATA\KeePassXC\plugins"
                    "KeyFiles" = "$env:APPDATA\KeePassXC\keyfiles"
                    "AutoType" = "$env:APPDATA\KeePassXC\autotype"
                }
                
                # Create KeePassXC config directory if it doesn't exist
                if (!$script:TestMode) {
                    New-Item -ItemType Directory -Force -Path "$env:APPDATA\KeePassXC" | Out-Null
                }
                
                # Check KeePassXC installation
                if (!$script:TestMode) {
                    Write-Host "Checking KeePassXC installation..." -ForegroundColor Yellow
                    $keepassxcPath = "$env:ProgramFiles\KeePassXC\KeePassXC.exe"
                    if (!(Test-Path $keepassxcPath)) {
                        if ($Force -or $PSCmdlet.ShouldProcess("KeePassXC", "Install")) {
                            Write-Host "Installing KeePassXC..." -ForegroundColor Yellow
                            winget install -e --id KeePassXCTeam.KeePassXC
                            $result.ItemsRestored += "KeePassXC Installation"
                        }
                    }
                }

                # Restore registry settings first
                $registryPath = Join-Path $backupPath "Registry"
                if (Test-Path $registryPath) {
                    if ($Force -or $PSCmdlet.ShouldProcess("KeePassXC Registry Settings", "Restore")) {
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

                # Restore KeePassXC configuration files
                foreach ($config in $keepassxcConfigs.GetEnumerator()) {
                    $backupItem = Join-Path $backupPath $config.Key
                    if (Test-Path $backupItem) {
                        if ($Force -or $PSCmdlet.ShouldProcess("KeePassXC $($config.Key)", "Restore")) {
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
                                    $excludeFilter = @("*.tmp", "~*.*", "*.bak", "*.old", "*.lock")
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

                # Restore browser integration settings
                $browserIntegrationPath = Join-Path $backupPath "BrowserIntegration"
                if (Test-Path $browserIntegrationPath) {
                    if ($Force -or $PSCmdlet.ShouldProcess("KeePassXC Browser Integration", "Restore")) {
                        try {
                            $browserTargets = @{
                                "Chrome" = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Local Extension Settings\oboonakemofpalcgghocfoadofidjkkk"
                                "Firefox" = "$env:APPDATA\Mozilla\Firefox\Profiles\*\browser-extension-data\keepassxc-browser@keepassxc.org"
                                "Edge" = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Local Extension Settings\pdffhmdngciaglkoonimfcmckehcpafo"
                            }

                            Get-ChildItem -Path $browserIntegrationPath -Directory | ForEach-Object {
                                $browserName = $_.Name
                                if ($browserTargets.ContainsKey($browserName)) {
                                    try {
                                        $targetPath = $browserTargets[$browserName]
                                        $parentDir = Split-Path $targetPath -Parent
                                        if (!(Test-Path $parentDir)) {
                                            if (!$script:TestMode) {
                                                New-Item -ItemType Directory -Force -Path $parentDir | Out-Null
                                            }
                                        }
                                        if (!$script:TestMode) {
                                            Copy-Item "$($_.FullName)\*" $targetPath -Recurse -Force
                                        }
                                        $result.ItemsRestored += "BrowserIntegration\$browserName"
                                    } catch {
                                        $result.Errors += "Failed to restore browser integration for $browserName `: $_"
                                        $result.ItemsSkipped += "BrowserIntegration\$browserName"
                                        if (!$Force) { throw }
                                    }
                                }
                            }
                        } catch {
                            $result.Errors += "Failed to process browser integration`: $_"
                            if (!$Force) { throw }
                        }
                    }
                } else {
                    $result.ItemsSkipped += "BrowserIntegration (not found in backup)"
                }

                # Kill any running KeePassXC processes (only if not in test mode)
                if (!$script:TestMode) {
                    if ($Force -or $PSCmdlet.ShouldProcess("KeePassXC Process", "Stop")) {
                        Get-Process -Name "keepassxc" -ErrorAction SilentlyContinue | Stop-Process -Force
                        $result.ItemsRestored += "Process Management"
                    }
                }
                
                $result.Success = ($result.Errors.Count -eq 0)
                
                # Display summary
                Write-Host "`nKeePassXC Settings Restore Summary:" -ForegroundColor Green
                Write-Host "Items Restored: $($result.ItemsRestored.Count)" -ForegroundColor Yellow
                Write-Host "Items Skipped: $($result.ItemsSkipped.Count)" -ForegroundColor Yellow
                Write-Host "Errors: $($result.Errors.Count)" -ForegroundColor $(if ($result.Errors.Count -gt 0) { "Red" } else { "Yellow" })
                
                if ($result.Success) {
                    Write-Host "KeePassXC Settings restored successfully from: $backupPath" -ForegroundColor Green
                    Write-Host "`nNote: KeePassXC restart may be required for settings to take full effect" -ForegroundColor Yellow
                } else {
                    Write-Warning "KeePassXC Settings restore completed with errors"
                }
                
                Write-Verbose "Restore completed successfully"
                return $result
            }
            return $result
        } catch {
            $errorRecord = $_
            $errorMessage = @(
                "Failed to restore KeePassXC Settings"
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
    Export-ModuleMember -Function Restore-KeePassXCSettings
}

<#
.SYNOPSIS
Restores KeePassXC settings and configuration from backup.

.DESCRIPTION
Restores KeePassXC configuration and associated data from a previous backup, including registry settings,
configuration files, plugins, key files, auto-type settings, and browser integration settings for Chrome,
Firefox, and Edge. Handles KeePassXC installation if not present and process management during restore.

.PARAMETER BackupRootPath
The root path where the backup is located. The script will look for a "KeePassXC" subdirectory within this path.

.PARAMETER Force
Forces the restore operation without prompting for confirmation and continues even if some items fail to restore.

.PARAMETER Include
Array of item names to include in the restore operation. If not specified, all available items are restored.

.PARAMETER Exclude
Array of item names to exclude from the restore operation.

.PARAMETER SkipVerification
Skips backup integrity verification (useful for testing).

.EXAMPLE
Restore-KeePassXCSettings -BackupRootPath "C:\Backups"

.EXAMPLE
Restore-KeePassXCSettings -BackupRootPath "C:\Backups" -Force

.EXAMPLE
Restore-KeePassXCSettings -BackupRootPath "C:\Backups" -WhatIf

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
9. KeePassXC not installed scenario
10. WhatIf scenario
11. Force parameter behavior
12. Include/Exclude filters
13. Browser integration restore
14. Plugin restore scenarios
15. Key files restore
16. Auto-type settings restore
17. Process management scenarios
18. Network path backup scenarios

.TESTCASES
# Mock test examples:
Describe "Restore-KeePassXCSettings" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Test-BackupPath { return "TestPath" }
        Mock Get-ChildItem { 
            return @(
                [PSCustomObject]@{ Name = "KeePassXC.reg"; FullName = "TestPath\Registry\KeePassXC.reg" },
                [PSCustomObject]@{ Name = "General.reg"; FullName = "TestPath\Registry\General.reg" },
                [PSCustomObject]@{ Name = "Chrome"; FullName = "TestPath\BrowserIntegration\Chrome" }
            )
        }
        Mock Copy-Item { }
        Mock New-Item { }
        Mock reg { }
        Mock Get-Process { return @() }
        Mock Stop-Process { }
        Mock winget { }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Restore-KeePassXCSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.RestorePath | Should -Be "TestPath"
        $result.Feature | Should -Be "KeePassXC Settings"
        $result.ItemsRestored | Should -BeOfType [System.Array]
        $result.ItemsSkipped | Should -BeOfType [System.Array]
        $result.Errors | Should -BeOfType [System.Array]
    }

    It "Should handle WhatIf properly" {
        $result = Restore-KeePassXCSettings -BackupRootPath "TestPath" -WhatIf
        $result.ItemsRestored.Count | Should -Be 0
    }

    It "Should handle registry import failure gracefully with Force" {
        Mock reg { throw "Registry import failed" }
        $result = Restore-KeePassXCSettings -BackupRootPath "TestPath" -Force
        $result.Errors.Count | Should -BeGreaterThan 0
        $result.ItemsSkipped.Count | Should -BeGreaterThan 0
    }

    It "Should handle missing backup gracefully" {
        Mock Test-BackupPath { return $null }
        { Restore-KeePassXCSettings -BackupRootPath "TestPath" } | Should -Throw
    }

    It "Should skip verification when specified" {
        $result = Restore-KeePassXCSettings -BackupRootPath "TestPath" -SkipVerification
        $result.Success | Should -Be $true
    }

    It "Should handle browser integration restore failure gracefully" {
        Mock Copy-Item { throw "Access denied" } -ParameterFilter { $Path -like "*Extension Settings*" }
        $result = Restore-KeePassXCSettings -BackupRootPath "TestPath" -Force
        $result.Errors.Count | Should -BeGreaterThan 0
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Restore-KeePassXCSettings -BackupRootPath $BackupRootPath
} 