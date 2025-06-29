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
try {
    $config = Get-WindowsMelodyRecovery
    if (!$config.IsInitialized) {
        Write-Warning "Module not initialized. Using default configuration."
        $config = @{
            BackupRoot = "/tmp/WindowsMelodyRecovery/Backups"
            MachineName = $env:COMPUTERNAME ?? "UNKNOWN"
            IsInitialized = $false
        }
    }
} catch {
    Write-Warning "Module not initialized and no ConfigPath provided. Using default configuration."
    $config = @{
        BackupRoot = "/tmp/WindowsMelodyRecovery/Backups"
        MachineName = $env:COMPUTERNAME ?? "UNKNOWN"
        IsInitialized = $false
    }
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

function Backup-SystemSettings {
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
            Write-Verbose "Starting backup of System Settings..."
            Write-Host "Backing up System Settings..." -ForegroundColor Blue
            
            # Validate inputs before proceeding
            if (!(Test-Path $BackupRootPath)) {
                throw [System.IO.DirectoryNotFoundException]"Backup root path not found: $BackupRootPath"
            }
            
            $backupPath = Initialize-BackupDirectory -Path "SystemSettings" -BackupType "System Settings" -BackupRootPath $BackupRootPath
            
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

                # System-wide registry settings to backup
                $registryPaths = @(
                    # System control settings
                    "HKLM\SYSTEM\CurrentControlSet\Control",
                    "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup",
                    
                    # Performance and memory management
                    "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management",
                    "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects",
                    "HKLM\SYSTEM\CurrentControlSet\Control\PriorityControl",
                    
                    # System environment variables
                    "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment",
                    "HKCU\Environment",
                    
                    # Power management settings
                    "HKLM\SYSTEM\CurrentControlSet\Control\Power",
                    "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\PowerOptions",
                    
                    # Time, date, and region settings
                    "HKLM\SYSTEM\CurrentControlSet\Control\TimeZoneInformation",
                    "HKCU\Control Panel\International",
                    "HKLM\SYSTEM\CurrentControlSet\Control\Nls",
                    
                    # System restore settings
                    "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore",
                    "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\SystemRestore",
                    
                    # Remote access settings
                    "HKLM\SYSTEM\CurrentControlSet\Control\Remote Assistance",
                    "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server",
                    "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services",
                    
                    # Security and UAC settings
                    "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System",
                    "HKLM\SYSTEM\CurrentControlSet\Control\Lsa",
                    "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer",
                    
                    # Windows Update settings
                    "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate",
                    "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate",
                    
                    # System services configuration
                    "HKLM\SYSTEM\CurrentControlSet\Services",
                    
                    # Hardware and device settings
                    "HKLM\SYSTEM\CurrentControlSet\Control\Class",
                    "HKLM\SYSTEM\CurrentControlSet\Enum"
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

                # Export system configuration data
                $systemConfigPath = Join-Path $backupPath "SystemConfig"
                if ($WhatIf) {
                    Write-Host "WhatIf: Would create system config backup directory at $systemConfigPath"
                } else {
                    New-Item -ItemType Directory -Force -Path $systemConfigPath | Out-Null
                }

                # Export power schemes and settings
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export power schemes and settings"
                } else {
                    try {
                        if (!$script:TestMode) {
                            powercfg /list | Out-File (Join-Path $systemConfigPath "power_schemes.txt") -Force
                            powercfg /query | Out-File (Join-Path $systemConfigPath "power_settings.txt") -Force
                            
                            # Get active power scheme
                            $activePowerScheme = powercfg /getactivescheme
                            $activePowerScheme | Out-File (Join-Path $systemConfigPath "active_power_scheme.txt") -Force
                        }
                        $backedUpItems += "Power schemes and settings"
                    } catch {
                        $errors += "Failed to export power settings: $_"
                    }
                }

                # Export system performance settings
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export system performance settings"
                } else {
                    try {
                        $performanceSettings = @{}
                        
                        if (!$script:TestMode) {
                            # Get memory information
                            $memoryInfo = Get-CimInstance Win32_OperatingSystem | 
                                Select-Object FreePhysicalMemory, TotalVisibleMemorySize, SizeStoredInPagingFiles
                            $performanceSettings.Memory = $memoryInfo
                            
                            # Get processor information
                            $processorInfo = Get-CimInstance Win32_Processor | 
                                Select-Object Name, NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed
                            $performanceSettings.Processor = $processorInfo
                            
                            # Get system performance counters
                            $performanceCounters = @{
                                ProcessorTime = (Get-Counter "\Processor(_Total)\% Processor Time" -SampleInterval 1 -MaxSamples 1).CounterSamples.CookedValue
                                AvailableMemory = (Get-Counter "\Memory\Available MBytes" -SampleInterval 1 -MaxSamples 1).CounterSamples.CookedValue
                            }
                            $performanceSettings.Counters = $performanceCounters
                        }
                        
                        $performanceSettings | ConvertTo-Json -Depth 10 | Out-File (Join-Path $systemConfigPath "performance_settings.json") -Force
                        $backedUpItems += "System performance settings"
                    } catch {
                        $errors += "Failed to export system performance settings: $_"
                    }
                }

                # Export system restore points information
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export system restore points information"
                } else {
                    try {
                        if (!$script:TestMode) {
                            $restorePoints = Get-ComputerRestorePoint | 
                                Select-Object Description, CreationTime, RestorePointType, SequenceNumber
                            $restorePoints | ConvertTo-Json -Depth 10 | Out-File (Join-Path $systemConfigPath "restore_points.json") -Force
                        }
                        $backedUpItems += "System restore points information"
                    } catch {
                        $errors += "Failed to export system restore points: $_"
                    }
                }

                # Export page file settings
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export page file settings"
                } else {
                    try {
                        if (!$script:TestMode) {
                            $pageFileSettings = Get-CimInstance Win32_PageFileSetting | 
                                Select-Object Name, InitialSize, MaximumSize
                            $pageFileSettings | ConvertTo-Json -Depth 10 | Out-File (Join-Path $systemConfigPath "pagefile_settings.json") -Force
                        }
                        $backedUpItems += "Page file settings"
                    } catch {
                        $errors += "Failed to export page file settings: $_"
                    }
                }

                # Export time and region settings
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export time and region settings"
                } else {
                    try {
                        $timeSettings = @{}
                        
                        if (!$script:TestMode) {
                            $timeSettings.TimeZone = (Get-TimeZone).Id
                            $timeSettings.Region = (Get-WinHomeLocation).GeoId
                            $timeSettings.SystemLocale = (Get-WinSystemLocale).Name
                            $timeSettings.UserLocale = (Get-WinUserLanguageList)[0].LanguageTag
                            $timeSettings.Culture = (Get-Culture).Name
                        }
                        
                        $timeSettings | ConvertTo-Json -Depth 10 | Out-File (Join-Path $systemConfigPath "time_settings.json") -Force
                        $backedUpItems += "Time and region settings"
                    } catch {
                        $errors += "Failed to export time and region settings: $_"
                    }
                }

                # Export environment variables
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export environment variables"
                } else {
                    try {
                        $environmentVariables = @{
                            User = [Environment]::GetEnvironmentVariables('User')
                            Machine = [Environment]::GetEnvironmentVariables('Machine')
                        }
                        $environmentVariables | ConvertTo-Json -Depth 10 | Out-File (Join-Path $backupPath "environment_variables.json") -Force
                        $backedUpItems += "Environment variables"
                    } catch {
                        $errors += "Failed to export environment variables: $_"
                    }
                }

                # Export printer settings
                $printerPath = Join-Path $backupPath "Printers"
                if ($WhatIf) {
                    Write-Host "WhatIf: Would backup printer settings"
                } else {
                    try {
                        New-Item -ItemType Directory -Path $printerPath -Force | Out-Null

                        if (!$script:TestMode) {
                            # Export printer list and settings
                            $printers = Get-Printer
                            $printers | Export-Clixml "$printerPath\printers.xml"

                            # Export printer configurations
                            $printerConfigs = @{}
                            foreach ($printer in $printers) {
                                try {
                                    $config = Get-PrintConfiguration -PrinterName $printer.Name -ErrorAction SilentlyContinue
                                    if ($config) {
                                        $printerConfigs[$printer.Name] = $config
                                    }
                                } catch {
                                    Write-Verbose "Could not get configuration for printer: $($printer.Name)"
                                }
                            }
                            $printerConfigs | Export-Clixml "$printerPath\printer_configs.xml"

                            # Export printer ports and drivers
                            Get-PrinterPort | Export-Clixml "$printerPath\printer_ports.xml"
                            Get-PrinterDriver | Export-Clixml "$printerPath\printer_drivers.xml"
                        }
                        
                        $backedUpItems += "Printer settings"
                    } catch {
                        $errors += "Failed to backup printer settings: $_"
                    }
                }

                # Backup network profiles and settings
                $networkPath = Join-Path $backupPath "Network"
                if ($WhatIf) {
                    Write-Host "WhatIf: Would backup network settings"
                } else {
                    try {
                        New-Item -ItemType Directory -Force -Path $networkPath | Out-Null
                        
                        if (!$script:TestMode) {
                            Get-NetAdapter | Export-Clixml "$networkPath\adapters.xml"
                            Get-NetIPAddress | Export-Clixml "$networkPath\ip_addresses.xml"
                            Get-NetRoute | Export-Clixml "$networkPath\routes.xml"
                            Get-DnsClientServerAddress | Export-Clixml "$networkPath\dns_settings.xml"
                            
                            # Export wireless profiles
                            netsh wlan export profile folder="$networkPath" key=clear 2>$null
                        }
                        
                        $backedUpItems += "Network settings"
                    } catch {
                        $errors += "Failed to backup network settings: $_"
                    }
                }

                # Backup scheduled tasks (custom only)
                $tasksPath = Join-Path $backupPath "ScheduledTasks"
                if ($WhatIf) {
                    Write-Host "WhatIf: Would backup scheduled tasks"
                } else {
                    try {
                        New-Item -ItemType Directory -Force -Path $tasksPath | Out-Null
                        
                        if (!$script:TestMode) {
                            $customTasks = Get-ScheduledTask | Where-Object { 
                                $_.TaskPath -like "\Custom Tasks\*" -or 
                                $_.TaskPath -like "\User Tasks\*" -or
                                ($_.Author -and $_.Author -ne "Microsoft Corporation")
                            }
                            
                            foreach ($task in $customTasks) {
                                try {
                                    $taskXml = Export-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath
                                    $taskXml | Out-File "$tasksPath\$($task.TaskName).xml" -Force
                                } catch {
                                    Write-Verbose "Could not export task: $($task.TaskName)"
                                }
                            }
                        }
                        
                        $backedUpItems += "Scheduled tasks"
                    } catch {
                        $errors += "Failed to backup scheduled tasks: $_"
                    }
                }

                # Backup mapped drives
                if ($WhatIf) {
                    Write-Host "WhatIf: Would backup mapped drives"
                } else {
                    try {
                        if (!$script:TestMode) {
                            $mappedDrives = Get-PSDrive -PSProvider FileSystem | 
                                Where-Object { $_.DisplayRoot } | 
                                Select-Object Name, Root, DisplayRoot, Description
                            $mappedDrives | Export-Clixml (Join-Path $backupPath "mapped_drives.xml")
                        }
                        $backedUpItems += "Mapped drives"
                    } catch {
                        $errors += "Failed to backup mapped drives: $_"
                    }
                }

                # Export system services configuration
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export system services configuration"
                } else {
                    try {
                        if (!$script:TestMode) {
                            $services = Get-Service | Where-Object { 
                                $_.StartType -ne "Disabled" -and 
                                $_.ServiceType -ne "Unknown" 
                            } | Select-Object Name, Status, StartType, ServiceType, DisplayName
                            $services | Export-Clixml (Join-Path $backupPath "services.xml")
                        }
                        $backedUpItems += "System services configuration"
                    } catch {
                        $errors += "Failed to export system services: $_"
                    }
                }

                # Export Windows features
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export Windows features"
                } else {
                    try {
                        if (!$script:TestMode) {
                            $features = Get-WindowsOptionalFeature -Online | Where-Object { 
                                $_.State -eq "Enabled" 
                            } | Select-Object FeatureName, State, Description
                            $features | Export-Clixml (Join-Path $backupPath "windows_features.xml")
                        }
                        $backedUpItems += "Windows features"
                    } catch {
                        $errors += "Failed to export Windows features: $_"
                    }
                }
                
                # Return object for better testing and validation
                $result = [PSCustomObject]@{
                    Success = $true
                    BackupPath = $backupPath
                    Feature = "System Settings"
                    Timestamp = Get-Date
                    Items = $backedUpItems
                    Errors = $errors
                }
                
                Write-Host "System Settings backed up successfully to: $backupPath" -ForegroundColor Green
                Write-Verbose "Backup completed successfully"
                return $result
            }
            return $false
        } catch {
            $errorRecord = $_
            $errorMessage = @(
                "Failed to backup System Settings"
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
Backs up comprehensive system settings, configurations, and administrative settings.

.DESCRIPTION
Creates a comprehensive backup of system-wide settings including registry configurations, 
power management, performance settings, environment variables, network settings, printer 
configurations, scheduled tasks, mapped drives, system services, and Windows features. 
Handles both user-specific and machine-wide settings with proper error handling.

.PARAMETER BackupRootPath
The root path where the backup will be created. A subdirectory named "SystemSettings" will be created within this path.

.PARAMETER Force
Forces the backup operation even if the destination already exists.

.PARAMETER WhatIf
Shows what would be backed up without actually performing the backup operation.

.EXAMPLE
Backup-SystemSettings -BackupRootPath "C:\Backups"

.EXAMPLE
Backup-SystemSettings -BackupRootPath "C:\Backups" -WhatIf

.NOTES
Test cases to consider:
1. Valid backup path with proper permissions
2. Invalid/nonexistent backup path
3. Empty backup path
4. No permissions to write
5. Registry export success/failure for each key
6. Power settings export success/failure
7. Performance settings export success/failure
8. System restore points export success/failure
9. Page file settings export success/failure
10. Time and region settings export success/failure
11. Environment variables export success/failure
12. Printer settings backup success/failure
13. Network settings backup success/failure
14. Scheduled tasks backup success/failure
15. Mapped drives backup success/failure
16. System services export success/failure
17. Windows features export success/failure
18. Administrative privileges scenarios
19. Network path scenarios
20. System component availability

.TESTCASES
# Mock test examples:
Describe "Backup-SystemSettings" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Initialize-BackupDirectory { return "TestPath" }
        Mock New-Item { }
        Mock Get-CimInstance { return @{ FreePhysicalMemory = 1000; TotalVisibleMemorySize = 8000 } }
        Mock Get-ComputerRestorePoint { return @() }
        Mock Get-TimeZone { return @{ Id = "Eastern Standard Time" } }
        Mock Get-WinHomeLocation { return @{ GeoId = 244 } }
        Mock Get-WinSystemLocale { return @{ Name = "en-US" } }
        Mock Get-WinUserLanguageList { return @(@{ LanguageTag = "en-US" }) }
        Mock Get-Culture { return @{ Name = "en-US" } }
        Mock Get-Printer { return @() }
        Mock Get-NetAdapter { return @() }
        Mock Get-ScheduledTask { return @() }
        Mock Get-PSDrive { return @() }
        Mock Get-Service { return @() }
        Mock Get-WindowsOptionalFeature { return @() }
        Mock Export-Clixml { }
        Mock ConvertTo-Json { return '{"test":"value"}' }
        Mock Out-File { }
        Mock reg { $global:LASTEXITCODE = 0 }
        Mock powercfg { return "Power scheme list" }
        Mock netsh { }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Backup-SystemSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.BackupPath | Should -Be "TestPath"
        $result.Feature | Should -Be "System Settings"
        $result.Items | Should -BeOfType [System.Array]
        $result.Errors | Should -BeOfType [System.Array]
    }

    It "Should handle registry export failure gracefully" {
        Mock reg { $global:LASTEXITCODE = 1; return "Error" }
        $result = Backup-SystemSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle power settings export failure gracefully" {
        Mock powercfg { throw "Power config failed" }
        $result = Backup-SystemSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should support WhatIf parameter" {
        $result = Backup-SystemSettings -BackupRootPath "TestPath" -WhatIf
        $result.Success | Should -Be $true
    }

    It "Should handle system performance export failure gracefully" {
        Mock Get-CimInstance { throw "CIM query failed" }
        $result = Backup-SystemSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle printer settings backup failure gracefully" {
        Mock Get-Printer { throw "Printer query failed" }
        $result = Backup-SystemSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle network settings backup failure gracefully" {
        Mock Get-NetAdapter { throw "Network query failed" }
        $result = Backup-SystemSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle missing system components gracefully" {
        Mock Test-Path { return $false }
        $result = Backup-SystemSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
    }

    It "Should handle scheduled tasks backup failure gracefully" {
        Mock Get-ScheduledTask { throw "Task query failed" }
        $result = Backup-SystemSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Backup-SystemSettings -BackupRootPath $BackupRootPath
} 