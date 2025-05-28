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
            
            $backupPath = Initialize-BackupDirectory -Path "Network" -BackupType "Network" -BackupRootPath $BackupRootPath
            
            if ($backupPath) {
                $backedUpItems = @()
                $errors = @()
                
                # Registry paths for network settings
                $registryPaths = @(
                    "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters",
                    "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces",
                    "HKLM\SYSTEM\CurrentControlSet\Services\Dhcp\Parameters",
                    "HKLM\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters",
                    "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\NetworkCards"
                )

                # Export registry settings
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export registry settings for network"
                } else {
                    foreach ($path in $registryPaths) {
                        try {
                            $regFile = Join-Path $backupPath "network_$($path.Split('\')[-1]).reg"
                            reg export $path $regFile /y | Out-Null
                            $backedUpItems += "Registry: $path"
                        } catch {
                            $errors += "Failed to export registry path $path : $_"
                        }
                    }
                }

                # Get network adapter information
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export network adapter information"
                } else {
                    try {
                        $networkAdapters = Get-NetAdapter | Select-Object Name, InterfaceDescription, Status, MacAddress, LinkSpeed
                        $networkAdapters | ConvertTo-Json | Out-File "$backupPath\network_adapters.json" -Force
                        $backedUpItems += "Network adapters information"
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
                        $backedUpItems += "Network configuration"
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
                        $backedUpItems += "Wireless network profiles"
                    } catch {
                        $errors += "Failed to get wireless network profiles: $_"
                    }
                }
                
                # Return object for better testing and validation
                $result = [PSCustomObject]@{
                    Success = $true
                    BackupPath = $backupPath
                    Feature = "Network"
                    Timestamp = Get-Date
                    Items = $backedUpItems
                    Errors = $errors
                }
                
                Write-Host "Network settings backed up successfully to: $backupPath" -ForegroundColor Green
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
Backs up network settings and configurations.

.DESCRIPTION
Creates a backup of network settings including registry settings, adapter information, network configuration, and wireless profiles.

.EXAMPLE
Backup-NetworkSettings -BackupRootPath "C:\Backups"

.NOTES
Test cases to consider:
1. Valid backup path with proper permissions
2. Invalid/nonexistent backup path
3. Empty backup path
4. No permissions to write
5. Registry export success/failure
6. Network adapter information retrieval success/failure
7. Network configuration retrieval success/failure
8. Wireless profile retrieval success/failure
9. JSON serialization success/failure

.TESTCASES
# Mock test examples:
Describe "Backup-NetworkSettings" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Initialize-BackupDirectory { return "TestPath" }
        Mock Get-NetAdapter { return @(
            [PSCustomObject]@{
                Name = "Ethernet"
                InterfaceDescription = "Intel(R) Ethernet Connection"
                Status = "Up"
                MacAddress = "00:11:22:33:44:55"
                LinkSpeed = "1 Gbps"
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
        Mock netsh { return @"
All User Profile     : TestNetwork
"@
        }
        Mock ConvertTo-Json { return '{"test":"value"}' }
        Mock Out-File { }
        Mock reg { }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Backup-NetworkSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.BackupPath | Should -Be "TestPath"
        $result.Feature | Should -Be "Network"
    }

    It "Should handle registry export failure gracefully" {
        Mock reg { throw "Failed to export registry" }
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