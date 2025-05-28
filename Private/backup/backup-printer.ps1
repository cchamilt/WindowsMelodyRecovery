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

function Backup-PrinterSettings {
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
            Write-Verbose "Starting backup of Printer Settings..."
            Write-Host "Backing up Printer Settings..." -ForegroundColor Blue
            
            # Validate inputs before proceeding
            if (!(Test-Path $BackupRootPath)) {
                throw [System.IO.DirectoryNotFoundException]"Backup root path not found: $BackupRootPath"
            }
            
            $backupPath = Initialize-BackupDirectory -Path "Printer" -BackupType "Printer" -BackupRootPath $BackupRootPath
            
            if ($backupPath) {
                $backedUpItems = @()
                $errors = @()
                
                # Registry paths for printer settings
                $registryPaths = @(
                    "HKLM\SYSTEM\CurrentControlSet\Control\Print\Printers",
                    "HKLM\SYSTEM\CurrentControlSet\Control\Print\Monitors",
                    "HKLM\SYSTEM\CurrentControlSet\Control\Print\Providers",
                    "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Print\Printers",
                    "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\Printer Cache"
                )

                # Export registry settings
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export registry settings for printers"
                } else {
                    foreach ($path in $registryPaths) {
                        try {
                            $regFile = Join-Path $backupPath "printer_$($path.Split('\')[-1]).reg"
                            reg export $path $regFile /y | Out-Null
                            $backedUpItems += "Registry: $path"
                        } catch {
                            $errors += "Failed to export registry path $path : $_"
                        }
                    }
                }

                # Get printer information
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export printer information"
                } else {
                    try {
                        $printers = Get-Printer | Select-Object Name, DriverName, PortName, Shared, ShareName, Published, DeviceType, Status
                        $printers | ConvertTo-Json | Out-File "$backupPath\printers.json" -Force
                        $backedUpItems += "Printer information"
                    } catch {
                        $errors += "Failed to get printer information: $_"
                    }
                }

                # Get printer ports
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export printer ports"
                } else {
                    try {
                        $printerPorts = Get-PrinterPort | Select-Object Name, HostAddress, PortNumber, Protocol
                        $printerPorts | ConvertTo-Json | Out-File "$backupPath\printer_ports.json" -Force
                        $backedUpItems += "Printer ports"
                    } catch {
                        $errors += "Failed to get printer ports: $_"
                    }
                }

                # Get printer drivers
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export printer drivers"
                } else {
                    try {
                        $printerDrivers = Get-PrinterDriver | Select-Object Name, Manufacturer, DriverVersion, Environment
                        $printerDrivers | ConvertTo-Json | Out-File "$backupPath\printer_drivers.json" -Force
                        $backedUpItems += "Printer drivers"
                    } catch {
                        $errors += "Failed to get printer drivers: $_"
                    }
                }

                # Export printer preferences
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export printer preferences"
                } else {
                    try {
                        $printerPreferences = @{
                            DefaultPrinter = (Get-Printer | Where-Object {$_.IsDefault}).Name
                            PrinterPreferences = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Windows" -Name "Device" -ErrorAction SilentlyContinue
                        }
                        $printerPreferences | ConvertTo-Json | Out-File "$backupPath\printer_preferences.json" -Force
                        $backedUpItems += "Printer preferences"
                    } catch {
                        $errors += "Failed to get printer preferences: $_"
                    }
                }
                
                # Return object for better testing and validation
                $result = [PSCustomObject]@{
                    Success = $true
                    BackupPath = $backupPath
                    Feature = "Printer"
                    Timestamp = Get-Date
                    Items = $backedUpItems
                    Errors = $errors
                }
                
                Write-Host "Printer settings backed up successfully to: $backupPath" -ForegroundColor Green
                Write-Verbose "Backup completed successfully"
                return $result
            }
            return $false
        } catch {
            $errorRecord = $_
            $errorMessage = @(
                "Failed to backup Printer Settings"
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
    Export-ModuleMember -Function Backup-PrinterSettings
}

<#
.SYNOPSIS
Backs up printer settings and configurations.

.DESCRIPTION
Creates a backup of printer settings including registry settings, printer information, ports, drivers, and preferences.

.EXAMPLE
Backup-PrinterSettings -BackupRootPath "C:\Backups"

.NOTES
Test cases to consider:
1. Valid backup path with proper permissions
2. Invalid/nonexistent backup path
3. Empty backup path
4. No permissions to write
5. Registry export success/failure
6. Printer information retrieval success/failure
7. Printer ports retrieval success/failure
8. Printer drivers retrieval success/failure
9. Printer preferences retrieval success/failure
10. JSON serialization success/failure

.TESTCASES
# Mock test examples:
Describe "Backup-PrinterSettings" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Initialize-BackupDirectory { return "TestPath" }
        Mock Get-Printer { return @(
            [PSCustomObject]@{
                Name = "Test Printer"
                DriverName = "Test Driver"
                PortName = "Test Port"
                Shared = $true
                ShareName = "TestShare"
                Published = $true
                DeviceType = "Local"
                Status = "Ready"
                IsDefault = $true
            }
        )}
        Mock Get-PrinterPort { return @(
            [PSCustomObject]@{
                Name = "Test Port"
                HostAddress = "192.168.1.100"
                PortNumber = 9100
                Protocol = "RAW"
            }
        )}
        Mock Get-PrinterDriver { return @(
            [PSCustomObject]@{
                Name = "Test Driver"
                Manufacturer = "Test Manufacturer"
                DriverVersion = "1.0.0.0"
                Environment = "Windows x64"
            }
        )}
        Mock Get-ItemProperty { return @{
            Device = "Test Printer,winspool,Test Port"
        }}
        Mock ConvertTo-Json { return '{"test":"value"}' }
        Mock Out-File { }
        Mock reg { }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Backup-PrinterSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.BackupPath | Should -Be "TestPath"
        $result.Feature | Should -Be "Printer"
    }

    It "Should handle registry export failure gracefully" {
        Mock reg { throw "Failed to export registry" }
        $result = Backup-PrinterSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Backup-PrinterSettings -BackupRootPath $BackupRootPath
} 