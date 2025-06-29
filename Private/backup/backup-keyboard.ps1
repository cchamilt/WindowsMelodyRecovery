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

function Backup-KeyboardSettings {
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
            Write-Verbose "Starting backup of Keyboard Settings..."
            Write-Host "Backing up Keyboard Settings..." -ForegroundColor Blue
            
            # Validate inputs before proceeding
            if (!(Test-Path $BackupRootPath)) {
                throw [System.IO.DirectoryNotFoundException]"Backup root path not found: $BackupRootPath"
            }
            
            $backupPath = Initialize-BackupDirectory -Path "Keyboard" -BackupType "Keyboard Settings" -BackupRootPath $BackupRootPath
            
            if ($backupPath) {
                $backedUpItems = @()
                $errors = @()
                
                # Export keyboard registry settings
                $regPaths = @(
                    # Keyboard layouts and input methods
                    "HKCU\Keyboard Layout",
                    "HKCU\Software\Microsoft\CTF",
                    "HKCU\Software\Microsoft\Input",
                    "HKLM\SYSTEM\CurrentControlSet\Control\Keyboard Layout",
                    "HKLM\SYSTEM\CurrentControlSet\Control\Keyboard Layouts",
                    
                    # Input method preferences
                    "HKCU\Software\Microsoft\Windows\CurrentVersion\CPSS\InputMethod",
                    "HKCU\Software\Microsoft\Windows\CurrentVersion\IME",
                    
                    # Keyboard hardware settings
                    "HKLM\SYSTEM\CurrentControlSet\Services\i8042prt",
                    "HKLM\SYSTEM\CurrentControlSet\Services\kbdclass",
                    
                    # AutoHotkey and keyboard macros
                    "HKCU\Software\AutoHotkey",
                    
                    # Keyboard accessibility options
                    "HKCU\Control Panel\Accessibility\Keyboard Response",
                    "HKCU\Control Panel\Accessibility\StickyKeys",
                    "HKCU\Control Panel\Accessibility\ToggleKeys",
                    "HKCU\Control Panel\Accessibility\FilterKeys"
                )

                # Create registry backup directory
                $registryPath = Join-Path $backupPath "Registry"
                if ($WhatIf) {
                    Write-Host "WhatIf: Would create registry backup directory at $registryPath"
                } else {
                    New-Item -ItemType Directory -Force -Path $registryPath | Out-Null
                }

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

                # Export keyboard devices using WMI
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export keyboard devices to $backupPath\keyboard_devices.json"
                } else {
                    try {
                        $keyboardDevices = Get-WmiObject Win32_Keyboard | Select-Object -Property *
                        $keyboardDevices | ConvertTo-Json -Depth 10 | Out-File "$backupPath\keyboard_devices.json" -Force
                        $backedUpItems += "keyboard_devices.json"
                    } catch {
                        $errors += "Failed to export keyboard devices: $_"
                    }
                }

                # Export input language settings
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export input settings to $backupPath\input_settings.json"
                } else {
                    try {
                        $inputSettings = @{
                            Languages = Get-WinUserLanguageList
                            DefaultInputMethod = (Get-WinDefaultInputMethodOverride).InputMethodTip
                            Hotkeys = Get-WinLanguageBarOption
                        }
                        $inputSettings | ConvertTo-Json -Depth 10 | Out-File "$backupPath\input_settings.json" -Force
                        $backedUpItems += "input_settings.json"
                    } catch {
                        $errors += "Failed to export input settings: $_"
                    }
                }

                # Export keyboard scan code mappings
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export scan code mappings to $backupPath\scancode_mappings.json"
                } else {
                    try {
                        $scanCodeMappings = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layout" -Name "Scancode Map" -ErrorAction SilentlyContinue
                        if ($scanCodeMappings) {
                            $scanCodeMappings | ConvertTo-Json | Out-File "$backupPath\scancode_mappings.json" -Force
                            $backedUpItems += "scancode_mappings.json"
                        }
                    } catch {
                        $errors += "Failed to export scan code mappings: $_"
                    }
                }

                # Export keyboard repeat delay and speed
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export keyboard speed settings to $backupPath\keyboard_speed.json"
                } else {
                    try {
                        $keyboardSpeed = Get-ItemProperty -Path "HKCU:\Control Panel\Keyboard"
                        $keyboardSpeed | ConvertTo-Json | Out-File "$backupPath\keyboard_speed.json" -Force
                        $backedUpItems += "keyboard_speed.json"
                    } catch {
                        $errors += "Failed to export keyboard speed settings: $_"
                    }
                }
                
                # Return object for better testing and validation
                $result = [PSCustomObject]@{
                    Success = $true
                    BackupPath = $backupPath
                    Feature = "Keyboard Settings"
                    Timestamp = Get-Date
                    Items = $backedUpItems
                    Errors = $errors
                }
                
                Write-Host "Keyboard Settings backed up successfully to: $backupPath" -ForegroundColor Green
                Write-Verbose "Backup completed successfully"
                return $result
            }
            return $false
        } catch {
            $errorRecord = $_
            $errorMessage = @(
                "Failed to backup Keyboard Settings"
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
Backs up Windows Keyboard settings and configuration.

.DESCRIPTION
Creates a backup of Windows Keyboard settings, including keyboard layouts, input methods, accessibility options,
device information, custom key mappings, scan code mappings, and keyboard speed settings. Supports comprehensive
keyboard customizations and user preferences across multiple languages and input methods.

.PARAMETER BackupRootPath
The root path where the backup will be created. A subdirectory named "Keyboard" will be created within this path.

.PARAMETER Force
Forces the backup operation even if the destination already exists.

.PARAMETER WhatIf
Shows what would be backed up without actually performing the backup operation.

.EXAMPLE
Backup-KeyboardSettings -BackupRootPath "C:\Backups"

.EXAMPLE
Backup-KeyboardSettings -BackupRootPath "C:\Backups" -WhatIf

.NOTES
Test cases to consider:
1. Valid backup path with proper permissions
2. Invalid/nonexistent backup path
3. Empty backup path
4. No permissions to write
5. Registry export success/failure for each key
6. WMI query success/failure
7. Input settings export success/failure
8. Scan code mappings export success/failure
9. Keyboard speed settings export success/failure
10. Multiple keyboard layouts scenario
11. Custom key mappings scenario
12. Accessibility options enabled
13. AutoHotkey configurations
14. Multiple input methods
15. Network path scenarios

.TESTCASES
# Mock test examples:
Describe "Backup-KeyboardSettings" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Initialize-BackupDirectory { return "TestPath" }
        Mock reg { }
        Mock Get-WmiObject { return @(
            [PSCustomObject]@{
                Name = "HID Keyboard"
                Description = "Standard Keyboard"
                Status = "OK"
            }
        )}
        Mock Get-WinUserLanguageList { return @("en-US") }
        Mock Get-WinDefaultInputMethodOverride { return @{ InputMethodTip = "en-US" } }
        Mock Get-WinLanguageBarOption { return @{ Hotkeys = @() } }
        Mock Get-ItemProperty { return @{ "Scancode Map" = $null } }
        Mock ConvertTo-Json { return '{"test":"value"}' }
        Mock Out-File { }
        Mock New-Item { }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Backup-KeyboardSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.BackupPath | Should -Be "TestPath"
        $result.Feature | Should -Be "Keyboard Settings"
        $result.Items | Should -BeOfType [System.Array]
        $result.Errors | Should -BeOfType [System.Array]
    }

    It "Should handle registry export failure gracefully" {
        Mock reg { throw "Registry export failed" }
        $result = Backup-KeyboardSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle WMI query failure gracefully" {
        Mock Get-WmiObject { throw "WMI query failed" }
        $result = Backup-KeyboardSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should support WhatIf parameter" {
        $result = Backup-KeyboardSettings -BackupRootPath "TestPath" -WhatIf
        $result.Success | Should -Be $true
    }

    It "Should handle input settings export failure gracefully" {
        Mock Get-WinUserLanguageList { throw "Language list access denied" }
        $result = Backup-KeyboardSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Backup-KeyboardSettings -BackupRootPath $BackupRootPath
} 