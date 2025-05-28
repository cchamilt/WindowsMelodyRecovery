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

function Backup-DisplaySettings {
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
            Write-Verbose "Starting backup of Display Settings..."
            Write-Host "Backing up Display Settings..." -ForegroundColor Blue
            
            # Validate inputs before proceeding
            if (!(Test-Path $BackupRootPath)) {
                throw [System.IO.DirectoryNotFoundException]"Backup root path not found: $BackupRootPath"
            }
            
            $backupPath = Initialize-BackupDirectory -Path "Display" -BackupType "Display Settings" -BackupRootPath $BackupRootPath
            
            if ($backupPath) {
                $backedUpItems = @()
                $errors = @()
                
                # Export display registry settings
                $regPaths = @(
                    # Display settings
                    "HKCU\Control Panel\Desktop",
                    "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers",
                    "HKLM\SYSTEM\CurrentControlSet\Control\Video",
                    "HKLM\SYSTEM\CurrentControlSet\Hardware Profiles\Current\System\CurrentControlSet\Control\Video",
                    
                    # Visual Effects and DWM
                    "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects",
                    "HKCU\Software\Microsoft\Windows\DWM",
                    
                    # Color calibration
                    "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ICM",
                    "HKCU\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ICM",
                    
                    # DPI settings
                    "HKCU\Control Panel\Desktop\WindowMetrics",
                    "HKCU\Software\Microsoft\Windows\CurrentVersion\ThemeManager",
                    
                    # HDR and advanced color
                    "HKCU\Software\Microsoft\Windows\CurrentVersion\VideoSettings",
                    "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\HDR"
                )

                foreach ($regPath in $regPaths) {
                    # Check if registry key exists before trying to export
                    $keyExists = $false
                    if ($regPath -match '^HKCU\\') {
                        $keyExists = Test-Path "Registry::HKEY_CURRENT_USER\$($regPath.Substring(5))"
                    } elseif ($regPath -match '^HKLM\\') {
                        $keyExists = Test-Path "Registry::HKEY_LOCAL_MACHINE\$($regPath.Substring(5))"
                    }
                    
                    if ($keyExists) {
                        $regFile = "$backupPath\$($regPath.Split('\')[-1]).reg"
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

                # Export Win32_VideoController configuration
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export video controllers to $backupPath\video_controllers.json"
                } else {
                    try {
                        $videoControllers = Get-CimInstance -Namespace root\cimv2 -ClassName Win32_VideoController | Select-Object -Property *
                        $videoControllers | ConvertTo-Json -Depth 10 | Out-File "$backupPath\video_controllers.json" -Force
                        $backedUpItems += "video_controllers.json"
                    } catch {
                        $errors += "Failed to export video controllers: $_"
                    }
                }

                # Get display configuration using WMI
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export display information to $backupPath\displays.json"
                } else {
                    try {
                        $displays = Get-WmiObject -Namespace root\wmi -Class WmiMonitorID | ForEach-Object {
                            @{
                                ManufacturerName = [System.Text.Encoding]::ASCII.GetString($_.ManufacturerName).Trim("`0")
                                ProductCodeID = [System.Text.Encoding]::ASCII.GetString($_.ProductCodeID).Trim("`0")
                                SerialNumberID = [System.Text.Encoding]::ASCII.GetString($_.SerialNumberID).Trim("`0")
                                UserFriendlyName = [System.Text.Encoding]::ASCII.GetString($_.UserFriendlyName).Trim("`0")
                                Settings = Get-WmiObject -Namespace root\wmi -Class WmiMonitorBasicDisplayParams | Where-Object { $_.InstanceName -eq $_.InstanceName }
                            }
                        }
                        $displays | ConvertTo-Json -Depth 10 | Out-File "$backupPath\displays.json" -Force
                        $backedUpItems += "displays.json"
                    } catch {
                        $errors += "Failed to export display information: $_"
                    }
                }

                # Export CCD profiles
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export color profiles to $backupPath\ColorProfiles"
                } else {
                    try {
                        $ccdPath = "$env:SystemRoot\System32\spool\drivers\color"
                        if (Test-Path $ccdPath) {
                            $ccdBackupPath = Join-Path $backupPath "ColorProfiles"
                            New-Item -ItemType Directory -Path $ccdBackupPath -Force | Out-Null
                            $colorProfiles = @()
                            
                            # Copy ICM files
                            $icmFiles = Get-ChildItem -Path "$ccdPath\*.icm" -ErrorAction SilentlyContinue
                            if ($icmFiles) {
                                Copy-Item -Path $icmFiles.FullName -Destination $ccdBackupPath -Force
                                $colorProfiles += $icmFiles.Name
                            }
                            
                            # Copy ICC files
                            $iccFiles = Get-ChildItem -Path "$ccdPath\*.icc" -ErrorAction SilentlyContinue
                            if ($iccFiles) {
                                Copy-Item -Path $iccFiles.FullName -Destination $ccdBackupPath -Force
                                $colorProfiles += $iccFiles.Name
                            }
                            
                            if ($colorProfiles.Count -gt 0) {
                                $backedUpItems += "ColorProfiles\$($colorProfiles -join ', ')"
                            }
                        }
                    } catch {
                        $errors += "Failed to export color profiles: $_"
                    }
                }
                
                # Return object for better testing and validation
                $result = [PSCustomObject]@{
                    Success = $true
                    BackupPath = $backupPath
                    Feature = "Display Settings"
                    Timestamp = Get-Date
                    Items = $backedUpItems
                    Errors = $errors
                }
                
                Write-Host "Display Settings backed up successfully to: $backupPath" -ForegroundColor Green
                Write-Verbose "Backup completed successfully"
                return $result
            }
            return $false
        } catch {
            $errorRecord = $_
            $errorMessage = @(
                "Failed to backup Display Settings"
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

# Export the function if being imported as a module
if ($MyInvocation.Line -eq "") {
    Export-ModuleMember -Function Backup-DisplaySettings
}

<#
.SYNOPSIS
Backs up Windows Display settings and configuration.

.DESCRIPTION
Creates a backup of Windows Display settings, including display configuration, video controller settings, color profiles, and monitor information.

.EXAMPLE
Backup-DisplaySettings -BackupRootPath "C:\Backups"

.NOTES
Test cases to consider:
1. Valid backup path with proper permissions
2. Invalid/nonexistent backup path
3. Empty backup path
4. No permissions to write
5. Registry export success/failure for each key
6. WMI query success/failure
7. Color profile export success/failure
8. Multiple display configuration
9. HDR settings export

.TESTCASES
# Mock test examples:
Describe "Backup-DisplaySettings" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Initialize-BackupDirectory { return "TestPath" }
        Mock reg { }
        Mock Get-CimInstance { return @(
            [PSCustomObject]@{
                Name = "NVIDIA GeForce RTX 3080"
                AdapterRAM = 1073741824
                DriverVersion = "31.0.15.3598"
            }
        )}
        Mock Get-WmiObject { return @(
            [PSCustomObject]@{
                ManufacturerName = [byte[]]@(77, 83, 73)
                ProductCodeID = [byte[]]@(77, 65, 71)
                SerialNumberID = [byte[]]@(49, 50, 51)
                UserFriendlyName = [byte[]]@(77, 83, 73)
            }
        )}
        Mock Get-ChildItem { return @(
            [PSCustomObject]@{
                Name = "sRGB Color Space Profile.icm"
                FullName = "C:\Windows\System32\spool\drivers\color\sRGB Color Space Profile.icm"
            }
        )}
        Mock Copy-Item { }
        Mock ConvertTo-Json { return '{"test":"value"}' }
        Mock Out-File { }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Backup-DisplaySettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.BackupPath | Should -Be "TestPath"
        $result.Feature | Should -Be "Display Settings"
    }

    It "Should handle registry export failure gracefully" {
        Mock reg { throw "Registry export failed" }
        $result = Backup-DisplaySettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Backup-DisplaySettings -BackupRootPath $BackupRootPath
} 