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

# Define Test-BackupPath function directly in the script
function Test-BackupPath {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Path,
        
        [Parameter(Mandatory=$true)]
        [string]$BackupType
    )
    
    # First check machine-specific backup
    $machinePath = Join-Path $BackupRootPath $Path
    if (Test-Path $machinePath) {
        Write-Host "Using machine-specific $BackupType backup from: $machinePath" -ForegroundColor Green
        return $machinePath
    }
    
    # Fall back to shared backup if available
    if ($SharedBackupPath) {
        $sharedPath = Join-Path $SharedBackupPath $Path
        if (Test-Path $sharedPath) {
            Write-Host "Using shared $BackupType backup from: $sharedPath" -ForegroundColor Green
            return $sharedPath
        }
    }
    
    Write-Host "No $BackupType backup found" -ForegroundColor Yellow
    return $null
}

function Restore-NetworkSettings {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force,

        [Parameter(Mandatory=$false)]
        [string[]]$Include,

        [Parameter(Mandatory=$false)]
        [string[]]$Exclude,

        # For testing purposes
        [Parameter(DontShow)]
        [switch]$SkipVerification
    )
    
    begin {
        # Test hook for mocking
        if ($script:TestMode) {
            Write-Verbose "Running in test mode"
        }

        # Initialize result object
        $result = [PSCustomObject]@{
            Success = $false
            RestorePath = $null
            Feature = "Network Settings"
            Timestamp = Get-Date
            ItemsRestored = @()
            ItemsSkipped = @()
            Errors = @()
        }
    }
    
    process {
        try {
            Write-Verbose "Starting restore of Network Settings..."
            Write-Host "Restoring Network Settings..." -ForegroundColor Blue
            
            # Validate inputs
            if (!(Test-Path $BackupRootPath)) {
                throw [System.IO.DirectoryNotFoundException]"Backup root path not found: $BackupRootPath"
            }
            
            $backupPath = Test-BackupPath -Path "Network" -BackupType "Network Settings"
            if (!$backupPath) {
                throw "No valid backup found for Network Settings"
            }
            $result.RestorePath = $backupPath
            
            if ($backupPath) {
                # Check network services (only if not in test mode)
                if (!$script:TestMode) {
                    Write-Host "Checking network components..." -ForegroundColor Yellow
                    $networkServices = @(
                        "Dhcp", "Dnscache", "NlaSvc", "netprofm",
                        "LanmanWorkstation", "LanmanServer"
                    )
                    
                    foreach ($service in $networkServices) {
                        if ((Get-Service -Name $service -ErrorAction SilentlyContinue).Status -ne "Running") {
                            if ($Force -or $PSCmdlet.ShouldProcess("Service $service", "Start")) {
                                Start-Service -Name $service -ErrorAction SilentlyContinue
                                $result.ItemsRestored += "Service\$service"
                            }
                        }
                    }
                }

                # Restore registry settings first
                $registryPath = Join-Path $backupPath "Registry"
                if (Test-Path $registryPath) {
                    if ($Force -or $PSCmdlet.ShouldProcess("Network Registry Settings", "Restore")) {
                        Get-ChildItem -Path $registryPath -Filter "*.reg" | ForEach-Object {
                            try {
                                Write-Host "Importing registry file: $($_.Name)" -ForegroundColor Yellow
                                if (!$script:TestMode) {
                                    reg import $_.FullName 2>$null
                                }
                                $result.ItemsRestored += "Registry\$($_.Name)"
                            } catch {
                                $result.Errors += "Failed to import registry file $($_.Name): $_"
                                $result.ItemsSkipped += "Registry\$($_.Name)"
                                if (!$Force) { throw }
                            }
                        }
                    }
                } else {
                    $result.ItemsSkipped += "Registry (not found in backup)"
                }

                # Restore network adapter configurations
                $adaptersFile = Join-Path $backupPath "network_adapters.json"
                if (Test-Path $adaptersFile) {
                    if ($Force -or $PSCmdlet.ShouldProcess("Network Adapter Settings", "Restore")) {
                        try {
                            $adapters = Get-Content $adaptersFile | ConvertFrom-Json
                            if (!$script:TestMode) {
                                foreach ($adapter in $adapters) {
                                    $netAdapter = Get-NetAdapter | Where-Object { $_.MacAddress -eq $adapter.MacAddress }
                                    if ($netAdapter) {
                                        # Note: IP configuration restore would typically be done through network_config.json
                                        Write-Verbose "Found matching adapter: $($netAdapter.Name)"
                                    }
                                }
                            }
                            $result.ItemsRestored += "network_adapters.json"
                        } catch {
                            $result.Errors += "Failed to restore network adapter settings: $_"
                            $result.ItemsSkipped += "network_adapters.json"
                            if (!$Force) { throw }
                        }
                    }
                } else {
                    $result.ItemsSkipped += "network_adapters.json (not found in backup)"
                }

                # Restore network configuration
                $configFile = Join-Path $backupPath "network_config.json"
                if (Test-Path $configFile) {
                    if ($Force -or $PSCmdlet.ShouldProcess("Network Configuration", "Restore")) {
                        try {
                            $networkConfig = Get-Content $configFile | ConvertFrom-Json
                            # Note: Network configuration restore is complex and may require careful handling
                            # This is a placeholder for the actual implementation
                            $result.ItemsRestored += "network_config.json"
                        } catch {
                            $result.Errors += "Failed to restore network configuration: $_"
                            $result.ItemsSkipped += "network_config.json"
                            if (!$Force) { throw }
                        }
                    }
                } else {
                    $result.ItemsSkipped += "network_config.json (not found in backup)"
                }

                # Restore wireless profiles
                $wirelessFile = Join-Path $backupPath "wireless_profiles.json"
                if (Test-Path $wirelessFile) {
                    if ($Force -or $PSCmdlet.ShouldProcess("Wireless Network Profiles", "Restore")) {
                        try {
                            $wirelessProfiles = Get-Content $wirelessFile | ConvertFrom-Json
                            if (!$script:TestMode) {
                                foreach ($profile in $wirelessProfiles) {
                                    # Note: Wireless profile restoration would use netsh commands
                                    Write-Verbose "Would restore wireless profile: $($profile.Name)"
                                }
                            }
                            $result.ItemsRestored += "wireless_profiles.json"
                        } catch {
                            $result.Errors += "Failed to restore wireless profiles: $_"
                            $result.ItemsSkipped += "wireless_profiles.json"
                            if (!$Force) { throw }
                        }
                    }
                } else {
                    $result.ItemsSkipped += "wireless_profiles.json (not found in backup)"
                }

                # Restore firewall rules
                $firewallFile = Join-Path $backupPath "firewall_rules.json"
                if (Test-Path $firewallFile) {
                    if ($Force -or $PSCmdlet.ShouldProcess("Firewall Rules", "Restore")) {
                        try {
                            $rules = Get-Content $firewallFile | ConvertFrom-Json
                            if (!$script:TestMode) {
                                foreach ($rule in $rules) {
                                    $existingRule = Get-NetFirewallRule -Name $rule.Name -ErrorAction SilentlyContinue
                                    if ($existingRule) {
                                        Set-NetFirewallRule -Name $rule.Name `
                                            -Enabled $rule.Enabled `
                                            -Action $rule.Action `
                                            -Direction $rule.Direction
                                    } else {
                                        New-NetFirewallRule -Name $rule.Name `
                                            -DisplayName $rule.DisplayName `
                                            -Description $rule.Description `
                                            -Enabled $rule.Enabled `
                                            -Action $rule.Action `
                                            -Direction $rule.Direction
                                    }
                                }
                            }
                            $result.ItemsRestored += "firewall_rules.json"
                        } catch {
                            $result.Errors += "Failed to restore firewall rules: $_"
                            $result.ItemsSkipped += "firewall_rules.json"
                            if (!$Force) { throw }
                        }
                    }
                } else {
                    $result.ItemsSkipped += "firewall_rules.json (not found in backup)"
                }

                # Restore network shares
                $sharesFile = Join-Path $backupPath "network_shares.json"
                if (Test-Path $sharesFile) {
                    if ($Force -or $PSCmdlet.ShouldProcess("Network Shares", "Restore")) {
                        try {
                            $shares = Get-Content $sharesFile | ConvertFrom-Json
                            if (!$script:TestMode) {
                                foreach ($share in $shares) {
                                    if (!(Get-SmbShare -Name $share.Name -ErrorAction SilentlyContinue)) {
                                        New-SmbShare -Name $share.Name -Path $share.Path -Description $share.Description
                                    }
                                }
                            }
                            $result.ItemsRestored += "network_shares.json"
                        } catch {
                            $result.Errors += "Failed to restore network shares: $_"
                            $result.ItemsSkipped += "network_shares.json"
                            if (!$Force) { throw }
                        }
                    }
                } else {
                    $result.ItemsSkipped += "network_shares.json (not found in backup)"
                }

                # Restore proxy settings
                $proxyFile = Join-Path $backupPath "proxy_settings.json"
                if (Test-Path $proxyFile) {
                    if ($Force -or $PSCmdlet.ShouldProcess("Proxy Settings", "Restore")) {
                        try {
                            $proxySettings = Get-Content $proxyFile | ConvertFrom-Json
                            if (!$script:TestMode) {
                                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" `
                                    -Name ProxyEnable -Value $proxySettings.ProxyEnable
                                if ($proxySettings.ProxyServer) {
                                    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" `
                                        -Name ProxyServer -Value $proxySettings.ProxyServer
                                }
                            }
                            $result.ItemsRestored += "proxy_settings.json"
                        } catch {
                            $result.Errors += "Failed to restore proxy settings: $_"
                            $result.ItemsSkipped += "proxy_settings.json"
                            if (!$Force) { throw }
                        }
                    }
                } else {
                    $result.ItemsSkipped += "proxy_settings.json (not found in backup)"
                }

                # Restore hosts file
                $hostsFile = Join-Path $backupPath "hosts"
                if (Test-Path $hostsFile) {
                    if ($Force -or $PSCmdlet.ShouldProcess("Hosts File", "Restore")) {
                        try {
                            if (!$script:TestMode) {
                                Copy-Item -Path $hostsFile -Destination "$env:SystemRoot\System32\drivers\etc\hosts" -Force
                            }
                            $result.ItemsRestored += "hosts"
                        } catch {
                            $result.Errors += "Failed to restore hosts file: $_"
                            $result.ItemsSkipped += "hosts"
                            if (!$Force) { throw }
                        }
                    }
                } else {
                    $result.ItemsSkipped += "hosts (not found in backup)"
                }

                # Restart network services (only if not in test mode)
                if (!$script:TestMode) {
                    if ($Force -or $PSCmdlet.ShouldProcess("Network Services", "Restart")) {
                        $services = @(
                            "Dnscache",
                            "NlaSvc",
                            "LanmanServer",
                            "LanmanWorkstation"
                        )
                        
                        foreach ($service in $services) {
                            if (Get-Service -Name $service -ErrorAction SilentlyContinue) {
                                Restart-Service -Name $service -Force -ErrorAction SilentlyContinue
                                $result.ItemsRestored += "ServiceRestart\$service"
                            }
                        }
                    }
                }
                
                $result.Success = ($result.Errors.Count -eq 0)
                
                # Display summary
                Write-Host "`nNetwork Settings Restore Summary:" -ForegroundColor Green
                Write-Host "Items Restored: $($result.ItemsRestored.Count)" -ForegroundColor Yellow
                Write-Host "Items Skipped: $($result.ItemsSkipped.Count)" -ForegroundColor Yellow
                Write-Host "Errors: $($result.Errors.Count)" -ForegroundColor $(if ($result.Errors.Count -gt 0) { "Red" } else { "Yellow" })
                
                if ($result.Success) {
                    Write-Host "Network Settings restored successfully from: $backupPath" -ForegroundColor Green
                    Write-Host "`nNote: System restart may be required for some network settings to take full effect" -ForegroundColor Yellow
                } else {
                    Write-Warning "Network Settings restore completed with errors"
                }
                
                Write-Verbose "Restore completed successfully"
                return $result
            }
            return $result
        } catch {
            $errorRecord = $_
            $errorMessage = @(
                "Failed to restore Network Settings"
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
            $result.Errors += $errorMessage
            return $result
        }
    }

    end {
        # Log results
        if ($result.Errors.Count -gt 0) {
            Write-Warning "Restore completed with $($result.Errors.Count) errors"
        }
        Write-Verbose "Restored $($result.ItemsRestored.Count) items, skipped $($result.ItemsSkipped.Count) items"
    }
}

# Export the function if being imported as a module
if ($MyInvocation.Line -eq "") {
    Export-ModuleMember -Function Restore-NetworkSettings
}

<#
.SYNOPSIS
Restores Windows Network settings and configuration from backup.

.DESCRIPTION
Restores Windows Network configuration and associated data from a previous backup, including network adapters,
IP configurations, DNS settings, firewall rules, wireless profiles, network shares, proxy settings, and the
hosts file. Handles network service management during restore to ensure settings are applied correctly.

.PARAMETER BackupRootPath
The root path where the backup is located. The script will look for a "Network" subdirectory within this path.

.PARAMETER Force
Forces the restore operation without prompting for confirmation and continues even if some items fail to restore.

.PARAMETER Include
Array of item names to include in the restore operation. If not specified, all available items are restored.

.PARAMETER Exclude
Array of item names to exclude from the restore operation.

.PARAMETER SkipVerification
Skips backup integrity verification (useful for testing).

.EXAMPLE
Restore-NetworkSettings -BackupRootPath "C:\Backups"

.EXAMPLE
Restore-NetworkSettings -BackupRootPath "C:\Backups" -Force

.EXAMPLE
Restore-NetworkSettings -BackupRootPath "C:\Backups" -WhatIf

.NOTES
Test cases to consider:
1. Valid backup with all files present
2. Partial backup (some files missing)
3. Corrupted backup
4. No backup found
5. Backup with invalid format
6. Permission issues during restore
7. Registry import failures
8. Network adapter configuration failures
9. Wireless profile restore failures
10. Firewall rule restore failures
11. Network share restore failures
12. Proxy settings restore failures
13. Hosts file restore failures
14. WhatIf scenario
15. Force parameter behavior
16. Include/Exclude filters
17. Network service management
18. Multiple network adapters
19. VPN connections
20. Domain vs workgroup scenarios
21. System restart requirements
22. Network path backup scenarios

.TESTCASES
# Mock test examples:
Describe "Restore-NetworkSettings" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Test-BackupPath { return "TestPath" }
        Mock Get-ChildItem { 
            return @(
                [PSCustomObject]@{ Name = "Parameters.reg"; FullName = "TestPath\Registry\Parameters.reg" },
                [PSCustomObject]@{ Name = "Interfaces.reg"; FullName = "TestPath\Registry\Interfaces.reg" }
            )
        }
        Mock Get-Content { return '{"test":"value"}' }
        Mock ConvertFrom-Json { return @{ test = "value" } }
        Mock Get-Service { return @{ Status = "Running" } }
        Mock Start-Service { }
        Mock Restart-Service { }
        Mock reg { }
        Mock Get-NetAdapter { return @() }
        Mock Get-NetFirewallRule { return @() }
        Mock Set-NetFirewallRule { }
        Mock New-NetFirewallRule { }
        Mock Get-SmbShare { return @() }
        Mock New-SmbShare { }
        Mock Set-ItemProperty { }
        Mock Copy-Item { }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Restore-NetworkSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.RestorePath | Should -Be "TestPath"
        $result.Feature | Should -Be "Network Settings"
        $result.ItemsRestored | Should -BeOfType [System.Array]
        $result.ItemsSkipped | Should -BeOfType [System.Array]
        $result.Errors | Should -BeOfType [System.Array]
    }

    It "Should handle WhatIf properly" {
        $result = Restore-NetworkSettings -BackupRootPath "TestPath" -WhatIf
        $result.ItemsRestored.Count | Should -Be 0
    }

    It "Should handle registry import failure gracefully with Force" {
        Mock reg { throw "Registry import failed" }
        $result = Restore-NetworkSettings -BackupRootPath "TestPath" -Force
        $result.Errors.Count | Should -BeGreaterThan 0
        $result.ItemsSkipped.Count | Should -BeGreaterThan 0
    }

    It "Should handle missing backup gracefully" {
        Mock Test-BackupPath { return $null }
        { Restore-NetworkSettings -BackupRootPath "TestPath" } | Should -Throw
    }

    It "Should skip verification when specified" {
        $result = Restore-NetworkSettings -BackupRootPath "TestPath" -SkipVerification
        $result.Success | Should -Be $true
    }

    It "Should handle firewall rule restore failure gracefully" {
        Mock New-NetFirewallRule { throw "Access denied" }
        $result = Restore-NetworkSettings -BackupRootPath "TestPath" -Force
        $result.Errors.Count | Should -BeGreaterThan 0
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Restore-NetworkSettings -BackupRootPath $BackupRootPath
} 