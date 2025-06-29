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

function Backup-MouseSettings {
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
            Write-Verbose "Starting backup of Mouse Settings..."
            Write-Host "Backing up Mouse Settings..." -ForegroundColor Blue
            
            # Validate inputs before proceeding
            if (!(Test-Path $BackupRootPath)) {
                throw [System.IO.DirectoryNotFoundException]"Backup root path not found: $BackupRootPath"
            }
            
            $backupPath = Initialize-BackupDirectory -Path "Mouse" -BackupType "Mouse Settings" -BackupRootPath $BackupRootPath
            
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

                # Registry paths for mouse settings
                $registryPaths = @(
                    "HKCU\Control Panel\Mouse",
                    "HKCU\Control Panel\Cursors",
                    "HKCU\Control Panel\Accessibility\MouseKeys",
                    "HKLM\SYSTEM\CurrentControlSet\Services\mouclass\Parameters",
                    "HKLM\SYSTEM\CurrentControlSet\Services\mouhid\Parameters",
                    "HKLM\SYSTEM\CurrentControlSet\Services\i8042prt\Parameters"
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
                                reg export $path $regFile /y 2>$null
                                $backedUpItems += "$($path.Split('\')[-1]).reg"
                            } catch {
                                $errors += "Failed to export registry path $path : $_"
                            }
                        }
                    } else {
                        Write-Verbose "Registry key not found: $path"
                    }
                }

                # Get mouse device information
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export mouse device information"
                } else {
                    try {
                        $mouseInfo = Get-CimInstance -ClassName Win32_PointingDevice | Select-Object Name, Manufacturer, DeviceID, Status, HardwareType
                        $mouseInfo | ConvertTo-Json -Depth 10 | Out-File "$backupPath\mouse_devices.json" -Force
                        $backedUpItems += "mouse_devices.json"
                    } catch {
                        $errors += "Failed to get mouse device information: $_"
                    }
                }

                # Get mouse settings from Control Panel
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export mouse control panel settings"
                } else {
                    try {
                        $mouseSettings = @{}
                        
                        # Get mouse settings with error handling for each property
                        $mouseProperties = @(
                            "DoubleClickSpeed", "MouseSpeed", "MouseThreshold1", "MouseThreshold2", 
                            "MouseSensitivity", "SnapToDefaultButton", "SwapMouseButtons", 
                            "MouseHoverTime", "MouseTrails", "ActiveWindowTracking"
                        )
                        
                        foreach ($property in $mouseProperties) {
                            try {
                                $value = Get-ItemProperty -Path "HKCU:\Control Panel\Mouse" -Name $property -ErrorAction SilentlyContinue
                                if ($value) {
                                    $mouseSettings[$property] = $value.$property
                                }
                            } catch {
                                Write-Verbose "Could not retrieve mouse property: $property"
                            }
                        }
                        
                        $mouseSettings | ConvertTo-Json -Depth 10 | Out-File "$backupPath\mouse_settings.json" -Force
                        $backedUpItems += "mouse_settings.json"
                    } catch {
                        $errors += "Failed to get mouse control panel settings: $_"
                    }
                }

                # Get cursor scheme information
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export cursor scheme information"
                } else {
                    try {
                        $cursorSettings = Get-ItemProperty -Path "HKCU:\Control Panel\Cursors" -ErrorAction SilentlyContinue
                        if ($cursorSettings) {
                            $cursorSettings | ConvertTo-Json -Depth 10 | Out-File "$backupPath\cursor_settings.json" -Force
                            $backedUpItems += "cursor_settings.json"
                        }
                    } catch {
                        $errors += "Failed to get cursor settings: $_"
                    }
                }

                # Get mouse accessibility settings
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export mouse accessibility settings"
                } else {
                    try {
                        $accessibilitySettings = Get-ItemProperty -Path "HKCU:\Control Panel\Accessibility\MouseKeys" -ErrorAction SilentlyContinue
                        if ($accessibilitySettings) {
                            $accessibilitySettings | ConvertTo-Json -Depth 10 | Out-File "$backupPath\mouse_accessibility.json" -Force
                            $backedUpItems += "mouse_accessibility.json"
                        }
                    } catch {
                        $errors += "Failed to get mouse accessibility settings: $_"
                    }
                }
                
                # Return object for better testing and validation
                $result = [PSCustomObject]@{
                    Success = $true
                    BackupPath = $backupPath
                    Feature = "Mouse Settings"
                    Timestamp = Get-Date
                    Items = $backedUpItems
                    Errors = $errors
                }
                
                Write-Host "Mouse Settings backed up successfully to: $backupPath" -ForegroundColor Green
                Write-Verbose "Backup completed successfully"
                return $result
            }
            return $false
        } catch {
            $errorRecord = $_
            $errorMessage = @(
                "Failed to backup Mouse Settings"
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
Backs up Windows Mouse settings and configurations.

.DESCRIPTION
Creates a backup of Windows Mouse settings, including registry settings, device information, control panel configurations,
cursor schemes, and accessibility settings. Supports comprehensive mouse customizations and user preferences.

.PARAMETER BackupRootPath
The root path where the backup will be created. A subdirectory named "Mouse" will be created within this path.

.PARAMETER Force
Forces the backup operation even if the destination already exists.

.PARAMETER WhatIf
Shows what would be backed up without actually performing the backup operation.

.EXAMPLE
Backup-MouseSettings -BackupRootPath "C:\Backups"

.EXAMPLE
Backup-MouseSettings -BackupRootPath "C:\Backups" -WhatIf

.NOTES
Test cases to consider:
1. Valid backup path with proper permissions
2. Invalid/nonexistent backup path
3. Empty backup path
4. No permissions to write
5. Registry export success/failure for each key
6. Device information retrieval success/failure
7. Control panel settings retrieval success/failure
8. Cursor scheme retrieval success/failure
9. Accessibility settings retrieval success/failure
10. JSON serialization success/failure
11. Multiple mouse devices scenario
12. Gaming mouse with custom settings
13. Accessibility features enabled
14. Custom cursor themes
15. Network path scenarios

.TESTCASES
# Mock test examples:
Describe "Backup-MouseSettings" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Initialize-BackupDirectory { return "TestPath" }
        Mock New-Item { }
        Mock Get-CimInstance { return @(
            [PSCustomObject]@{
                Name = "Test Mouse"
                Manufacturer = "Test Manufacturer"
                DeviceID = "TestDeviceID"
                Status = "OK"
                HardwareType = "USB"
            }
        )}
        Mock Get-ItemProperty { return @{
            DoubleClickSpeed = 500
            MouseSpeed = 1
            MouseThreshold1 = 6
            MouseThreshold2 = 10
            MouseSensitivity = 10
            SnapToDefaultButton = 1
            SwapMouseButtons = 0
        }}
        Mock ConvertTo-Json { return '{"test":"value"}' }
        Mock Out-File { }
        Mock reg { }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Backup-MouseSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.BackupPath | Should -Be "TestPath"
        $result.Feature | Should -Be "Mouse Settings"
        $result.Items | Should -BeOfType [System.Array]
        $result.Errors | Should -BeOfType [System.Array]
    }

    It "Should handle registry export failure gracefully" {
        Mock reg { throw "Failed to export registry" }
        $result = Backup-MouseSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle device information failure gracefully" {
        Mock Get-CimInstance { throw "Device query failed" }
        $result = Backup-MouseSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should support WhatIf parameter" {
        $result = Backup-MouseSettings -BackupRootPath "TestPath" -WhatIf
        $result.Success | Should -Be $true
    }

    It "Should handle control panel settings failure gracefully" {
        Mock Get-ItemProperty { throw "Registry access denied" }
        $result = Backup-MouseSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Backup-MouseSettings -BackupRootPath $BackupRootPath
} 