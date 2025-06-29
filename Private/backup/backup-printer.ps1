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
            
            $backupPath = Initialize-BackupDirectory -Path "Printer" -BackupType "Printer Settings" -BackupRootPath $BackupRootPath
            
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

                # Registry paths for printer settings
                $registryPaths = @(
                    "HKLM\SYSTEM\CurrentControlSet\Control\Print\Printers",
                    "HKLM\SYSTEM\CurrentControlSet\Control\Print\Monitors",
                    "HKLM\SYSTEM\CurrentControlSet\Control\Print\Providers",
                    "HKLM\SYSTEM\CurrentControlSet\Control\Print\Environments",
                    "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Print\Printers",
                    "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Print\Providers",
                    "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\Printer Cache",
                    "HKCU\Software\Microsoft\Windows NT\CurrentVersion\Windows",
                    "HKCU\Printers",
                    "HKCU\Software\Microsoft\Windows NT\CurrentVersion\PrinterPorts"
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

                # Get printer information
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export printer information"
                } else {
                    try {
                        $printers = Get-Printer | Select-Object Name, DriverName, PortName, Shared, ShareName, Published, DeviceType, Status, Location, Comment
                        $printers | ConvertTo-Json -Depth 10 | Out-File "$backupPath\printers.json" -Force
                        $backedUpItems += "printers.json"
                    } catch {
                        $errors += "Failed to get printer information: $_"
                    }
                }

                # Get printer ports
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export printer ports"
                } else {
                    try {
                        $printerPorts = Get-PrinterPort | Select-Object Name, HostAddress, PortNumber, Protocol, Description, SNMPEnabled, SNMPCommunity
                        $printerPorts | ConvertTo-Json -Depth 10 | Out-File "$backupPath\printer_ports.json" -Force
                        $backedUpItems += "printer_ports.json"
                    } catch {
                        $errors += "Failed to get printer ports: $_"
                    }
                }

                # Get printer drivers
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export printer drivers"
                } else {
                    try {
                        $printerDrivers = Get-PrinterDriver | Select-Object Name, Manufacturer, DriverVersion, Environment, PrinterEnvironment, InfPath, ConfigFile, DataFile, DriverPath, HelpFile
                        $printerDrivers | ConvertTo-Json -Depth 10 | Out-File "$backupPath\printer_drivers.json" -Force
                        $backedUpItems += "printer_drivers.json"
                    } catch {
                        $errors += "Failed to get printer drivers: $_"
                    }
                }

                # Export printer preferences and default printer
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export printer preferences"
                } else {
                    try {
                        $defaultPrinter = Get-Printer | Where-Object {$_.IsDefault}
                        $deviceSetting = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Windows" -Name "Device" -ErrorAction SilentlyContinue
                        
                        $printerPreferences = @{
                            DefaultPrinter = if ($defaultPrinter) { $defaultPrinter.Name } else { $null }
                            DeviceSetting = if ($deviceSetting) { $deviceSetting.Device } else { $null }
                            PrinterPorts = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\PrinterPorts" -ErrorAction SilentlyContinue
                        }
                        $printerPreferences | ConvertTo-Json -Depth 10 | Out-File "$backupPath\printer_preferences.json" -Force
                        $backedUpItems += "printer_preferences.json"
                    } catch {
                        $errors += "Failed to get printer preferences: $_"
                    }
                }

                # Get print queues and jobs information
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export print queues information"
                } else {
                    try {
                        $printQueues = @()
                        foreach ($printer in (Get-Printer)) {
                            try {
                                $queue = Get-PrintJob -PrinterName $printer.Name -ErrorAction SilentlyContinue
                                if ($queue) {
                                    $printQueues += @{
                                        PrinterName = $printer.Name
                                        Jobs = $queue | Select-Object Id, DocumentName, UserName, Status, Size, SubmittedTime
                                    }
                                }
                            } catch {
                                Write-Verbose "Could not get print jobs for printer: $($printer.Name)"
                            }
                        }
                        
                        if ($printQueues.Count -gt 0) {
                            $printQueues | ConvertTo-Json -Depth 10 | Out-File "$backupPath\print_queues.json" -Force
                            $backedUpItems += "print_queues.json"
                        }
                    } catch {
                        $errors += "Failed to get print queues information: $_"
                    }
                }

                # Get print spooler configuration
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export print spooler configuration"
                } else {
                    try {
                        $spoolerService = Get-Service -Name "Spooler" -ErrorAction SilentlyContinue
                        $spoolerConfig = @{
                            ServiceStatus = if ($spoolerService) { $spoolerService.Status } else { "Not Found" }
                            ServiceStartType = if ($spoolerService) { $spoolerService.StartType } else { "Unknown" }
                            SpoolDirectory = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Print\Printers" -Name "DefaultSpoolDirectory" -ErrorAction SilentlyContinue
                        }
                        $spoolerConfig | ConvertTo-Json -Depth 10 | Out-File "$backupPath\spooler_config.json" -Force
                        $backedUpItems += "spooler_config.json"
                    } catch {
                        $errors += "Failed to get print spooler configuration: $_"
                    }
                }
                
                # Return object for better testing and validation
                $result = [PSCustomObject]@{
                    Success = $true
                    BackupPath = $backupPath
                    Feature = "Printer Settings"
                    Timestamp = Get-Date
                    Items = $backedUpItems
                    Errors = $errors
                }
                
                Write-Host "Printer Settings backed up successfully to: $backupPath" -ForegroundColor Green
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

<#
.SYNOPSIS
Backs up Windows Printer settings and configurations.

.DESCRIPTION
Creates a comprehensive backup of Windows Printer settings, including registry settings, printer information,
ports, drivers, preferences, print queues, and spooler configuration. Supports both local and network printers
with detailed configuration preservation.

.PARAMETER BackupRootPath
The root path where the backup will be created. A subdirectory named "Printer" will be created within this path.

.PARAMETER Force
Forces the backup operation even if the destination already exists.

.PARAMETER WhatIf
Shows what would be backed up without actually performing the backup operation.

.EXAMPLE
Backup-PrinterSettings -BackupRootPath "C:\Backups"

.EXAMPLE
Backup-PrinterSettings -BackupRootPath "C:\Backups" -WhatIf

.NOTES
Test cases to consider:
1. Valid backup path with proper permissions
2. Invalid/nonexistent backup path
3. Empty backup path
4. No permissions to write
5. Registry export success/failure for each key
6. Printer information retrieval success/failure
7. Printer ports retrieval success/failure
8. Printer drivers retrieval success/failure
9. Printer preferences retrieval success/failure
10. Print queues retrieval success/failure
11. Spooler configuration retrieval success/failure
12. JSON serialization success/failure
13. No printers installed scenario
14. Network printers scenario
15. Local printers scenario
16. Mixed printer types scenario
17. Print spooler service stopped
18. Driver installation issues
19. Network connectivity issues
20. Administrative privileges scenarios

.TESTCASES
# Mock test examples:
Describe "Backup-PrinterSettings" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Initialize-BackupDirectory { return "TestPath" }
        Mock New-Item { }
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
                Location = "Office"
                Comment = "Test printer"
            }
        )}
        Mock Get-PrinterPort { return @(
            [PSCustomObject]@{
                Name = "Test Port"
                HostAddress = "192.168.1.100"
                PortNumber = 9100
                Protocol = "RAW"
                Description = "Test Port Description"
                SNMPEnabled = $true
                SNMPCommunity = "public"
            }
        )}
        Mock Get-PrinterDriver { return @(
            [PSCustomObject]@{
                Name = "Test Driver"
                Manufacturer = "Test Manufacturer"
                DriverVersion = "1.0.0.0"
                Environment = "Windows x64"
                PrinterEnvironment = "Windows x64"
                InfPath = "C:\Windows\inf\test.inf"
                ConfigFile = "test.dll"
                DataFile = "test.ppd"
                DriverPath = "test.dll"
                HelpFile = "test.hlp"
            }
        )}
        Mock Get-PrintJob { return @() }
        Mock Get-Service { return @{
            Status = "Running"
            StartType = "Automatic"
        }}
        Mock Get-ItemProperty { return @{
            Device = "Test Printer,winspool,Test Port"
            DefaultSpoolDirectory = "C:\Windows\System32\spool\PRINTERS"
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
        $result.Feature | Should -Be "Printer Settings"
        $result.Items | Should -BeOfType [System.Array]
        $result.Errors | Should -BeOfType [System.Array]
    }

    It "Should handle registry export failure gracefully" {
        Mock reg { throw "Failed to export registry" }
        $result = Backup-PrinterSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle printer information failure gracefully" {
        Mock Get-Printer { throw "Printer access denied" }
        $result = Backup-PrinterSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should support WhatIf parameter" {
        $result = Backup-PrinterSettings -BackupRootPath "TestPath" -WhatIf
        $result.Success | Should -Be $true
    }

    It "Should handle printer ports failure gracefully" {
        Mock Get-PrinterPort { throw "Port access denied" }
        $result = Backup-PrinterSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle printer drivers failure gracefully" {
        Mock Get-PrinterDriver { throw "Driver access denied" }
        $result = Backup-PrinterSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle no printers scenario" {
        Mock Get-Printer { return @() }
        $result = Backup-PrinterSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Backup-PrinterSettings -BackupRootPath $BackupRootPath
} 