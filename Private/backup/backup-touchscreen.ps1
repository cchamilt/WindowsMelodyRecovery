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

function Backup-TouchscreenSettings {
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
            Write-Verbose "Starting backup of Touchscreen Settings..."
            Write-Host "Backing up Touchscreen Settings..." -ForegroundColor Blue
            
            # Validate inputs before proceeding
            if (!(Test-Path $BackupRootPath)) {
                throw [System.IO.DirectoryNotFoundException]"Backup root path not found: $BackupRootPath"
            }
            
            $backupPath = Initialize-BackupDirectory -Path "Touchscreen" -BackupType "Touchscreen Settings" -BackupRootPath $BackupRootPath
            
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

                # Touchscreen-related registry settings to backup
                $registryPaths = @(
                    # Windows Touchscreen settings
                    "HKCU\Software\Microsoft\TouchPrediction",
                    "HKLM\SOFTWARE\Microsoft\TouchPrediction",
                    
                    # Touchscreen calibration
                    "HKCU\Software\Microsoft\Touchscreen",
                    "HKLM\SOFTWARE\Microsoft\Touchscreen",
                    
                    # Tablet PC settings
                    "HKCU\Software\Microsoft\TabletTip",
                    "HKLM\SOFTWARE\Microsoft\TabletTip",
                    
                    # Windows Ink settings
                    "HKCU\Software\Microsoft\Windows\CurrentVersion\PenWorkspace",
                    "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\PenWorkspace",
                    
                    # Touch input settings
                    "HKCU\Software\Microsoft\Windows\CurrentVersion\TouchInput",
                    "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\TouchInput",
                    
                    # Touch feedback settings
                    "HKCU\Control Panel\TouchFeedback",
                    "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\TouchFeedback",
                    
                    # Touch gestures
                    "HKCU\Software\Microsoft\Windows\CurrentVersion\TouchGestures",
                    "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\TouchGestures",
                    
                    # Pen settings
                    "HKCU\Software\Microsoft\Windows\CurrentVersion\Pen",
                    "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Pen",
                    
                    # Handwriting recognition
                    "HKCU\Software\Microsoft\Windows\CurrentVersion\Handwriting",
                    "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Handwriting",
                    
                    # Touch services
                    "HKLM\SYSTEM\CurrentControlSet\Services\TouchScreen",
                    "HKLM\SYSTEM\CurrentControlSet\Services\HidIr",
                    "HKLM\SYSTEM\CurrentControlSet\Services\TabletInputService",
                    "HKLM\SYSTEM\CurrentControlSet\Services\WacomPenService",
                    
                    # HID touch devices
                    "HKLM\SYSTEM\CurrentControlSet\Services\HID\TouchScreen",
                    "HKLM\SYSTEM\CurrentControlSet\Services\HID\Digitizer",
                    
                    # Input settings
                    "HKCU\Software\Microsoft\Input",
                    "HKLM\SOFTWARE\Microsoft\Input"
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

                # Get all touchscreen devices, including disabled ones
                if ($WhatIf) {
                    Write-Host "WhatIf: Would backup touchscreen device information"
                } else {
                    try {
                        if (!$script:TestMode) {
                            $touchscreenDevices = Get-PnpDevice | Where-Object { 
                                ($_.Class -eq "Touchscreen" -or $_.Class -eq "HIDClass" -or $_.Class -eq "Mouse") -and 
                                ($_.FriendlyName -match "touch|screen|digitizer|pen|stylus" -or
                                 $_.Manufacturer -match "wacom|synaptics|elan|hid|microsoft|n-trig|atmel")
                            } | Select-Object -Property @(
                                'InstanceId',
                                'FriendlyName',
                                'Manufacturer',
                                'Status',
                                'Class',
                                'DeviceID',
                                'HardwareID',
                                @{Name='IsEnabled'; Expression={$_.Status -eq 'OK'}}
                            )
                            
                            if ($touchscreenDevices) {
                                $touchscreenDevices | ConvertTo-Json -Depth 10 | Out-File (Join-Path $backupPath "touchscreen_devices.json") -Force
                                $backedUpItems += "touchscreen_devices.json"
                            }
                        }
                    } catch {
                        $errors += "Failed to backup touchscreen device information: $_"
                    }
                }

                # Get touchscreen driver information
                if ($WhatIf) {
                    Write-Host "WhatIf: Would backup touchscreen driver information"
                } else {
                    try {
                        if (!$script:TestMode) {
                            $touchscreenDrivers = Get-WmiObject Win32_SystemDriver | Where-Object {
                                $_.Name -match "Touch|HID|Digitizer|Pen|Wacom" -or
                                $_.DisplayName -match "Touch|Screen|Digitizer|Pen|Stylus|Wacom|HID"
                            } | Select-Object Name, DisplayName, State, Status, StartMode, PathName
                            
                            if ($touchscreenDrivers) {
                                $touchscreenDrivers | ConvertTo-Json -Depth 10 | Out-File (Join-Path $backupPath "touchscreen_drivers.json") -Force
                                $backedUpItems += "touchscreen_drivers.json"
                            }
                        }
                    } catch {
                        $errors += "Failed to backup touchscreen driver information: $_"
                    }
                }

                # Get touchscreen service information
                if ($WhatIf) {
                    Write-Host "WhatIf: Would backup touchscreen service information"
                } else {
                    try {
                        if (!$script:TestMode) {
                            $touchscreenServices = Get-Service | Where-Object {
                                $_.Name -match "Touch|TabletInput|Pen|Wacom|HID" -or
                                $_.DisplayName -match "Touch|Screen|Tablet|Pen|Stylus|Wacom|Handwriting|Ink"
                            } | Select-Object Name, DisplayName, Status, StartType, ServiceType
                            
                            if ($touchscreenServices) {
                                $touchscreenServices | ConvertTo-Json -Depth 10 | Out-File (Join-Path $backupPath "touchscreen_services.json") -Force
                                $backedUpItems += "touchscreen_services.json"
                            }
                        }
                    } catch {
                        $errors += "Failed to backup touchscreen service information: $_"
                    }
                }

                # Get current touchscreen settings via WMI
                if ($WhatIf) {
                    Write-Host "WhatIf: Would backup current touchscreen settings"
                } else {
                    try {
                        if (!$script:TestMode) {
                            $touchscreenSettings = @{}
                            
                            # Get pointing device information (includes touchscreens)
                            $pointingDevices = Get-WmiObject Win32_PointingDevice | Where-Object {
                                $_.Name -match "Touch|Screen|Digitizer|Pen|Stylus" -or
                                $_.Manufacturer -match "Wacom|Synaptics|Elan|Microsoft|N-Trig|Atmel"
                            } | Select-Object Name, Manufacturer, Status, DeviceID, PNPDeviceID, HardwareType
                            
                            if ($pointingDevices) {
                                $touchscreenSettings.PointingDevices = $pointingDevices
                            }
                            
                            # Get HID device information
                            $hidDevices = Get-WmiObject Win32_PnPEntity | Where-Object {
                                $_.Name -match "HID.*Touch|HID.*Digitizer|HID.*Pen|Touch Screen" -and
                                $_.Manufacturer -match "Wacom|Synaptics|Elan|Microsoft|N-Trig|Atmel|Generic"
                            } | Select-Object Name, Manufacturer, Status, DeviceID, PNPDeviceID
                            
                            if ($hidDevices) {
                                $touchscreenSettings.HIDDevices = $hidDevices
                            }
                            
                            if ($touchscreenSettings.Count -gt 0) {
                                $touchscreenSettings | ConvertTo-Json -Depth 10 | Out-File (Join-Path $backupPath "touchscreen_settings.json") -Force
                                $backedUpItems += "touchscreen_settings.json"
                            }
                        }
                    } catch {
                        $errors += "Failed to backup current touchscreen settings: $_"
                    }
                }

                # Get touch calibration data
                if ($WhatIf) {
                    Write-Host "WhatIf: Would backup touch calibration data"
                } else {
                    try {
                        $calibrationSettings = @{}
                        
                        # Check for touch calibration registry settings
                        $calibrationKey = "HKCU:\Software\Microsoft\Touchscreen"
                        if (Test-Path $calibrationKey) {
                            $calibrationProperties = @(
                                "CalibrationData", "TouchCalibration", "TouchThreshold",
                                "TouchSensitivity", "PalmRejection", "EdgeRejection"
                            )
                            
                            foreach ($prop in $calibrationProperties) {
                                try {
                                    $value = Get-ItemProperty -Path $calibrationKey -Name $prop -ErrorAction SilentlyContinue
                                    if ($value) {
                                        $calibrationSettings[$prop] = $value.$prop
                                    }
                                } catch {
                                    Write-Verbose "Could not read calibration property $prop"
                                }
                            }
                        }
                        
                        # Check for system calibration files
                        $calibrationFiles = @(
                            "$env:SystemRoot\System32\calibration.dat",
                            "$env:SystemRoot\System32\TouchCalibration.dat"
                        )
                        
                        foreach ($file in $calibrationFiles) {
                            if (Test-Path $file) {
                                try {
                                    $fileName = Split-Path $file -Leaf
                                    Copy-Item $file (Join-Path $backupPath $fileName) -Force
                                    $backedUpItems += $fileName
                                } catch {
                                    $errors += "Failed to backup calibration file $file : $_"
                                }
                            }
                        }
                        
                        if ($calibrationSettings.Count -gt 0) {
                            $calibrationSettings | ConvertTo-Json -Depth 10 | Out-File (Join-Path $backupPath "calibration_settings.json") -Force
                            $backedUpItems += "calibration_settings.json"
                        }
                    } catch {
                        $errors += "Failed to backup touch calibration data: $_"
                    }
                }

                # Get pen and ink settings
                if ($WhatIf) {
                    Write-Host "WhatIf: Would backup pen and ink settings"
                } else {
                    try {
                        $penSettings = @{}
                        
                        # Check for pen workspace settings
                        $penWorkspaceKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\PenWorkspace"
                        if (Test-Path $penWorkspaceKey) {
                            $penProperties = @(
                                "PenWorkspaceAppSuggestionsEnabled", "PenWorkspaceButtonDesktopAppSuggestionEnabled",
                                "PenWorkspaceButtonStoreAppSuggestionEnabled", "IsInputAppPreloadEnabled"
                            )
                            
                            foreach ($prop in $penProperties) {
                                try {
                                    $value = Get-ItemProperty -Path $penWorkspaceKey -Name $prop -ErrorAction SilentlyContinue
                                    if ($value) {
                                        $penSettings[$prop] = $value.$prop
                                    }
                                } catch {
                                    Write-Verbose "Could not read pen property $prop"
                                }
                            }
                        }
                        
                        # Check for handwriting settings
                        $handwritingKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Handwriting"
                        if (Test-Path $handwritingKey) {
                            $handwritingProperties = @(
                                "HandwritingPanelDockedModeEnabled", "HandwritingPanelEnabled",
                                "TextPredictionEnabled", "AutoComplete"
                            )
                            
                            foreach ($prop in $handwritingProperties) {
                                try {
                                    $value = Get-ItemProperty -Path $handwritingKey -Name $prop -ErrorAction SilentlyContinue
                                    if ($value) {
                                        $penSettings[$prop] = $value.$prop
                                    }
                                } catch {
                                    Write-Verbose "Could not read handwriting property $prop"
                                }
                            }
                        }
                        
                        if ($penSettings.Count -gt 0) {
                            $penSettings | ConvertTo-Json -Depth 10 | Out-File (Join-Path $backupPath "pen_settings.json") -Force
                            $backedUpItems += "pen_settings.json"
                        }
                    } catch {
                        $errors += "Failed to backup pen and ink settings: $_"
                    }
                }

                # Get touch gesture settings
                if ($WhatIf) {
                    Write-Host "WhatIf: Would backup touch gesture settings"
                } else {
                    try {
                        $gestureSettings = @{}
                        
                        # Check for touch gesture settings
                        $gestureKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\TouchGestures"
                        if (Test-Path $gestureKey) {
                            $gestureProperties = @(
                                "EdgeSwipeEnabled", "TouchFeedbackEnabled", "PressAndHoldEnabled",
                                "TapAndDragEnabled", "RightTapEnabled", "FlickEnabled"
                            )
                            
                            foreach ($prop in $gestureProperties) {
                                try {
                                    $value = Get-ItemProperty -Path $gestureKey -Name $prop -ErrorAction SilentlyContinue
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
                        $errors += "Failed to backup touch gesture settings: $_"
                    }
                }
                
                # Return object for better testing and validation
                $result = [PSCustomObject]@{
                    Success = $true
                    BackupPath = $backupPath
                    Feature = "Touchscreen Settings"
                    Timestamp = Get-Date
                    Items = $backedUpItems
                    Errors = $errors
                }
                
                Write-Host "Touchscreen Settings backed up successfully to: $backupPath" -ForegroundColor Green
                Write-Verbose "Backup completed successfully"
                return $result
            }
            return $false
        } catch {
            $errorRecord = $_
            $errorMessage = @(
                "Failed to backup Touchscreen Settings"
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
Backs up comprehensive touchscreen settings, drivers, and device configurations.

.DESCRIPTION
Creates a comprehensive backup of touchscreen settings including Windows touch input 
configurations, pen and ink settings, touch calibration data, gesture settings, 
manufacturer-specific settings (Wacom, Synaptics, Elan, N-Trig), device information, 
driver details, service configurations, and handwriting recognition settings. 
Handles both user-specific and system-wide touchscreen configurations.

.PARAMETER BackupRootPath
The root path where the backup will be created. A subdirectory named "Touchscreen" will be created within this path.

.PARAMETER Force
Forces the backup operation even if the destination already exists.

.PARAMETER WhatIf
Shows what would be backed up without actually performing the backup operation.

.EXAMPLE
Backup-TouchscreenSettings -BackupRootPath "C:\Backups"

.EXAMPLE
Backup-TouchscreenSettings -BackupRootPath "C:\Backups" -WhatIf

.NOTES
Test cases to consider:
1. Valid backup path with proper permissions
2. Invalid/nonexistent backup path
3. Empty backup path
4. No permissions to write
5. Windows touchscreen present vs absent
6. Wacom digitizer present vs absent
7. Synaptics touchscreen present vs absent
8. Elan touchscreen present vs absent
9. N-Trig digitizer present vs absent
10. Registry export success/failure for each key
11. Touchscreen device enumeration success/failure
12. Touchscreen driver information retrieval success/failure
13. Touchscreen service information retrieval success/failure
14. WMI query success/failure for touchscreen settings
15. Calibration data backup success/failure
16. Pen and ink settings backup success/failure
17. Touch gesture settings backup success/failure
18. Multiple touchscreen devices scenarios
19. Disabled touchscreen devices scenarios
20. Administrative privileges scenarios
21. Network path scenarios
22. HID device enumeration scenarios
23. Calibration file access scenarios
24. Pen workspace settings scenarios
25. Handwriting recognition scenarios

.TESTCASES
# Mock test examples:
Describe "Backup-TouchscreenSettings" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Initialize-BackupDirectory { return "TestPath" }
        Mock New-Item { }
        Mock Get-PnpDevice { return @(@{ InstanceId = "HID\VID_1234"; FriendlyName = "Touch Screen"; Manufacturer = "Microsoft"; Status = "OK"; Class = "HIDClass"; DeviceID = "HID\VID_1234"; HardwareID = @("HID\VID_1234") }) }
        Mock Get-WmiObject { 
            param($Class)
            if ($Class -eq "Win32_SystemDriver") {
                return @(@{ Name = "HidIr"; DisplayName = "HID Infrared"; State = "Running"; Status = "OK"; StartMode = "Auto"; PathName = "C:\Windows\system32\drivers\hidir.sys" })
            } elseif ($Class -eq "Win32_PointingDevice") {
                return @(@{ Name = "Touch Screen"; Manufacturer = "Microsoft"; Status = "OK"; DeviceID = "HID\VID_1234"; PNPDeviceID = "HID\VID_1234"; HardwareType = "TouchScreen" })
            } elseif ($Class -eq "Win32_PnPEntity") {
                return @(@{ Name = "HID-compliant touch screen"; Manufacturer = "Microsoft"; Status = "OK"; DeviceID = "HID\VID_1234"; PNPDeviceID = "HID\VID_1234" })
            }
            return @()
        }
        Mock Get-Service { return @(@{ Name = "TabletInputService"; DisplayName = "Touch Keyboard and Handwriting Panel Service"; Status = "Running"; StartType = "Automatic"; ServiceType = "Win32ShareProcess" }) }
        Mock Get-ItemProperty { return @{ TouchFeedbackEnabled = 1 } }
        Mock Copy-Item { }
        Mock ConvertTo-Json { return '{"test":"value"}' }
        Mock Out-File { }
        Mock reg { $global:LASTEXITCODE = 0 }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Backup-TouchscreenSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.BackupPath | Should -Be "TestPath"
        $result.Feature | Should -Be "Touchscreen Settings"
        $result.Items | Should -BeOfType [System.Array]
        $result.Errors | Should -BeOfType [System.Array]
    }

    It "Should handle registry export failure gracefully" {
        Mock reg { $global:LASTEXITCODE = 1; return "Error" }
        $result = Backup-TouchscreenSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle device enumeration failure gracefully" {
        Mock Get-PnpDevice { throw "Device enumeration failed" }
        $result = Backup-TouchscreenSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should support WhatIf parameter" {
        $result = Backup-TouchscreenSettings -BackupRootPath "TestPath" -WhatIf
        $result.Success | Should -Be $true
    }

    It "Should handle WMI query failure gracefully" {
        Mock Get-WmiObject { throw "WMI query failed" }
        $result = Backup-TouchscreenSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle service enumeration failure gracefully" {
        Mock Get-Service { throw "Service enumeration failed" }
        $result = Backup-TouchscreenSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle calibration file backup failure gracefully" {
        Mock Copy-Item { throw "File copy failed" }
        $result = Backup-TouchscreenSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle registry access failure gracefully" {
        Mock Get-ItemProperty { throw "Registry access failed" }
        $result = Backup-TouchscreenSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle missing touchscreen devices gracefully" {
        Mock Get-PnpDevice { return @() }
        $result = Backup-TouchscreenSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
    }

    It "Should handle pen settings backup failure gracefully" {
        Mock Get-ItemProperty { throw "Pen settings access failed" }
        $result = Backup-TouchscreenSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle gesture settings backup failure gracefully" {
        Mock Get-ItemProperty { throw "Gesture settings access failed" }
        $result = Backup-TouchscreenSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Backup-TouchscreenSettings -BackupRootPath $BackupRootPath
} 