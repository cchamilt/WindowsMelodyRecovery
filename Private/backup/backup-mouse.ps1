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
            
            $backupPath = Initialize-BackupDirectory -Path "Mouse" -BackupType "Mouse" -BackupRootPath $BackupRootPath
            
            if ($backupPath) {
                $backedUpItems = @()
                $errors = @()
                
                # Registry paths for mouse settings
                $registryPaths = @(
                    "HKCU\Control Panel\Mouse",
                    "HKCU\Control Panel\Cursors",
                    "HKLM\SYSTEM\CurrentControlSet\Services\mouclass\Parameters",
                    "HKLM\SYSTEM\CurrentControlSet\Services\mouhid\Parameters"
                )

                # Export registry settings
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export registry settings for mouse"
                } else {
                    foreach ($path in $registryPaths) {
                        try {
                            $regFile = Join-Path $backupPath "mouse_$($path.Split('\')[-1]).reg"
                            reg export $path $regFile /y | Out-Null
                            $backedUpItems += "Registry: $path"
                        } catch {
                            $errors += "Failed to export registry path $path : $_"
                        }
                    }
                }

                # Get mouse device information
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export mouse device information"
                } else {
                    try {
                        $mouseInfo = Get-CimInstance -ClassName Win32_PointingDevice | Select-Object Name, Manufacturer, DeviceID, Status
                        $mouseInfo | ConvertTo-Json | Out-File "$backupPath\mouse_devices.json" -Force
                        $backedUpItems += "Mouse devices information"
                    } catch {
                        $errors += "Failed to get mouse device information: $_"
                    }
                }

                # Get mouse settings from Control Panel
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export mouse control panel settings"
                } else {
                    try {
                        $mouseSettings = @{
                            DoubleClickSpeed = (Get-ItemProperty -Path "HKCU:\Control Panel\Mouse" -Name DoubleClickSpeed).DoubleClickSpeed
                            MouseSpeed = (Get-ItemProperty -Path "HKCU:\Control Panel\Mouse" -Name MouseSpeed).MouseSpeed
                            MouseThreshold1 = (Get-ItemProperty -Path "HKCU:\Control Panel\Mouse" -Name MouseThreshold1).MouseThreshold1
                            MouseThreshold2 = (Get-ItemProperty -Path "HKCU:\Control Panel\Mouse" -Name MouseThreshold2).MouseThreshold2
                            MouseSensitivity = (Get-ItemProperty -Path "HKCU:\Control Panel\Mouse" -Name MouseSensitivity).MouseSensitivity
                            SnapToDefaultButton = (Get-ItemProperty -Path "HKCU:\Control Panel\Mouse" -Name SnapToDefaultButton).SnapToDefaultButton
                            SwapMouseButtons = (Get-ItemProperty -Path "HKCU:\Control Panel\Mouse" -Name SwapMouseButtons).SwapMouseButtons
                        }
                        $mouseSettings | ConvertTo-Json | Out-File "$backupPath\mouse_settings.json" -Force
                        $backedUpItems += "Mouse control panel settings"
                    } catch {
                        $errors += "Failed to get mouse control panel settings: $_"
                    }
                }
                
                # Return object for better testing and validation
                $result = [PSCustomObject]@{
                    Success = $true
                    BackupPath = $backupPath
                    Feature = "Mouse"
                    Timestamp = Get-Date
                    Items = $backedUpItems
                    Errors = $errors
                }
                
                Write-Host "Mouse settings backed up successfully to: $backupPath" -ForegroundColor Green
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

# Export the function if being imported as a module
if ($MyInvocation.Line -eq "") {
    Export-ModuleMember -Function Backup-MouseSettings
}

<#
.SYNOPSIS
Backs up mouse settings and configurations.

.DESCRIPTION
Creates a backup of mouse settings including registry settings, device information, and control panel configurations.

.EXAMPLE
Backup-MouseSettings -BackupRootPath "C:\Backups"

.NOTES
Test cases to consider:
1. Valid backup path with proper permissions
2. Invalid/nonexistent backup path
3. Empty backup path
4. No permissions to write
5. Registry export success/failure
6. Device information retrieval success/failure
7. Control panel settings retrieval success/failure
8. JSON serialization success/failure

.TESTCASES
# Mock test examples:
Describe "Backup-MouseSettings" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Initialize-BackupDirectory { return "TestPath" }
        Mock Get-CimInstance { return @(
            [PSCustomObject]@{
                Name = "Test Mouse"
                Manufacturer = "Test Manufacturer"
                DeviceID = "TestDeviceID"
                Status = "OK"
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
        $result.Feature | Should -Be "Mouse"
    }

    It "Should handle registry export failure gracefully" {
        Mock reg { throw "Failed to export registry" }
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