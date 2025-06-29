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

function Backup-OneNoteSettings {
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
            Write-Verbose "Starting backup of OneNote Settings..."
            Write-Host "Backing up OneNote Settings..." -ForegroundColor Blue
            
            # Validate inputs before proceeding
            if (!(Test-Path $BackupRootPath)) {
                throw [System.IO.DirectoryNotFoundException]"Backup root path not found: $BackupRootPath"
            }
            
            $backupPath = Initialize-BackupDirectory -Path "OneNote" -BackupType "OneNote Settings" -BackupRootPath $BackupRootPath
            
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

                # Export OneNote registry settings (cleaned up duplicates)
                $regPaths = @(
                    # OneNote 2016 registry settings
                    "HKCU\Software\Microsoft\Office\16.0\OneNote",
                    "HKLM\SOFTWARE\Microsoft\Office\16.0\OneNote",
                    # OneNote common settings
                    "HKCU\Software\Microsoft\Office\16.0\Common\OneNote",
                    # OneNote standalone settings
                    "HKCU\Software\Microsoft\OneNote",
                    "HKLM\SOFTWARE\Microsoft\OneNote",
                    # File associations
                    "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.one",
                    "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.onepkg",
                    # Office common settings that affect OneNote
                    "HKCU\Software\Microsoft\Office\Common\UserInfo",
                    "HKCU\Software\Microsoft\Office\16.0\Common\General"
                )

                foreach ($regPath in $regPaths) {
                    # Check if registry key exists before trying to export
                    $keyExists = $false
                    if ($regPath -match '^HKCU\\') {
                        $keyExists = Test-Path "Registry::HKEY_CURRENT_USER\$($regPath.Substring(5))"
                    } elseif ($regPath -match '^HKLM\\') {
                        $keyExists = Test-Path "Registry::HKEY_LOCAL_MACHINE\$($regPath.Substring(5))"
                    }
                    
                    if ($keyExists) {
                        $regFile = Join-Path $registryPath "$($regPath.Split('\')[-1]).reg"
                        if ($WhatIf) {
                            Write-Host "WhatIf: Would export registry key $regPath to $regFile"
                        } else {
                            try {
                                reg export $regPath $regFile /y 2>$null
                                $backedUpItems += "$($regPath.Split('\')[-1]).reg"
                            } catch {
                                $errors += "Failed to export $regPath : $_"
                            }
                        }
                    } else {
                        Write-Verbose "Registry key not found: $regPath"
                    }
                }

                # Backup OneNote configuration files
                $configPaths = @{
                    "AppData" = "$env:LOCALAPPDATA\Microsoft\OneNote"
                    "Settings" = "$env:APPDATA\Microsoft\OneNote"
                    "Templates" = "$env:APPDATA\Microsoft\Templates"
                    "RecentFiles" = "$env:APPDATA\Microsoft\Office\Recent"
                    "UWPSettings" = "$env:LOCALAPPDATA\Packages\Microsoft.Office.OneNote_8wekyb3d8bbwe\LocalState"
                }

                foreach ($config in $configPaths.GetEnumerator()) {
                    if (Test-Path $config.Value) {
                        $destPath = Join-Path $backupPath $config.Key
                        if ($WhatIf) {
                            Write-Host "WhatIf: Would copy configuration from $($config.Value) to $destPath"
                        } else {
                            try {
                                New-Item -ItemType Directory -Path $destPath -Force | Out-Null
                                # Skip temporary files and cache during backup
                                $excludeFilter = @("*.tmp", "~*.*", "*.log", "cache", "Cache")
                                Copy-Item -Path "$($config.Value)\*" -Destination $destPath -Recurse -Force -Exclude $excludeFilter
                                $backedUpItems += $config.Key
                            } catch {
                                $errors += "Failed to backup $($config.Key) : $_"
                            }
                        }
                    } else {
                        Write-Verbose "Configuration path not found: $($config.Value)"
                    }
                }

                # Export notebook list and locations
                $notebookListPath = "$env:APPDATA\Microsoft\OneNote\16.0\NotebookList.xml"
                if (Test-Path $notebookListPath) {
                    if ($WhatIf) {
                        Write-Host "WhatIf: Would export notebook locations to notebook_locations.xml"
                    } else {
                        try {
                            $notebookFile = Join-Path $backupPath "notebook_locations.xml"
                            Copy-Item -Path $notebookListPath -Destination $notebookFile -Force
                            $backedUpItems += "notebook_locations.xml"
                        } catch {
                            $errors += "Failed to backup notebook locations : $_"
                        }
                    }
                } else {
                    Write-Verbose "Notebook list not found at: $notebookListPath"
                }

                # Backup OneNote cache and sync settings
                $cachePath = "$env:LOCALAPPDATA\Microsoft\OneNote\16.0\cache"
                if (Test-Path $cachePath) {
                    if ($WhatIf) {
                        Write-Host "WhatIf: Would backup OneNote cache settings"
                    } else {
                        try {
                            $cacheDestPath = Join-Path $backupPath "Cache"
                            New-Item -ItemType Directory -Path $cacheDestPath -Force | Out-Null
                            # Only backup settings files, not actual cache data
                            Get-ChildItem -Path $cachePath -Filter "*.xml" | ForEach-Object {
                                Copy-Item -Path $_.FullName -Destination $cacheDestPath -Force
                            }
                            $backedUpItems += "Cache"
                        } catch {
                            $errors += "Failed to backup OneNote cache settings : $_"
                        }
                    }
                }
                
                # Return object for better testing and validation
                $result = [PSCustomObject]@{
                    Success = $true
                    BackupPath = $backupPath
                    Feature = "OneNote Settings"
                    Timestamp = Get-Date
                    Items = $backedUpItems
                    Errors = $errors
                }
                
                Write-Host "OneNote Settings backed up successfully to: $backupPath" -ForegroundColor Green
                Write-Verbose "Backup completed successfully"
                return $result
            }
            return $false
        } catch {
            $errorRecord = $_
            $errorMessage = @(
                "Failed to backup OneNote Settings"
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

<#
.SYNOPSIS
Backs up Microsoft OneNote settings and configuration.

.DESCRIPTION
Creates a backup of Microsoft OneNote settings, including registry settings, configuration files, templates,
notebook locations, recent files, and UWP app settings. Supports both OneNote 2016 and OneNote for Windows 10/11.

.PARAMETER BackupRootPath
The root path where the backup will be created. A subdirectory named "OneNote" will be created within this path.

.PARAMETER Force
Forces the backup operation even if the destination already exists.

.PARAMETER WhatIf
Shows what would be backed up without actually performing the backup operation.

.EXAMPLE
Backup-OneNoteSettings -BackupRootPath "C:\Backups"

.EXAMPLE
Backup-OneNoteSettings -BackupRootPath "C:\Backups" -WhatIf

.NOTES
Test cases to consider:
1. Valid backup path with proper permissions
2. Invalid/nonexistent backup path
3. Empty backup path
4. No permissions to write
5. Registry export success/failure for each key
6. Configuration file backup success/failure
7. Notebook list export success/failure
8. OneNote 2016 vs UWP app scenarios
9. Missing OneNote installation
10. Corrupted configuration files
11. Network path scenarios
12. Multiple user profiles
13. Template customizations
14. Add-in configurations
15. Sync settings and cache

.TESTCASES
# Mock test examples:
Describe "Backup-OneNoteSettings" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Initialize-BackupDirectory { return "TestPath" }
        Mock New-Item { }
        Mock reg { }
        Mock Get-Content { return "<notebooks><notebook path='test'/></notebooks>" }
        Mock Copy-Item { }
        Mock Get-ChildItem { return @(
            [PSCustomObject]@{ Name = "settings.xml"; FullName = "C:\cache\settings.xml" }
        )}
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Backup-OneNoteSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.BackupPath | Should -Be "TestPath"
        $result.Feature | Should -Be "OneNote Settings"
        $result.Items | Should -BeOfType [System.Array]
        $result.Errors | Should -BeOfType [System.Array]
    }

    It "Should handle registry export failure gracefully" {
        Mock reg { throw "Registry export failed" }
        $result = Backup-OneNoteSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle configuration file backup failure gracefully" {
        Mock Copy-Item { throw "File copy failed" }
        $result = Backup-OneNoteSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should support WhatIf parameter" {
        $result = Backup-OneNoteSettings -BackupRootPath "TestPath" -WhatIf
        $result.Success | Should -Be $true
    }

    It "Should handle missing OneNote installation gracefully" {
        Mock Test-Path { return $false }
        $result = Backup-OneNoteSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Items.Count | Should -Be 0
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Backup-OneNoteSettings -BackupRootPath $BackupRootPath
} 