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

function Restore-DefaultAppsSettings {
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
            Write-Verbose "Starting restore of Default Apps Settings..."
            Write-Host "Restoring Default Apps Settings..." -ForegroundColor Blue
            
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
            
            $backupPath = Test-BackupPath -Path "DefaultApps" -BackupType "Default Apps Settings" -BackupRootPath $MachineBackupPath
            $sharedBackupPath = Test-BackupPath -Path "DefaultApps" -BackupType "Shared Default Apps Settings" -BackupRootPath $SharedBackupPath -IsShared
            $restoredItems = @()
            $errors = @()
            
            # Use machine backup path as primary, fall back to shared if needed
            $primaryBackupPath = if ($backupPath) { $backupPath } elseif ($sharedBackupPath) { $sharedBackupPath } else { $null }
            
            if ($primaryBackupPath) {
                # Restore registry settings from .reg files
                $regFiles = Get-ChildItem -Path "$primaryBackupPath\*.reg" -ErrorAction SilentlyContinue
                foreach ($regFile in $regFiles) {
                    if ($WhatIf) {
                        Write-Host "WhatIf: Would restore registry from $($regFile.FullName)"
                    } else {
                        try {
                            Write-Host "Restoring registry settings from $($regFile.Name)..." -ForegroundColor Yellow
                            reg import $regFile.FullName /y 2>$null
                            $restoredItems += $regFile.Name
                        } catch {
                            $errors += "Failed to restore registry from $($regFile.Name): $_"
                            Write-Host "Warning: Failed to restore registry from $($regFile.Name)" -ForegroundColor Yellow
                        }
                    }
                }

                # Restore default apps XML configuration using DISM
                $defaultAppsXml = Join-Path $primaryBackupPath "defaultapps.xml"
                if (Test-Path $defaultAppsXml) {
                    if ($WhatIf) {
                        Write-Host "WhatIf: Would restore default apps XML from $defaultAppsXml"
                    } else {
                        try {
                            Write-Host "Restoring default apps XML configuration..." -ForegroundColor Yellow
                            Dism.exe /Online /Import-DefaultAppAssociations:"$defaultAppsXml" | Out-Null
                            $restoredItems += "defaultapps.xml"
                        } catch {
                            $errors += "Failed to restore default apps XML: $_"
                            Write-Host "Warning: Failed to restore default apps XML" -ForegroundColor Yellow
                        }
                    }
                }

                # Restore user choice settings
                $userChoicesFile = "$primaryBackupPath\user_choices.json"
                if (Test-Path $userChoicesFile) {
                    if ($WhatIf) {
                        Write-Host "WhatIf: Would restore user choices from $userChoicesFile"
                    } else {
                        try {
                            Write-Host "Restoring user choice settings..." -ForegroundColor Yellow
                            $userChoices = Get-Content $userChoicesFile | ConvertFrom-Json
                            foreach ($choice in $userChoices) {
                                if ($choice.Extension -and $choice.ProgId) {
                                    $extPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$($choice.Extension)\UserChoice"
                                    if (!(Test-Path $extPath)) {
                                        New-Item -Path $extPath -Force | Out-Null
                                    }
                                    Set-ItemProperty -Path $extPath -Name "ProgId" -Value $choice.ProgId -ErrorAction SilentlyContinue
                                    if ($choice.Hash) {
                                        Set-ItemProperty -Path $extPath -Name "Hash" -Value $choice.Hash -ErrorAction SilentlyContinue
                                    }
                                }
                            }
                            $restoredItems += "user_choices.json"
                        } catch {
                            $errors += "Failed to restore user choices: $_"
                            Write-Host "Warning: Failed to restore user choices" -ForegroundColor Yellow
                        }
                    }
                }

                # Restore app capabilities (informational only - cannot directly modify)
                $appCapabilitiesFile = "$primaryBackupPath\app_capabilities.json"
                if (Test-Path $appCapabilitiesFile) {
                    if ($WhatIf) {
                        Write-Host "WhatIf: Would restore app capabilities from $appCapabilitiesFile"
                    } else {
                        try {
                            Write-Host "Restoring app capabilities information..." -ForegroundColor Yellow
                            $appCapabilities = Get-Content $appCapabilitiesFile | ConvertFrom-Json
                            Write-Host "App capabilities restored (informational - cannot directly modify capabilities)" -ForegroundColor Green
                            $restoredItems += "app_capabilities.json"
                        } catch {
                            $errors += "Failed to restore app capabilities: $_"
                            Write-Host "Warning: Failed to restore app capabilities" -ForegroundColor Yellow
                        }
                    }
                }

                # Restore browser settings
                $browserSettingsFile = "$primaryBackupPath\browser_settings.json"
                if (Test-Path $browserSettingsFile) {
                    if ($WhatIf) {
                        Write-Host "WhatIf: Would restore browser settings from $browserSettingsFile"
                    } else {
                        try {
                            Write-Host "Restoring browser settings..." -ForegroundColor Yellow
                            $browserSettings = Get-Content $browserSettingsFile | ConvertFrom-Json
                            
                            # Set default browser
                            if ($browserSettings.DefaultBrowser) {
                                $httpPath = "HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\http\UserChoice"
                                if (!(Test-Path $httpPath)) {
                                    New-Item -Path $httpPath -Force | Out-Null
                                }
                                Set-ItemProperty -Path $httpPath -Name "ProgId" -Value $browserSettings.DefaultBrowser -ErrorAction SilentlyContinue
                            }

                            # Set default apps for common file types
                            $fileTypes = @{
                                ".pdf" = $browserSettings.PDFViewer
                                ".jpg" = $browserSettings.ImageViewer
                                ".mp4" = $browserSettings.VideoPlayer
                                ".mp3" = $browserSettings.MusicPlayer
                            }

                            foreach ($type in $fileTypes.GetEnumerator()) {
                                if ($type.Value) {
                                    $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$($type.Key)\UserChoice"
                                    if (!(Test-Path $path)) {
                                        New-Item -Path $path -Force | Out-Null
                                    }
                                    Set-ItemProperty -Path $path -Name "ProgId" -Value $type.Value -ErrorAction SilentlyContinue
                                }
                            }
                            $restoredItems += "browser_settings.json"
                        } catch {
                            $errors += "Failed to restore browser settings: $_"
                            Write-Host "Warning: Failed to restore browser settings" -ForegroundColor Yellow
                        }
                    }
                }

                # Refresh shell associations
                if (!$WhatIf) {
                    try {
                        Write-Host "Refreshing shell associations..." -ForegroundColor Yellow
                        $signature = @"
                            [DllImport("shell32.dll")]
                            public static extern void SHChangeNotify(int eventId, int flags, IntPtr item1, IntPtr item2);
"@
                        $type = Add-Type -MemberDefinition $signature -Name WinAPI -Namespace Win32Functions -PassThru
                        $type::SHChangeNotify(0x8000000, 0x1000, [IntPtr]::Zero, [IntPtr]::Zero)
                    } catch {
                        Write-Verbose "Could not refresh shell associations: $_"
                    }
                }
                
                # Return object for better testing and validation
                $result = [PSCustomObject]@{
                    Success = $true
                    BackupPath = $primaryBackupPath
                    SharedBackupPath = $sharedBackupPath
                    Feature = "DefaultApps"
                    Timestamp = Get-Date
                    Items = $restoredItems
                    Errors = $errors
                }
                
                Write-Host "Default Apps Settings restored successfully from: $primaryBackupPath" -ForegroundColor Green
                if ($errors.Count -eq 0) {
                    Write-Host "`nNote: You may need to restart applications or log off/on for all changes to take effect" -ForegroundColor Yellow
                } else {
                    Write-Host "`nWarning: Some settings could not be restored. Check errors for details." -ForegroundColor Yellow
                }
                Write-Verbose "Restore completed successfully"
                return $result
            } else {
                throw "No backup found for Default Apps Settings in either machine or shared paths"
            }
        } catch {
            $errorRecord = $_
            $errorMessage = @(
                "Failed to restore Default Apps Settings"
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
    Export-ModuleMember -Function Restore-DefaultAppsSettings
}

<#
.SYNOPSIS
Restores Windows default app associations and settings.

.DESCRIPTION
Restores Windows default app settings from backup, including:
- Registry settings for file type associations and default programs
- DISM XML configuration for default app associations
- User choice settings for common file types
- App capabilities information
- Browser settings for default applications
- Both machine-specific and shared settings

.EXAMPLE
Restore-DefaultAppsSettings -BackupRootPath "C:\Backups" -MachineBackupPath "C:\Backups\Machine" -SharedBackupPath "C:\Backups\Shared"

.NOTES
Test cases to consider:
1. Valid backup paths with proper permissions
2. Invalid/nonexistent backup paths
3. Registry import success/failure
4. DISM import success/failure
5. Missing backup files
6. Partial restore scenarios
7. Shell notification success/failure

.TESTCASES
# Mock test examples:
Describe "Restore-DefaultAppsSettings" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Test-BackupPath { return "TestPath" }
        Mock Get-ChildItem { return @(
            [PSCustomObject]@{
                Name = "FileExts.reg"
                FullName = "TestPath\FileExts.reg"
            }
        )}
        Mock reg { }
        Mock Dism.exe { }
        Mock Get-Content { return '[{"Extension":".txt","ProgId":"txtfile","Hash":"test"}]' | ConvertFrom-Json }
        Mock New-Item { }
        Mock Set-ItemProperty { }
        Mock Add-Type { return [PSCustomObject]@{ SHChangeNotify = { } } }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Restore-DefaultAppsSettings -BackupRootPath "TestPath" -MachineBackupPath "TestPath\Machine" -SharedBackupPath "TestPath\Shared"
        $result.Success | Should -Be $true
        $result.BackupPath | Should -Be "TestPath"
        $result.Feature | Should -Be "DefaultApps"
    }

    It "Should handle missing backup gracefully" {
        Mock Test-BackupPath { return $null }
        { Restore-DefaultAppsSettings -BackupRootPath "TestPath" -MachineBackupPath "TestPath\Machine" -SharedBackupPath "TestPath\Shared" } | Should -Throw
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Restore-DefaultAppsSettings -BackupRootPath $BackupRootPath -MachineBackupPath $MachineBackupPath -SharedBackupPath $SharedBackupPath
} 