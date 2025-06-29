[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$BackupRootPath = $null,
    
    [Parameter(Mandatory=$false)]
    [string]$MachineBackupPath = $null,
    
    [Parameter(Mandatory=$false)]
    [string]$SharedBackupPath = $null,
    
    [Parameter(Mandatory=$false)]
    [switch]$Force,

    # For testing purposes
    [Parameter(DontShow)]
    [switch]$WhatIf
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

# Set default paths if not provided
if (!$BackupRootPath) {
    $BackupRootPath = Join-Path $config.BackupRoot $config.MachineName
}
if (!$MachineBackupPath) {
    $MachineBackupPath = $BackupRootPath
}
if (!$SharedBackupPath) {
    $SharedBackupPath = Join-Path $config.BackupRoot "shared"
}

# Define Test-BackupPath function directly in the script
function Test-BackupPath {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Path,
        
        [Parameter(Mandatory=$true)]
        [string]$BackupType,
        
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath,
        
        [Parameter(Mandatory=$false)]
        [switch]$IsShared
    )
    
    $backupPath = Join-Path $BackupRootPath $Path
    if (Test-Path -Path $backupPath) {
        Write-Host "Found backup directory for $BackupType at: $backupPath" -ForegroundColor Green
        return $backupPath
    } else {
        Write-Host "Backup directory for $BackupType not found at: $backupPath" -ForegroundColor Yellow
        return $null
    }
}

function Restore-BrowserSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath,
        
        [Parameter(Mandatory=$true)]
        [string]$MachineBackupPath,
        
        [Parameter(Mandatory=$true)]
        [string]$SharedBackupPath,
        
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
            Write-Verbose "Starting restore of Browser Settings..."
            Write-Host "Restoring Browser Settings..." -ForegroundColor Blue
            
            # Validate inputs before proceeding
            if (!(Test-Path $BackupRootPath)) {
                throw [System.IO.DirectoryNotFoundException]"Backup root path not found: $BackupRootPath"
            }
            if (!(Test-Path $MachineBackupPath)) {
                throw [System.IO.DirectoryNotFoundException]"Machine backup path not found: $MachineBackupPath"
            }
            if (!(Test-Path $SharedBackupPath)) {
                throw [System.IO.DirectoryNotFoundException]"Shared backup path not found: $SharedBackupPath"
            }
            
            $backupPath = Test-BackupPath -Path "Browsers" -BackupType "Browser Settings" -BackupRootPath $MachineBackupPath
            $sharedBackupPath = Test-BackupPath -Path "Browsers" -BackupType "Shared Browser Settings" -BackupRootPath $SharedBackupPath -IsShared
            $restoredItems = @()
            $errors = @()
            
            # Use machine backup path as primary, fall back to shared if needed
            $primaryBackupPath = if ($backupPath) { $backupPath } elseif ($sharedBackupPath) { $sharedBackupPath } else { $null }
            
            if ($primaryBackupPath) {
                # Define browser profiles and their locations
                $browserProfiles = @{
                    "Chrome" = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default"
                    "Edge" = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default"
                    "Firefox" = "$env:APPDATA\Mozilla\Firefox\Profiles"
                    "Brave" = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default"
                    "Vivaldi" = "$env:LOCALAPPDATA\Vivaldi\User Data\Default"
                }

                # Define browser processes for stopping them before restore
                $browserProcesses = @{
                    "Chrome" = "chrome"
                    "Edge" = "msedge"
                    "Firefox" = "firefox"
                    "Brave" = "brave"
                    "Vivaldi" = "vivaldi"
                }

                # Stop browser processes before restore (for safety)
                foreach ($browser in $browserProcesses.GetEnumerator()) {
                    $browserBackupDir = Join-Path $primaryBackupPath $browser.Key
                    if (Test-Path $browserBackupDir) {
                        if ($WhatIf) {
                            Write-Host "WhatIf: Would stop $($browser.Key) processes"
                        } else {
                            try {
                                Stop-Process -Name $browser.Value -Force -ErrorAction SilentlyContinue
                                Write-Host "Stopped $($browser.Key) processes for safe restore" -ForegroundColor Yellow
                            } catch {
                                # Ignore errors if process isn't running
                            }
                        }
                    }
                }

                # Restore registry settings for each browser
                foreach ($browserName in $browserProfiles.Keys) {
                    $browserBackupDir = Join-Path $primaryBackupPath $browserName
                    if (Test-Path $browserBackupDir) {
                        Write-Host "Restoring $browserName settings..." -ForegroundColor Yellow
                        
                        # Import registry files
                        $regFiles = Get-ChildItem -Path "$browserBackupDir\*.reg" -ErrorAction SilentlyContinue
                        foreach ($regFile in $regFiles) {
                            if ($WhatIf) {
                                Write-Host "WhatIf: Would import registry file $($regFile.FullName)"
                            } else {
                                try {
                                    Write-Host "Importing registry settings for $browserName from $($regFile.Name)..." -ForegroundColor Yellow
                                    reg import $regFile.FullName /y 2>$null
                                    $restoredItems += "$browserName\$($regFile.Name)"
                                } catch {
                                    $errors += "Failed to import registry for $browserName from $($regFile.Name)`: $_"
                                    Write-Host "Warning: Failed to import registry for $browserName" -ForegroundColor Yellow
                                }
                            }
                        }

                        # Restore user data files
                        $userDataDir = Join-Path $browserBackupDir "UserData"
                        if (Test-Path $userDataDir) {
                            $targetDir = $browserProfiles[$browserName]
                            
                            # Create target directory if it doesn't exist
                            if ($WhatIf) {
                                Write-Host "WhatIf: Would ensure target directory exists: $targetDir"
                            } else {
                                $parentDir = Split-Path $targetDir -Parent
                                if (!(Test-Path $parentDir)) {
                                    New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
                                }
                                if (!(Test-Path $targetDir)) {
                                    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
                                }
                            }
                            
                            # Restore specific user data files
                            $userDataFiles = Get-ChildItem -Path $userDataDir -ErrorAction SilentlyContinue
                            foreach ($file in $userDataFiles) {
                                $targetPath = Join-Path $targetDir $file.Name
                                if ($WhatIf) {
                                    Write-Host "WhatIf: Would restore $($file.Name) to $targetPath"
                                } else {
                                    try {
                                        if ($file.PSIsContainer) {
                                            # Directory - copy recursively, excluding cache files
                                            $excludeFilter = @(
                                                "*.tmp", "~*.*", "Cache*", "*cache*",
                                                "*.ldb", "*.log", "*.old", "Crash Reports",
                                                "GPUCache", "Code Cache", "Service Worker"
                                            )
                                            Copy-Item -Path $file.FullName -Destination $targetPath -Recurse -Force -Exclude $excludeFilter
                                        } else {
                                            # File - copy directly
                                            Copy-Item -Path $file.FullName -Destination $targetPath -Force
                                        }
                                        $restoredItems += "$browserName\UserData\$($file.Name)"
                                        Write-Host "Restored $($file.Name) for $browserName" -ForegroundColor Green
                                    } catch {
                                        $errors += "Failed to restore $($file.Name) for $browserName`: $_"
                                        Write-Host "Warning: Failed to restore $($file.Name) for $browserName" -ForegroundColor Yellow
                                    }
                                }
                            }
                        }

                        # Restore browser-specific files that were backed up directly
                        $browserSpecificFiles = @("Bookmarks", "Preferences", "Favicons", "Extensions", "extensions.json")
                        foreach ($fileName in $browserSpecificFiles) {
                            $sourceFile = Join-Path $browserBackupDir $fileName
                            if (Test-Path $sourceFile) {
                                $targetPath = Join-Path $browserProfiles[$browserName] $fileName
                                if ($WhatIf) {
                                    Write-Host "WhatIf: Would restore $fileName to $targetPath"
                                } else {
                                    try {
                                        # Ensure target directory exists
                                        $targetDir = Split-Path $targetPath -Parent
                                        if (!(Test-Path $targetDir)) {
                                            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
                                        }
                                        
                                        if (Test-Path $sourceFile -PathType Container) {
                                            Copy-Item -Path $sourceFile -Destination $targetPath -Recurse -Force
                                        } else {
                                            Copy-Item -Path $sourceFile -Destination $targetPath -Force
                                        }
                                        $restoredItems += "$browserName\$fileName"
                                        Write-Host "Restored $fileName for $browserName" -ForegroundColor Green
                                    } catch {
                                        $errors += "Failed to restore $fileName for $browserName`: $_"
                                        Write-Host "Warning: Failed to restore $fileName for $browserName" -ForegroundColor Yellow
                                    }
                                }
                            }
                        }
                    }
                }

                # Special handling for Firefox profiles (since they have unique profile names)
                $firefoxBackupDir = Join-Path $primaryBackupPath "Firefox"
                if (Test-Path $firefoxBackupDir) {
                    Write-Host "Restoring Firefox profile-specific settings..." -ForegroundColor Yellow
                    
                    # Find the default Firefox profile directory
                    $firefoxProfilesPath = "$env:APPDATA\Mozilla\Firefox\Profiles"
                    if (Test-Path $firefoxProfilesPath) {
                        $defaultProfile = Get-ChildItem -Path $firefoxProfilesPath -Directory | Where-Object { $_.Name -like "*.default*" } | Select-Object -First 1
                        if ($defaultProfile) {
                            $firefoxFiles = @("bookmarkbackups", "prefs.js", "extensions.json", "extensions")
                            foreach ($fileName in $firefoxFiles) {
                                $sourceFile = Join-Path $firefoxBackupDir $fileName
                                if (Test-Path $sourceFile) {
                                    $targetPath = Join-Path $defaultProfile.FullName $fileName
                                    if ($WhatIf) {
                                        Write-Host "WhatIf: Would restore Firefox $fileName to $targetPath"
                                    } else {
                                        try {
                                            if (Test-Path $sourceFile -PathType Container) {
                                                Copy-Item -Path $sourceFile -Destination $targetPath -Recurse -Force
                                            } else {
                                                Copy-Item -Path $sourceFile -Destination $targetPath -Force
                                            }
                                            $restoredItems += "Firefox\$fileName"
                                            Write-Host "Restored Firefox $fileName" -ForegroundColor Green
                                        } catch {
                                            $errors += "Failed to restore Firefox $fileName`: $_"
                                            Write-Host "Warning: Failed to restore Firefox $fileName" -ForegroundColor Yellow
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                # Return object for better testing and validation
                $result = [PSCustomObject]@{
                    Success = $true
                    BackupPath = $primaryBackupPath
                    SharedBackupPath = $sharedBackupPath
                    Feature = "Browser Settings"
                    Timestamp = Get-Date
                    Items = $restoredItems
                    Errors = $errors
                }
                
                Write-Host "Browser Settings restored successfully from: $primaryBackupPath" -ForegroundColor Green
                if ($errors.Count -eq 0) {
                    Write-Host "`nNote: Browser restart may be required for settings to take effect" -ForegroundColor Yellow
                } else {
                    Write-Host "`nWarning: Some browser settings could not be restored. Check errors for details." -ForegroundColor Yellow
                }
                Write-Verbose "Restore completed successfully"
                return $result
            } else {
                throw "No backup found for Browser Settings in either machine or shared paths"
            }
        } catch {
            $errorRecord = $_
            $errorMessage = @(
                "Failed to restore Browser Settings"
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
    Export-ModuleMember -Function Restore-BrowserSettings
}

<#
.SYNOPSIS
Restores browser settings and configuration.

.DESCRIPTION
Restores browser settings from backup, including:
- Chrome, Edge, Firefox, Brave, and Vivaldi settings
- Registry settings for each browser
- Bookmarks, extensions, and preferences
- Browser profiles and user data
- Login data, history, and shortcuts
- Both machine-specific and shared settings

.EXAMPLE
Restore-BrowserSettings -BackupRootPath "C:\Backups" -MachineBackupPath "C:\Backups\Machine" -SharedBackupPath "C:\Backups\Shared"

.NOTES
Test cases to consider:
1. Valid backup paths with proper permissions
2. Invalid/nonexistent backup paths
3. Registry import success/failure
4. Browser profile restore success/failure
5. Browser processes running/stopped
6. Missing backup files
7. Partial restore scenarios
8. Firefox profile detection

.TESTCASES
# Mock test examples:
Describe "Restore-BrowserSettings" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Test-BackupPath { return "TestPath" }
        Mock Get-ChildItem { return @(
            [PSCustomObject]@{
                Name = "Chrome.reg"
                FullName = "TestPath\Chrome\Chrome.reg"
            }
        )}
        Mock reg { }
        Mock Stop-Process { }
        Mock Copy-Item { }
        Mock New-Item { }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Restore-BrowserSettings -BackupRootPath "TestPath" -MachineBackupPath "TestPath\Machine" -SharedBackupPath "TestPath\Shared"
        $result.Success | Should -Be $true
        $result.BackupPath | Should -Be "TestPath"
        $result.Feature | Should -Be "Browser Settings"
    }

    It "Should handle missing backup gracefully" {
        Mock Test-BackupPath { return $null }
        { Restore-BrowserSettings -BackupRootPath "TestPath" -MachineBackupPath "TestPath\Machine" -SharedBackupPath "TestPath\Shared" } | Should -Throw
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Restore-BrowserSettings -BackupRootPath $BackupRootPath -MachineBackupPath $MachineBackupPath -SharedBackupPath $SharedBackupPath
} 