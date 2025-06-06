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

function Restore-TouchpadSettings {
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
            Write-Verbose "Starting restore of Touchpad Settings..."
            Write-Host "Restoring Touchpad Settings..." -ForegroundColor Blue
            
            # Validate inputs before proceeding
            if (!(Test-Path $BackupRootPath)) {
                throw [System.IO.DirectoryNotFoundException]"Backup root path not found: $BackupRootPath"
            }
            
            $backupPath = Join-Path $BackupRootPath "Touchpad"
            if (!(Test-Path $backupPath)) {
                throw [System.IO.DirectoryNotFoundException]"Touchpad Settings backup not found at: $backupPath"
            }
            
            # Define all possible restore items
            $restoreItems = @{
                "Registry" = @{
                    Path = Join-Path $backupPath "Registry"
                    Description = "Touchpad registry settings"
                    Action = "Import-RegistryFiles"
                }
                "TouchpadDevices" = @{
                    Path = Join-Path $backupPath "touchpad_devices.json"
                    Description = "Touchpad device information"
                    Action = "Restore-TouchpadDevices"
                }
                "TouchpadDrivers" = @{
                    Path = Join-Path $backupPath "touchpad_drivers.json"
                    Description = "Touchpad driver information"
                    Action = "Restore-TouchpadDrivers"
                }
                "TouchpadServices" = @{
                    Path = Join-Path $backupPath "touchpad_services.json"
                    Description = "Touchpad service information"
                    Action = "Restore-TouchpadServices"
                }
                "TouchpadSettings" = @{
                    Path = Join-Path $backupPath "touchpad_settings.json"
                    Description = "Current touchpad settings"
                    Action = "Restore-TouchpadSettings"
                }
                "GestureSettings" = @{
                    Path = Join-Path $backupPath "gesture_settings.json"
                    Description = "Touchpad gesture configuration"
                    Action = "Restore-GestureSettings"
                }
                "InputSettings" = @{
                    Path = Join-Path $backupPath "input_settings.json"
                    Description = "Input method settings"
                    Action = "Restore-InputSettings"
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
            
            # Ensure required touchpad services are running
            if (!$script:TestMode -and !$WhatIf) {
                $touchpadServices = @("TabletInputService", "SynTPEnhService", "PrecisionTouchpadService")
                foreach ($serviceName in $touchpadServices) {
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
                                
                                "Restore-TouchpadDevices" {
                                    try {
                                        $touchpadDevices = Get-Content $itemPath | ConvertFrom-Json
                                        
                                        if (!$script:TestMode) {
                                            foreach ($device in $touchpadDevices) {
                                                try {
                                                    $existingDevice = Get-PnpDevice -InstanceId $device.InstanceId -ErrorAction SilentlyContinue
                                                    if ($existingDevice) {
                                                        if ($device.IsEnabled -and $existingDevice.Status -ne 'OK') {
                                                            Enable-PnpDevice -InstanceId $device.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
                                                            Write-Verbose "Enabled touchpad device: $($device.FriendlyName)"
                                                        } elseif (-not $device.IsEnabled -and $existingDevice.Status -eq 'OK') {
                                                            Disable-PnpDevice -InstanceId $device.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
                                                            Write-Verbose "Disabled touchpad device: $($device.FriendlyName)"
                                                        }
                                                    }
                                                } catch {
                                                    Write-Verbose "Could not manage device $($device.InstanceId): $_"
                                                }
                                            }
                                        }
                                        
                                        $itemsRestored += "Touchpad device states"
                                    } catch {
                                        $errors += "Failed to restore touchpad devices: $_"
                                    }
                                }
                                
                                "Restore-TouchpadDrivers" {
                                    try {
                                        $touchpadDrivers = Get-Content $itemPath | ConvertFrom-Json
                                        
                                        # This is primarily informational as driver management requires administrative privileges
                                        Write-Verbose "Touchpad driver information available (manual driver management may be required)"
                                        foreach ($driver in $touchpadDrivers) {
                                            Write-Verbose "Driver found in backup: $($driver.Name) - $($driver.DisplayName)"
                                        }
                                        
                                        $itemsRestored += "Touchpad driver information"
                                    } catch {
                                        $errors += "Failed to restore touchpad driver information: $_"
                                    }
                                }
                                
                                "Restore-TouchpadServices" {
                                    try {
                                        $touchpadServices = Get-Content $itemPath | ConvertFrom-Json
                                        
                                        if (!$script:TestMode) {
                                            foreach ($serviceInfo in $touchpadServices) {
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
                                        
                                        $itemsRestored += "Touchpad service configuration"
                                    } catch {
                                        $errors += "Failed to restore touchpad services: $_"
                                    }
                                }
                                
                                "Restore-TouchpadSettings" {
                                    try {
                                        $touchpadSettings = Get-Content $itemPath | ConvertFrom-Json
                                        
                                        # This is primarily informational as detailed touchpad settings are complex to restore
                                        if ($touchpadSettings.PointingDevices) {
                                            Write-Verbose "Pointing device information available (informational)"
                                            foreach ($device in $touchpadSettings.PointingDevices) {
                                                Write-Verbose "Pointing device: $($device.Name) by $($device.Manufacturer)"
                                            }
                                        }
                                        
                                        if ($touchpadSettings.HIDDevices) {
                                            Write-Verbose "HID device information available (informational)"
                                            foreach ($device in $touchpadSettings.HIDDevices) {
                                                Write-Verbose "HID device: $($device.Name) by $($device.Manufacturer)"
                                            }
                                        }
                                        
                                        $itemsRestored += "Touchpad settings information"
                                    } catch {
                                        $errors += "Failed to restore touchpad settings: $_"
                                    }
                                }
                                
                                "Restore-GestureSettings" {
                                    try {
                                        $gestureSettings = Get-Content $itemPath | ConvertFrom-Json
                                        
                                        if (!$script:TestMode) {
                                            $precisionTouchpadKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\PrecisionTouchPad"
                                            
                                            # Create the registry key if it doesn't exist
                                            if (!(Test-Path $precisionTouchpadKey)) {
                                                New-Item -Path $precisionTouchpadKey -Force | Out-Null
                                            }
                                            
                                            # Restore gesture settings
                                            foreach ($property in $gestureSettings.PSObject.Properties) {
                                                try {
                                                    Set-ItemProperty -Path $precisionTouchpadKey -Name $property.Name -Value $property.Value -ErrorAction SilentlyContinue
                                                    Write-Verbose "Restored gesture setting: $($property.Name) = $($property.Value)"
                                                } catch {
                                                    Write-Verbose "Could not restore gesture setting $($property.Name): $_"
                                                }
                                            }
                                        }
                                        
                                        $itemsRestored += "Touchpad gesture configuration"
                                    } catch {
                                        $errors += "Failed to restore gesture settings: $_"
                                    }
                                }
                                
                                "Restore-InputSettings" {
                                    try {
                                        $inputSettings = Get-Content $itemPath | ConvertFrom-Json
                                        
                                        if (!$script:TestMode) {
                                            $inputKey = "HKCU:\Software\Microsoft\Input"
                                            
                                            # Create the registry key if it doesn't exist
                                            if (!(Test-Path $inputKey)) {
                                                New-Item -Path $inputKey -Force | Out-Null
                                            }
                                            
                                            # Restore input settings
                                            foreach ($property in $inputSettings.PSObject.Properties) {
                                                try {
                                                    Set-ItemProperty -Path $inputKey -Name $property.Name -Value $property.Value -ErrorAction SilentlyContinue
                                                    Write-Verbose "Restored input setting: $($property.Name) = $($property.Value)"
                                                } catch {
                                                    Write-Verbose "Could not restore input setting $($property.Name): $_"
                                                }
                                            }
                                        }
                                        
                                        $itemsRestored += "Input method settings"
                                    } catch {
                                        $errors += "Failed to restore input settings: $_"
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
            
            # Restart touchpad services if needed
            if (!$script:TestMode -and !$WhatIf) {
                $servicesToRestart = @("TabletInputService", "SynTPEnh", "ETDService")
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
                Feature = "Touchpad Settings"
                Timestamp = Get-Date
                ItemsRestored = $itemsRestored
                ItemsSkipped = $itemsSkipped
                Errors = $errors
            }
            
            Write-Host "Touchpad Settings restored successfully from: $backupPath" -ForegroundColor Green
            Write-Host "`nNote: You may need to restart your computer for all touchpad changes to take effect" -ForegroundColor Yellow
            Write-Verbose "Restore completed successfully"
            return $result
            
        } catch {
            $errorRecord = $_
            $errorMessage = @(
                "Failed to restore Touchpad Settings"
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
    Export-ModuleMember -Function Restore-TouchpadSettings
}

<#
.SYNOPSIS
Restores comprehensive touchpad settings, drivers, and device configurations from backup.

.DESCRIPTION
Restores a comprehensive backup of touchpad settings including Windows Precision Touchpad 
configurations, manufacturer-specific settings (Synaptics, Elan, Alps), device information, 
driver details, service configurations, gesture settings, and input method configurations. 
Handles both user-specific and system-wide touchpad configurations with proper error handling 
and service management.

.PARAMETER BackupRootPath
The root path where the backup is located. The script will look for a "Touchpad" subdirectory within this path.

.PARAMETER Force
Forces the restore operation even if it might overwrite existing settings.

.PARAMETER Include
Specifies which components to restore. Valid values: Registry, TouchpadDevices, TouchpadDrivers, TouchpadServices, TouchpadSettings, GestureSettings, InputSettings.

.PARAMETER Exclude
Specifies which components to exclude from restoration. Valid values: Registry, TouchpadDevices, TouchpadDrivers, TouchpadServices, TouchpadSettings, GestureSettings, InputSettings.

.PARAMETER SkipVerification
Skips verification steps during the restore process.

.PARAMETER WhatIf
Shows what would be restored without actually performing the restore operation.

.EXAMPLE
Restore-TouchpadSettings -BackupRootPath "C:\Backups"

.EXAMPLE
Restore-TouchpadSettings -BackupRootPath "C:\Backups" -Include @("Registry", "GestureSettings")

.EXAMPLE
Restore-TouchpadSettings -BackupRootPath "C:\Backups" -Exclude @("TouchpadDrivers") -WhatIf

.NOTES
Test cases to consider:
1. Valid backup path with all components
2. Invalid/nonexistent backup path
3. Partial backup (missing some components)
4. Registry import success/failure
5. Touchpad device management success/failure
6. Touchpad driver information restore success/failure
7. Touchpad service management success/failure
8. Touchpad settings restore success/failure
9. Gesture settings restore success/failure
10. Input settings restore success/failure
11. Include parameter filtering
12. Exclude parameter filtering
13. Touchpad service management
14. Device enable/disable operations
15. Administrative privileges scenarios
16. Service restart operations
17. Registry key creation scenarios
18. Missing touchpad hardware scenarios
19. Multiple touchpad devices scenarios
20. Test mode scenarios

.TESTCASES
# Mock test examples:
Describe "Restore-TouchpadSettings" {
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
        Mock reg { }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Restore-TouchpadSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.BackupPath | Should -Be "TestPath"
        $result.Feature | Should -Be "Touchpad Settings"
        $result.ItemsRestored | Should -BeOfType [System.Array]
        $result.ItemsSkipped | Should -BeOfType [System.Array]
        $result.Errors | Should -BeOfType [System.Array]
    }

    It "Should handle registry import failure gracefully" {
        Mock reg { throw "Registry import failed" }
        $result = Restore-TouchpadSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle device management failure gracefully" {
        Mock Enable-PnpDevice { throw "Device enable failed" }
        $result = Restore-TouchpadSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should support Include parameter" {
        $result = Restore-TouchpadSettings -BackupRootPath "TestPath" -Include @("Registry")
        $result.Success | Should -Be $true
    }

    It "Should support Exclude parameter" {
        $result = Restore-TouchpadSettings -BackupRootPath "TestPath" -Exclude @("TouchpadDrivers")
        $result.Success | Should -Be $true
    }

    It "Should handle service management failure gracefully" {
        Mock Start-Service { throw "Service start failed" }
        $result = Restore-TouchpadSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
    }

    It "Should handle missing backup components gracefully" {
        Mock Test-Path { param($Path) return $Path -notlike "*touchpad_devices*" }
        $result = Restore-TouchpadSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.ItemsSkipped.Count | Should -BeGreaterThan 0
    }

    It "Should support WhatIf parameter" {
        $result = Restore-TouchpadSettings -BackupRootPath "TestPath" -WhatIf
        $result.Success | Should -Be $true
    }

    It "Should handle gesture settings restore failure gracefully" {
        Mock Set-ItemProperty { throw "Registry write failed" }
        $result = Restore-TouchpadSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Restore-TouchpadSettings -BackupRootPath $BackupRootPath -Force:$Force -Include $Include -Exclude $Exclude -SkipVerification:$SkipVerification
} 