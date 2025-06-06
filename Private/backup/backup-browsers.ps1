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

# Define Initialize-BackupDirectory function directly in the script
function Initialize-BackupDirectory {
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
    
    # Create backup directory if it doesn't exist
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

function Backup-BrowserSettings {
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
            Write-Verbose "Starting backup of Browser Settings..."
            Write-Host "Backing up Browser Settings..." -ForegroundColor Blue
            
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
            
            $backupPath = Initialize-BackupDirectory -Path "Browsers" -BackupType "Browser Settings" -BackupRootPath $MachineBackupPath
            $sharedBackupPath = Initialize-BackupDirectory -Path "Browsers" -BackupType "Shared Browser Settings" -BackupRootPath $SharedBackupPath -IsShared
            $backedUpItems = @()
            $errors = @()
            
            if ($backupPath -and $sharedBackupPath) {
                # Define browser profiles
                $browserProfiles = @{
                    "Chrome" = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default"
                    "Edge" = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default"
                    "Firefox" = "$env:APPDATA\Mozilla\Firefox\Profiles"
                    "Brave" = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default"
                    "Vivaldi" = "$env:LOCALAPPDATA\Vivaldi\User Data\Default"
                }

                foreach ($browser in $browserProfiles.GetEnumerator()) {
                    if (Test-Path $browser.Value) {
                        Write-Host "Backing up $($browser.Key) settings..." -ForegroundColor Yellow
                        
                        # Create browser-specific backup directories
                        $browserBackupPath = Join-Path $backupPath $browser.Key
                        $browserSharedBackupPath = Join-Path $sharedBackupPath $browser.Key
                        
                        if ($WhatIf) {
                            Write-Host "WhatIf: Would create directories: $browserBackupPath and $browserSharedBackupPath"
                        } else {
                            New-Item -ItemType Directory -Force -Path $browserBackupPath | Out-Null
                            New-Item -ItemType Directory -Force -Path $browserSharedBackupPath | Out-Null
                        }
                        
                        switch ($browser.Key) {
                            { $_ -in "Chrome", "Edge", "Brave", "Vivaldi" } {
                                # Backup Chromium-based browser settings
                                $filesToCopy = @("Bookmarks", "Preferences", "Favicons", "Extensions")
                                foreach ($file in $filesToCopy) {
                                    $sourcePath = "$($browser.Value)\$file"
                                    if (Test-Path $sourcePath) {
                                        if ($WhatIf) {
                                            Write-Host "WhatIf: Would copy $sourcePath to $browserBackupPath"
                                        } else {
                                            Copy-Item $sourcePath $browserBackupPath -ErrorAction SilentlyContinue
                                            $backedUpItems += "$($browser.Key)\$file"
                                        }
                                    }
                                }
                                
                                # Export extensions list
                                if (Test-Path "$($browser.Value)\Extensions") {
                                    if ($WhatIf) {
                                        Write-Host "WhatIf: Would export extensions list to $browserBackupPath\extensions.json"
                                    } else {
                                        $extensions = Get-ChildItem "$($browser.Value)\Extensions" -ErrorAction SilentlyContinue |
                                            Select-Object Name, LastWriteTime
                                        $extensions | ConvertTo-Json | Out-File "$browserBackupPath\extensions.json" -Force
                                        $backedUpItems += "$($browser.Key)\extensions.json"
                                    }
                                }
                            }
                            "Firefox" {
                                # Backup Firefox settings
                                Get-ChildItem "$($browser.Value)\*.default*" -ErrorAction SilentlyContinue | ForEach-Object {
                                    $filesToCopy = @("bookmarkbackups", "prefs.js", "extensions.json", "extensions")
                                    foreach ($file in $filesToCopy) {
                                        $sourcePath = "$($_.FullName)\$file"
                                        if (Test-Path $sourcePath) {
                                            if ($WhatIf) {
                                                Write-Host "WhatIf: Would copy $sourcePath to $browserBackupPath"
                                            } else {
                                                Copy-Item $sourcePath $browserBackupPath -ErrorAction SilentlyContinue
                                                $backedUpItems += "$($browser.Key)\$file"
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                # Export browser registry settings
                $regPaths = @{
                    Chrome = @(
                        "HKCU\Software\Google\Chrome",
                        "HKLM\SOFTWARE\Google\Chrome",
                        "HKLM\SOFTWARE\Policies\Google\Chrome"
                    )
                    Edge = @(
                        "HKCU\Software\Microsoft\Edge",
                        "HKLM\SOFTWARE\Microsoft\Edge",
                        "HKLM\SOFTWARE\Policies\Microsoft\Edge"
                    )
                    Vivaldi = @(
                        "HKCU\Software\Vivaldi",
                        "HKLM\SOFTWARE\Vivaldi"
                    )
                    Firefox = @(
                        "HKCU\Software\Mozilla",
                        "HKLM\SOFTWARE\Mozilla",
                        "HKLM\SOFTWARE\Policies\Mozilla"
                    )
                    Brave = @(
                        "HKCU\Software\BraveSoftware",
                        "HKLM\SOFTWARE\BraveSoftware",
                        "HKLM\SOFTWARE\Policies\BraveSoftware"
                    )
                }

                # Add Firefox and Brave to browser data paths
                $browserData = @{
                    Chrome = "$env:LOCALAPPDATA\Google\Chrome\User Data"
                    Edge = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"
                    Vivaldi = "$env:LOCALAPPDATA\Vivaldi\User Data"
                    Firefox = "$env:APPDATA\Mozilla\Firefox\Profiles"
                    Brave = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data"
                }

                foreach ($browser in $regPaths.Keys) {
                    Write-Host "Backing up $browser settings..." -ForegroundColor Blue
                    $browserPath = Join-Path $backupPath $browser
                    $browserSharedPath = Join-Path $sharedBackupPath $browser
                    
                    if ($WhatIf) {
                        Write-Host "WhatIf: Would create directories: $browserPath and $browserSharedPath"
                    } else {
                        New-Item -ItemType Directory -Path $browserPath -Force | Out-Null
                        New-Item -ItemType Directory -Path $browserSharedPath -Force | Out-Null
                    }

                    foreach ($regPath in $regPaths[$browser]) {
                        # Check if registry key exists before trying to export
                        $keyExists = $false
                        if ($regPath -match '^HKCU\\') {
                            $keyExists = Test-Path "Registry::HKEY_CURRENT_USER\$($regPath.Substring(5))"
                        } elseif ($regPath -match '^HKLM\\') {
                            $keyExists = Test-Path "Registry::HKEY_LOCAL_MACHINE\$($regPath.Substring(5))"
                        }
                        
                        if ($keyExists) {
                            try {
                                $regFile = "$browserPath\$($regPath.Split('\')[-1]).reg"
                                $sharedRegFile = "$browserSharedPath\$($regPath.Split('\')[-1]).reg"
                                if ($WhatIf) {
                                    Write-Host "WhatIf: Would export registry key: $regPath to $regFile and $sharedRegFile"
                                } else {
                                    $result = reg export $regPath $regFile /y 2>&1
                                    if ($LASTEXITCODE -eq 0) {
                                        Copy-Item $regFile $sharedRegFile -Force
                                        $backedUpItems += "$browser\$($regPath.Split('\')[-1]).reg"
                                    } else {
                                        $errors += "Could not export registry key: $regPath"
                                    }
                                }
                            } catch {
                                $errors += "Failed to export registry key: $regPath - $($_.Exception.Message)"
                            }
                        }
                    }

                    # Backup browser profiles and data
                    if (Test-Path $browserData[$browser]) {
                        # Export bookmarks, extensions, and preferences
                        $dataPath = Join-Path $browserPath "UserData"
                        $sharedDataPath = Join-Path $browserSharedPath "UserData"
                        
                        if ($WhatIf) {
                            Write-Host "WhatIf: Would create directories: $dataPath and $sharedDataPath"
                        } else {
                            New-Item -ItemType Directory -Path $dataPath -Force | Out-Null
                            New-Item -ItemType Directory -Path $sharedDataPath -Force | Out-Null
                        }

                        # Copy specific files instead of entire profile
                        $filesToCopy = @(
                            "Bookmarks",
                            "Preferences",
                            "Extensions",
                            "Favicons",
                            "History",
                            "Login Data",
                            "Shortcuts",
                            "Top Sites"
                        )

                        foreach ($file in $filesToCopy) {
                            $sourcePath = Join-Path $browserData[$browser] "Default\$file"
                            if (Test-Path $sourcePath) {
                                if ($WhatIf) {
                                    Write-Host "WhatIf: Would copy $sourcePath to $dataPath\$file and $sharedDataPath\$file"
                                } else {
                                    Copy-Item -Path $sourcePath -Destination "$dataPath\$file" -Force
                                    Copy-Item -Path $sourcePath -Destination "$sharedDataPath\$file" -Force
                                    $backedUpItems += "$browser\UserData\$file"
                                }
                            }
                        }
                    }
                }

                # Return object for better testing and validation
                $result = [PSCustomObject]@{
                    Success = $true
                    BackupPath = $backupPath
                    SharedBackupPath = $sharedBackupPath
                    Feature = "Browser Settings"
                    Timestamp = Get-Date
                    Items = $backedUpItems
                    Errors = $errors
                }
                
                Write-Host "Browser Settings backed up successfully to: $backupPath" -ForegroundColor Green
                Write-Host "Shared Browser Settings backed up successfully to: $sharedBackupPath" -ForegroundColor Green
                Write-Verbose "Backup completed successfully"
                return $result
            }
            return $false
        } catch {
            $errorRecord = $_
            $errorMessage = @(
                "Failed to backup Browser Settings"
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
    Export-ModuleMember -Function Backup-BrowserSettings
}

<#
.SYNOPSIS
Backs up browser settings and configuration.

.DESCRIPTION
Creates a backup of browser settings including:
- Chrome, Edge, Firefox, Brave, and Vivaldi settings
- Bookmarks, extensions, and preferences
- Browser profiles and data
- Registry settings for each browser
- Both machine-specific and shared settings

.EXAMPLE
Backup-BrowserSettings -BackupRootPath "C:\Backups" -MachineBackupPath "C:\Backups\Machine" -SharedBackupPath "C:\Backups\Shared"

.NOTES
Test cases to consider:
1. Valid backup paths with proper permissions
2. Invalid/nonexistent backup paths
3. Empty backup paths
4. No permissions to write
5. Browser profiles exist/don't exist
6. Registry keys exist/don't exist
7. Browser data paths exist/don't exist

.TESTCASES
# Mock test examples:
Describe "Backup-BrowserSettings" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Initialize-BackupDirectory { return "TestPath" }
        Mock Copy-Item { }
        Mock Get-ChildItem { return @() }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Backup-BrowserSettings -BackupRootPath "TestPath" -MachineBackupPath "TestPath\Machine" -SharedBackupPath "TestPath\Shared"
        $result.Success | Should -Be $true
        $result.BackupPath | Should -Be "TestPath"
        $result.SharedBackupPath | Should -Be "TestPath\Shared"
        $result.Feature | Should -Be "Browser Settings"
    }

    It "Should handle missing browser profiles gracefully" {
        Mock Test-Path { return $false }
        $result = Backup-BrowserSettings -BackupRootPath "TestPath" -MachineBackupPath "TestPath\Machine" -SharedBackupPath "TestPath\Shared"
        $result.Success | Should -Be $true
        $result.Items.Count | Should -Be 0
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Backup-BrowserSettings -BackupRootPath $BackupRootPath -MachineBackupPath $MachineBackupPath -SharedBackupPath $SharedBackupPath
} 