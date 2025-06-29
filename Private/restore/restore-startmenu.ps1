[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory=$false)]
    [string]$BackupRootPath = $null,
    
    [Parameter(Mandatory=$false)]
    [string]$MachineBackupPath = $null,
    
    [Parameter(Mandatory=$false)]
    [string]$SharedBackupPath = $null,
    
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
$config = Get-WindowsMissingRecovery
if (!$config.IsInitialized) {
    throw "Module not initialized. Please run Initialize-WindowsMissingRecovery first."
}

if (!$BackupRootPath) {
    $BackupRootPath = Join-Path $config.BackupRoot $config.MachineName
}

function Restore-StartMenuSettings {
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
        $itemsRestored = @()
        $itemsSkipped = @()
        $errors = @()
    }
    
    process {
        try {
            Write-Verbose "Starting restore of Start Menu Settings..."
            Write-Host "Restoring Start Menu Settings..." -ForegroundColor Blue
            
            # Validate inputs before proceeding
            if (!(Test-Path $BackupRootPath)) {
                throw [System.IO.DirectoryNotFoundException]"Backup root path not found: $BackupRootPath"
            }
            
            $backupPath = Join-Path $BackupRootPath "StartMenu"
            if (!(Test-Path $backupPath)) {
                throw [System.IO.DirectoryNotFoundException]"Start Menu backup not found at: $backupPath"
            }
            
            # Define all possible restore items
            $restoreItems = @{
                "Registry" = @{
                    Path = Join-Path $backupPath "Registry"
                    Description = "Start Menu registry settings"
                    Action = "Import-RegistryFiles"
                }
                "Layout" = @{
                    Path = Join-Path $backupPath "startlayout.xml"
                    Description = "Start Menu layout"
                    Action = "Import-StartLayout"
                }
                "UserStartMenu" = @{
                    Path = Join-Path $backupPath "User"
                    Description = "User Start Menu folders"
                    Action = "Restore-UserStartMenu"
                }
                "AllUsersStartMenu" = @{
                    Path = Join-Path $backupPath "AllUsers"
                    Description = "All Users Start Menu folders"
                    Action = "Restore-AllUsersStartMenu"
                }
                "PinnedItems" = @{
                    Path = Join-Path $backupPath "pinned_items.json"
                    Description = "Pinned Start Menu items"
                    Action = "Restore-PinnedItems"
                }
                "TaskbarSettings" = @{
                    Path = Join-Path $backupPath "taskbar_settings.json"
                    Description = "Taskbar settings"
                    Action = "Restore-TaskbarSettings"
                }
                "JumpLists" = @{
                    Path = Join-Path $backupPath "JumpLists"
                    Description = "Jump lists"
                    Action = "Restore-JumpLists"
                }
                "TilesData" = @{
                    Path = Join-Path $backupPath "tiles_data.json"
                    Description = "Start Menu tiles data"
                    Action = "Restore-TilesData"
                }
                "SearchSettings" = @{
                    Path = Join-Path $backupPath "search_settings.json"
                    Description = "Start Menu search settings"
                    Action = "Restore-SearchSettings"
                }
            }
            
            # Filter items based on Include/Exclude parameters
            $itemsToRestore = $restoreItems.GetEnumerator() | Where-Object {
                $itemName = $_.Key
                $shouldInclude = $true
                
                if ($Include.Count -gt 0) {
                    $shouldInclude = $Include -contains $itemName
                }
                
                if ($Exclude.Count -gt 0 -and $Exclude -contains $itemName) {
                    $shouldInclude = $false
                }
                
                return $shouldInclude
            }
            
            # Stop Explorer before making changes (if not in test mode)
            $explorerStopped = $false
            if (!$script:TestMode -and !$WhatIf) {
                try {
                    if ($PSCmdlet.ShouldProcess("Explorer", "Stop Process")) {
                        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
                        $explorerStopped = $true
                        Start-Sleep -Seconds 2
                        Write-Verbose "Stopped Explorer process"
                    }
                } catch {
                    Write-Verbose "Could not stop Explorer process: $_"
                }
            }
            
            # Process each restore item
            foreach ($item in $itemsToRestore) {
                $itemName = $item.Key
                $itemInfo = $item.Value
                $itemPath = $itemInfo.Path
                $itemDescription = $itemInfo.Description
                $itemAction = $itemInfo.Action
                
                try {
                    if (Test-Path $itemPath) {
                        if ($PSCmdlet.ShouldProcess($itemDescription, "Restore")) {
                            Write-Host "Restoring $itemDescription..." -ForegroundColor Yellow
                            
                            switch ($itemAction) {
                                "Import-RegistryFiles" {
                                    $regFiles = Get-ChildItem -Path $itemPath -Filter "*.reg" -ErrorAction SilentlyContinue
                                    foreach ($regFile in $regFiles) {
                                        try {
                                            if (!$script:TestMode) {
                                                reg import $regFile.FullName 2>$null
                                            }
                                            $itemsRestored += "Registry\$($regFile.Name)"
                                        } catch {
                                            $errors += "Failed to import registry file $($regFile.Name)`: $_"
                                            Write-Warning "Failed to import registry file $($regFile.Name)"
                                        }
                                    }
                                }
                                
                                "Import-StartLayout" {
                                    try {
                                        if (!$script:TestMode) {
                                            Import-StartLayout -LayoutPath $itemPath -MountPath $env:SystemDrive\ -ErrorAction SilentlyContinue
                                        }
                                        $itemsRestored += "Start Menu layout"
                                    } catch {
                                        $errors += "Failed to import Start Menu layout: $_"
                                    }
                                }
                                
                                "Restore-UserStartMenu" {
                                    $userStartMenuPath = "$env:APPDATA\Microsoft\Windows\Start Menu"
                                    
                                    # Create user Start Menu directory if it doesn't exist
                                    if (!(Test-Path $userStartMenuPath)) {
                                        if (!$script:TestMode) {
                                            New-Item -ItemType Directory -Path $userStartMenuPath -Force | Out-Null
                                        }
                                    }
                                    
                                    try {
                                        if (!$script:TestMode) {
                                            # Exclude temporary files during restore
                                            $excludeFilter = @("*.tmp", "~*.*", "*.bak", "*.old")
                                            Copy-Item -Path "$itemPath\*" -Destination $userStartMenuPath -Recurse -Force -Exclude $excludeFilter
                                        }
                                        $itemsRestored += "User Start Menu folders"
                                    } catch {
                                        $errors += "Failed to restore user Start Menu folders: $_"
                                    }
                                }
                                
                                "Restore-AllUsersStartMenu" {
                                    $allUsersStartMenuPath = "$env:ProgramData\Microsoft\Windows\Start Menu"
                                    
                                    # Create All Users Start Menu directory if it doesn't exist
                                    if (!(Test-Path $allUsersStartMenuPath)) {
                                        if (!$script:TestMode) {
                                            New-Item -ItemType Directory -Path $allUsersStartMenuPath -Force | Out-Null
                                        }
                                    }
                                    
                                    try {
                                        if (!$script:TestMode) {
                                            # Exclude temporary files during restore
                                            $excludeFilter = @("*.tmp", "~*.*", "*.bak", "*.old")
                                            Copy-Item -Path "$itemPath\*" -Destination $allUsersStartMenuPath -Recurse -Force -Exclude $excludeFilter
                                        }
                                        $itemsRestored += "All Users Start Menu folders"
                                    } catch {
                                        $errors += "Failed to restore All Users Start Menu folders: $_"
                                    }
                                }
                                
                                "Restore-PinnedItems" {
                                    try {
                                        $pinnedItems = Get-Content $itemPath | ConvertFrom-Json
                                        
                                        if (!$script:TestMode) {
                                            foreach ($item in $pinnedItems) {
                                                try {
                                                    if (Test-Path $item.Path) {
                                                        $shell = New-Object -ComObject Shell.Application
                                                        $folder = $shell.Namespace([System.IO.Path]::GetDirectoryName($item.Path))
                                                        $file = $folder.ParseName([System.IO.Path]::GetFileName($item.Path))
                                                        $verb = $file.Verbs() | Where-Object { $_.Name -eq "Pin to Start" }
                                                        if ($verb) { 
                                                            $verb.DoIt() 
                                                            Write-Verbose "Pinned item: $($item.Name)"
                                                        }
                                                    }
                                                } catch {
                                                    Write-Verbose "Could not pin item $($item.Name): $_"
                                                }
                                            }
                                        }
                                        $itemsRestored += "Pinned Start Menu items"
                                    } catch {
                                        $errors += "Failed to restore pinned Start Menu items: $_"
                                    }
                                }
                                
                                "Restore-TaskbarSettings" {
                                    try {
                                        $taskbarSettings = Get-Content $itemPath | ConvertFrom-Json
                                        
                                        if (!$script:TestMode) {
                                            # Restore taskbar position and settings
                                            if ($taskbarSettings.TaskbarData -and $taskbarSettings.TaskbarData.Settings) {
                                                try {
                                                    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3" `
                                                        -Name Settings -Value $taskbarSettings.TaskbarData.Settings -ErrorAction SilentlyContinue
                                                } catch {
                                                    Write-Verbose "Could not restore taskbar position settings: $_"
                                                }
                                            }
                                            
                                            # Restore taskbar toolbars
                                            if ($taskbarSettings.Toolbars) {
                                                foreach ($toolbar in $taskbarSettings.Toolbars) {
                                                    try {
                                                        $toolbarPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Streams\Desktop\$($toolbar.PSChildName)"
                                                        New-Item -Path $toolbarPath -Force -ErrorAction SilentlyContinue | Out-Null
                                                        if ($toolbar.Property) {
                                                            Set-ItemProperty -Path $toolbarPath -Name $toolbar.Property.Name -Value $toolbar.Property.Value -ErrorAction SilentlyContinue
                                                        }
                                                    } catch {
                                                        Write-Verbose "Could not restore toolbar $($toolbar.PSChildName): $_"
                                                    }
                                                }
                                            }
                                            
                                            # Restore notification area settings
                                            if ($taskbarSettings.NotificationArea) {
                                                try {
                                                    $notificationPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\TrayNotify"
                                                    foreach ($property in $taskbarSettings.NotificationArea.PSObject.Properties) {
                                                        if ($property.Name -ne "PSPath" -and $property.Name -ne "PSParentPath" -and $property.Name -ne "PSChildName") {
                                                            Set-ItemProperty -Path $notificationPath -Name $property.Name -Value $property.Value -ErrorAction SilentlyContinue
                                                        }
                                                    }
                                                } catch {
                                                    Write-Verbose "Could not restore notification area settings: $_"
                                                }
                                            }
                                        }
                                        $itemsRestored += "Taskbar settings"
                                    } catch {
                                        $errors += "Failed to restore taskbar settings: $_"
                                    }
                                }
                                
                                "Restore-JumpLists" {
                                    $jumpListDestPath = "$env:APPDATA\Microsoft\Windows\Recent\AutomaticDestinations"
                                    
                                    # Create jump list directory if it doesn't exist
                                    if (!(Test-Path $jumpListDestPath)) {
                                        if (!$script:TestMode) {
                                            New-Item -ItemType Directory -Path $jumpListDestPath -Force | Out-Null
                                        }
                                    }
                                    
                                    try {
                                        if (!$script:TestMode) {
                                            Copy-Item -Path "$itemPath\*" -Destination $jumpListDestPath -Force
                                        }
                                        $itemsRestored += "Jump lists"
                                    } catch {
                                        $errors += "Failed to restore jump lists: $_"
                                    }
                                }
                                
                                "Restore-TilesData" {
                                    try {
                                        $tilesData = Get-Content $itemPath | ConvertFrom-Json
                                        
                                        # This is primarily informational as tiles data is complex to restore
                                        if ($tilesData.LiveTilesPath) {
                                            Write-Verbose "Live tiles data was backed up from: $($tilesData.LiveTilesPath)"
                                        }
                                        if ($tilesData.StartCachePath) {
                                            Write-Verbose "Start cache data was backed up from: $($tilesData.StartCachePath)"
                                        }
                                        
                                        $itemsRestored += "Start Menu tiles data (informational)"
                                    } catch {
                                        $errors += "Failed to restore Start Menu tiles data: $_"
                                    }
                                }
                                
                                "Restore-SearchSettings" {
                                    try {
                                        $searchSettings = Get-Content $itemPath | ConvertFrom-Json
                                        
                                        if (!$script:TestMode) {
                                            # Restore user search settings
                                            if ($searchSettings.UserSettings) {
                                                try {
                                                    $searchPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"
                                                    foreach ($property in $searchSettings.UserSettings.PSObject.Properties) {
                                                        if ($property.Name -ne "PSPath" -and $property.Name -ne "PSParentPath" -and $property.Name -ne "PSChildName") {
                                                            Set-ItemProperty -Path $searchPath -Name $property.Name -Value $property.Value -ErrorAction SilentlyContinue
                                                        }
                                                    }
                                                } catch {
                                                    Write-Verbose "Could not restore user search settings: $_"
                                                }
                                            }
                                            
                                            # Restore Cortana settings
                                            if ($searchSettings.CortanaSettings) {
                                                try {
                                                    $cortanaPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search\Flighting"
                                                    if (!(Test-Path $cortanaPath)) {
                                                        New-Item -Path $cortanaPath -Force | Out-Null
                                                    }
                                                    foreach ($property in $searchSettings.CortanaSettings.PSObject.Properties) {
                                                        if ($property.Name -ne "PSPath" -and $property.Name -ne "PSParentPath" -and $property.Name -ne "PSChildName") {
                                                            Set-ItemProperty -Path $cortanaPath -Name $property.Name -Value $property.Value -ErrorAction SilentlyContinue
                                                        }
                                                    }
                                                } catch {
                                                    Write-Verbose "Could not restore Cortana settings: $_"
                                                }
                                            }
                                        }
                                        $itemsRestored += "Start Menu search settings"
                                    } catch {
                                        $errors += "Failed to restore Start Menu search settings: $_"
                                    }
                                }
                            }
                            
                            Write-Host "Restored $itemDescription" -ForegroundColor Green
                        }
                    } else {
                        $itemsSkipped += "$itemDescription (not found in backup)"
                        Write-Verbose "Skipped $itemDescription - not found in backup"
                    }
                } catch {
                    $errors += "Failed to restore $itemDescription : $_"
                    Write-Warning "Failed to restore $itemDescription : $_"
                }
            }
            
            # Restart Explorer if we stopped it
            if ($explorerStopped -and !$script:TestMode -and !$WhatIf) {
                try {
                    if ($PSCmdlet.ShouldProcess("Explorer", "Start Process")) {
                        Start-Process explorer
                        Write-Verbose "Restarted Explorer process"
                    }
                } catch {
                    Write-Verbose "Could not restart Explorer process: $_"
                }
            }
            
            # Restart Start Menu related services if needed
            if (!$script:TestMode -and !$WhatIf) {
                $startMenuServices = @("ShellExperienceHost", "StartMenuExperienceHost")
                foreach ($serviceName in $startMenuServices) {
                    try {
                        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
                        if ($service -and $service.Status -ne "Running") {
                            if ($PSCmdlet.ShouldProcess($serviceName, "Start Service")) {
                                Start-Service -Name $serviceName -ErrorAction SilentlyContinue
                                Write-Verbose "Started service: $serviceName"
                            }
                        }
                    } catch {
                        Write-Verbose "Could not start service $serviceName : $_"
                    }
                }
            }
            
            # Return result object
            $result = [PSCustomObject]@{
                Success = $true
                BackupPath = $backupPath
                Feature = "Start Menu Settings"
                Timestamp = Get-Date
                ItemsRestored = $itemsRestored
                ItemsSkipped = $itemsSkipped
                Errors = $errors
            }
            
            Write-Host "Start Menu Settings restored successfully from: $backupPath" -ForegroundColor Green
            Write-Verbose "Restore completed successfully"
            return $result
            
        } catch {
            $errorRecord = $_
            $errorMessage = @(
                "Failed to restore Start Menu Settings"
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

# Export the function if being imported as a module
if ($MyInvocation.Line -eq "") {
    Export-ModuleMember -Function Restore-StartMenuSettings
}

<#
.SYNOPSIS
Restores Start Menu settings, layout, taskbar configuration, and related customizations from backup.

.DESCRIPTION
Restores a comprehensive backup of Start Menu-related settings including layout, pinned items, 
taskbar configuration, jump lists, search settings, tiles data, and both user-specific and 
system-wide Start Menu folders. Handles registry settings, file-based configurations, and 
COM object data with proper error handling and Explorer process management.

.PARAMETER BackupRootPath
The root path where the backup is located. The script will look for a "StartMenu" subdirectory within this path.

.PARAMETER Force
Forces the restore operation even if it might overwrite existing settings.

.PARAMETER Include
Specifies which components to restore. Valid values: Registry, Layout, UserStartMenu, AllUsersStartMenu, PinnedItems, TaskbarSettings, JumpLists, TilesData, SearchSettings.

.PARAMETER Exclude
Specifies which components to exclude from restoration. Valid values: Registry, Layout, UserStartMenu, AllUsersStartMenu, PinnedItems, TaskbarSettings, JumpLists, TilesData, SearchSettings.

.PARAMETER SkipVerification
Skips verification steps during the restore process.

.PARAMETER WhatIf
Shows what would be restored without actually performing the restore operation.

.EXAMPLE
Restore-StartMenuSettings -BackupRootPath "C:\Backups"

.EXAMPLE
Restore-StartMenuSettings -BackupRootPath "C:\Backups" -Include @("Registry", "Layout")

.EXAMPLE
Restore-StartMenuSettings -BackupRootPath "C:\Backups" -Exclude @("TilesData") -WhatIf

.NOTES
Test cases to consider:
1. Valid backup path with all components
2. Invalid/nonexistent backup path
3. Partial backup (missing some components)
4. Registry import success/failure
5. Start Menu layout import success/failure
6. Start Menu folders restore success/failure
7. Pinned items restore success/failure
8. Taskbar settings restore success/failure
9. Jump lists restore success/failure
10. Tiles data restore success/failure
11. Search settings restore success/failure
12. Include parameter filtering
13. Exclude parameter filtering
14. Explorer process management
15. Start Menu service management
16. COM object access failure
17. Administrative privileges scenarios
18. Network path scenarios
19. File permission issues
20. Test mode scenarios

.TESTCASES
# Mock test examples:
Describe "Restore-StartMenuSettings" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Join-Path { return "TestPath" }
        Mock Get-ChildItem { 
            param($Path, $Filter)
            if ($Filter -eq "*.reg") {
                return @([PSCustomObject]@{ FullName = "test.reg"; Name = "test.reg" })
            } else {
                return @()
            }
        }
        Mock Get-Content { return '{"test":"value"}' | ConvertFrom-Json }
        Mock New-Item { }
        Mock Copy-Item { }
        Mock Set-ItemProperty { }
        Mock Get-Service { return @{ Status = "Stopped" } }
        Mock Start-Service { }
        Mock Stop-Process { }
        Mock Start-Process { }
        Mock Import-StartLayout { }
        Mock New-Object { 
            param($ComObject)
            if ($ComObject -eq "-ComObject Shell.Application") {
                return @{
                    Namespace = { return @{ ParseName = { return @{ Verbs = { return @() } } } } }
                }
            }
        }
        Mock reg { }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Restore-StartMenuSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.BackupPath | Should -Be "TestPath"
        $result.Feature | Should -Be "Start Menu Settings"
        $result.ItemsRestored | Should -BeOfType [System.Array]
        $result.ItemsSkipped | Should -BeOfType [System.Array]
        $result.Errors | Should -BeOfType [System.Array]
    }

    It "Should handle registry import failure gracefully" {
        Mock reg { throw "Registry import failed" }
        $result = Restore-StartMenuSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle Start Menu layout import failure gracefully" {
        Mock Import-StartLayout { throw "Layout import failed" }
        $result = Restore-StartMenuSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should support Include parameter" {
        $result = Restore-StartMenuSettings -BackupRootPath "TestPath" -Include @("Registry")
        $result.Success | Should -Be $true
    }

    It "Should support Exclude parameter" {
        $result = Restore-StartMenuSettings -BackupRootPath "TestPath" -Exclude @("TilesData")
        $result.Success | Should -Be $true
    }

    It "Should handle Explorer process management failure gracefully" {
        Mock Stop-Process { throw "Process stop failed" }
        Mock Start-Process { throw "Process start failed" }
        $result = Restore-StartMenuSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
    }

    It "Should handle missing backup components gracefully" {
        Mock Test-Path { param($Path) return $Path -notlike "*Layout*" }
        $result = Restore-StartMenuSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.ItemsSkipped.Count | Should -BeGreaterThan 0
    }

    It "Should support WhatIf parameter" {
        $result = Restore-StartMenuSettings -BackupRootPath "TestPath" -WhatIf
        $result.Success | Should -Be $true
    }

    It "Should handle pinned items restore failure gracefully" {
        Mock New-Object { throw "COM object creation failed" }
        $result = Restore-StartMenuSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Restore-StartMenuSettings -BackupRootPath $BackupRootPath -Force:$Force -Include $Include -Exclude $Exclude -SkipVerification:$SkipVerification
} 