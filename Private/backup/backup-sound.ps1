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

function Backup-SoundSettings {
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
            Write-Verbose "Starting backup of Sound Settings..."
            Write-Host "Backing up Sound Settings..." -ForegroundColor Blue
            
            # Validate inputs before proceeding
            if (!(Test-Path $BackupRootPath)) {
                throw [System.IO.DirectoryNotFoundException]"Backup root path not found: $BackupRootPath"
            }
            
            $backupPath = Initialize-BackupDirectory -Path "Sound" -BackupType "Sound Settings" -BackupRootPath $BackupRootPath
            
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

                # Registry paths for sound settings
                $registryPaths = @(
                    # Windows Audio settings
                    "HKCU\Software\Microsoft\Multimedia\Audio",
                    "HKCU\Software\Microsoft\Multimedia\Audio\DeviceCpl",
                    "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio",
                    "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Drivers32",
                    "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows",
                    
                    # Sound scheme and events
                    "HKCU\AppEvents\Schemes",
                    "HKCU\AppEvents\EventLabels",
                    "HKCU\AppEvents\Schemes\Apps",
                    "HKCU\AppEvents\Schemes\Names",
                    
                    # Spatial sound and enhancements
                    "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Audio",
                    "HKCU\Software\Microsoft\Windows\CurrentVersion\Audio",
                    "HKCU\Software\Microsoft\Windows\CurrentVersion\Audio\SpatialSound",
                    
                    # Volume mixer and per-app settings
                    "HKCU\Software\Microsoft\Windows\CurrentVersion\Multimedia\Audio",
                    "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Audio\AudioEnhancements",
                    
                    # Audio endpoint builder
                    "HKLM\SYSTEM\CurrentControlSet\Services\AudioEndpointBuilder",
                    "HKLM\SYSTEM\CurrentControlSet\Services\Audiosrv"
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
                                $backedUpItems += "Registry\$($path.Split('\')[-1]).reg"
                            } catch {
                                $errors += "Failed to export registry path $path : $_"
                            }
                        }
                    } else {
                        Write-Verbose "Registry key not found: $path"
                    }
                }

                # Export audio devices using WMI
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export audio device information"
                } else {
                    try {
                        $audioDevices = Get-WmiObject -Class Win32_SoundDevice | Select-Object -Property *
                        if ($audioDevices) {
                            $audioDevices | ConvertTo-Json -Depth 10 | Out-File "$backupPath\audio_devices.json" -Force
                            $backedUpItems += "audio_devices.json"
                        }
                    } catch {
                        $errors += "Could not retrieve sound device information: $_"
                    }
                }

                # Export default devices using MMDevice COM object
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export default audio devices"
                } else {
                    try {
                        # Define COM interfaces for audio device enumeration
                        if (!$script:TestMode) {
                            Add-Type -TypeDefinition @'
                                using System.Runtime.InteropServices;
                                [Guid("BCDE0395-E52F-467C-8E3D-C4579291692E"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
                                internal interface IMMDeviceEnumerator {
                                    int NotImpl1();
                                    int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice ppDevice);
                                }
                                [Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
                                internal interface IMMDevice {
                                    int Activate(ref Guid iid, int dwClsCtx, IntPtr pActivationParams, [MarshalAs(UnmanagedType.IUnknown)] out object ppInterface);
                                    int OpenPropertyStore(int stgmAccess, out IPropertyStore ppProperties);
                                    int GetId([MarshalAs(UnmanagedType.LPWStr)] out string ppstrId);
                                }
                                [Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
                                internal interface IPropertyStore {
                                    int GetCount(out int cProps);
                                    int GetAt(int iProp, out PropertyKey pkey);
                                    int GetValue(ref PropertyKey key, out PropVariant pv);
                                }
                                [StructLayout(LayoutKind.Sequential)]
                                internal struct PropertyKey {
                                    public Guid fmtid;
                                    public int pid;
                                }
                                [StructLayout(LayoutKind.Explicit)]
                                internal struct PropVariant {
                                    [FieldOffset(0)] public short vt;
                                    [FieldOffset(8)] public string pwszVal;
                                }
'@ -ErrorAction SilentlyContinue
                        }
                        
                        $defaultDevices = @{
                            DefaultPlayback = $null
                            DefaultRecording = $null
                            DefaultCommunications = $null
                        }

                        if (!$script:TestMode) {
                            $enumerator = [Activator]::CreateInstance([Type]::GetTypeFromCLSID([Guid]"BCDE0395-E52F-467C-8E3D-C4579291692E"))

                            # Get default playback device (eRender = 0, eConsole = 0)
                            $device = $null
                            $enumerator.GetDefaultAudioEndpoint(0, 0, [ref]$device)
                            if ($device) {
                                $id = ""
                                $device.GetId([ref]$id)
                                $defaultDevices.DefaultPlayback = $id
                            }

                            # Get default recording device (eCapture = 1, eConsole = 0)
                            $device = $null
                            $enumerator.GetDefaultAudioEndpoint(1, 0, [ref]$device)
                            if ($device) {
                                $id = ""
                                $device.GetId([ref]$id)
                                $defaultDevices.DefaultRecording = $id
                            }

                            # Get default communications device (eRender = 0, eCommunications = 1)
                            $device = $null
                            $enumerator.GetDefaultAudioEndpoint(0, 1, [ref]$device)
                            if ($device) {
                                $id = ""
                                $device.GetId([ref]$id)
                                $defaultDevices.DefaultCommunications = $id
                            }
                        }

                        $defaultDevices | ConvertTo-Json -Depth 10 | Out-File "$backupPath\default_devices.json" -Force
                        $backedUpItems += "default_devices.json"
                    } catch {
                        $errors += "Could not retrieve default audio devices: $_"
                    }
                }

                # Backup sound scheme files
                if ($WhatIf) {
                    Write-Host "WhatIf: Would backup sound scheme files"
                } else {
                    try {
                        $schemePath = "$env:SystemRoot\Media"
                        if (Test-Path $schemePath) {
                            $schemeBackupPath = Join-Path $backupPath "SoundSchemes"
                            New-Item -ItemType Directory -Path $schemeBackupPath -Force | Out-Null
                            
                            $soundFiles = Get-ChildItem -Path $schemePath -Filter "*.wav" -ErrorAction SilentlyContinue
                            if ($soundFiles) {
                                foreach ($file in $soundFiles) {
                                    Copy-Item -Path $file.FullName -Destination $schemeBackupPath -Force
                                }
                                $backedUpItems += "SoundSchemes (*.wav files)"
                            }
                        }
                    } catch {
                        $errors += "Failed to backup sound scheme files: $_"
                    }
                }

                # Export audio service configuration
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export audio service configuration"
                } else {
                    try {
                        $audioServices = @("Audiosrv", "AudioEndpointBuilder", "MMCSS")
                        $serviceConfig = @{}
                        
                        foreach ($serviceName in $audioServices) {
                            try {
                                $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
                                if ($service) {
                                    $serviceConfig[$serviceName] = @{
                                        Status = $service.Status
                                        StartType = $service.StartType
                                        DisplayName = $service.DisplayName
                                    }
                                }
                            } catch {
                                Write-Verbose "Could not get service information for: $serviceName"
                            }
                        }
                        
                        if ($serviceConfig.Count -gt 0) {
                            $serviceConfig | ConvertTo-Json -Depth 10 | Out-File "$backupPath\audio_services.json" -Force
                            $backedUpItems += "audio_services.json"
                        }
                    } catch {
                        $errors += "Failed to export audio service configuration: $_"
                    }
                }

                # Export volume mixer settings
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export volume mixer settings"
                } else {
                    try {
                        $volumeSettings = @{}
                        
                        # Get system volume settings
                        try {
                            $systemVolume = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Multimedia\Audio" -ErrorAction SilentlyContinue
                            if ($systemVolume) {
                                $volumeSettings.SystemVolume = $systemVolume
                            }
                        } catch {
                            Write-Verbose "Could not get system volume settings"
                        }
                        
                        # Get per-application volume settings from registry
                        try {
                            $appVolumeKey = "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers"
                            $appVolume = Get-ItemProperty -Path $appVolumeKey -ErrorAction SilentlyContinue
                            if ($appVolume) {
                                $volumeSettings.AppVolume = $appVolume
                            }
                        } catch {
                            Write-Verbose "Could not get per-app volume settings"
                        }
                        
                        if ($volumeSettings.Count -gt 0) {
                            $volumeSettings | ConvertTo-Json -Depth 10 | Out-File "$backupPath\volume_settings.json" -Force
                            $backedUpItems += "volume_settings.json"
                        }
                    } catch {
                        $errors += "Failed to export volume mixer settings: $_"
                    }
                }

                # Export audio enhancements and effects
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export audio enhancements and effects"
                } else {
                    try {
                        $enhancementsSettings = @{}
                        
                        # Get audio enhancements settings
                        try {
                            $enhancementsKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Audio\AudioEnhancements"
                            if (Test-Path "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Audio\AudioEnhancements") {
                                $enhancements = Get-ItemProperty -Path $enhancementsKey -ErrorAction SilentlyContinue
                                if ($enhancements) {
                                    $enhancementsSettings.Enhancements = $enhancements
                                }
                            }
                        } catch {
                            Write-Verbose "Could not get audio enhancements settings"
                        }
                        
                        # Get spatial sound settings
                        try {
                            $spatialKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Audio\SpatialSound"
                            if (Test-Path "Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Audio\SpatialSound") {
                                $spatial = Get-ItemProperty -Path $spatialKey -ErrorAction SilentlyContinue
                                if ($spatial) {
                                    $enhancementsSettings.SpatialSound = $spatial
                                }
                            }
                        } catch {
                            Write-Verbose "Could not get spatial sound settings"
                        }
                        
                        if ($enhancementsSettings.Count -gt 0) {
                            $enhancementsSettings | ConvertTo-Json -Depth 10 | Out-File "$backupPath\audio_enhancements.json" -Force
                            $backedUpItems += "audio_enhancements.json"
                        }
                    } catch {
                        $errors += "Failed to export audio enhancements and effects: $_"
                    }
                }
                
                # Return object for better testing and validation
                $result = [PSCustomObject]@{
                    Success = $true
                    BackupPath = $backupPath
                    Feature = "Sound Settings"
                    Timestamp = Get-Date
                    Items = $backedUpItems
                    Errors = $errors
                }
                
                Write-Host "Sound Settings backed up successfully to: $backupPath" -ForegroundColor Green
                Write-Verbose "Backup completed successfully"
                return $result
            }
            return $false
        } catch {
            $errorRecord = $_
            $errorMessage = @(
                "Failed to backup Sound Settings"
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
Backs up Windows sound and audio settings and configurations.

.DESCRIPTION
Creates a comprehensive backup of Windows sound settings, including registry settings, audio device configurations, 
sound schemes, volume mixer settings, spatial audio settings, and audio enhancements. Supports both system-wide 
and per-application audio configurations with detailed device and service information preservation.

.PARAMETER BackupRootPath
The root path where the backup will be created. A subdirectory named "Sound" will be created within this path.

.PARAMETER Force
Forces the backup operation even if the destination already exists.

.PARAMETER WhatIf
Shows what would be backed up without actually performing the backup operation.

.EXAMPLE
Backup-SoundSettings -BackupRootPath "C:\Backups"

.EXAMPLE
Backup-SoundSettings -BackupRootPath "C:\Backups" -WhatIf

.NOTES
Test cases to consider:
1. Valid backup path with proper permissions
2. Invalid/nonexistent backup path
3. Empty backup path
4. No permissions to write
5. Registry export success/failure for each key
6. Audio device enumeration success/failure
7. Default device detection success/failure
8. Sound scheme files backup success/failure
9. Audio service configuration export success/failure
10. Volume mixer settings export success/failure
11. Audio enhancements export success/failure
12. JSON serialization success/failure
13. No audio devices scenario
14. No sound scheme files scenario
15. Audio services not running scenario
16. COM object creation failure
17. WMI query failure
18. File permission issues
19. Network path scenarios
20. Administrative privileges scenarios

.TESTCASES
# Mock test examples:
Describe "Backup-SoundSettings" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Initialize-BackupDirectory { return "TestPath" }
        Mock New-Item { }
        Mock Get-WmiObject { return @(
            [PSCustomObject]@{
                Name = "Test Audio Device"
                DeviceID = "TEST_DEVICE_001"
                Status = "OK"
            }
        )}
        Mock Get-ChildItem { 
            param($Path, $Filter)
            if ($Filter -eq "*.wav") {
                return @([PSCustomObject]@{ FullName = "test.wav"; Name = "test.wav" })
            }
            return @()
        }
        Mock Get-Service { return @{
            Status = "Running"
            StartType = "Automatic"
            DisplayName = "Windows Audio"
        }}
        Mock Get-ItemProperty { return @{
            TestProperty = "TestValue"
        }}
        Mock ConvertTo-Json { return '{"test":"value"}' }
        Mock Out-File { }
        Mock Copy-Item { }
        Mock reg { }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Backup-SoundSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.BackupPath | Should -Be "TestPath"
        $result.Feature | Should -Be "Sound Settings"
        $result.Items | Should -BeOfType [System.Array]
        $result.Errors | Should -BeOfType [System.Array]
    }

    It "Should handle registry export failure gracefully" {
        Mock reg { throw "Failed to export registry" }
        $result = Backup-SoundSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle WMI query failure gracefully" {
        Mock Get-WmiObject { throw "WMI query failed" }
        $result = Backup-SoundSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should support WhatIf parameter" {
        $result = Backup-SoundSettings -BackupRootPath "TestPath" -WhatIf
        $result.Success | Should -Be $true
    }

    It "Should handle sound scheme backup failure gracefully" {
        Mock Copy-Item { throw "File copy failed" }
        $result = Backup-SoundSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle service configuration failure gracefully" {
        Mock Get-Service { throw "Service access denied" }
        $result = Backup-SoundSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle no sound files scenario" {
        Mock Get-ChildItem { return @() }
        $result = Backup-SoundSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
    }

    It "Should handle COM object failure gracefully" {
        Mock Add-Type { throw "COM type definition failed" }
        $result = Backup-SoundSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Backup-SoundSettings -BackupRootPath $BackupRootPath
} 