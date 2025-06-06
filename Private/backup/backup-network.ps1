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

function Backup-NetworkSettings {
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
            Write-Verbose "Starting backup of Network Settings..."
            Write-Host "Backing up Network Settings..." -ForegroundColor Blue
            
            # Validate inputs before proceeding
            if (!(Test-Path $BackupRootPath)) {
                throw [System.IO.DirectoryNotFoundException]"Backup root path not found: $BackupRootPath"
            }
            
            $backupPath = Initialize-BackupDirectory -Path "Network" -BackupType "Network Settings" -BackupRootPath $BackupRootPath
            
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

                # Registry paths for network settings
                $registryPaths = @(
                    "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters",
                    "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces",
                    "HKLM\SYSTEM\CurrentControlSet\Services\Dhcp\Parameters",
                    "HKLM\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters",
                    "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\NetworkCards",
                    "HKLM\SYSTEM\CurrentControlSet\Control\Network",
                    "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\NetworkList",
                    "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
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
                                $backedUpItems += "$($path.Split('\')[-1]).reg"
                            } catch {
                                $errors += "Failed to export registry path $path : $_"
                            }
                        }
                    } else {
                        Write-Verbose "Registry key not found: $path"
                    }
                }

                # Get network adapter information
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export network adapter information"
                } else {
                    try {
                        $networkAdapters = Get-NetAdapter | Select-Object Name, InterfaceDescription, Status, MacAddress, LinkSpeed, InterfaceIndex
                        $networkAdapters | ConvertTo-Json -Depth 10 | Out-File "$backupPath\network_adapters.json" -Force
                        $backedUpItems += "network_adapters.json"
                    } catch {
                        $errors += "Failed to get network adapter information: $_"
                    }
                }

                # Get network configuration
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export network configuration"
                } else {
                    try {
                        $networkConfig = @{
                            IPConfig = Get-NetIPConfiguration | Select-Object InterfaceAlias, InterfaceIndex, IPv4Address, IPv6Address, DNSServer
                            Routes = Get-NetRoute | Select-Object InterfaceAlias, DestinationPrefix, NextHop, RouteMetric
                            DNS = Get-DnsClientServerAddress | Select-Object InterfaceAlias, ServerAddresses
                            Firewall = Get-NetFirewallProfile | Select-Object Name, Enabled, DefaultInboundAction, DefaultOutboundAction
                        }
                        $networkConfig | ConvertTo-Json -Depth 10 | Out-File "$backupPath\network_config.json" -Force
                        $backedUpItems += "network_config.json"
                    } catch {
                        $errors += "Failed to get network configuration: $_"
                    }
                }

                # Get wireless network profiles
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export wireless network profiles"
                } else {
                    try {
                        $wirelessProfiles = netsh wlan show profiles | Select-String "All User Profile" | ForEach-Object {
                            $profileName = $_.ToString().Split(":")[1].Trim()
                            $profileInfo = netsh wlan show profile name="$profileName" key=clear
                            @{
                                Name = $profileName
                                Info = $profileInfo
                            }
                        }
                        $wirelessProfiles | ConvertTo-Json -Depth 10 | Out-File "$backupPath\wireless_profiles.json" -Force
                        $backedUpItems += "wireless_profiles.json"
                    } catch {
                        $errors += "Failed to get wireless network profiles: $_"
                    }
                }

                # Get firewall rules
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export firewall rules"
                } else {
                    try {
                        $firewallRules = Get-NetFirewallRule | Select-Object Name, DisplayName, Description, Enabled, Action, Direction
                        $firewallRules | ConvertTo-Json -Depth 10 | Out-File "$backupPath\firewall_rules.json" -Force
                        $backedUpItems += "firewall_rules.json"
                    } catch {
                        $errors += "Failed to get firewall rules: $_"
                    }
                }

                # Get network shares
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export network shares"
                } else {
                    try {
                        $networkShares = Get-SmbShare | Select-Object Name, Path, Description, ShareType
                        $networkShares | ConvertTo-Json -Depth 10 | Out-File "$backupPath\network_shares.json" -Force
                        $backedUpItems += "network_shares.json"
                    } catch {
                        $errors += "Failed to get network shares: $_"
                    }
                }

                # Get proxy settings
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export proxy settings"
                } else {
                    try {
                        $proxySettings = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -ErrorAction SilentlyContinue
                        if ($proxySettings) {
                            $proxySettings | ConvertTo-Json -Depth 10 | Out-File "$backupPath\proxy_settings.json" -Force
                            $backedUpItems += "proxy_settings.json"
                        }
                    } catch {
                        $errors += "Failed to get proxy settings: $_"
                    }
                }

                # Backup hosts file
                if ($WhatIf) {
                    Write-Host "WhatIf: Would backup hosts file"
                } else {
                    try {
                        $hostsFile = "$env:SystemRoot\System32\drivers\etc\hosts"
                        if (Test-Path $hostsFile) {
                            Copy-Item -Path $hostsFile -Destination "$backupPath\hosts" -Force
                            $backedUpItems += "hosts"
                        }
                    } catch {
                        $errors += "Failed to backup hosts file: $_"
                    }
                }
                
                # Return object for better testing and validation
                $result = [PSCustomObject]@{
                    Success = $true
                    BackupPath = $backupPath
                    Feature = "Network Settings"
                    Timestamp = Get-Date
                    Items = $backedUpItems
                    Errors = $errors
                }
                
                Write-Host "Network Settings backed up successfully to: $backupPath" -ForegroundColor Green
                Write-Verbose "Backup completed successfully"
                return $result
            }
            return $false
        } catch {
            $errorRecord = $_
            $errorMessage = @(
                "Failed to backup Network Settings"
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
    Export-ModuleMember -Function Backup-NetworkSettings
}

<#
.SYNOPSIS
Backs up Windows Network settings and configurations.

.DESCRIPTION
Creates a backup of Windows Network settings, including network adapters, IP configurations, DNS settings,
firewall rules, wireless profiles, network shares, proxy settings, and the hosts file. Supports comprehensive
network configuration backup for both wired and wireless connections.

.PARAMETER BackupRootPath
The root path where the backup will be created. A subdirectory named "Network" will be created within this path.

.PARAMETER Force
Forces the backup operation even if the destination already exists.

.PARAMETER WhatIf
Shows what would be backed up without actually performing the backup operation.

.EXAMPLE
Backup-NetworkSettings -BackupRootPath "C:\Backups"

.EXAMPLE
Backup-NetworkSettings -BackupRootPath "C:\Backups" -WhatIf

.NOTES
Test cases to consider:
1. Valid backup path with proper permissions
2. Invalid/nonexistent backup path
3. Empty backup path
4. No permissions to write
5. Registry export success/failure for each key
6. Network adapter information retrieval success/failure
7. Network configuration retrieval success/failure
8. Wireless profile retrieval success/failure
9. Firewall rules retrieval success/failure
10. Network shares retrieval success/failure
11. Proxy settings retrieval success/failure
12. Hosts file backup success/failure
13. JSON serialization success/failure
14. Multiple network adapters scenario
15. VPN connections scenario
16. Domain vs workgroup scenarios
17. Network path scenarios

.TESTCASES
# Mock test examples:
Describe "Backup-NetworkSettings" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Initialize-BackupDirectory { return "TestPath" }
        Mock New-Item { }
        Mock Get-NetAdapter { return @(
            [PSCustomObject]@{
                Name = "Ethernet"
                InterfaceDescription = "Intel(R) Ethernet Connection"
                Status = "Up"
                MacAddress = "00:11:22:33:44:55"
                LinkSpeed = "1 Gbps"
                InterfaceIndex = 1
            }
        )}
        Mock Get-NetIPConfiguration { return @(
            [PSCustomObject]@{
                InterfaceAlias = "Ethernet"
                InterfaceIndex = 1
                IPv4Address = "192.168.1.100"
                IPv6Address = "fe80::1234:5678:9abc:def0"
                DNSServer = @("8.8.8.8", "8.8.4.4")
            }
        )}
        Mock Get-NetRoute { return @(
            [PSCustomObject]@{
                InterfaceAlias = "Ethernet"
                DestinationPrefix = "0.0.0.0/0"
                NextHop = "192.168.1.1"
                RouteMetric = 256
            }
        )}
        Mock Get-DnsClientServerAddress { return @(
            [PSCustomObject]@{
                InterfaceAlias = "Ethernet"
                ServerAddresses = @("8.8.8.8", "8.8.4.4")
            }
        )}
        Mock Get-NetFirewallProfile { return @(
            [PSCustomObject]@{
                Name = "Domain"
                Enabled = $true
                DefaultInboundAction = "Block"
                DefaultOutboundAction = "Allow"
            }
        )}
        Mock Get-NetFirewallRule { return @(
            [PSCustomObject]@{
                Name = "TestRule"
                DisplayName = "Test Firewall Rule"
                Description = "Test rule description"
                Enabled = $true
                Action = "Allow"
                Direction = "Inbound"
            }
        )}
        Mock Get-SmbShare { return @(
            [PSCustomObject]@{
                Name = "TestShare"
                Path = "C:\TestShare"
                Description = "Test share"
                ShareType = "FileSystemDirectory"
            }
        )}
        Mock Get-ItemProperty { return @{ ProxyEnable = 0; ProxyServer = "" } }
        Mock netsh { return @"
All User Profile     : TestNetwork
"@
        }
        Mock ConvertTo-Json { return '{"test":"value"}' }
        Mock Out-File { }
        Mock Copy-Item { }
        Mock reg { }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Backup-NetworkSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.BackupPath | Should -Be "TestPath"
        $result.Feature | Should -Be "Network Settings"
        $result.Items | Should -BeOfType [System.Array]
        $result.Errors | Should -BeOfType [System.Array]
    }

    It "Should handle registry export failure gracefully" {
        Mock reg { throw "Failed to export registry" }
        $result = Backup-NetworkSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle network adapter query failure gracefully" {
        Mock Get-NetAdapter { throw "Network adapter query failed" }
        $result = Backup-NetworkSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should support WhatIf parameter" {
        $result = Backup-NetworkSettings -BackupRootPath "TestPath" -WhatIf
        $result.Success | Should -Be $true
    }

    It "Should handle wireless profile export failure gracefully" {
        Mock netsh { throw "Wireless profile export failed" }
        $result = Backup-NetworkSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Backup-NetworkSettings -BackupRootPath $BackupRootPath
} 