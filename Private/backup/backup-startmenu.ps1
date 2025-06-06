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

# Define Initialize-BackupDirectory function directly in the script
function Initialize-BackupDirectory {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Path,
        
        [Parameter(Mandatory=$true)]
        [string]$BackupType,
        
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath
    )
    
    # Create machine-specific backup directory if it doesn't exist
    $backupPath = Join-Path $BackupRootPath $Path
    if (!(Test-Path -Path $backupPath)) {
        try {
            New-Item -ItemType Directory -Path $backupPath -Force | Out-Null
            Write-Host "Created backup directory for $BackupType at: $backupPath" -ForegroundColor Green
        } catch {
            Write-Host "Failed to create backup directory for $BackupType : $_" -ForegroundColor Red
            return $null
        }
    }
    
    return $backupPath
}

function Backup-StartMenuSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force,

        # For testing purposes
        [Parameter(DontShow)]
        [switch]$WhatIf
    )
    
    begin {
        # Test hook for mocking
        if ($script:TestMode) {
            Write-Verbose "Running in test mode"
        }
    }
    
    process {
        try {
            Write-Verbose "Starting backup of Start Menu Settings..."
            Write-Host "Backing up Start Menu Settings..." -ForegroundColor Blue
            
            # Validate inputs before proceeding
            if (!(Test-Path $BackupRootPath)) {
                throw [System.IO.DirectoryNotFoundException]"Backup root path not found: $BackupRootPath"
            }
            
            $backupPath = Initialize-BackupDirectory -Path "StartMenu" -BackupType "Start Menu Settings" -BackupRootPath $BackupRootPath
            
            if ($backupPath) {
                $backedUpItems = @()
                $errors = @()
                
                # Create registry backup directory
                $registryPath = Join-Path $backupPath "Registry"
                if ($WhatIf) {
                    Write-Host "WhatIf: Would create registry backup directory at $registryPath"
                } else {
                    New-Item -ItemType Directory -Force -Path $registryPath | Out-Null
                }

                # Registry paths for Start Menu settings
                $registryPaths = @(
                    # Start Menu layout and customization
                    "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced",
                    "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced",
                    "HKCU\Software\Microsoft\Windows\CurrentVersion\Start",
                    "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartPage",
                    
                    # Taskbar settings
                    "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband",
                    "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\TaskbarItemsCache",
                    "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3",
                    "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Streams\Desktop",
                    
                    # Jump Lists
                    "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\JumpLists",
                    
                    # Search settings
                    "HKCU\Software\Microsoft\Windows\CurrentVersion\Search",
                    "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Search",
                    
                    # Start Menu cloud store
                    "HKCU\Software\Microsoft\Windows\CurrentVersion\CloudStore\Store\Cache\DefaultAccount",
                    
                    # Recent documents
                    "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\RecentDocs",
                    
                    # Start Menu experience
                    "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\StartLayout",
                    "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartLayout"
                )

                # Export registry settings
                foreach ($path in $registryPaths) {
                    # Check if registry key exists before trying to export
                    $keyExists = $false
                    if ($path -match '^HKCU\\') {
                        $keyExists = Test-Path "Registry::HKEY_CURRENT_USER\$($path.Substring(5))"
                    } elseif ($path -match '^HKLM\\') {
                        $keyExists = Test-Path "Registry::HKEY_LOCAL_MACHINE\$($path.Substring(5))"
                    }
                    
                    if ($keyExists) {
                        $regFile = Join-Path $registryPath "$($path.Split('\')[-1]).reg"
                        if ($WhatIf) {
                            Write-Host "WhatIf: Would export registry key $path to $regFile"
                        } else {
                            try {
                                $result = reg export $path $regFile /y 2>&1
                                if ($LASTEXITCODE -eq 0) {
                                    $backedUpItems += "Registry\$($path.Split('\')[-1]).reg"
                                } else {
                                    $errors += "Could not export registry key: $path"
                                }
                            } catch {
                                $errors += "Failed to export registry key $path : $_"
                            }
                        }
                    } else {
                        Write-Verbose "Registry key not found: $path"
                    }
                }

                # Export Start Menu layout
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export Start Menu layout"
                } else {
                    try {
                        if (!$script:TestMode) {
                            Export-StartLayout -Path "$backupPath\startlayout.xml" -ErrorAction SilentlyContinue
                        }
                        $backedUpItems += "startlayout.xml"
                    } catch {
                        $errors += "Failed to export Start Menu layout: $_"
                    }
                }

                # Backup Start Menu folders
                $startMenuPaths = @{
                    "User" = "$env:APPDATA\Microsoft\Windows\Start Menu"
                    "AllUsers" = "$env:ProgramData\Microsoft\Windows\Start Menu"
                }

                foreach ($startMenu in $startMenuPaths.GetEnumerator()) {
                    if (Test-Path $startMenu.Value) {
                        $destPath = Join-Path $backupPath $startMenu.Key
                        if ($WhatIf) {
                            Write-Host "WhatIf: Would backup Start Menu $($startMenu.Key) from $($startMenu.Value)"
                        } else {
                            try {
                                New-Item -ItemType Directory -Path $destPath -Force | Out-Null
                                Copy-Item -Path "$($startMenu.Value)\*" -Destination $destPath -Recurse -Force
                                $backedUpItems += "Start Menu $($startMenu.Key)"
                            } catch {
                                $errors += "Failed to backup Start Menu $($startMenu.Key): $_"
                            }
                        }
                    } else {
                        Write-Verbose "Start Menu $($startMenu.Key) directory not found: $($startMenu.Value)"
                    }
                }

                # Export pinned items
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export pinned Start Menu items"
                } else {
                    try {
                        if (!$script:TestMode) {
                            $pinnedApps = (New-Object -Com Shell.Application).NameSpace("shell:::{4234d49b-0245-4df3-b780-3893943456e1}").Items()
                            $pinnedItems = $pinnedApps | Select-Object Name, Path
                            $pinnedItems | ConvertTo-Json | Out-File "$backupPath\pinned_items.json" -Force
                        }
                        $backedUpItems += "pinned_items.json"
                    } catch {
                        $errors += "Failed to export pinned Start Menu items: $_"
                    }
                }

                # Export taskbar settings
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export taskbar settings"
                } else {
                    try {
                        $taskbarSettings = @{}
                        
                        # Get taskbar position and settings
                        $taskbarKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3"
                        if (Test-Path $taskbarKey) {
                            $taskbarSettings.TaskbarData = Get-ItemProperty -Path $taskbarKey -Name Settings -ErrorAction SilentlyContinue | 
                                Select-Object Settings
                        }
                        
                        # Get toolbar data
                        $toolbarsPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Streams\Desktop"
                        if (Test-Path $toolbarsPath) {
                            $toolbars = Get-ChildItem $toolbarsPath -ErrorAction SilentlyContinue | 
                                Select-Object PSChildName, Property |
                                Where-Object { $_.Property }
                            
                            if ($toolbars) {
                                $taskbarSettings.Toolbars = $toolbars
                            }
                        }

                        # Get taskbar notification area settings
                        $notificationKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\TrayNotify"
                        if (Test-Path $notificationKey) {
                            $taskbarSettings.NotificationArea = Get-ItemProperty -Path $notificationKey -ErrorAction SilentlyContinue
                        }

                        if ($taskbarSettings.Count -gt 0) {
                            $taskbarSettings | ConvertTo-Json -Depth 10 | Out-File "$backupPath\taskbar_settings.json" -Force
                            $backedUpItems += "taskbar_settings.json"
                        }
                    } catch {
                        $errors += "Failed to export taskbar settings: $_"
                    }
                }

                # Export jump list customizations
                $jumpListPath = "$env:APPDATA\Microsoft\Windows\Recent\AutomaticDestinations"
                if (Test-Path $jumpListPath) {
                    $jumpListBackupPath = Join-Path $backupPath "JumpLists"
                    if ($WhatIf) {
                        Write-Host "WhatIf: Would backup jump lists from $jumpListPath"
                    } else {
                        try {
                            New-Item -ItemType Directory -Path $jumpListBackupPath -Force | Out-Null
                            Copy-Item -Path "$jumpListPath\*" -Destination $jumpListBackupPath -Force
                            $backedUpItems += "JumpLists"
                        } catch {
                            $errors += "Failed to backup jump lists: $_"
                        }
                    }
                }

                # Export Start Menu tiles data
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export Start Menu tiles data"
                } else {
                    try {
                        $tilesData = @{}
                        
                        # Get live tiles data
                        $liveTilesPath = "$env:LOCALAPPDATA\TileDataLayer\Database"
                        if (Test-Path $liveTilesPath) {
                            $tilesData.LiveTilesPath = $liveTilesPath
                        }
                        
                        # Get Start Menu cache
                        $startCachePath = "$env:LOCALAPPDATA\Microsoft\Windows\Caches"
                        if (Test-Path $startCachePath) {
                            $tilesData.StartCachePath = $startCachePath
                        }
                        
                        if ($tilesData.Count -gt 0) {
                            $tilesData | ConvertTo-Json -Depth 10 | Out-File "$backupPath\tiles_data.json" -Force
                            $backedUpItems += "tiles_data.json"
                        }
                    } catch {
                        $errors += "Failed to export Start Menu tiles data: $_"
                    }
                }

                # Export Start Menu search settings
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export Start Menu search settings"
                } else {
                    try {
                        $searchSettings = @{}
                        
                        # Get search indexer settings
                        $searchKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"
                        if (Test-Path $searchKey) {
                            $searchSettings.UserSettings = Get-ItemProperty -Path $searchKey -ErrorAction SilentlyContinue
                        }
                        
                        # Get Cortana settings
                        $cortanaKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search\Flighting"
                        if (Test-Path $cortanaKey) {
                            $searchSettings.CortanaSettings = Get-ItemProperty -Path $cortanaKey -ErrorAction SilentlyContinue
                        }
                        
                        if ($searchSettings.Count -gt 0) {
                            $searchSettings | ConvertTo-Json -Depth 10 | Out-File "$backupPath\search_settings.json" -Force
                            $backedUpItems += "search_settings.json"
                        }
                    } catch {
                        $errors += "Failed to export Start Menu search settings: $_"
                    }
                }
                
                # Return object for better testing and validation
                $result = [PSCustomObject]@{
                    Success = $true
                    BackupPath = $backupPath
                    Feature = "Start Menu Settings"
                    Timestamp = Get-Date
                    Items = $backedUpItems
                    Errors = $errors
                }
                
                Write-Host "Start Menu Settings backed up successfully to: $backupPath" -ForegroundColor Green
                Write-Verbose "Backup completed successfully"
                return $result
            }
            return $false
        } catch {
            $errorRecord = $_
            $errorMessage = @(
                "Failed to backup Start Menu Settings"
                "Error Message: $($errorRecord.Exception.Message)"
                "Error Type: $($errorRecord.Exception.GetType().FullName)"
                "Script Line Number: $($errorRecord.InvocationInfo.ScriptLineNumber)"
                "Script Name: $($errorRecord.InvocationInfo.ScriptName)"
                "Statement: $($errorRecord.InvocationInfo.Line.Trim())"
                if ($errorRecord.Exception.StackTrace) { "Stack Trace: $($errorRecord.Exception.StackTrace)" }
                if ($errorRecord.Exception.InnerException) { "Inner Exception: $($errorRecord.Exception.InnerException.Message)" }
            ) -join "`n"
            
            Write-Error $errorMessage
            Write-Verbose "Backup failed"
            throw  # Re-throw for proper error handling
        }
    }
}

# Export the function if being imported as a module
if ($MyInvocation.Line -eq "") {
    Export-ModuleMember -Function Backup-StartMenuSettings
}

<#
.SYNOPSIS
Backs up Start Menu settings, layout, taskbar configuration, and related customizations.

.DESCRIPTION
Creates a comprehensive backup of Start Menu-related settings including layout, pinned items, 
taskbar configuration, jump lists, search settings, tiles data, and both user-specific and 
system-wide Start Menu folders. Handles registry settings, file-based configurations, and 
COM object data with proper error handling.

.PARAMETER BackupRootPath
The root path where the backup will be created. A subdirectory named "StartMenu" will be created within this path.

.PARAMETER Force
Forces the backup operation even if the destination already exists.

.PARAMETER WhatIf
Shows what would be backed up without actually performing the backup operation.

.EXAMPLE
Backup-StartMenuSettings -BackupRootPath "C:\Backups"

.EXAMPLE
Backup-StartMenuSettings -BackupRootPath "C:\Backups" -WhatIf

.NOTES
Test cases to consider:
1. Valid backup path with proper permissions
2. Invalid/nonexistent backup path
3. Empty backup path
4. No permissions to write
5. Registry export success/failure for each key
6. Start Menu layout export success/failure
7. Start Menu folders backup success/failure
8. Pinned items export success/failure
9. Taskbar settings export success/failure
10. Jump lists backup success/failure
11. Tiles data export success/failure
12. Search settings export success/failure
13. COM object access failure
14. File access issues
15. Network path scenarios
16. Administrative privileges scenarios
17. Start Menu service availability
18. Windows version compatibility
19. Missing Start Menu components
20. Corrupted Start Menu data

.TESTCASES
# Mock test examples:
Describe "Backup-StartMenuSettings" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Initialize-BackupDirectory { return "TestPath" }
        Mock New-Item { }
        Mock Copy-Item { }
        Mock Export-StartLayout { }
        Mock Get-ItemProperty { return @{ Settings = "TestData" } }
        Mock Get-ChildItem { return @() }
        Mock ConvertTo-Json { return '{"test":"value"}' }
        Mock Out-File { }
        Mock reg { $global:LASTEXITCODE = 0 }
        Mock New-Object { 
            param($ComObject)
            if ($ComObject -eq "-Com Shell.Application") {
                return @{
                    NameSpace = { 
                        return @{
                            Items = { return @() }
                        }
                    }
                }
            }
        }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Backup-StartMenuSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.BackupPath | Should -Be "TestPath"
        $result.Feature | Should -Be "Start Menu Settings"
        $result.Items | Should -BeOfType [System.Array]
        $result.Errors | Should -BeOfType [System.Array]
    }

    It "Should handle registry export failure gracefully" {
        Mock reg { $global:LASTEXITCODE = 1; return "Error" }
        $result = Backup-StartMenuSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle Start Menu layout export failure gracefully" {
        Mock Export-StartLayout { throw "Layout export failed" }
        $result = Backup-StartMenuSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should support WhatIf parameter" {
        $result = Backup-StartMenuSettings -BackupRootPath "TestPath" -WhatIf
        $result.Success | Should -Be $true
    }

    It "Should handle pinned items export failure gracefully" {
        Mock New-Object { throw "COM object creation failed" }
        $result = Backup-StartMenuSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle taskbar settings export failure gracefully" {
        Mock Get-ItemProperty { throw "Registry access failed" }
        $result = Backup-StartMenuSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle Start Menu folders backup failure gracefully" {
        Mock Copy-Item { throw "File copy failed" }
        $result = Backup-StartMenuSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle missing Start Menu components gracefully" {
        Mock Test-Path { return $false }
        $result = Backup-StartMenuSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
    }

    It "Should handle jump lists backup failure gracefully" {
        Mock Copy-Item { param($Path) if ($Path -like "*JumpLists*") { throw "Jump lists backup failed" } }
        $result = Backup-StartMenuSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Backup-StartMenuSettings -BackupRootPath $BackupRootPath
} 