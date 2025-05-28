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
                
                # Export touchpad registry settings
                $regPaths = @(
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
                    
                    # General input settings
                    "HKLM\SYSTEM\CurrentControlSet\Services\MouseLikeTouchPad",
                    "HKLM\SYSTEM\CurrentControlSet\Services\SynTP",
                    "HKLM\SYSTEM\CurrentControlSet\Services\ETD"
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

                # Get all touchpad devices, including disabled ones
                $touchpadDevices = Get-PnpDevice | Where-Object { 
                    ($_.Class -eq "Mouse" -or $_.Class -eq "HIDClass") -and 
                    ($_.FriendlyName -match "touchpad|synaptics|elan|precision" -or
                     $_.Manufacturer -match "synaptics|elan|alps")
                } | Select-Object -Property @(
                    'InstanceId',
                    'FriendlyName',
                    'Manufacturer',
                    'Status',
                    @{Name='IsEnabled'; Expression={$_.Status -eq 'OK'}}
                )
                
                if ($touchpadDevices) {
                    $jsonFile = "$backupPath\touchpad_devices.json"
                    if ($WhatIf) {
                        Write-Host "WhatIf: Would export touchpad devices to $jsonFile"
                    } else {
                        $touchpadDevices | ConvertTo-Json | Out-File $jsonFile -Force
                        $backedUpItems += "touchpad_devices.json"
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

# Export the function if being imported as a module
if ($MyInvocation.Line -eq "") {
    Export-ModuleMember -Function Backup-TouchpadSettings
}

<#
.SYNOPSIS
Backs up Windows Touchpad settings and configuration.

.DESCRIPTION
Creates a backup of Windows Touchpad settings, including Precision Touchpad settings, Synaptics settings, Elan settings, and device information.

.EXAMPLE
Backup-TouchpadSettings -BackupRootPath "C:\Backups"

.NOTES
Test cases to consider:
1. Valid backup path with proper permissions
2. Invalid/nonexistent backup path
3. Empty backup path
4. No permissions to write
5. Registry export success/failure for each key
6. Device detection success/failure
7. JSON export success/failure

.TESTCASES
# Mock test examples:
Describe "Backup-TouchpadSettings" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Initialize-BackupDirectory { return "TestPath" }
        Mock reg { }
        Mock Get-PnpDevice { return @(
            [PSCustomObject]@{
                Class = "Mouse"
                FriendlyName = "Synaptics TouchPad"
                Manufacturer = "Synaptics"
                Status = "OK"
            }
        )}
        Mock ConvertTo-Json { return '{"InstanceId":"test","FriendlyName":"test"}' }
        Mock Out-File { }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Backup-TouchpadSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.BackupPath | Should -Be "TestPath"
        $result.Feature | Should -Be "Touchpad Settings"
    }

    It "Should handle registry export failure gracefully" {
        Mock reg { throw "Registry export failed" }
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