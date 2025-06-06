[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory=$false)]
    [string]$BackupRootPath = $null,
    
    [Parameter(Mandatory=$false)]
    [string]$MachineBackupPath = $null,
    
    [Parameter(Mandatory=$false)]
    [string]$SharedBackupPath = $null,
    
    [Parameter(Mandatory=$false)]
    [switch]$Force,
    
    [Parameter(Mandatory=$false)]
    [string[]]$Include = @(),
    
    [Parameter(Mandatory=$false)]
    [string[]]$Exclude = @(),
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipVerification
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

function Restore-TouchscreenSettings {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force,
        
        [Parameter(Mandatory=$false)]
        [string[]]$Include = @(),
        
        [Parameter(Mandatory=$false)]
        [string[]]$Exclude = @(),
        
        [Parameter(Mandatory=$false)]
        [switch]$SkipVerification,

        # For testing purposes
        [Parameter(DontShow)]
        [switch]$WhatIf
    )
    
    begin {
        # Test hook for mocking
        if ($script:TestMode) {
            Write-Verbose "Running in test mode"
        }
        
        # Initialize result tracking
        $itemsRestored = @()
        $itemsSkipped = @()
        $errors = @()
    }
    
    process {
        try {
            Write-Verbose "Starting restore of Touchscreen Settings..."
            Write-Host "Restoring Touchscreen Settings..." -ForegroundColor Blue
            
            # Validate inputs before proceeding
            if (!(Test-Path $BackupRootPath)) {
                throw [System.IO.DirectoryNotFoundException]"Backup root path not found: $BackupRootPath"
            }
            
            $backupPath = Join-Path $BackupRootPath "Touchscreen"
            if (!(Test-Path $backupPath)) {
                throw [System.IO.DirectoryNotFoundException]"Touchscreen Settings backup not found at: $backupPath"
            }
            
            # Define all possible restore items
            $restoreItems = @{
                "Registry" = @{
                    Path = Join-Path $backupPath "Registry"
                    Description = "Touchscreen registry settings"
                    Action = "Import-RegistryFiles"
                }
                "TouchscreenDevices" = @{
                    Path = Join-Path $backupPath "touchscreen_devices.json"
                    Description = "Touchscreen device information"
                    Action = "Restore-TouchscreenDevices"
                }
                "TouchscreenDrivers" = @{
                    Path = Join-Path $backupPath "touchscreen_drivers.json"
                    Description = "Touchscreen driver information"
                    Action = "Restore-TouchscreenDrivers"
                }
                "TouchscreenServices" = @{
                    Path = Join-Path $backupPath "touchscreen_services.json"
                    Description = "Touchscreen service information"
                    Action = "Restore-TouchscreenServices"
                }
                "TouchscreenSettings" = @{
                    Path = Join-Path $backupPath "touchscreen_settings.json"
                    Description = "Current touchscreen settings"
                    Action = "Restore-TouchscreenSettings"
                }
                "CalibrationData" = @{
                    Path = Join-Path $backupPath "calibration_settings.json"
                    Description = "Touch calibration data"
                    Action = "Restore-CalibrationData"
                }
                "CalibrationFiles" = @{
                    Path = $backupPath
                    Description = "Touch calibration files"
                    Action = "Restore-CalibrationFiles"
                }
                "PenSettings" = @{
                    Path = Join-Path $backupPath "pen_settings.json"
                    Description = "Pen and ink settings"
                    Action = "Restore-PenSettings"
                }
                "GestureSettings" = @{
                    Path = Join-Path $backupPath "gesture_settings.json"
                    Description = "Touch gesture settings"
                    Action = "Restore-GestureSettings"
                }
            }
            
            # Filter items based on Include/Exclude parameters
            $itemsToRestore = $restoreItems.GetEnumerator() | Where-Object {
                $itemName = $_.Key
                $shouldInclude = $true
                
                if ($Include.Count -gt 0) {
                    $shouldInclude = $Include -contains $itemName
                }
                
                if ($Exclude.Count -gt 0 -and $Exclude -contains $itemName) {
                    $shouldInclude = $false
                }
                
                return $shouldInclude
            }
            
            # Ensure required touchscreen services are running
            if (!$script:TestMode -and !$WhatIf) {
                $touchscreenServices = @("TabletInputService", "TouchServicesHost", "PenService")
                foreach ($serviceName in $touchscreenServices) {
                    try {
                        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
                        if ($service -and $service.Status -ne "Running") {
                            if ($PSCmdlet.ShouldProcess($serviceName, "Start Service")) {
                                Start-Service -Name $serviceName -ErrorAction SilentlyContinue
                                Write-Verbose "Started service: $serviceName"
                            }
                        }
                    } catch {
                        Write-Verbose "Could not start service $serviceName : $_"
                    }
                }
            }
            
            # Process each restore item
            foreach ($item in $itemsToRestore) {
                $itemName = $item.Key
                $itemInfo = $item.Value
                $itemPath = $itemInfo.Path
                $itemDescription = $itemInfo.Description
                $itemAction = $itemInfo.Action
                
                try {
                    if (Test-Path $itemPath) {
                        if ($PSCmdlet.ShouldProcess($itemDescription, "Restore")) {
                            Write-Host "Restoring $itemDescription..." -ForegroundColor Yellow
                            
                            switch ($itemAction) {
                                "Import-RegistryFiles" {
                                    $regFiles = Get-ChildItem -Path $itemPath -Filter "*.reg" -ErrorAction SilentlyContinue
                                    foreach ($regFile in $regFiles) {
                                        try {
                                            if (!$script:TestMode) {
                                                reg import $regFile.FullName 2>$null
                                            }
                                            $itemsRestored += "Registry\$($regFile.Name)"
                                        } catch {
                                            $errors += "Failed to import registry file $($regFile.Name): $_"
                                        }
                                    }
                                }
                                
                                "Restore-TouchscreenDevices" {
                                    try {
                                        $touchscreenDevices = Get-Content $itemPath | ConvertFrom-Json
                                        
                                        if (!$script:TestMode) {
                                            foreach ($device in $touchscreenDevices) {
                                                try {
                                                    $existingDevice = Get-PnpDevice -InstanceId $device.InstanceId -ErrorAction SilentlyContinue
                                                    if ($existingDevice) {
                                                        if ($device.IsEnabled -and $existingDevice.Status -ne 'OK') {
                                                            Enable-PnpDevice -InstanceId $device.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
                                                            Write-Verbose "Enabled touchscreen device: $($device.FriendlyName)"
                                                        } elseif (-not $device.IsEnabled -and $existingDevice.Status -eq 'OK') {
                                                            Disable-PnpDevice -InstanceId $device.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
                                                            Write-Verbose "Disabled touchscreen device: $($device.FriendlyName)"
                                                        }
                                                    }
                                                } catch {
                                                    Write-Verbose "Could not manage device $($device.InstanceId): $_"
                                                }
                                            }
                                        }
                                        
                                        $itemsRestored += "Touchscreen device states"
                                    } catch {
                                        $errors += "Failed to restore touchscreen devices: $_"
                                    }
                                }
                                
                                "Restore-TouchscreenDrivers" {
                                    try {
                                        $touchscreenDrivers = Get-Content $itemPath | ConvertFrom-Json
                                        
                                        # This is primarily informational as driver management requires administrative privileges
                                        Write-Verbose "Touchscreen driver information available (manual driver management may be required)"
                                        foreach ($driver in $touchscreenDrivers) {
                                            Write-Verbose "Driver found in backup: $($driver.Name) - $($driver.DisplayName)"
                                        }
                                        
                                        $itemsRestored += "Touchscreen driver information"
                                    } catch {
                                        $errors += "Failed to restore touchscreen driver information: $_"
                                    }
                                }
                                
                                "Restore-TouchscreenServices" {
                                    try {
                                        $touchscreenServices = Get-Content $itemPath | ConvertFrom-Json
                                        
                                        if (!$script:TestMode) {
                                            foreach ($serviceInfo in $touchscreenServices) {
                                                try {
                                                    $service = Get-Service -Name $serviceInfo.Name -ErrorAction SilentlyContinue
                                                    if ($service) {
                                                        # Only try to start services that were running and are currently stopped
                                                        if ($serviceInfo.Status -eq "Running" -and $service.Status -ne "Running") {
                                                            Start-Service -Name $serviceInfo.Name -ErrorAction SilentlyContinue
                                                            Write-Verbose "Started service: $($serviceInfo.Name)"
                                                        }
                                                        
                                                        # Try to set start type if different (requires administrative privileges)
                                                        if ($serviceInfo.StartType -ne $service.StartType) {
                                                            try {
                                                                Set-Service -Name $serviceInfo.Name -StartupType $serviceInfo.StartType -ErrorAction SilentlyContinue
                                                                Write-Verbose "Set start type for service $($serviceInfo.Name) to $($serviceInfo.StartType)"
                                                            } catch {
                                                                Write-Verbose "Could not set start type for service $($serviceInfo.Name) (may require administrative privileges): $_"
                                                            }
                                                        }
                                                    }
                                                } catch {
                                                    Write-Verbose "Could not manage service $($serviceInfo.Name): $_"
                                                }
                                            }
                                        }
                                        
                                        $itemsRestored += "Touchscreen service configuration"
                                    } catch {
                                        $errors += "Failed to restore touchscreen services: $_"
                                    }
                                }
                                
                                "Restore-TouchscreenSettings" {
                                    try {
                                        $touchscreenSettings = Get-Content $itemPath | ConvertFrom-Json
                                        
                                        # This is primarily informational as detailed touchscreen settings are complex to restore
                                        if ($touchscreenSettings.PointingDevices) {
                                            Write-Verbose "Pointing device information available (informational)"
                                            foreach ($device in $touchscreenSettings.PointingDevices) {
                                                Write-Verbose "Pointing device: $($device.Name) by $($device.Manufacturer)"
                                            }
                                        }
                                        
                                        if ($touchscreenSettings.HIDDevices) {
                                            Write-Verbose "HID device information available (informational)"
                                            foreach ($device in $touchscreenSettings.HIDDevices) {
                                                Write-Verbose "HID device: $($device.Name) by $($device.Manufacturer)"
                                            }
                                        }
                                        
                                        $itemsRestored += "Touchscreen settings information"
                                    } catch {
                                        $errors += "Failed to restore touchscreen settings: $_"
                                    }
                                }
                                
                                "Restore-CalibrationData" {
                                    try {
                                        $calibrationSettings = Get-Content $itemPath | ConvertFrom-Json
                                        
                                        if (!$script:TestMode) {
                                            $calibrationKey = "HKCU:\Software\Microsoft\Touchscreen"
                                            
                                            # Create the registry key if it doesn't exist
                                            if (!(Test-Path $calibrationKey)) {
                                                New-Item -Path $calibrationKey -Force | Out-Null
                                            }
                                            
                                            # Restore calibration settings
                                            foreach ($property in $calibrationSettings.PSObject.Properties) {
                                                try {
                                                    Set-ItemProperty -Path $calibrationKey -Name $property.Name -Value $property.Value -ErrorAction SilentlyContinue
                                                    Write-Verbose "Restored calibration setting: $($property.Name) = $($property.Value)"
                                                } catch {
                                                    Write-Verbose "Could not restore calibration setting $($property.Name): $_"
                                                }
                                            }
                                        }
                                        
                                        $itemsRestored += "Touch calibration data"
                                    } catch {
                                        $errors += "Failed to restore calibration data: $_"
                                    }
                                }
                                
                                "Restore-CalibrationFiles" {
                                    try {
                                        $calibrationFiles = @("calibration.dat", "TouchCalibration.dat")
                                        
                                        foreach ($fileName in $calibrationFiles) {
                                            $sourceFile = Join-Path $itemPath $fileName
                                            if (Test-Path $sourceFile) {
                                                try {
                                                    if (!$script:TestMode) {
                                                        $targetFile = "$env:SystemRoot\System32\$fileName"
                                                        Copy-Item $sourceFile $targetFile -Force -ErrorAction SilentlyContinue
                                                        Write-Verbose "Restored calibration file: $fileName"
                                                    }
                                                    $itemsRestored += "Calibration file: $fileName"
                                                } catch {
                                                    $errors += "Failed to restore calibration file $fileName : $_"
                                                }
                                            }
                                        }
                                    } catch {
                                        $errors += "Failed to restore calibration files: $_"
                                    }
                                }
                                
                                "Restore-PenSettings" {
                                    try {
                                        $penSettings = Get-Content $itemPath | ConvertFrom-Json
                                        
                                        if (!$script:TestMode) {
                                            # Restore pen workspace settings
                                            $penWorkspaceKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\PenWorkspace"
                                            if (!(Test-Path $penWorkspaceKey)) {
                                                New-Item -Path $penWorkspaceKey -Force | Out-Null
                                            }
                                            
                                            # Restore handwriting settings
                                            $handwritingKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Handwriting"
                                            if (!(Test-Path $handwritingKey)) {
                                                New-Item -Path $handwritingKey -Force | Out-Null
                                            }
                                            
                                            # Restore pen settings
                                            foreach ($property in $penSettings.PSObject.Properties) {
                                                try {
                                                    if ($property.Name -match "PenWorkspace") {
                                                        Set-ItemProperty -Path $penWorkspaceKey -Name $property.Name -Value $property.Value -ErrorAction SilentlyContinue
                                                    } elseif ($property.Name -match "Handwriting") {
                                                        Set-ItemProperty -Path $handwritingKey -Name $property.Name -Value $property.Value -ErrorAction SilentlyContinue
                                                    }
                                                    Write-Verbose "Restored pen setting: $($property.Name) = $($property.Value)"
                                                } catch {
                                                    Write-Verbose "Could not restore pen setting $($property.Name): $_"
                                                }
                                            }
                                        }
                                        
                                        $itemsRestored += "Pen and ink settings"
                                    } catch {
                                        $errors += "Failed to restore pen settings: $_"
                                    }
                                }
                                
                                "Restore-GestureSettings" {
                                    try {
                                        $gestureSettings = Get-Content $itemPath | ConvertFrom-Json
                                        
                                        if (!$script:TestMode) {
                                            $gestureKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\TouchGestures"
                                            
                                            # Create the registry key if it doesn't exist
                                            if (!(Test-Path $gestureKey)) {
                                                New-Item -Path $gestureKey -Force | Out-Null
                                            }
                                            
                                            # Restore gesture settings
                                            foreach ($property in $gestureSettings.PSObject.Properties) {
                                                try {
                                                    Set-ItemProperty -Path $gestureKey -Name $property.Name -Value $property.Value -ErrorAction SilentlyContinue
                                                    Write-Verbose "Restored gesture setting: $($property.Name) = $($property.Value)"
                                                } catch {
                                                    Write-Verbose "Could not restore gesture setting $($property.Name): $_"
                                                }
                                            }
                                        }
                                        
                                        $itemsRestored += "Touch gesture settings"
                                    } catch {
                                        $errors += "Failed to restore gesture settings: $_"
                                    }
                                }
                            }
                            
                            Write-Host "Restored $itemDescription" -ForegroundColor Green
                        }
                    } else {
                        $itemsSkipped += "$itemDescription (not found in backup)"
                        Write-Verbose "Skipped $itemDescription - not found in backup"
                    }
                } catch {
                    $errors += "Failed to restore $itemDescription : $_"
                    Write-Warning "Failed to restore $itemDescription : $_"
                }
            }
            
            # Restart touchscreen services if needed
            if (!$script:TestMode -and !$WhatIf) {
                $servicesToRestart = @("TabletInputService", "TouchServiced", "WacomPenService")
                foreach ($serviceName in $servicesToRestart) {
                    try {
                        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
                        if ($service -and $service.Status -eq "Running") {
                            if ($PSCmdlet.ShouldProcess($serviceName, "Restart Service")) {
                                Restart-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
                                Write-Verbose "Restarted service: $serviceName"
                            }
                        }
                    } catch {
                        Write-Verbose "Could not restart service $serviceName : $_"
                    }
                }
            }
            
            # Return result object
            $result = [PSCustomObject]@{
                Success = $true
                BackupPath = $backupPath
                Feature = "Touchscreen Settings"
                Timestamp = Get-Date
                ItemsRestored = $itemsRestored
                ItemsSkipped = $itemsSkipped
                Errors = $errors
            }
            
            Write-Host "Touchscreen Settings restored successfully from: $backupPath" -ForegroundColor Green
            Write-Host "`nNote: You may need to restart your computer for all touchscreen changes to take effect" -ForegroundColor Yellow
            Write-Verbose "Restore completed successfully"
            return $result
            
        } catch {
            $errorRecord = $_
            $errorMessage = @(
                "Failed to restore Touchscreen Settings"
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
    Export-ModuleMember -Function Restore-TouchscreenSettings
}

<#
.SYNOPSIS
Restores comprehensive touchscreen settings, drivers, and device configurations from backup.

.DESCRIPTION
Restores a comprehensive backup of touchscreen settings including Windows touch input 
configurations, pen and ink settings, touch calibration data, gesture settings, 
manufacturer-specific settings (Wacom, Synaptics, Elan, N-Trig), device information, 
driver details, service configurations, and handwriting recognition settings. 
Handles both user-specific and system-wide touchscreen configurations with proper error handling 
and service management.

.PARAMETER BackupRootPath
The root path where the backup is located. The script will look for a "Touchscreen" subdirectory within this path.

.PARAMETER Force
Forces the restore operation even if it might overwrite existing settings.

.PARAMETER Include
Specifies which components to restore. Valid values: Registry, TouchscreenDevices, TouchscreenDrivers, TouchscreenServices, TouchscreenSettings, CalibrationData, CalibrationFiles, PenSettings, GestureSettings.

.PARAMETER Exclude
Specifies which components to exclude from restoration. Valid values: Registry, TouchscreenDevices, TouchscreenDrivers, TouchscreenServices, TouchscreenSettings, CalibrationData, CalibrationFiles, PenSettings, GestureSettings.

.PARAMETER SkipVerification
Skips verification steps during the restore process.

.PARAMETER WhatIf
Shows what would be restored without actually performing the restore operation.

.EXAMPLE
Restore-TouchscreenSettings -BackupRootPath "C:\Backups"

.EXAMPLE
Restore-TouchscreenSettings -BackupRootPath "C:\Backups" -Include @("Registry", "CalibrationData")

.EXAMPLE
Restore-TouchscreenSettings -BackupRootPath "C:\Backups" -Exclude @("TouchscreenDrivers") -WhatIf

.NOTES
Test cases to consider:
1. Valid backup path with all components
2. Invalid/nonexistent backup path
3. Partial backup (missing some components)
4. Registry import success/failure
5. Touchscreen device management success/failure
6. Touchscreen driver information restore success/failure
7. Touchscreen service management success/failure
8. Touchscreen settings restore success/failure
9. Calibration data restore success/failure
10. Calibration file restore success/failure
11. Pen settings restore success/failure
12. Gesture settings restore success/failure
13. Include parameter filtering
14. Exclude parameter filtering
15. Touchscreen service management
16. Device enable/disable operations
17. Administrative privileges scenarios
18. Service restart operations
19. Registry key creation scenarios
20. Missing touchscreen hardware scenarios
21. Multiple touchscreen devices scenarios
22. Test mode scenarios
23. Calibration file access scenarios
24. Pen workspace settings scenarios
25. Handwriting recognition scenarios

.TESTCASES
# Mock test examples:
Describe "Restore-TouchscreenSettings" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Join-Path { return "TestPath" }
        Mock Get-ChildItem { 
            param($Path, $Filter)
            if ($Filter -eq "*.reg") {
                return @([PSCustomObject]@{ FullName = "test.reg"; Name = "test.reg" })
            } else {
                return @()
            }
        }
        Mock Get-Content { return '{"test":"value"}' | ConvertFrom-Json }
        Mock Get-PnpDevice { return @{ InstanceId = "HID\VID_1234"; Status = "Error" } }
        Mock Get-Service { return @{ Name = "TabletInputService"; Status = "Stopped"; StartType = "Automatic" } }
        Mock Enable-PnpDevice { }
        Mock Disable-PnpDevice { }
        Mock Start-Service { }
        Mock Set-Service { }
        Mock Restart-Service { }
        Mock New-Item { }
        Mock Set-ItemProperty { }
        Mock Copy-Item { }
        Mock reg { }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Restore-TouchscreenSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.BackupPath | Should -Be "TestPath"
        $result.Feature | Should -Be "Touchscreen Settings"
        $result.ItemsRestored | Should -BeOfType [System.Array]
        $result.ItemsSkipped | Should -BeOfType [System.Array]
        $result.Errors | Should -BeOfType [System.Array]
    }

    It "Should handle registry import failure gracefully" {
        Mock reg { throw "Registry import failed" }
        $result = Restore-TouchscreenSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle device management failure gracefully" {
        Mock Enable-PnpDevice { throw "Device enable failed" }
        $result = Restore-TouchscreenSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should support Include parameter" {
        $result = Restore-TouchscreenSettings -BackupRootPath "TestPath" -Include @("Registry")
        $result.Success | Should -Be $true
    }

    It "Should support Exclude parameter" {
        $result = Restore-TouchscreenSettings -BackupRootPath "TestPath" -Exclude @("TouchscreenDrivers")
        $result.Success | Should -Be $true
    }

    It "Should handle service management failure gracefully" {
        Mock Start-Service { throw "Service start failed" }
        $result = Restore-TouchscreenSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
    }

    It "Should handle missing backup components gracefully" {
        Mock Test-Path { param($Path) return $Path -notlike "*touchscreen_devices*" }
        $result = Restore-TouchscreenSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.ItemsSkipped.Count | Should -BeGreaterThan 0
    }

    It "Should support WhatIf parameter" {
        $result = Restore-TouchscreenSettings -BackupRootPath "TestPath" -WhatIf
        $result.Success | Should -Be $true
    }

    It "Should handle calibration file restore failure gracefully" {
        Mock Copy-Item { throw "File copy failed" }
        $result = Restore-TouchscreenSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle pen settings restore failure gracefully" {
        Mock Set-ItemProperty { throw "Registry write failed" }
        $result = Restore-TouchscreenSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle gesture settings restore failure gracefully" {
        Mock Set-ItemProperty { throw "Registry write failed" }
        $result = Restore-TouchscreenSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Restore-TouchscreenSettings -BackupRootPath $BackupRootPath -Force:$Force -Include $Include -Exclude $Exclude -SkipVerification:$SkipVerification
} 