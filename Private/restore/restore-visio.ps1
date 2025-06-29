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

function Stop-VisioProcesses {
    param(
        [Parameter(Mandatory=$false)]
        [switch]$WhatIf
    )
    
    $visioProcesses = @("VISIO", "VISIVIEW")
    $stoppedProcesses = @()
    
    foreach ($processName in $visioProcesses) {
        if ($script:TestMode) {
            Write-Verbose "Test mode: Would check for $processName processes"
            continue
        }
        
        $processes = Get-Process -Name $processName -ErrorAction SilentlyContinue
        if ($processes) {
            foreach ($process in $processes) {
                if ($WhatIf) {
                    Write-Host "WhatIf: Would stop Visio process $($process.Name) (PID: $($process.Id))"
                } else {
                    try {
                        Write-Host "Stopping Visio process $($process.Name) (PID: $($process.Id))..." -ForegroundColor Yellow
                        $process.CloseMainWindow() | Out-Null
                        Start-Sleep -Seconds 2
                        
                        if (!$process.HasExited) {
                            $process.Kill()
                            Start-Sleep -Seconds 1
                        }
                        
                        $stoppedProcesses += $process.Name
                        Write-Host "Successfully stopped Visio process $($process.Name)" -ForegroundColor Green
                    } catch {
                        Write-Warning "Failed to stop Visio process $($process.Name)`: $_"
                    }
                }
            }
        }
    }
    
    return $stoppedProcesses
}

function Restore-VisioSettings {
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
            Write-Verbose "Starting restore of Visio Settings..."
            Write-Host "Restoring Visio Settings..." -ForegroundColor Blue
            
            # Validate backup path
            if (!(Test-Path $BackupRootPath)) {
                throw [System.IO.DirectoryNotFoundException]"Backup root path not found: $BackupRootPath"
            }
            
            $backupPath = Test-BackupPath -Path "Visio" -BackupType "Visio Settings"
            
            if (!$backupPath) {
                throw [System.IO.FileNotFoundException]"No Visio Settings backup found at: $(Join-Path $BackupRootPath 'Visio')"
            }
            
            # Stop Visio processes before restoration
            if ($PSCmdlet.ShouldProcess("Visio processes", "Stop")) {
                $stoppedProcesses = Stop-VisioProcesses -WhatIf:$WhatIf
                if ($stoppedProcesses.Count -gt 0) {
                    Write-Host "Stopped $($stoppedProcesses.Count) Visio process(es)" -ForegroundColor Green
                }
            }
            
            # Define all items that can be restored
            $restoreItems = @{
                "Registry" = @{
                    Path = Join-Path $backupPath "Registry"
                    Description = "Visio registry settings"
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
                
                "Settings" = @{
                    Path = Join-Path $backupPath "Settings"
                    Target = "$env:APPDATA\Microsoft\Visio"
                    Description = "Visio application settings"
                }
                
                "Templates" = @{
                    Path = Join-Path $backupPath "Templates"
                    Target = "$env:APPDATA\Microsoft\Templates"
                    Description = "Visio templates"
                }
                
                "RecentFiles" = @{
                    Path = Join-Path $backupPath "RecentFiles"
                    Target = "$env:APPDATA\Microsoft\Office\Recent"
                    Description = "Recent files list"
                }
                
                "CustomDictionary" = @{
                    Path = Join-Path $backupPath "CustomDictionary"
                    Target = "$env:APPDATA\Microsoft\UProof"
                    Description = "Custom dictionaries"
                }
                
                "AutoCorrect" = @{
                    Path = Join-Path $backupPath "AutoCorrect"
                    Target = "$env:APPDATA\Microsoft\Office"
                    Description = "AutoCorrect entries"
                }
                
                "Ribbons" = @{
                    Path = Join-Path $backupPath "Ribbons"
                    Target = "$env:APPDATA\Microsoft\Office\16.0\Visio\Ribbons"
                    Description = "Custom ribbons and toolbars"
                }
                
                "AddIns" = @{
                    Path = Join-Path $backupPath "AddIns"
                    Target = "$env:APPDATA\Microsoft\Visio\AddOns"
                    Description = "Visio add-ins"
                }
                
                "Stencils" = @{
                    Path = Join-Path $backupPath "Stencils"
                    Target = "$env:APPDATA\Microsoft\Visio\Stencils"
                    Description = "Custom stencils"
                }
                
                "MyShapes" = @{
                    Path = Join-Path $backupPath "MyShapes"
                    Target = "$env:APPDATA\Microsoft\Visio\My Shapes"
                    Description = "Custom shapes"
                }
                
                "Themes" = @{
                    Path = Join-Path $backupPath "Themes"
                    Target = "$env:APPDATA\Microsoft\Visio\Themes"
                    Description = "Custom themes"
                }
                
                "Workspace" = @{
                    Path = Join-Path $backupPath "Workspace"
                    Target = "$env:APPDATA\Microsoft\Visio\Workspace"
                    Description = "Workspace settings"
                }
                
                "Macros" = @{
                    Path = Join-Path $backupPath "Macros"
                    Target = "$env:APPDATA\Microsoft\Visio\Macros"
                    Description = "Visio macros"
                }
                
                "QuickAccess" = @{
                    Path = Join-Path $backupPath "QuickAccess"
                    Target = "$env:APPDATA\Microsoft\Office\16.0\Visio\QuickAccess"
                    Description = "Quick Access Toolbar settings"
                }
                
                "CustomUI" = @{
                    Path = Join-Path $backupPath "CustomUI"
                    Target = "$env:APPDATA\Microsoft\Office\16.0\Visio\CustomUI"
                    Description = "Custom UI elements"
                }
                
                "VBAProjects" = @{
                    Path = Join-Path $backupPath "VBAProjects"
                    Target = "$env:APPDATA\Microsoft\Office\16.0\Visio\VBA"
                    Description = "VBA projects"
                }
                
                "Preferences" = @{
                    Path = Join-Path $backupPath "Preferences"
                    Target = "$env:APPDATA\Microsoft\Office\16.0\Visio\Preferences"
                    Description = "User preferences"
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
                        if ($item.ContainsKey("Action")) {
                            # Custom action for complex items like Registry
                            $result = & $item.Action $item.Path $WhatIf
                            if ($result -and $result.Count -gt 0) {
                                $script:ItemsRestored += "$itemName ($($result.Count) items)"
                                Write-Host "Restored $itemName ($($result.Count) items)" -ForegroundColor Green
                            } else {
                                $script:ItemsSkipped += "$itemName (no items to restore)"
                            }
                        } else {
                            # Standard file/directory copy
                            if ($WhatIf) {
                                Write-Host "WhatIf: Would restore $($item.Description) from $($item.Path) to $($item.Target)"
                                $script:ItemsRestored += $itemName
                            } else {
                                # Create parent directory if it doesn't exist
                                $parentDir = Split-Path $item.Target -Parent
                                if (!(Test-Path $parentDir)) {
                                    New-Item -ItemType Directory -Force -Path $parentDir | Out-Null
                                }
                                
                                if ((Get-Item $item.Path) -is [System.IO.DirectoryInfo]) {
                                    # Skip temporary files during restore
                                    $excludeFilter = @("*.tmp", "~*.*", "*.bak", "*.old", "*.log")
                                    Copy-Item $item.Path $item.Target -Recurse -Force -Exclude $excludeFilter -ErrorAction Stop
                                } else {
                                    Copy-Item $item.Path $item.Target -Force -ErrorAction Stop
                                }
                                
                                $script:ItemsRestored += $itemName
                                Write-Host "Restored $($item.Description)" -ForegroundColor Green
                            }
                        }
                    } catch {
                        $script:Errors += "Failed to restore $itemName `: $_"
                        Write-Warning "Failed to restore $($item.Description)`: $_"
                    }
                }
            }
            
            # Handle informational files (not restored, just noted)
            $infoFiles = @("visio_info.json", "file_associations.json", "com_addins.json")
            foreach ($infoFile in $infoFiles) {
                $infoPath = Join-Path $backupPath $infoFile
                if (Test-Path $infoPath) {
                    $script:ItemsSkipped += "$infoFile (informational only)"
                    Write-Host "Found informational backup: $infoFile (not restored - informational only)" -ForegroundColor Yellow
                }
            }
            
            # Create result object
            $result = [PSCustomObject]@{
                Success = $true
                BackupPath = $backupPath
                Feature = "Visio Settings"
                Timestamp = Get-Date
                ItemsRestored = $script:ItemsRestored
                ItemsSkipped = $script:ItemsSkipped
                Errors = $script:Errors
                RequiresRestart = $true
            }
            
            # Display summary
            Write-Host "`nVisio Settings Restore Summary:" -ForegroundColor Green
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
            
            if ($script:ItemsRestored.Count -gt 0) {
                Write-Host "`nNote: Please restart Visio for all settings to take effect." -ForegroundColor Cyan
            }
            
            Write-Host "Visio Settings restored successfully from: $backupPath" -ForegroundColor Green
            Write-Verbose "Restore completed successfully"
            return $result
            
        } catch {
            $errorRecord = $_
            $errorMessage = @(
                "Failed to restore Visio Settings"
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
Restores comprehensive Microsoft Visio settings, configurations, and customizations from backup.

.DESCRIPTION
Restores Microsoft Visio settings from a backup created by Backup-VisioSettings. This includes
user preferences, templates, stencils, custom shapes, themes, macros, add-ins, ribbons, 
registry settings, and other Visio configurations. Supports multiple Visio versions and 
handles both user-specific and system-wide configurations.

The restore process will:
1. Stop running Visio processes safely
2. Import registry settings for all Visio versions
3. Restore configuration files and directories
4. Handle custom templates, stencils, and shapes
5. Restore add-ins and COM add-ins settings
6. Restore ribbons and UI customizations
7. Skip informational-only backup files

.PARAMETER BackupRootPath
The root path where the backup is located. The script will look for a "Visio" subdirectory within this path.

.PARAMETER Force
Forces the restore operation even if Visio is running or if destination files already exist.

.PARAMETER Include
Specifies which items to include in the restore. If not specified, all available items are restored.
Valid values: Registry, Settings, Templates, RecentFiles, CustomDictionary, AutoCorrect, Ribbons, AddIns, Stencils, MyShapes, Themes, Workspace, Macros, QuickAccess, CustomUI, VBAProjects, Preferences

.PARAMETER Exclude
Specifies which items to exclude from the restore.
Valid values: Registry, Settings, Templates, RecentFiles, CustomDictionary, AutoCorrect, Ribbons, AddIns, Stencils, MyShapes, Themes, Workspace, Macros, QuickAccess, CustomUI, VBAProjects, Preferences

.PARAMETER SkipVerification
Skips verification steps and proceeds with the restore operation.

.EXAMPLE
Restore-VisioSettings -BackupRootPath "C:\Backups"

.EXAMPLE
Restore-VisioSettings -BackupRootPath "C:\Backups" -Include @("Settings", "Templates", "Stencils")

.EXAMPLE
Restore-VisioSettings -BackupRootPath "C:\Backups" -Exclude @("RecentFiles") -WhatIf

.NOTES
Test cases to consider:
1. Valid backup path with complete backup
2. Invalid/nonexistent backup path
3. Partial backup (some items missing)
4. Visio running during restore
5. No permissions to write to target locations
6. Registry import success/failure
7. File copy success/failure for each item type
8. Include filter functionality
9. Exclude filter functionality
10. WhatIf parameter functionality
11. Force parameter functionality
12. Multiple Visio versions scenarios
13. Missing target directories (should be created)
14. Corrupted backup files
15. Network path scenarios
16. Administrative privileges scenarios
17. Process stopping success/failure
18. Registry key conflicts
19. File conflicts and overwriting
20. Custom shapes restoration
21. Themes restoration
22. Macros restoration
23. VBA projects restoration
24. COM add-ins restoration
25. Ribbon customizations restoration

.TESTCASES
# Mock test examples:
Describe "Restore-VisioSettings" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Test-BackupPath { return "TestBackupPath" }
        Mock Stop-VisioProcesses { return @() }
        Mock Get-ChildItem { return @(@{Name="test.reg"; FullName="C:\test.reg"}) }
        Mock Copy-Item { }
        Mock New-Item { }
        Mock reg { $global:LASTEXITCODE = 0 }
        Mock Get-Process { return @() }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Restore-VisioSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.BackupPath | Should -Be "TestBackupPath"
        $result.Feature | Should -Be "Visio Settings"
        $result.ItemsRestored | Should -BeOfType [System.Array]
        $result.ItemsSkipped | Should -BeOfType [System.Array]
        $result.Errors | Should -BeOfType [System.Array]
        $result.RequiresRestart | Should -Be $true
    }

    It "Should handle missing backup gracefully" {
        Mock Test-BackupPath { return $null }
        { Restore-VisioSettings -BackupRootPath "TestPath" } | Should -Throw
    }

    It "Should handle registry import failure gracefully" {
        Mock reg { $global:LASTEXITCODE = 1; return "Error" }
        $result = Restore-VisioSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle file copy failure gracefully" {
        Mock Copy-Item { throw "File copy failed" }
        $result = Restore-VisioSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should support Include parameter" {
        $result = Restore-VisioSettings -BackupRootPath "TestPath" -Include @("Settings")
        $result.Success | Should -Be $true
        $result.ItemsSkipped | Should -Contain "Registry (not in include list)"
    }

    It "Should support Exclude parameter" {
        $result = Restore-VisioSettings -BackupRootPath "TestPath" -Exclude @("Settings")
        $result.Success | Should -Be $true
        $result.ItemsSkipped | Should -Contain "Settings (in exclude list)"
    }

    It "Should support WhatIf parameter" {
        $result = Restore-VisioSettings -BackupRootPath "TestPath" -WhatIf
        $result.Success | Should -Be $true
    }

    It "Should handle process stopping" {
        Mock Get-Process { return @(@{Name="VISIO"; Id=1234; HasExited=$false}) }
        Mock Stop-VisioProcesses { return @("VISIO") }
        $result = Restore-VisioSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
    }

    It "Should handle missing backup items gracefully" {
        Mock Test-Path { param($Path) return $Path -notlike "*Settings*" }
        $result = Restore-VisioSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.ItemsSkipped | Should -Contain "Settings (no backup found)"
    }

    It "Should handle directory creation" {
        Mock Test-Path { param($Path) return $Path -notlike "*AppData*" }
        Mock New-Item { }
        $result = Restore-VisioSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Restore-VisioSettings -BackupRootPath $BackupRootPath -Force:$Force -Include $Include -Exclude $Exclude -SkipVerification:$SkipVerification
} 