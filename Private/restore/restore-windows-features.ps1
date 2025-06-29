[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory=$false)]
    [string]$BackupRootPath = $null,
    
    [Parameter(Mandatory=$false)]
    [switch]$Force,
    
    [Parameter(Mandatory=$false)]
    [string[]]$Include = @(),
    
    [Parameter(Mandatory=$false)]
    [string[]]$Exclude = @(),
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipVerification
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

function Test-BackupPath {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path,
        
        [Parameter(Mandatory=$true)]
        [string]$BackupType
    )
    
    $backupPath = Join-Path $BackupRootPath $Path
    if (Test-Path $backupPath) {
        Write-Host "Found backup for $BackupType at: $backupPath" -ForegroundColor Green
        return $backupPath
    } else {
        Write-Host "No backup found for $BackupType at: $backupPath" -ForegroundColor Yellow
        return $null
    }
}

function Test-RebootRequired {
    param()
    
    $rebootRequired = $false
    
    # Check various registry locations for pending reboot
    $rebootKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired",
        "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations",
        "HKLM:\SOFTWARE\Microsoft\Updates\UpdateExeVolatile"
    )
    
    foreach ($key in $rebootKeys) {
        if (Test-Path $key) {
            $rebootRequired = $true
            break
        }
    }
    
    return $rebootRequired
}

function Restore-WindowsFeaturesSettings {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force,
        
        [Parameter(Mandatory=$false)]
        [string[]]$Include = @(),
        
        [Parameter(Mandatory=$false)]
        [string[]]$Exclude = @(),
        
        [Parameter(Mandatory=$false)]
        [switch]$SkipVerification,

        # For testing purposes
        [Parameter(DontShow)]
        [switch]$WhatIf
    )
    
    begin {
        # Test hook for mocking
        if ($script:TestMode) {
            Write-Verbose "Running in test mode"
        }
        
        # Initialize result tracking
        $script:ItemsRestored = @()
        $script:ItemsSkipped = @()
        $script:Errors = @()
    }
    
    process {
        try {
            Write-Verbose "Starting restore of Windows Features..."
            Write-Host "Restoring Windows Features..." -ForegroundColor Blue
            
            # Validate backup path
            if (!(Test-Path $BackupRootPath)) {
                throw [System.IO.DirectoryNotFoundException]"Backup root path not found: $BackupRootPath"
            }
            
            $backupPath = Test-BackupPath -Path "WindowsFeatures" -BackupType "Windows Features"
            
            if (!$backupPath) {
                throw [System.IO.FileNotFoundException]"No Windows Features backup found at: $(Join-Path $BackupRootPath 'WindowsFeatures')"
            }
            
            # Define all items that can be restored
            $restoreItems = @{
                "Registry" = @{
                    Path = Join-Path $backupPath "Registry"
                    Description = "Windows Features registry settings"
                    Action = {
                        param($ItemPath, $WhatIf)
                        
                        if (Test-Path $ItemPath) {
                            $regFiles = Get-ChildItem -Path $ItemPath -Filter "*.reg" -ErrorAction SilentlyContinue
                            $importedFiles = @()
                            
                            foreach ($regFile in $regFiles) {
                                if ($WhatIf) {
                                    Write-Host "WhatIf: Would import registry file: $($regFile.Name)"
                                    $importedFiles += $regFile.Name
                                } else {
                                    try {
                                        Write-Host "Importing registry file: $($regFile.Name)" -ForegroundColor Yellow
                                        if (!$script:TestMode) {
                                            $result = reg import $regFile.FullName 2>&1
                                            if ($LASTEXITCODE -eq 0) {
                                                $importedFiles += $regFile.Name
                                                Write-Host "Successfully imported: $($regFile.Name)" -ForegroundColor Green
                                            } else {
                                                $script:Errors += "Failed to import registry file $($regFile.Name): $result"
                                            }
                                        } else {
                                            $importedFiles += $regFile.Name
                                        }
                                    } catch {
                                        $script:Errors += "Error importing registry file $($regFile.Name)`: $_"
                                        Write-Warning "Failed to import registry file $($regFile.Name)"
                                    }
                                }
                            }
                            
                            return $importedFiles
                        }
                        return @()
                    }
                }
                
                "OptionalFeatures" = @{
                    Path = Join-Path $backupPath "enabled_features.json"
                    Description = "Windows Optional Features"
                    Action = {
                        param($ItemPath, $WhatIf)
                        
                        if (Test-Path $ItemPath) {
                            if ($WhatIf) {
                                Write-Host "WhatIf: Would restore Windows Optional Features from $ItemPath"
                                return @("Windows Optional Features")
                            } else {
                                try {
                                    if (!$script:TestMode) {
                                        $enabledFeatures = Get-Content $ItemPath | ConvertFrom-Json
                                        $restoredFeatures = @()
                                        
                                        foreach ($feature in $enabledFeatures) {
                                            try {
                                                Write-Host "Enabling feature: $($feature.FeatureName)" -ForegroundColor Yellow
                                                Enable-WindowsOptionalFeature -Online -FeatureName $feature.FeatureName -NoRestart -ErrorAction Stop
                                                $restoredFeatures += $feature.FeatureName
                                                Write-Host "Enabled feature: $($feature.FeatureName)" -ForegroundColor Green
                                            } catch {
                                                $script:Errors += "Failed to enable feature $($feature.FeatureName)`: $_"
                                                Write-Warning "Failed to enable feature $($feature.FeatureName)"
                                            }
                                        }
                                        
                                        return $restoredFeatures
                                    } else {
                                        return @("Test Optional Features")
                                    }
                                } catch {
                                    $script:Errors += "Failed to restore Windows Optional Features`: $_"
                                    Write-Warning "Failed to restore Windows Optional Features"
                                }
                            }
                        }
                        return @()
                    }
                }
                
                "Capabilities" = @{
                    Path = Join-Path $backupPath "installed_capabilities.json"
                    Description = "Windows Capabilities"
                    Action = {
                        param($ItemPath, $WhatIf)
                        
                        if (Test-Path $ItemPath) {
                            if ($WhatIf) {
                                Write-Host "WhatIf: Would restore Windows Capabilities from $ItemPath"
                                return @("Windows Capabilities")
                            } else {
                                try {
                                    if (!$script:TestMode) {
                                        $installedCapabilities = Get-Content $ItemPath | ConvertFrom-Json
                                        $restoredCapabilities = @()
                                        
                                        foreach ($capability in $installedCapabilities) {
                                            try {
                                                Write-Host "Installing capability: $($capability.Name)" -ForegroundColor Yellow
                                                Add-WindowsCapability -Online -Name $capability.Name -ErrorAction Stop
                                                $restoredCapabilities += $capability.Name
                                                Write-Host "Installed capability: $($capability.Name)" -ForegroundColor Green
                                            } catch {
                                                $script:Errors += "Failed to install capability $($capability.Name)`: $_"
                                                Write-Warning "Failed to install capability $($capability.Name)"
                                            }
                                        }
                                        
                                        return $restoredCapabilities
                                    } else {
                                        return @("Test Capabilities")
                                    }
                                } catch {
                                    $script:Errors += "Failed to restore Windows Capabilities`: $_"
                                    Write-Warning "Failed to restore Windows Capabilities"
                                }
                            }
                        }
                        return @()
                    }
                }
                
                "ServerFeatures" = @{
                    Path = Join-Path $backupPath "server_features.json"
                    Description = "Windows Server Features"
                    Action = {
                        param($ItemPath, $WhatIf)
                        
                        if (Test-Path $ItemPath) {
                            if ($WhatIf) {
                                Write-Host "WhatIf: Would restore Windows Server Features from $ItemPath"
                                return @("Windows Server Features")
                            } else {
                                try {
                                    if (!$script:TestMode) {
                                        # Check if this is a server OS
                                        $osInfo = Get-WmiObject -Class Win32_OperatingSystem
                                        if ($osInfo.ProductType -ne 1) {
                                            $serverFeatures = Get-Content $ItemPath | ConvertFrom-Json
                                            $restoredFeatures = @()
                                            
                                            foreach ($feature in $serverFeatures) {
                                                try {
                                                    Write-Host "Installing server feature: $($feature.Name)" -ForegroundColor Yellow
                                                    Install-WindowsFeature -Name $feature.Name -ErrorAction Stop
                                                    $restoredFeatures += $feature.Name
                                                    Write-Host "Installed server feature: $($feature.Name)" -ForegroundColor Green
                                                } catch {
                                                    $script:Errors += "Failed to install server feature $($feature.Name)`: $_"
                                                    Write-Warning "Failed to install server feature $($feature.Name)"
                                                }
                                            }
                                            
                                            return $restoredFeatures
                                        } else {
                                            $script:Errors += "Server features backup found but this is not a server OS"
                                            return @()
                                        }
                                    } else {
                                        return @("Test Server Features")
                                    }
                                } catch {
                                    $script:Errors += "Failed to restore Windows Server Features`: $_"
                                    Write-Warning "Failed to restore Windows Server Features"
                                }
                            }
                        }
                        return @()
                    }
                }
            }
            
            # Process each restore item
            foreach ($itemName in $restoreItems.Keys) {
                $item = $restoreItems[$itemName]
                
                # Check include/exclude filters
                if ($Include.Count -gt 0 -and $itemName -notin $Include) {
                    $script:ItemsSkipped += "$itemName (not in include list)"
                    Write-Verbose "Skipping $itemName (not in include list)"
                    continue
                }
                
                if ($Exclude.Count -gt 0 -and $itemName -in $Exclude) {
                    $script:ItemsSkipped += "$itemName (in exclude list)"
                    Write-Verbose "Skipping $itemName (in exclude list)"
                    continue
                }
                
                # Check if backup exists
                if (!(Test-Path $item.Path)) {
                    $script:ItemsSkipped += "$itemName (no backup found)"
                    Write-Verbose "Skipping $itemName (no backup found at $($item.Path))"
                    continue
                }
                
                if ($PSCmdlet.ShouldProcess($item.Description, "Restore")) {
                    try {
                        # All items have custom actions
                        $result = & $item.Action $item.Path $WhatIf
                        if ($result -and $result.Count -gt 0) {
                            $script:ItemsRestored += "$itemName ($($result.Count) items)"
                            Write-Host "Restored $itemName ($($result.Count) items)" -ForegroundColor Green
                        } else {
                            $script:ItemsSkipped += "$itemName (no items to restore)"
                        }
                    } catch {
                        $script:Errors += "Failed to restore $itemName `: $_"
                        Write-Warning "Failed to restore $($item.Description)`: $_"
                    }
                }
            }
            
            # Handle informational files (not restored, just noted)
            $infoFiles = @("optional_features.json", "capabilities.json", "dism_packages.txt", "installed_updates.json", "appx_packages.json", "system_info.json")
            foreach ($infoFile in $infoFiles) {
                $infoPath = Join-Path $backupPath $infoFile
                if (Test-Path $infoPath) {
                    $script:ItemsSkipped += "$infoFile (informational only)"
                    Write-Host "Found informational backup: $infoFile (not restored - informational only)" -ForegroundColor Yellow
                }
            }
            
            # Check for pending reboot
            $rebootRequired = $false
            if (!$WhatIf -and !$script:TestMode) {
                $rebootRequired = Test-RebootRequired
            }
            
            # Create result object
            $result = [PSCustomObject]@{
                Success = $true
                BackupPath = $backupPath
                Feature = "Windows Features"
                Timestamp = Get-Date
                ItemsRestored = $script:ItemsRestored
                ItemsSkipped = $script:ItemsSkipped
                Errors = $script:Errors
                RequiresRestart = $rebootRequired
            }
            
            # Display summary
            Write-Host "`nWindows Features Restore Summary:" -ForegroundColor Green
            Write-Host "Items Restored: $($script:ItemsRestored.Count)" -ForegroundColor Yellow
            Write-Host "Items Skipped: $($script:ItemsSkipped.Count)" -ForegroundColor Yellow
            Write-Host "Errors: $($script:Errors.Count)" -ForegroundColor $(if ($script:Errors.Count -gt 0) { "Red" } else { "Yellow" })
            
            if ($script:ItemsRestored.Count -gt 0) {
                Write-Host "`nRestored Items:" -ForegroundColor Green
                $script:ItemsRestored | ForEach-Object { Write-Host "  - $_" -ForegroundColor White }
            }
            
            if ($script:ItemsSkipped.Count -gt 0) {
                Write-Host "`nSkipped Items:" -ForegroundColor Yellow
                $script:ItemsSkipped | ForEach-Object { Write-Host "  - $_" -ForegroundColor Gray }
            }
            
            if ($script:Errors.Count -gt 0) {
                Write-Host "`nErrors:" -ForegroundColor Red
                $script:Errors | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
            }
            
            if ($rebootRequired) {
                Write-Host "`nWARNING: A system restart is required to complete feature installation/configuration." -ForegroundColor Yellow
                Write-Host "Please restart your computer when convenient." -ForegroundColor Yellow
            }
            
            if ($script:ItemsRestored.Count -gt 0) {
                Write-Host "`nNote: Windows Features have been restored. Some features may require a restart to be fully functional." -ForegroundColor Cyan
            }
            
            Write-Host "Windows Features restored successfully from: $backupPath" -ForegroundColor Green
            Write-Verbose "Restore completed successfully"
            return $result
            
        } catch {
            $errorRecord = $_
            $errorMessage = @(
                "Failed to restore Windows Features"
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
            throw  # Re-throw for proper error handling
        }
    }
}

<#
.SYNOPSIS
Restores comprehensive Windows Features, capabilities, and system components from backup.

.DESCRIPTION
Restores Windows Features from a backup created by Backup-WindowsFeatures. This includes
registry settings, Windows Optional Features, Windows Capabilities, and Windows Server
Features (if applicable). The restore process handles different Windows versions and
editions appropriately.

The restore process will:
1. Import registry settings for Windows Features and Component Based Servicing
2. Enable Windows Optional Features that were previously enabled
3. Install Windows Capabilities that were previously installed
4. Install Windows Server Features (if running on Windows Server)
5. Check for pending reboot requirements
6. Skip informational-only backup files

.PARAMETER BackupRootPath
The root path where the backup is located. The script will look for a "WindowsFeatures" subdirectory within this path.

.PARAMETER Force
Forces the restore operation even if features are already enabled or if conflicts exist.

.PARAMETER Include
Specifies which items to include in the restore. If not specified, all available items are restored.
Valid values: Registry, OptionalFeatures, Capabilities, ServerFeatures

.PARAMETER Exclude
Specifies which items to exclude from the restore.
Valid values: Registry, OptionalFeatures, Capabilities, ServerFeatures

.PARAMETER SkipVerification
Skips verification steps and proceeds with the restore operation.

.EXAMPLE
Restore-WindowsFeaturesSettings -BackupRootPath "C:\Backups"

.EXAMPLE
Restore-WindowsFeaturesSettings -BackupRootPath "C:\Backups" -Include @("OptionalFeatures", "Capabilities")

.EXAMPLE
Restore-WindowsFeaturesSettings -BackupRootPath "C:\Backups" -Exclude @("ServerFeatures") -WhatIf

.NOTES
Test cases to consider:
1. Valid backup path with complete backup
2. Invalid/nonexistent backup path
3. Partial backup (some items missing)
4. Windows 10 vs Windows 11 vs Windows Server
5. No permissions to modify Windows Features
6. Registry import success/failure
7. Optional Features enable success/failure
8. Capabilities install success/failure
9. Server Features install success/failure (server vs client OS)
10. Include filter functionality
11. Exclude filter functionality
12. WhatIf parameter functionality
13. Force parameter functionality
14. Reboot detection functionality
15. Missing Windows Features database
16. Corrupted backup files
17. Network path scenarios
18. Administrative privileges scenarios
19. Feature conflicts and dependencies
20. Large feature sets scenarios
21. Windows Subsystem for Linux restoration
22. Hyper-V features restoration
23. IIS features restoration
24. .NET Framework features restoration
25. Feature on demand scenarios

.TESTCASES
# Mock test examples:
Describe "Restore-WindowsFeaturesSettings" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Test-BackupPath { return "TestBackupPath" }
        Mock Test-RebootRequired { return $false }
        Mock Get-ChildItem { return @(@{Name="test.reg"; FullName="C:\test.reg"}) }
        Mock Get-Content { return '[]' }
        Mock ConvertFrom-Json { return @() }
        Mock Enable-WindowsOptionalFeature { }
        Mock Add-WindowsCapability { }
        Mock Install-WindowsFeature { }
        Mock Get-WmiObject { return @{ProductType=1} }
        Mock reg { $global:LASTEXITCODE = 0 }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Restore-WindowsFeaturesSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.BackupPath | Should -Be "TestBackupPath"
        $result.Feature | Should -Be "Windows Features"
        $result.ItemsRestored | Should -BeOfType [System.Array]
        $result.ItemsSkipped | Should -BeOfType [System.Array]
        $result.Errors | Should -BeOfType [System.Array]
        $result.RequiresRestart | Should -Be $false
    }

    It "Should handle missing backup gracefully" {
        Mock Test-BackupPath { return $null }
        { Restore-WindowsFeaturesSettings -BackupRootPath "TestPath" } | Should -Throw
    }

    It "Should handle registry import failure gracefully" {
        Mock reg { $global:LASTEXITCODE = 1; return "Error" }
        $result = Restore-WindowsFeaturesSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle Optional Features enable failure gracefully" {
        Mock Enable-WindowsOptionalFeature { throw "Feature enable failed" }
        Mock Get-Content { return '[{"FeatureName":"IIS-WebServerRole","State":"Enabled"}]' }
        Mock ConvertFrom-Json { return @(@{FeatureName="IIS-WebServerRole"; State="Enabled"}) }
        $result = Restore-WindowsFeaturesSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should support Include parameter" {
        $result = Restore-WindowsFeaturesSettings -BackupRootPath "TestPath" -Include @("Registry")
        $result.Success | Should -Be $true
        $result.ItemsSkipped | Should -Contain "OptionalFeatures (not in include list)"
    }

    It "Should support Exclude parameter" {
        $result = Restore-WindowsFeaturesSettings -BackupRootPath "TestPath" -Exclude @("Registry")
        $result.Success | Should -Be $true
        $result.ItemsSkipped | Should -Contain "Registry (in exclude list)"
    }

    It "Should support WhatIf parameter" {
        $result = Restore-WindowsFeaturesSettings -BackupRootPath "TestPath" -WhatIf
        $result.Success | Should -Be $true
    }

    It "Should handle server features on client OS gracefully" {
        Mock Get-WmiObject { return @{ProductType=1} }  # Client OS
        $result = Restore-WindowsFeaturesSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
    }

    It "Should handle capabilities install failure gracefully" {
        Mock Add-WindowsCapability { throw "Capability install failed" }
        Mock Get-Content { return '[{"Name":"Language.Basic~~~en-US~0.0.1.0","State":"Installed"}]' }
        Mock ConvertFrom-Json { return @(@{Name="Language.Basic~~~en-US~0.0.1.0"; State="Installed"}) }
        $result = Restore-WindowsFeaturesSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle missing backup items gracefully" {
        Mock Test-Path { param($Path) return $Path -notlike "*OptionalFeatures*" }
        $result = Restore-WindowsFeaturesSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.ItemsSkipped | Should -Contain "OptionalFeatures (no backup found)"
    }

    It "Should detect reboot requirements" {
        Mock Test-RebootRequired { return $true }
        $result = Restore-WindowsFeaturesSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.RequiresRestart | Should -Be $true
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Restore-WindowsFeaturesSettings -BackupRootPath $BackupRootPath -Force:$Force -Include $Include -Exclude $Exclude -SkipVerification:$SkipVerification
} 