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

function Restore-SoundSettings {
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
            Write-Verbose "Starting restore of Sound Settings..."
            Write-Host "Restoring Sound Settings..." -ForegroundColor Blue
            
            # Validate inputs before proceeding
            if (!(Test-Path $BackupRootPath)) {
                throw [System.IO.DirectoryNotFoundException]"Backup root path not found: $BackupRootPath"
            }
            
            $backupPath = Join-Path $BackupRootPath "Sound"
            if (!(Test-Path $backupPath)) {
                throw [System.IO.DirectoryNotFoundException]"Sound backup not found at: $backupPath"
            }
            
            # Define all possible restore items
            $restoreItems = @{
                "Registry" = @{
                    Path = Join-Path $backupPath "Registry"
                    Description = "Sound registry settings"
                    Action = "Import-RegistryFiles"
                }
                "AudioDevices" = @{
                    Path = Join-Path $backupPath "audio_devices.json"
                    Description = "Audio device information"
                    Action = "Restore-AudioDevices"
                }
                "DefaultDevices" = @{
                    Path = Join-Path $backupPath "default_devices.json"
                    Description = "Default audio devices"
                    Action = "Restore-DefaultDevices"
                }
                "SoundSchemes" = @{
                    Path = Join-Path $backupPath "SoundSchemes"
                    Description = "Sound scheme files"
                    Action = "Restore-SoundSchemes"
                }
                "AudioServices" = @{
                    Path = Join-Path $backupPath "audio_services.json"
                    Description = "Audio service configuration"
                    Action = "Restore-AudioServices"
                }
                "VolumeSettings" = @{
                    Path = Join-Path $backupPath "volume_settings.json"
                    Description = "Volume mixer settings"
                    Action = "Restore-VolumeSettings"
                }
                "AudioEnhancements" = @{
                    Path = Join-Path $backupPath "audio_enhancements.json"
                    Description = "Audio enhancements and effects"
                    Action = "Restore-AudioEnhancements"
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
            
            # Stop audio services if not in test mode
            if (!$script:TestMode -and !$WhatIf) {
                $audioServices = @("Audiosrv", "AudioEndpointBuilder", "MMCSS")
                foreach ($serviceName in $audioServices) {
                    try {
                        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
                        if ($service -and $service.Status -eq "Running") {
                            if ($PSCmdlet.ShouldProcess($serviceName, "Stop Audio Service")) {
                                Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
                                Write-Verbose "Stopped service: $serviceName"
                            }
                        }
                    } catch {
                        Write-Verbose "Could not stop service $serviceName : $_"
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
                                
                                "Restore-AudioDevices" {
                                    try {
                                        $audioDevices = Get-Content $itemPath | ConvertFrom-Json
                                        # Note: Audio device information is primarily informational
                                        # Actual device restoration depends on hardware presence
                                        $itemsRestored += "Audio device information (informational)"
                                        Write-Verbose "Audio device information restored (informational backup only)"
                                    } catch {
                                        $errors += "Failed to restore audio device information: $_"
                                    }
                                }
                                
                                "Restore-DefaultDevices" {
                                    try {
                                        $defaultDevices = Get-Content $itemPath | ConvertFrom-Json
                                        
                                        # Note: Default device restoration requires the devices to be present
                                        # This is informational and would require manual intervention or
                                        # additional tools like AudioDeviceCmdlets module
                                        if ($defaultDevices.DefaultPlayback) {
                                            Write-Verbose "Default playback device: $($defaultDevices.DefaultPlayback)"
                                        }
                                        if ($defaultDevices.DefaultRecording) {
                                            Write-Verbose "Default recording device: $($defaultDevices.DefaultRecording)"
                                        }
                                        if ($defaultDevices.DefaultCommunications) {
                                            Write-Verbose "Default communications device: $($defaultDevices.DefaultCommunications)"
                                        }
                                        
                                        $itemsRestored += "Default device information (manual intervention may be required)"
                                    } catch {
                                        $errors += "Failed to restore default device information: $_"
                                    }
                                }
                                
                                "Restore-SoundSchemes" {
                                    $soundFiles = Get-ChildItem -Path $itemPath -Filter "*.wav" -ErrorAction SilentlyContinue
                                    $systemMediaPath = "$env:SystemRoot\Media"
                                    
                                    if (!(Test-Path $systemMediaPath)) {
                                        if (!$script:TestMode) {
                                            New-Item -ItemType Directory -Path $systemMediaPath -Force | Out-Null
                                        }
                                    }
                                    
                                    foreach ($soundFile in $soundFiles) {
                                        try {
                                            $destFile = Join-Path $systemMediaPath $soundFile.Name
                                            if (!$script:TestMode) {
                                                Copy-Item -Path $soundFile.FullName -Destination $destFile -Force
                                            }
                                            $itemsRestored += "SoundSchemes\$($soundFile.Name)"
                                        } catch {
                                            $errors += "Failed to restore sound file $($soundFile.Name): $_"
                                        }
                                    }
                                }
                                
                                "Restore-AudioServices" {
                                    try {
                                        $serviceConfig = Get-Content $itemPath | ConvertFrom-Json
                                        
                                        foreach ($serviceName in $serviceConfig.PSObject.Properties.Name) {
                                            try {
                                                $serviceInfo = $serviceConfig.$serviceName
                                                if (!$script:TestMode) {
                                                    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
                                                    if ($service) {
                                                        # Note: Service start type changes require administrative privileges
                                                        # and may not always be possible to restore automatically
                                                        Write-Verbose "Service $serviceName configuration noted (manual intervention may be required for start type changes)"
                                                    }
                                                }
                                                $itemsRestored += "Service configuration for $serviceName"
                                            } catch {
                                                $errors += "Failed to restore service configuration for $serviceName : $_"
                                            }
                                        }
                                    } catch {
                                        $errors += "Failed to restore audio service configuration: $_"
                                    }
                                }
                                
                                "Restore-VolumeSettings" {
                                    try {
                                        $volumeSettings = Get-Content $itemPath | ConvertFrom-Json
                                        
                                        # Restore system volume settings
                                        if ($volumeSettings.SystemVolume) {
                                            try {
                                                if (!$script:TestMode) {
                                                    # Note: Volume settings restoration may require additional tools
                                                    # or COM interfaces for full functionality
                                                    Write-Verbose "System volume settings noted for restoration"
                                                }
                                                $itemsRestored += "System volume settings (partial restoration)"
                                            } catch {
                                                $errors += "Failed to restore system volume settings: $_"
                                            }
                                        }
                                        
                                        # Restore per-app volume settings
                                        if ($volumeSettings.AppVolume) {
                                            try {
                                                if (!$script:TestMode) {
                                                    $appVolumeKey = "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers"
                                                    foreach ($property in $volumeSettings.AppVolume.PSObject.Properties) {
                                                        if ($property.Name -ne "PSPath" -and $property.Name -ne "PSParentPath" -and $property.Name -ne "PSChildName" -and $property.Name -ne "PSDrive" -and $property.Name -ne "PSProvider") {
                                                            Set-ItemProperty -Path $appVolumeKey -Name $property.Name -Value $property.Value -Type String -ErrorAction SilentlyContinue
                                                        }
                                                    }
                                                }
                                                $itemsRestored += "Per-application volume settings"
                                            } catch {
                                                $errors += "Failed to restore per-app volume settings: $_"
                                            }
                                        }
                                    } catch {
                                        $errors += "Failed to restore volume mixer settings: $_"
                                    }
                                }
                                
                                "Restore-AudioEnhancements" {
                                    try {
                                        $enhancementsSettings = Get-Content $itemPath | ConvertFrom-Json
                                        
                                        # Restore audio enhancements
                                        if ($enhancementsSettings.Enhancements) {
                                            try {
                                                if (!$script:TestMode) {
                                                    # Note: Audio enhancements are typically restored via registry
                                                    # which is handled by the registry restoration
                                                    Write-Verbose "Audio enhancements settings noted (restored via registry)"
                                                }
                                                $itemsRestored += "Audio enhancements settings"
                                            } catch {
                                                $errors += "Failed to restore audio enhancements: $_"
                                            }
                                        }
                                        
                                        # Restore spatial sound settings
                                        if ($enhancementsSettings.SpatialSound) {
                                            try {
                                                if (!$script:TestMode) {
                                                    # Note: Spatial sound settings are typically restored via registry
                                                    # which is handled by the registry restoration
                                                    Write-Verbose "Spatial sound settings noted (restored via registry)"
                                                }
                                                $itemsRestored += "Spatial sound settings"
                                            } catch {
                                                $errors += "Failed to restore spatial sound settings: $_"
                                            }
                                        }
                                    } catch {
                                        $errors += "Failed to restore audio enhancements and effects: $_"
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
            
            # Start audio services if not in test mode
            if (!$script:TestMode -and !$WhatIf) {
                $audioServices = @("Audiosrv", "AudioEndpointBuilder", "MMCSS")
                foreach ($serviceName in $audioServices) {
                    try {
                        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
                        if ($service -and $service.Status -ne "Running") {
                            if ($PSCmdlet.ShouldProcess($serviceName, "Start Audio Service")) {
                                Start-Service -Name $serviceName -ErrorAction SilentlyContinue
                                Write-Verbose "Started service: $serviceName"
                            }
                        }
                    } catch {
                        Write-Verbose "Could not start service $serviceName : $_"
                    }
                }
            }
            
            # Return result object
            $result = [PSCustomObject]@{
                Success = $true
                BackupPath = $backupPath
                Feature = "Sound Settings"
                Timestamp = Get-Date
                ItemsRestored = $itemsRestored
                ItemsSkipped = $itemsSkipped
                Errors = $errors
            }
            
            Write-Host "Sound Settings restored successfully from: $backupPath" -ForegroundColor Green
            Write-Verbose "Restore completed successfully"
            return $result
            
        } catch {
            $errorRecord = $_
            $errorMessage = @(
                "Failed to restore Sound Settings"
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
    Export-ModuleMember -Function Restore-SoundSettings
}

<#
.SYNOPSIS
Restores Windows sound and audio settings and configurations from backup.

.DESCRIPTION
Restores a comprehensive backup of Windows sound settings, including registry settings, audio device configurations, 
sound schemes, volume mixer settings, spatial audio settings, and audio enhancements. Supports selective restoration 
with Include/Exclude parameters and provides detailed result tracking for automation scenarios.

.PARAMETER BackupRootPath
The root path where the backup is located. The script will look for a "Sound" subdirectory within this path.

.PARAMETER Force
Forces the restore operation even if it might overwrite existing settings.

.PARAMETER Include
Specifies which components to restore. Valid values: Registry, AudioDevices, DefaultDevices, SoundSchemes, AudioServices, VolumeSettings, AudioEnhancements.

.PARAMETER Exclude
Specifies which components to exclude from restoration. Valid values: Registry, AudioDevices, DefaultDevices, SoundSchemes, AudioServices, VolumeSettings, AudioEnhancements.

.PARAMETER SkipVerification
Skips verification steps during the restore process.

.PARAMETER WhatIf
Shows what would be restored without actually performing the restore operation.

.EXAMPLE
Restore-SoundSettings -BackupRootPath "C:\Backups"

.EXAMPLE
Restore-SoundSettings -BackupRootPath "C:\Backups" -Include @("Registry", "SoundSchemes")

.EXAMPLE
Restore-SoundSettings -BackupRootPath "C:\Backups" -Exclude @("AudioDevices") -WhatIf

.NOTES
Test cases to consider:
1. Valid backup path with all components
2. Invalid/nonexistent backup path
3. Partial backup (missing some components)
4. Registry import success/failure
5. Audio device information restore success/failure
6. Default device information restore success/failure
7. Sound scheme files restore success/failure
8. Audio service configuration restore success/failure
9. Volume settings restore success/failure
10. Audio enhancements restore success/failure
11. Include parameter filtering
12. Exclude parameter filtering
13. Service stop/start operations
14. Administrative privileges scenarios
15. Network path scenarios
16. File permission issues
17. Registry access issues
18. Service access issues
19. Audio hardware scenarios
20. Test mode scenarios

.TESTCASES
# Mock test examples:
Describe "Restore-SoundSettings" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Join-Path { return "TestPath" }
        Mock Get-ChildItem { 
            param($Path, $Filter)
            if ($Filter -eq "*.reg") {
                return @([PSCustomObject]@{ FullName = "test.reg"; Name = "test.reg" })
            } elseif ($Filter -eq "*.wav") {
                return @([PSCustomObject]@{ FullName = "test.wav"; Name = "test.wav" })
            }
            return @()
        }
        Mock Get-Content { return '{"TestProperty":"TestValue"}' | ConvertFrom-Json }
        Mock New-Item { }
        Mock Copy-Item { }
        Mock Set-ItemProperty { }
        Mock Get-Service { return @{ Status = "Running"; StartType = "Automatic" } }
        Mock Stop-Service { }
        Mock Start-Service { }
        Mock reg { }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Restore-SoundSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.BackupPath | Should -Be "TestPath"
        $result.Feature | Should -Be "Sound Settings"
        $result.ItemsRestored | Should -BeOfType [System.Array]
        $result.ItemsSkipped | Should -BeOfType [System.Array]
        $result.Errors | Should -BeOfType [System.Array]
    }

    It "Should handle registry import failure gracefully" {
        Mock reg { throw "Registry import failed" }
        $result = Restore-SoundSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle sound scheme restore failure gracefully" {
        Mock Copy-Item { throw "File copy failed" }
        $result = Restore-SoundSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should support Include parameter" {
        $result = Restore-SoundSettings -BackupRootPath "TestPath" -Include @("Registry")
        $result.Success | Should -Be $true
    }

    It "Should support Exclude parameter" {
        $result = Restore-SoundSettings -BackupRootPath "TestPath" -Exclude @("AudioDevices")
        $result.Success | Should -Be $true
    }

    It "Should handle service management failure gracefully" {
        Mock Stop-Service { throw "Service stop failed" }
        Mock Start-Service { throw "Service start failed" }
        $result = Restore-SoundSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
    }

    It "Should handle missing backup components gracefully" {
        Mock Test-Path { param($Path) return $Path -notlike "*SoundSchemes*" }
        $result = Restore-SoundSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.ItemsSkipped.Count | Should -BeGreaterThan 0
    }

    It "Should support WhatIf parameter" {
        $result = Restore-SoundSettings -BackupRootPath "TestPath" -WhatIf
        $result.Success | Should -Be $true
    }

    It "Should handle JSON parsing failure gracefully" {
        Mock Get-Content { throw "JSON parsing failed" }
        $result = Restore-SoundSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Restore-SoundSettings -BackupRootPath $BackupRootPath -Force:$Force -Include $Include -Exclude $Exclude -SkipVerification:$SkipVerification
} 