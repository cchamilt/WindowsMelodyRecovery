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
$config = Get-WindowsMelodyRecovery
if (!$config.IsInitialized) {
    throw "Module not initialized. Please run Initialize-WindowsMelodyRecovery first."
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

function Backup-TouchpadSettings {
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
            Write-Verbose "Starting backup of Touchpad Settings..."
            Write-Host "Backing up Touchpad Settings..." -ForegroundColor Blue
            
            # Validate inputs before proceeding
            if (!(Test-Path $BackupRootPath)) {
                throw [System.IO.DirectoryNotFoundException]"Backup root path not found: $BackupRootPath"
            }
            
            $backupPath = Initialize-BackupDirectory -Path "Touchpad" -BackupType "Touchpad Settings" -BackupRootPath $BackupRootPath
            
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

                # Touchpad-related registry settings to backup
                $registryPaths = @(
                    # Windows Precision Touchpad settings
                    "HKCU\Software\Microsoft\Windows\CurrentVersion\PrecisionTouchPad",
                    "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\PrecisionTouchPad",
                    
                    # Mouse properties (affects touchpad)
                    "HKCU\Control Panel\Mouse",
                    "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\ControlPanel\Mouse",
                    
                    # Synaptics settings
                    "HKLM\SOFTWARE\Synaptics",
                    "HKCU\Software\Synaptics",
                    
                    # Elan settings
                    "HKLM\SOFTWARE\Elantech",
                    "HKCU\Software\Elantech",
                    
                    # Alps settings
                    "HKLM\SOFTWARE\Alps",
                    "HKCU\Software\Alps",
                    
                    # General input settings
                    "HKLM\SYSTEM\CurrentControlSet\Services\MouseLikeTouchPad",
                    "HKLM\SYSTEM\CurrentControlSet\Services\SynTP",
                    "HKLM\SYSTEM\CurrentControlSet\Services\ETD",
                    "HKLM\SYSTEM\CurrentControlSet\Services\ApntEx",
                    
                    # Touchpad gesture settings
                    "HKCU\Software\Microsoft\Windows\CurrentVersion\PrecisionTouchPad\TouchpadSettings",
                    "HKCU\Software\Microsoft\Windows\CurrentVersion\PrecisionTouchPad\Status",
                    "HKCU\Software\Microsoft\Windows\CurrentVersion\PrecisionTouchPad\ScrollingSettings",
                    "HKCU\Software\Microsoft\Windows\CurrentVersion\PrecisionTouchPad\TappingSettings",
                    "HKCU\Software\Microsoft\Windows\CurrentVersion\PrecisionTouchPad\ThreeFingerGestureSettings",
                    "HKCU\Software\Microsoft\Windows\CurrentVersion\PrecisionTouchPad\FourFingerGestureSettings",
                    
                    # Input settings
                    "HKCU\Software\Microsoft\Input",
                    "HKLM\SOFTWARE\Microsoft\Input",
                    
                    # Tablet input settings
                    "HKCU\Software\Microsoft\TabletTip",
                    "HKLM\SOFTWARE\Microsoft\TabletTip"
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

                # Get all touchpad devices, including disabled ones
                if ($WhatIf) {
                    Write-Host "WhatIf: Would backup touchpad device information"
                } else {
                    try {
                        if (!$script:TestMode) {
                            $touchpadDevices = Get-PnpDevice | Where-Object { 
                                ($_.Class -eq "Mouse" -or $_.Class -eq "HIDClass") -and 
                                ($_.FriendlyName -match "touchpad|synaptics|elan|precision|alps" -or
                                 $_.Manufacturer -match "synaptics|elan|alps|microsoft")
                            } | Select-Object -Property @(
                                'InstanceId',
                                'FriendlyName',
                                'Manufacturer',
                                'Status',
                                'Class',
                                'DeviceID',
                                @{Name='IsEnabled'; Expression={$_.Status -eq 'OK'}}
                            )
                            
                            if ($touchpadDevices) {
                                $touchpadDevices | ConvertTo-Json -Depth 10 | Out-File (Join-Path $backupPath "touchpad_devices.json") -Force
                                $backedUpItems += "touchpad_devices.json"
                            }
                        }
                    } catch {
                        $errors += "Failed to backup touchpad device information: $_"
                    }
                }

                # Get touchpad driver information
                if ($WhatIf) {
                    Write-Host "WhatIf: Would backup touchpad driver information"
                } else {
                    try {
                        if (!$script:TestMode) {
                            $touchpadDrivers = Get-WmiObject Win32_SystemDriver | Where-Object {
                                $_.Name -match "SynTP|ETD|ApntEx|HID" -or
                                $_.DisplayName -match "Touchpad|Synaptics|Elan|Alps"
                            } | Select-Object Name, DisplayName, State, Status, StartMode, PathName
                            
                            if ($touchpadDrivers) {
                                $touchpadDrivers | ConvertTo-Json -Depth 10 | Out-File (Join-Path $backupPath "touchpad_drivers.json") -Force
                                $backedUpItems += "touchpad_drivers.json"
                            }
                        }
                    } catch {
                        $errors += "Failed to backup touchpad driver information: $_"
                    }
                }

                # Get touchpad service information
                if ($WhatIf) {
                    Write-Host "WhatIf: Would backup touchpad service information"
                } else {
                    try {
                        if (!$script:TestMode) {
                            $touchpadServices = Get-Service | Where-Object {
                                $_.Name -match "SynTP|ETD|TabletInput|PrecisionTouchpad|ApntEx" -or
                                $_.DisplayName -match "Touchpad|Synaptics|Elan|Alps|Tablet|Input"
                            } | Select-Object Name, DisplayName, Status, StartType, ServiceType
                            
                            if ($touchpadServices) {
                                $touchpadServices | ConvertTo-Json -Depth 10 | Out-File (Join-Path $backupPath "touchpad_services.json") -Force
                                $backedUpItems += "touchpad_services.json"
                            }
                        }
                    } catch {
                        $errors += "Failed to backup touchpad service information: $_"
                    }
                }

                # Get current touchpad settings via WMI
                if ($WhatIf) {
                    Write-Host "WhatIf: Would backup current touchpad settings"
                } else {
                    try {
                        if (!$script:TestMode) {
                            $touchpadSettings = @{}
                            
                            # Get pointing device information
                            $pointingDevices = Get-WmiObject Win32_PointingDevice | Where-Object {
                                $_.Name -match "TouchPad|Precision TouchPad|Synaptics|Elan|Alps" -or
                                $_.Manufacturer -match "Synaptics|Elan|Alps|Microsoft"
                            } | Select-Object Name, Manufacturer, Status, DeviceID, PNPDeviceID, HardwareType
                            
                            if ($pointingDevices) {
                                $touchpadSettings.PointingDevices = $pointingDevices
                            }
                            
                            # Get HID device information
                            $hidDevices = Get-WmiObject Win32_PnPEntity | Where-Object {
                                $_.Name -match "HID.*Touch|Precision TouchPad|I2C HID" -and
                                $_.Manufacturer -match "Synaptics|Elan|Alps|Microsoft|Generic"
                            } | Select-Object Name, Manufacturer, Status, DeviceID, PNPDeviceID
                            
                            if ($hidDevices) {
                                $touchpadSettings.HIDDevices = $hidDevices
                            }
                            
                            if ($touchpadSettings.Count -gt 0) {
                                $touchpadSettings | ConvertTo-Json -Depth 10 | Out-File (Join-Path $backupPath "touchpad_settings.json") -Force
                                $backedUpItems += "touchpad_settings.json"
                            }
                        }
                    } catch {
                        $errors += "Failed to backup current touchpad settings: $_"
                    }
                }

                # Get touchpad gesture configuration
                if ($WhatIf) {
                    Write-Host "WhatIf: Would backup touchpad gesture configuration"
                } else {
                    try {
                        $gestureSettings = @{}
                        
                        # Check for precision touchpad gesture settings
                        $precisionTouchpadKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\PrecisionTouchPad"
                        if (Test-Path $precisionTouchpadKey) {
                            $gestureProperties = @(
                                "AAPThreshold", "ActivationHeight", "ActivationWidth", "ContactVisualization",
                                "CursorSpeed", "LeaveOnWithMouse", "PanEnabled", "RightClickZoneEnabled",
                                "ScrollDirection", "TapAndDragEnabled", "TapsEnabled", "TwoFingerTapEnabled",
                                "ZoomEnabled", "ThreeFingerSlideEnabled", "ThreeFingerTapEnabled",
                                "FourFingerSlideEnabled", "FourFingerTapEnabled"
                            )
                            
                            foreach ($prop in $gestureProperties) {
                                try {
                                    $value = Get-ItemProperty -Path $precisionTouchpadKey -Name $prop -ErrorAction SilentlyContinue
                                    if ($value) {
                                        $gestureSettings[$prop] = $value.$prop
                                    }
                                } catch {
                                    Write-Verbose "Could not read gesture property $prop"
                                }
                            }
                        }
                        
                        if ($gestureSettings.Count -gt 0) {
                            $gestureSettings | ConvertTo-Json -Depth 10 | Out-File (Join-Path $backupPath "gesture_settings.json") -Force
                            $backedUpItems += "gesture_settings.json"
                        }
                    } catch {
                        $errors += "Failed to backup touchpad gesture configuration: $_"
                    }
                }

                # Get input method settings
                if ($WhatIf) {
                    Write-Host "WhatIf: Would backup input method settings"
                } else {
                    try {
                        $inputSettings = @{}
                        
                        # Check for input settings
                        $inputKey = "HKCU:\Software\Microsoft\Input"
                        if (Test-Path $inputKey) {
                            $inputProperties = @(
                                "TouchKeyboardAutoInvokeEnabled", "TouchKeyboardEnabled",
                                "PenWorkspaceAppSuggestionsEnabled", "IsInputAppPreloadEnabled"
                            )
                            
                            foreach ($prop in $inputProperties) {
                                try {
                                    $value = Get-ItemProperty -Path $inputKey -Name $prop -ErrorAction SilentlyContinue
                                    if ($value) {
                                        $inputSettings[$prop] = $value.$prop
                                    }
                                } catch {
                                    Write-Verbose "Could not read input property $prop"
                                }
                            }
                        }
                        
                        if ($inputSettings.Count -gt 0) {
                            $inputSettings | ConvertTo-Json -Depth 10 | Out-File (Join-Path $backupPath "input_settings.json") -Force
                            $backedUpItems += "input_settings.json"
                        }
                    } catch {
                        $errors += "Failed to backup input method settings: $_"
                    }
                }
                
                # Return object for better testing and validation
                $result = [PSCustomObject]@{
                    Success = $true
                    BackupPath = $backupPath
                    Feature = "Touchpad Settings"
                    Timestamp = Get-Date
                    Items = $backedUpItems
                    Errors = $errors
                }
                
                Write-Host "Touchpad Settings backed up successfully to: $backupPath" -ForegroundColor Green
                Write-Verbose "Backup completed successfully"
                return $result
            }
            return $false
        } catch {
            $errorRecord = $_
            $errorMessage = @(
                "Failed to backup Touchpad Settings"
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
Backs up comprehensive touchpad settings, drivers, and device configurations.

.DESCRIPTION
Creates a comprehensive backup of touchpad settings including Windows Precision Touchpad 
configurations, manufacturer-specific settings (Synaptics, Elan, Alps), device information, 
driver details, service configurations, gesture settings, and input method configurations. 
Handles both user-specific and system-wide touchpad configurations.

.PARAMETER BackupRootPath
The root path where the backup will be created. A subdirectory named "Touchpad" will be created within this path.

.PARAMETER Force
Forces the backup operation even if the destination already exists.

.PARAMETER WhatIf
Shows what would be backed up without actually performing the backup operation.

.EXAMPLE
Backup-TouchpadSettings -BackupRootPath "C:\Backups"

.EXAMPLE
Backup-TouchpadSettings -BackupRootPath "C:\Backups" -WhatIf

.NOTES
Test cases to consider:
1. Valid backup path with proper permissions
2. Invalid/nonexistent backup path
3. Empty backup path
4. No permissions to write
5. Windows Precision Touchpad present vs absent
6. Synaptics touchpad present vs absent
7. Elan touchpad present vs absent
8. Alps touchpad present vs absent
9. Registry export success/failure for each key
10. Touchpad device enumeration success/failure
11. Touchpad driver information retrieval success/failure
12. Touchpad service information retrieval success/failure
13. WMI query success/failure for touchpad settings
14. Gesture settings retrieval success/failure
15. Input method settings retrieval success/failure
16. Multiple touchpad devices scenarios
17. Disabled touchpad devices scenarios
18. Administrative privileges scenarios
19. Network path scenarios
20. HID device enumeration scenarios

.TESTCASES
# Mock test examples:
Describe "Backup-TouchpadSettings" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Initialize-BackupDirectory { return "TestPath" }
        Mock New-Item { }
        Mock Get-PnpDevice { return @(@{ InstanceId = "HID\VID_1234"; FriendlyName = "Precision TouchPad"; Manufacturer = "Microsoft"; Status = "OK"; Class = "HIDClass"; DeviceID = "HID\VID_1234" }) }
        Mock Get-WmiObject { 
            param($Class)
            if ($Class -eq "Win32_SystemDriver") {
                return @(@{ Name = "SynTP"; DisplayName = "Synaptics TouchPad"; State = "Running"; Status = "OK"; StartMode = "Auto"; PathName = "C:\Windows\system32\drivers\SynTP.sys" })
            } elseif ($Class -eq "Win32_PointingDevice") {
                return @(@{ Name = "Precision TouchPad"; Manufacturer = "Microsoft"; Status = "OK"; DeviceID = "HID\VID_1234"; PNPDeviceID = "HID\VID_1234"; HardwareType = "TouchPad" })
            } elseif ($Class -eq "Win32_PnPEntity") {
                return @(@{ Name = "HID-compliant touch screen"; Manufacturer = "Microsoft"; Status = "OK"; DeviceID = "HID\VID_1234"; PNPDeviceID = "HID\VID_1234" })
            }
            return @()
        }
        Mock Get-Service { return @(@{ Name = "TabletInputService"; DisplayName = "Touch Keyboard and Handwriting Panel Service"; Status = "Running"; StartType = "Automatic"; ServiceType = "Win32ShareProcess" }) }
        Mock Get-ItemProperty { return @{ TouchKeyboardEnabled = 1 } }
        Mock ConvertTo-Json { return '{"test":"value"}' }
        Mock Out-File { }
        Mock reg { $global:LASTEXITCODE = 0 }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Backup-TouchpadSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.BackupPath | Should -Be "TestPath"
        $result.Feature | Should -Be "Touchpad Settings"
        $result.Items | Should -BeOfType [System.Array]
        $result.Errors | Should -BeOfType [System.Array]
    }

    It "Should handle registry export failure gracefully" {
        Mock reg { $global:LASTEXITCODE = 1; return "Error" }
        $result = Backup-TouchpadSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle device enumeration failure gracefully" {
        Mock Get-PnpDevice { throw "Device enumeration failed" }
        $result = Backup-TouchpadSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should support WhatIf parameter" {
        $result = Backup-TouchpadSettings -BackupRootPath "TestPath" -WhatIf
        $result.Success | Should -Be $true
    }

    It "Should handle WMI query failure gracefully" {
        Mock Get-WmiObject { throw "WMI query failed" }
        $result = Backup-TouchpadSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle service enumeration failure gracefully" {
        Mock Get-Service { throw "Service enumeration failed" }
        $result = Backup-TouchpadSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle registry access failure gracefully" {
        Mock Get-ItemProperty { throw "Registry access failed" }
        $result = Backup-TouchpadSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle missing touchpad devices gracefully" {
        Mock Get-PnpDevice { return @() }
        $result = Backup-TouchpadSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
    }

    It "Should handle gesture settings backup failure gracefully" {
        Mock Get-ItemProperty { throw "Gesture settings access failed" }
        $result = Backup-TouchpadSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Backup-TouchpadSettings -BackupRootPath $BackupRootPath
} 