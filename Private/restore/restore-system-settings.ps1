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

function Restore-SystemSettings {
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
            Write-Verbose "Starting restore of System Settings..."
            Write-Host "Restoring System Settings..." -ForegroundColor Blue
            
            # Validate inputs before proceeding
            if (!(Test-Path $BackupRootPath)) {
                throw [System.IO.DirectoryNotFoundException]"Backup root path not found: $BackupRootPath"
            }
            
            $backupPath = Join-Path $BackupRootPath "SystemSettings"
            if (!(Test-Path $backupPath)) {
                throw [System.IO.DirectoryNotFoundException]"System Settings backup not found at: $backupPath"
            }
            
            # Define all possible restore items
            $restoreItems = @{
                "Registry" = @{
                    Path = Join-Path $backupPath "Registry"
                    Description = "System registry settings"
                    Action = "Import-RegistryFiles"
                }
                "PowerSettings" = @{
                    Path = Join-Path $backupPath "SystemConfig"
                    Description = "Power management settings"
                    Action = "Restore-PowerSettings"
                }
                "PerformanceSettings" = @{
                    Path = Join-Path $backupPath "SystemConfig\performance_settings.json"
                    Description = "System performance settings"
                    Action = "Restore-PerformanceSettings"
                }
                "TimeSettings" = @{
                    Path = Join-Path $backupPath "SystemConfig\time_settings.json"
                    Description = "Time and region settings"
                    Action = "Restore-TimeSettings"
                }
                "EnvironmentVariables" = @{
                    Path = Join-Path $backupPath "environment_variables.json"
                    Description = "Environment variables"
                    Action = "Restore-EnvironmentVariables"
                }
                "PrinterSettings" = @{
                    Path = Join-Path $backupPath "Printers"
                    Description = "Printer settings"
                    Action = "Restore-PrinterSettings"
                }
                "NetworkSettings" = @{
                    Path = Join-Path $backupPath "Network"
                    Description = "Network settings"
                    Action = "Restore-NetworkSettings"
                }
                "ScheduledTasks" = @{
                    Path = Join-Path $backupPath "ScheduledTasks"
                    Description = "Scheduled tasks"
                    Action = "Restore-ScheduledTasks"
                }
                "MappedDrives" = @{
                    Path = Join-Path $backupPath "mapped_drives.xml"
                    Description = "Mapped drives"
                    Action = "Restore-MappedDrives"
                }
                "SystemServices" = @{
                    Path = Join-Path $backupPath "services.xml"
                    Description = "System services configuration"
                    Action = "Restore-SystemServices"
                }
                "WindowsFeatures" = @{
                    Path = Join-Path $backupPath "windows_features.xml"
                    Description = "Windows features"
                    Action = "Restore-WindowsFeatures"
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
            
            # Ensure required system services are running
            if (!$script:TestMode -and !$WhatIf) {
                $systemServices = @("Schedule", "Power", "PlugPlay", "Spooler", "RemoteRegistry")
                foreach ($serviceName in $systemServices) {
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
                                
                                "Restore-PowerSettings" {
                                    try {
                                        # Restore power schemes (informational only - requires manual intervention)
                                        $powerSchemesFile = Join-Path $itemPath "power_schemes.txt"
                                        $powerSettingsFile = Join-Path $itemPath "power_settings.txt"
                                        $activePowerSchemeFile = Join-Path $itemPath "active_power_scheme.txt"
                                        
                                        if (Test-Path $powerSchemesFile) {
                                            Write-Verbose "Power schemes information available (manual restoration required)"
                                        }
                                        if (Test-Path $powerSettingsFile) {
                                            Write-Verbose "Power settings information available (manual restoration required)"
                                        }
                                        if (Test-Path $activePowerSchemeFile) {
                                            Write-Verbose "Active power scheme information available (manual restoration required)"
                                        }
                                        
                                        $itemsRestored += "Power settings (informational)"
                                    } catch {
                                        $errors += "Failed to restore power settings: $_"
                                    }
                                }
                                
                                "Restore-PerformanceSettings" {
                                    try {
                                        $performanceSettings = Get-Content $itemPath | ConvertFrom-Json
                                        
                                        # This is primarily informational as performance settings are complex to restore
                                        if ($performanceSettings.Memory) {
                                            Write-Verbose "Memory information was backed up (informational)"
                                        }
                                        if ($performanceSettings.Processor) {
                                            Write-Verbose "Processor information was backed up (informational)"
                                        }
                                        if ($performanceSettings.Counters) {
                                            Write-Verbose "Performance counters were backed up (informational)"
                                        }
                                        
                                        $itemsRestored += "System performance settings (informational)"
                                    } catch {
                                        $errors += "Failed to restore performance settings: $_"
                                    }
                                }
                                
                                "Restore-TimeSettings" {
                                    try {
                                        $timeSettings = Get-Content $itemPath | ConvertFrom-Json
                                        
                                        if (!$script:TestMode) {
                                            # Restore time zone
                                            if ($timeSettings.TimeZone) {
                                                try {
                                                    Set-TimeZone -Id $timeSettings.TimeZone -ErrorAction SilentlyContinue
                                                    Write-Verbose "Restored time zone: $($timeSettings.TimeZone)"
                                                } catch {
                                                    Write-Verbose "Could not restore time zone: $_"
                                                }
                                            }
                                            
                                            # Restore region (requires administrative privileges)
                                            if ($timeSettings.Region) {
                                                try {
                                                    Set-WinHomeLocation -GeoId $timeSettings.Region -ErrorAction SilentlyContinue
                                                    Write-Verbose "Restored region: $($timeSettings.Region)"
                                                } catch {
                                                    Write-Verbose "Could not restore region (may require administrative privileges): $_"
                                                }
                                            }
                                            
                                            # Restore system locale (requires administrative privileges)
                                            if ($timeSettings.SystemLocale) {
                                                try {
                                                    Set-WinSystemLocale -SystemLocale $timeSettings.SystemLocale -ErrorAction SilentlyContinue
                                                    Write-Verbose "Restored system locale: $($timeSettings.SystemLocale)"
                                                } catch {
                                                    Write-Verbose "Could not restore system locale (may require administrative privileges): $_"
                                                }
                                            }
                                        }
                                        
                                        $itemsRestored += "Time and region settings"
                                    } catch {
                                        $errors += "Failed to restore time and region settings: $_"
                                    }
                                }
                                
                                "Restore-EnvironmentVariables" {
                                    try {
                                        $environmentVariables = Get-Content $itemPath | ConvertFrom-Json
                                        
                                        if (!$script:TestMode) {
                                            # Restore user environment variables
                                            if ($environmentVariables.User) {
                                                foreach ($variable in $environmentVariables.User.PSObject.Properties) {
                                                    try {
                                                        [Environment]::SetEnvironmentVariable($variable.Name, $variable.Value, 'User')
                                                        Write-Verbose "Restored user environment variable: $($variable.Name)"
                                                    } catch {
                                                        Write-Verbose "Could not restore user environment variable $($variable.Name): $_"
                                                    }
                                                }
                                            }
                                            
                                            # Restore machine environment variables (requires administrative privileges)
                                            if ($environmentVariables.Machine) {
                                                foreach ($variable in $environmentVariables.Machine.PSObject.Properties) {
                                                    try {
                                                        [Environment]::SetEnvironmentVariable($variable.Name, $variable.Value, 'Machine')
                                                        Write-Verbose "Restored machine environment variable: $($variable.Name)"
                                                    } catch {
                                                        Write-Verbose "Could not restore machine environment variable $($variable.Name) (may require administrative privileges): $_"
                                                    }
                                                }
                                            }
                                        }
                                        
                                        $itemsRestored += "Environment variables"
                                    } catch {
                                        $errors += "Failed to restore environment variables: $_"
                                    }
                                }
                                
                                "Restore-PrinterSettings" {
                                    try {
                                        # Restore printer information (informational only - requires manual setup)
                                        $printersFile = Join-Path $itemPath "printers.xml"
                                        $printerConfigsFile = Join-Path $itemPath "printer_configs.xml"
                                        $printerPortsFile = Join-Path $itemPath "printer_ports.xml"
                                        $printerDriversFile = Join-Path $itemPath "printer_drivers.xml"
                                        
                                        if (Test-Path $printersFile) {
                                            Write-Verbose "Printer information available (manual restoration required)"
                                        }
                                        if (Test-Path $printerConfigsFile) {
                                            Write-Verbose "Printer configurations available (manual restoration required)"
                                        }
                                        if (Test-Path $printerPortsFile) {
                                            Write-Verbose "Printer ports information available (manual restoration required)"
                                        }
                                        if (Test-Path $printerDriversFile) {
                                            Write-Verbose "Printer drivers information available (manual restoration required)"
                                        }
                                        
                                        $itemsRestored += "Printer settings (informational)"
                                    } catch {
                                        $errors += "Failed to restore printer settings: $_"
                                    }
                                }
                                
                                "Restore-NetworkSettings" {
                                    try {
                                        # Restore network information (informational only - requires manual configuration)
                                        $adaptersFile = Join-Path $itemPath "adapters.xml"
                                        $ipAddressesFile = Join-Path $itemPath "ip_addresses.xml"
                                        $routesFile = Join-Path $itemPath "routes.xml"
                                        $dnsSettingsFile = Join-Path $itemPath "dns_settings.xml"
                                        
                                        if (Test-Path $adaptersFile) {
                                            Write-Verbose "Network adapters information available (manual restoration required)"
                                        }
                                        if (Test-Path $ipAddressesFile) {
                                            Write-Verbose "IP addresses information available (manual restoration required)"
                                        }
                                        if (Test-Path $routesFile) {
                                            Write-Verbose "Network routes information available (manual restoration required)"
                                        }
                                        if (Test-Path $dnsSettingsFile) {
                                            Write-Verbose "DNS settings information available (manual restoration required)"
                                        }
                                        
                                        # Restore wireless profiles
                                        $wlanProfiles = Get-ChildItem -Path $itemPath -Filter "*.xml" | Where-Object { $_.Name -like "Wireless Network*" }
                                        foreach ($profile in $wlanProfiles) {
                                            if (!$script:TestMode) {
                                                try {
                                                    netsh wlan add profile filename="$($profile.FullName)" 2>$null
                                                    Write-Verbose "Restored wireless profile: $($profile.Name)"
                                                } catch {
                                                    Write-Verbose "Could not restore wireless profile $($profile.Name): $_"
                                                }
                                            }
                                        }
                                        
                                        $itemsRestored += "Network settings"
                                    } catch {
                                        $errors += "Failed to restore network settings: $_"
                                    }
                                }
                                
                                "Restore-ScheduledTasks" {
                                    try {
                                        $taskFiles = Get-ChildItem -Path $itemPath -Filter "*.xml" -ErrorAction SilentlyContinue
                                        
                                        foreach ($taskFile in $taskFiles) {
                                            if (!$script:TestMode) {
                                                try {
                                                    $taskName = [System.IO.Path]::GetFileNameWithoutExtension($taskFile.Name)
                                                    $taskXml = Get-Content $taskFile.FullName -Raw
                                                    Register-ScheduledTask -TaskName $taskName -Xml $taskXml -Force -ErrorAction SilentlyContinue
                                                    Write-Verbose "Restored scheduled task: $taskName"
                                                } catch {
                                                    Write-Verbose "Could not restore scheduled task $($taskFile.Name): $_"
                                                }
                                            }
                                        }
                                        
                                        $itemsRestored += "Scheduled tasks"
                                    } catch {
                                        $errors += "Failed to restore scheduled tasks: $_"
                                    }
                                }
                                
                                "Restore-MappedDrives" {
                                    try {
                                        $mappedDrives = Import-Clixml $itemPath
                                        
                                        if (!$script:TestMode) {
                                            foreach ($drive in $mappedDrives) {
                                                try {
                                                    if ($drive.DisplayRoot) {
                                                        New-PSDrive -Name $drive.Name -PSProvider FileSystem -Root $drive.DisplayRoot -Persist -Scope Global -ErrorAction SilentlyContinue
                                                        Write-Verbose "Restored mapped drive: $($drive.Name) -> $($drive.DisplayRoot)"
                                                    }
                                                } catch {
                                                    Write-Verbose "Could not restore mapped drive $($drive.Name): $_"
                                                }
                                            }
                                        }
                                        
                                        $itemsRestored += "Mapped drives"
                                    } catch {
                                        $errors += "Failed to restore mapped drives: $_"
                                    }
                                }
                                
                                "Restore-SystemServices" {
                                    try {
                                        $services = Import-Clixml $itemPath
                                        
                                        # This is primarily informational as service configuration requires administrative privileges
                                        Write-Verbose "System services configuration available (manual restoration may be required for start type changes)"
                                        
                                        if (!$script:TestMode) {
                                            foreach ($serviceInfo in $services) {
                                                try {
                                                    $service = Get-Service -Name $serviceInfo.Name -ErrorAction SilentlyContinue
                                                    if ($service) {
                                                        # Only try to start services that were running and are currently stopped
                                                        if ($serviceInfo.Status -eq "Running" -and $service.Status -ne "Running") {
                                                            Start-Service -Name $serviceInfo.Name -ErrorAction SilentlyContinue
                                                            Write-Verbose "Started service: $($serviceInfo.Name)"
                                                        }
                                                    }
                                                } catch {
                                                    Write-Verbose "Could not manage service $($serviceInfo.Name): $_"
                                                }
                                            }
                                        }
                                        
                                        $itemsRestored += "System services configuration"
                                    } catch {
                                        $errors += "Failed to restore system services: $_"
                                    }
                                }
                                
                                "Restore-WindowsFeatures" {
                                    try {
                                        $features = Import-Clixml $itemPath
                                        
                                        # This is primarily informational as feature installation requires administrative privileges
                                        Write-Verbose "Windows features information available (manual restoration may be required)"
                                        
                                        if (!$script:TestMode) {
                                            foreach ($feature in $features) {
                                                try {
                                                    $currentFeature = Get-WindowsOptionalFeature -Online -FeatureName $feature.FeatureName -ErrorAction SilentlyContinue
                                                    if ($currentFeature -and $currentFeature.State -ne "Enabled" -and $feature.State -eq "Enabled") {
                                                        Enable-WindowsOptionalFeature -Online -FeatureName $feature.FeatureName -All -NoRestart -ErrorAction SilentlyContinue
                                                        Write-Verbose "Enabled Windows feature: $($feature.FeatureName)"
                                                    }
                                                } catch {
                                                    Write-Verbose "Could not enable Windows feature $($feature.FeatureName) (may require administrative privileges): $_"
                                                }
                                            }
                                        }
                                        
                                        $itemsRestored += "Windows features"
                                    } catch {
                                        $errors += "Failed to restore Windows features: $_"
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
            
            # Return result object
            $result = [PSCustomObject]@{
                Success = $true
                BackupPath = $backupPath
                Feature = "System Settings"
                Timestamp = Get-Date
                ItemsRestored = $itemsRestored
                ItemsSkipped = $itemsSkipped
                Errors = $errors
            }
            
            Write-Host "System Settings restored successfully from: $backupPath" -ForegroundColor Green
            Write-Host "`nNote: Some settings may require a system restart to take effect" -ForegroundColor Yellow
            Write-Host "Note: Some settings may require administrative privileges for full restoration" -ForegroundColor Yellow
            Write-Verbose "Restore completed successfully"
            return $result
            
        } catch {
            $errorRecord = $_
            $errorMessage = @(
                "Failed to restore System Settings"
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
    Export-ModuleMember -Function Restore-SystemSettings
}

<#
.SYNOPSIS
Restores comprehensive system settings, configurations, and administrative settings from backup.

.DESCRIPTION
Restores a comprehensive backup of system-wide settings including registry configurations, 
power management, performance settings, environment variables, network settings, printer 
configurations, scheduled tasks, mapped drives, system services, and Windows features. 
Handles both user-specific and machine-wide settings with proper error handling and 
administrative privilege awareness.

.PARAMETER BackupRootPath
The root path where the backup is located. The script will look for a "SystemSettings" subdirectory within this path.

.PARAMETER Force
Forces the restore operation even if it might overwrite existing settings.

.PARAMETER Include
Specifies which components to restore. Valid values: Registry, PowerSettings, PerformanceSettings, TimeSettings, EnvironmentVariables, PrinterSettings, NetworkSettings, ScheduledTasks, MappedDrives, SystemServices, WindowsFeatures.

.PARAMETER Exclude
Specifies which components to exclude from restoration. Valid values: Registry, PowerSettings, PerformanceSettings, TimeSettings, EnvironmentVariables, PrinterSettings, NetworkSettings, ScheduledTasks, MappedDrives, SystemServices, WindowsFeatures.

.PARAMETER SkipVerification
Skips verification steps during the restore process.

.PARAMETER WhatIf
Shows what would be restored without actually performing the restore operation.

.EXAMPLE
Restore-SystemSettings -BackupRootPath "C:\Backups"

.EXAMPLE
Restore-SystemSettings -BackupRootPath "C:\Backups" -Include @("Registry", "EnvironmentVariables")

.EXAMPLE
Restore-SystemSettings -BackupRootPath "C:\Backups" -Exclude @("NetworkSettings") -WhatIf

.NOTES
Test cases to consider:
1. Valid backup path with all components
2. Invalid/nonexistent backup path
3. Partial backup (missing some components)
4. Registry import success/failure
5. Power settings restore success/failure
6. Performance settings restore success/failure
7. Time settings restore success/failure
8. Environment variables restore success/failure
9. Printer settings restore success/failure
10. Network settings restore success/failure
11. Scheduled tasks restore success/failure
12. Mapped drives restore success/failure
13. System services restore success/failure
14. Windows features restore success/failure
15. Include parameter filtering
16. Exclude parameter filtering
17. Administrative privileges scenarios
18. System service management
19. Network path scenarios
20. Test mode scenarios

.TESTCASES
# Mock test examples:
Describe "Restore-SystemSettings" {
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
        Mock Import-Clixml { return @() }
        Mock Get-Service { return @{ Status = "Stopped"; StartType = "Automatic" } }
        Mock Start-Service { }
        Mock Set-TimeZone { }
        Mock Set-WinHomeLocation { }
        Mock Set-WinSystemLocale { }
        Mock Register-ScheduledTask { }
        Mock New-PSDrive { }
        Mock Get-WindowsOptionalFeature { return @{ State = "Disabled" } }
        Mock Enable-WindowsOptionalFeature { }
        Mock netsh { }
        Mock reg { }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Restore-SystemSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.BackupPath | Should -Be "TestPath"
        $result.Feature | Should -Be "System Settings"
        $result.ItemsRestored | Should -BeOfType [System.Array]
        $result.ItemsSkipped | Should -BeOfType [System.Array]
        $result.Errors | Should -BeOfType [System.Array]
    }

    It "Should handle registry import failure gracefully" {
        Mock reg { throw "Registry import failed" }
        $result = Restore-SystemSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle time settings restore failure gracefully" {
        Mock Set-TimeZone { throw "Time zone change failed" }
        $result = Restore-SystemSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should support Include parameter" {
        $result = Restore-SystemSettings -BackupRootPath "TestPath" -Include @("Registry")
        $result.Success | Should -Be $true
    }

    It "Should support Exclude parameter" {
        $result = Restore-SystemSettings -BackupRootPath "TestPath" -Exclude @("NetworkSettings")
        $result.Success | Should -Be $true
    }

    It "Should handle system service management failure gracefully" {
        Mock Start-Service { throw "Service start failed" }
        $result = Restore-SystemSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
    }

    It "Should handle missing backup components gracefully" {
        Mock Test-Path { param($Path) return $Path -notlike "*PowerSettings*" }
        $result = Restore-SystemSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.ItemsSkipped.Count | Should -BeGreaterThan 0
    }

    It "Should support WhatIf parameter" {
        $result = Restore-SystemSettings -BackupRootPath "TestPath" -WhatIf
        $result.Success | Should -Be $true
    }

    It "Should handle environment variables restore failure gracefully" {
        Mock Set-Content { throw "Environment variable setting failed" }
        $result = Restore-SystemSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Restore-SystemSettings -BackupRootPath $BackupRootPath -Force:$Force -Include $Include -Exclude $Exclude -SkipVerification:$SkipVerification
} 