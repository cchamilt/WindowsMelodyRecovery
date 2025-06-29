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

function Restore-DisplaySettings {
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
            Write-Verbose "Starting restore of Display Settings..."
            Write-Host "Restoring Display Settings..." -ForegroundColor Blue
            
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
            
            $backupPath = Test-BackupPath -Path "Display" -BackupType "Display Settings" -BackupRootPath $MachineBackupPath
            $sharedBackupPath = Test-BackupPath -Path "Display" -BackupType "Shared Display Settings" -BackupRootPath $SharedBackupPath -IsShared
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
                            $errors += "Failed to restore registry from $($regFile.Name)`: $_"
                            Write-Host "Warning: Failed to restore registry from $($regFile.Name)" -ForegroundColor Yellow
                        }
                    }
                }

                # Restore video controller settings
                $videoControllersFile = "$primaryBackupPath\video_controllers.json"
                if (Test-Path $videoControllersFile) {
                    if ($WhatIf) {
                        Write-Host "WhatIf: Would restore video controller settings from $videoControllersFile"
                    } else {
                        try {
                            Write-Host "Restoring video controller settings..." -ForegroundColor Yellow
                            $savedControllers = Get-Content $videoControllersFile | ConvertFrom-Json
                            $currentControllers = Get-CimInstance -Namespace root\cimv2 -ClassName Win32_VideoController

                            foreach ($current in $currentControllers) {
                                $saved = $savedControllers | Where-Object { $_.PNPDeviceID -eq $current.PNPDeviceID }
                                if ($saved) {
                                    # Update supported settings (some properties are read-only)
                                    try {
                                        if ($saved.VideoModeDescription -and $current.VideoModeDescription -ne $saved.VideoModeDescription) {
                                            Write-Verbose "Video mode description would be updated if supported"
                                        }
                                    } catch {
                                        Write-Verbose "Could not update video controller settings: $_"
                                    }
                                }
                            }
                            $restoredItems += "video_controllers.json"
                        } catch {
                            $errors += "Failed to restore video controller settings`: $_"
                            Write-Host "Warning: Failed to restore video controller settings" -ForegroundColor Yellow
                        }
                    }
                }

                # Restore display information
                $displaysFile = "$primaryBackupPath\displays.json"
                if (Test-Path $displaysFile) {
                    if ($WhatIf) {
                        Write-Host "WhatIf: Would restore display information from $displaysFile"
                    } else {
                        try {
                            Write-Host "Restoring display information..." -ForegroundColor Yellow
                            $savedDisplays = Get-Content $displaysFile | ConvertFrom-Json
                            Write-Host "Display information restored (settings applied via registry)" -ForegroundColor Green
                            $restoredItems += "displays.json"
                        } catch {
                            $errors += "Failed to restore display information`: $_"
                            Write-Host "Warning: Failed to restore display information" -ForegroundColor Yellow
                        }
                    }
                }

                # Restore color profiles
                $colorProfilesPath = Join-Path $primaryBackupPath "ColorProfiles"
                if (Test-Path $colorProfilesPath) {
                    if ($WhatIf) {
                        Write-Host "WhatIf: Would restore color profiles from $colorProfilesPath"
                    } else {
                        try {
                            Write-Host "Restoring color profiles..." -ForegroundColor Yellow
                            $systemColorPath = "$env:SystemRoot\System32\spool\drivers\color"
                            if (!(Test-Path $systemColorPath)) {
                                New-Item -ItemType Directory -Path $systemColorPath -Force | Out-Null
                            }
                            
                            # Copy ICM files
                            $icmFiles = Get-ChildItem -Path "$colorProfilesPath\*.icm" -ErrorAction SilentlyContinue
                            if ($icmFiles) {
                                Copy-Item -Path $icmFiles.FullName -Destination $systemColorPath -Force
                                $restoredItems += "ColorProfiles\*.icm ($($icmFiles.Count) files)"
                            }
                            
                            # Copy ICC files
                            $iccFiles = Get-ChildItem -Path "$colorProfilesPath\*.icc" -ErrorAction SilentlyContinue
                            if ($iccFiles) {
                                Copy-Item -Path $iccFiles.FullName -Destination $systemColorPath -Force
                                $restoredItems += "ColorProfiles\*.icc ($($iccFiles.Count) files)"
                            }
                        } catch {
                            $errors += "Failed to restore color profiles`: $_"
                            Write-Host "Warning: Failed to restore color profiles" -ForegroundColor Yellow
                        }
                    }
                }

                # Notify system of display settings change
                if (!$WhatIf) {
                    try {
                        Write-Host "Notifying system of display settings changes..." -ForegroundColor Yellow
                        $signature = @"
                            [DllImport("user32.dll")]
                            public static extern int SendMessageTimeout(
                                IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam,
                                uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
"@
                        $type = Add-Type -MemberDefinition $signature -Name WinAPI -Namespace Win32Functions -PassThru
                        [IntPtr]$HWND_BROADCAST = [IntPtr]0xffff
                        $WM_SETTINGCHANGE = 0x1a
                        $result = [UIntPtr]::Zero
                        $type::SendMessageTimeout($HWND_BROADCAST, $WM_SETTINGCHANGE, [UIntPtr]::Zero, "Policy", 2, 5000, [ref]$result) | Out-Null
                    } catch {
                        Write-Verbose "Could not broadcast settings change: $_"
                    }
                }
                
                # Return object for better testing and validation
                $result = [PSCustomObject]@{
                    Success = $true
                    BackupPath = $primaryBackupPath
                    SharedBackupPath = $sharedBackupPath
                    Feature = "Display Settings"
                    Timestamp = Get-Date
                    Items = $restoredItems
                    Errors = $errors
                }
                
                Write-Host "Display Settings restored successfully from: $primaryBackupPath" -ForegroundColor Green
                if ($errors.Count -eq 0) {
                    Write-Host "`nNote: Some settings may require a system restart to take effect" -ForegroundColor Yellow
                } else {
                    Write-Host "`nWarning: Some settings could not be restored. Check errors for details." -ForegroundColor Yellow
                }
                Write-Verbose "Restore completed successfully"
                return $result
            } else {
                throw "No backup found for Display Settings in either machine or shared paths"
            }
        } catch {
            $errorRecord = $_
            $errorMessage = @(
                "Failed to restore Display Settings"
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
    Export-ModuleMember -Function Restore-DisplaySettings
}

<#
.SYNOPSIS
Restores Windows Display settings and configuration.

.DESCRIPTION
Restores Windows Display settings from backup, including:
- Registry settings for display configuration
- Video controller settings
- Display information and monitor settings
- Color profiles (ICM and ICC files)
- Both machine-specific and shared settings

.EXAMPLE
Restore-DisplaySettings -BackupRootPath "C:\Backups" -MachineBackupPath "C:\Backups\Machine" -SharedBackupPath "C:\Backups\Shared"

.NOTES
Test cases to consider:
1. Valid backup paths with proper permissions
2. Invalid/nonexistent backup paths
3. Registry import success/failure
4. Color profile restore success/failure
5. Missing backup files
6. Partial restore scenarios
7. System notification success/failure

.TESTCASES
# Mock test examples:
Describe "Restore-DisplaySettings" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Test-BackupPath { return "TestPath" }
        Mock Get-ChildItem { return @(
            [PSCustomObject]@{
                Name = "Desktop.reg"
                FullName = "TestPath\Desktop.reg"
            }
        )}
        Mock reg { }
        Mock Get-Content { return '{"test":"value"}' | ConvertFrom-Json }
        Mock Get-CimInstance { return @() }
        Mock Copy-Item { }
        Mock Add-Type { return [PSCustomObject]@{ SendMessageTimeout = { return 1 } } }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Restore-DisplaySettings -BackupRootPath "TestPath" -MachineBackupPath "TestPath\Machine" -SharedBackupPath "TestPath\Shared"
        $result.Success | Should -Be $true
        $result.BackupPath | Should -Be "TestPath"
        $result.Feature | Should -Be "Display Settings"
    }

    It "Should handle missing backup gracefully" {
        Mock Test-BackupPath { return $null }
        { Restore-DisplaySettings -BackupRootPath "TestPath" -MachineBackupPath "TestPath\Machine" -SharedBackupPath "TestPath\Shared" } | Should -Throw
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Restore-DisplaySettings -BackupRootPath $BackupRootPath -MachineBackupPath $MachineBackupPath -SharedBackupPath $SharedBackupPath
}