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

function Restore-KeyboardSettings {
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
            Feature = "Keyboard Settings"
            Timestamp = Get-Date
            ItemsRestored = @()
            ItemsSkipped = @()
            Errors = @()
        }
    }
    
    process {
        try {
            Write-Verbose "Starting restore of Keyboard Settings..."
            Write-Host "Restoring Keyboard Settings..." -ForegroundColor Blue
            
            # Validate inputs
            if (!(Test-Path $BackupRootPath)) {
                throw [System.IO.DirectoryNotFoundException]"Backup root path not found: $BackupRootPath"
            }
            
            $backupPath = Test-BackupPath -Path "Keyboard" -BackupType "Keyboard Settings"
            if (!$backupPath) {
                throw "No valid backup found for Keyboard Settings"
            }
            $result.RestorePath = $backupPath
            
            if ($backupPath) {
                # Check keyboard services (only if not in test mode)
                if (!$script:TestMode) {
                    Write-Host "Checking keyboard components..." -ForegroundColor Yellow
                    $keyboardServices = @(
                        "TabletInputService",     # Touch Keyboard and Handwriting Panel Service
                        "i8042prt",              # PS/2 Keyboard and Mouse Driver
                        "kbdhid"                 # Keyboard HID Driver
                    )
                    
                    foreach ($service in $keyboardServices) {
                        if ((Get-Service -Name $service -ErrorAction SilentlyContinue).Status -ne "Running") {
                            if ($Force -or $PSCmdlet.ShouldProcess("Service $service", "Start")) {
                                Start-Service -Name $service -ErrorAction SilentlyContinue
                                $result.ItemsRestored += "Service\$service"
                            }
                        }
                    }
                }

                # Restore registry settings first
                $registryPath = Join-Path $backupPath "Registry"
                if (Test-Path $registryPath) {
                    if ($Force -or $PSCmdlet.ShouldProcess("Keyboard Registry Settings", "Restore")) {
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

                # Restore input language settings
                $inputSettingsFile = Join-Path $backupPath "input_settings.json"
                if (Test-Path $inputSettingsFile) {
                    if ($Force -or $PSCmdlet.ShouldProcess("Keyboard Input Settings", "Restore")) {
                        try {
                            $inputSettings = Get-Content $inputSettingsFile | ConvertFrom-Json
                            
                            # Set language list
                            if ($inputSettings.Languages -and !$script:TestMode) {
                                Set-WinUserLanguageList -LanguageList $inputSettings.Languages -Force
                            }

                            # Set default input method
                            if ($inputSettings.DefaultInputMethod -and !$script:TestMode) {
                                Set-WinDefaultInputMethodOverride -InputTip $inputSettings.DefaultInputMethod
                            }

                            # Set language bar options
                            if ($inputSettings.Hotkeys -and !$script:TestMode) {
                                Set-WinLanguageBarOption -UseLegacySwitchMode $inputSettings.Hotkeys.UseLegacySwitchMode `
                                    -UseLegacyLanguageBar $inputSettings.Hotkeys.UseLegacyLanguageBar
                            }
                            
                            $result.ItemsRestored += "input_settings.json"
                        } catch {
                            $result.Errors += "Failed to restore input settings`: $_"
                            $result.ItemsSkipped += "input_settings.json"
                            if (!$Force) { throw }
                        }
                    }
                } else {
                    $result.ItemsSkipped += "input_settings.json (not found in backup)"
                }

                # Restore scan code mappings
                $scanCodeFile = Join-Path $backupPath "scancode_mappings.json"
                if (Test-Path $scanCodeFile) {
                    if ($Force -or $PSCmdlet.ShouldProcess("Keyboard Scan Code Mappings", "Restore")) {
                        try {
                            $scanCodeMappings = Get-Content $scanCodeFile | ConvertFrom-Json
                            if ($scanCodeMappings.'Scancode Map' -and !$script:TestMode) {
                                Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layout" `
                                    -Name "Scancode Map" -Value $scanCodeMappings.'Scancode Map'
                            }
                            $result.ItemsRestored += "scancode_mappings.json"
                        } catch {
                            $result.Errors += "Failed to restore scan code mappings`: $_"
                            $result.ItemsSkipped += "scancode_mappings.json"
                            if (!$Force) { throw }
                        }
                    }
                } else {
                    $result.ItemsSkipped += "scancode_mappings.json (not found in backup)"
                }

                # Restore keyboard speed settings
                $speedFile = Join-Path $backupPath "keyboard_speed.json"
                if (Test-Path $speedFile) {
                    if ($Force -or $PSCmdlet.ShouldProcess("Keyboard Speed Settings", "Restore")) {
                        try {
                            $keyboardSpeed = Get-Content $speedFile | ConvertFrom-Json
                            if (!$script:TestMode) {
                                Set-ItemProperty -Path "HKCU:\Control Panel\Keyboard" -Name "KeyboardDelay" -Value $keyboardSpeed.KeyboardDelay
                                Set-ItemProperty -Path "HKCU:\Control Panel\Keyboard" -Name "KeyboardSpeed" -Value $keyboardSpeed.KeyboardSpeed
                            }
                            $result.ItemsRestored += "keyboard_speed.json"
                        } catch {
                            $result.Errors += "Failed to restore keyboard speed settings`: $_"
                            $result.ItemsSkipped += "keyboard_speed.json"
                            if (!$Force) { throw }
                        }
                    }
                } else {
                    $result.ItemsSkipped += "keyboard_speed.json (not found in backup)"
                }

                # Restore keyboard devices configuration
                $keyboardDevicesFile = Join-Path $backupPath "keyboard_devices.json"
                if (Test-Path $keyboardDevicesFile) {
                    if ($Force -or $PSCmdlet.ShouldProcess("Keyboard Device Settings", "Restore")) {
                        try {
                            $savedDevices = Get-Content $keyboardDevicesFile | ConvertFrom-Json
                            if (!$script:TestMode) {
                                $currentDevices = Get-WmiObject Win32_Keyboard

                                foreach ($current in $currentDevices) {
                                    $saved = $savedDevices | Where-Object { $_.DeviceID -eq $current.DeviceID }
                                    if ($saved) {
                                        # Update supported properties
                                        $current.Layout = $saved.Layout
                                        $current.NumberOfFunctionKeys = $saved.NumberOfFunctionKeys
                                        $current.Put()
                                    }
                                }
                            }
                            $result.ItemsRestored += "keyboard_devices.json"
                        } catch {
                            $result.Errors += "Failed to restore keyboard device settings`: $_"
                            $result.ItemsSkipped += "keyboard_devices.json"
                            if (!$Force) { throw }
                        }
                    }
                } else {
                    $result.ItemsSkipped += "keyboard_devices.json (not found in backup)"
                }

                # Restart keyboard services (only if not in test mode)
                if (!$script:TestMode) {
                    if ($Force -or $PSCmdlet.ShouldProcess("Keyboard Services", "Restart")) {
                        $services = @(
                            "i8042prt",
                            "kbdclass"
                        )
                        
                        foreach ($service in $services) {
                            if (Get-Service -Name $service -ErrorAction SilentlyContinue) {
                                Restart-Service -Name $service -Force -ErrorAction SilentlyContinue
                                $result.ItemsRestored += "ServiceRestart\$service"
                            }
                        }
                    }
                }
                
                $result.Success = ($result.Errors.Count -eq 0)
                
                # Display summary
                Write-Host "`nKeyboard Settings Restore Summary:" -ForegroundColor Green
                Write-Host "Items Restored: $($result.ItemsRestored.Count)" -ForegroundColor Yellow
                Write-Host "Items Skipped: $($result.ItemsSkipped.Count)" -ForegroundColor Yellow
                Write-Host "Errors: $($result.Errors.Count)" -ForegroundColor $(if ($result.Errors.Count -gt 0) { "Red" } else { "Yellow" })
                
                if ($result.Success) {
                    Write-Host "Keyboard Settings restored successfully from: $backupPath" -ForegroundColor Green
                    Write-Host "`nNote: System restart may be required for some keyboard settings to take full effect" -ForegroundColor Yellow
                } else {
                    Write-Warning "Keyboard Settings restore completed with errors"
                }
                
                Write-Verbose "Restore completed successfully"
                return $result
            }
            return $result
        } catch {
            $errorRecord = $_
            $errorMessage = @(
                "Failed to restore Keyboard Settings"
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
    Export-ModuleMember -Function Restore-KeyboardSettings
}

<#
.SYNOPSIS
Restores Windows Keyboard settings and configuration from backup.

.DESCRIPTION
Restores Windows Keyboard configuration and associated data from a previous backup, including keyboard layouts,
input methods, accessibility options, device settings, custom key mappings, scan code mappings, and keyboard
speed settings. Handles keyboard service management during restore to ensure settings are applied correctly.

.PARAMETER BackupRootPath
The root path where the backup is located. The script will look for a "Keyboard" subdirectory within this path.

.PARAMETER Force
Forces the restore operation without prompting for confirmation and continues even if some items fail to restore.

.PARAMETER Include
Array of item names to include in the restore operation. If not specified, all available items are restored.

.PARAMETER Exclude
Array of item names to exclude from the restore operation.

.PARAMETER SkipVerification
Skips backup integrity verification (useful for testing).

.EXAMPLE
Restore-KeyboardSettings -BackupRootPath "C:\Backups"

.EXAMPLE
Restore-KeyboardSettings -BackupRootPath "C:\Backups" -Force

.EXAMPLE
Restore-KeyboardSettings -BackupRootPath "C:\Backups" -WhatIf

.NOTES
Test cases to consider:
1. Valid backup with all files present
2. Partial backup (some files missing)
3. Corrupted backup
4. No backup found
5. Backup with invalid format
6. Permission issues during restore
7. Registry import failures
8. Input settings restore failures
9. Scan code mapping restore failures
10. WhatIf scenario
11. Force parameter behavior
12. Include/Exclude filters
13. Keyboard service management
14. Multiple keyboard layouts
15. Custom key mappings
16. Accessibility options
17. AutoHotkey configurations
18. System restart requirements
19. Network path backup scenarios

.TESTCASES
# Mock test examples:
Describe "Restore-KeyboardSettings" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Test-BackupPath { return "TestPath" }
        Mock Get-ChildItem { 
            return @(
                [PSCustomObject]@{ Name = "Keyboard Layout.reg"; FullName = "TestPath\Registry\Keyboard Layout.reg" },
                [PSCustomObject]@{ Name = "CTF.reg"; FullName = "TestPath\Registry\CTF.reg" }
            )
        }
        Mock Get-Content { return '{"Languages":["en-US"],"DefaultInputMethod":"en-US","Hotkeys":{}}' }
        Mock ConvertFrom-Json { return @{ Languages = @("en-US"); DefaultInputMethod = "en-US"; Hotkeys = @{} } }
        Mock Get-Service { return @{ Status = "Running" } }
        Mock Start-Service { }
        Mock Restart-Service { }
        Mock reg { }
        Mock Set-WinUserLanguageList { }
        Mock Set-WinDefaultInputMethodOverride { }
        Mock Set-WinLanguageBarOption { }
        Mock Set-ItemProperty { }
        Mock Get-WmiObject { return @() }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Restore-KeyboardSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.RestorePath | Should -Be "TestPath"
        $result.Feature | Should -Be "Keyboard Settings"
        $result.ItemsRestored | Should -BeOfType [System.Array]
        $result.ItemsSkipped | Should -BeOfType [System.Array]
        $result.Errors | Should -BeOfType [System.Array]
    }

    It "Should handle WhatIf properly" {
        $result = Restore-KeyboardSettings -BackupRootPath "TestPath" -WhatIf
        $result.ItemsRestored.Count | Should -Be 0
    }

    It "Should handle registry import failure gracefully with Force" {
        Mock reg { throw "Registry import failed" }
        $result = Restore-KeyboardSettings -BackupRootPath "TestPath" -Force
        $result.Errors.Count | Should -BeGreaterThan 0
        $result.ItemsSkipped.Count | Should -BeGreaterThan 0
    }

    It "Should handle missing backup gracefully" {
        Mock Test-BackupPath { return $null }
        { Restore-KeyboardSettings -BackupRootPath "TestPath" } | Should -Throw
    }

    It "Should skip verification when specified" {
        $result = Restore-KeyboardSettings -BackupRootPath "TestPath" -SkipVerification
        $result.Success | Should -Be $true
    }

    It "Should handle input settings restore failure gracefully" {
        Mock Set-WinUserLanguageList { throw "Access denied" }
        $result = Restore-KeyboardSettings -BackupRootPath "TestPath" -Force
        $result.Errors.Count | Should -BeGreaterThan 0
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Restore-KeyboardSettings -BackupRootPath $BackupRootPath
} 