[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$BackupRootPath = $null
)

# Load environment if not provided
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path (Split-Path $scriptPath -Parent) "scripts\load-environment.ps1")

if (!$BackupRootPath) {
    if (!(Load-Environment)) {
        Write-Host "Failed to load environment configuration" -ForegroundColor Red
        exit 1
    }
    $BackupRootPath = "$env:BACKUP_ROOT\$env:MACHINE_NAME"
}

function Restore-NetworkSettings {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath
    )
    
    try {
        Write-Host "Restoring Network Settings..." -ForegroundColor Blue
        $backupPath = Test-BackupPath -Path "Network" -BackupType "Network Settings"
        
        if ($backupPath) {
            # Network config locations
            $networkConfigs = @{
                # Network adapter settings
                "Adapters" = "HKLM:\SYSTEM\CurrentControlSet\Control\Network"
                # TCP/IP settings
                "TCPIP" = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"
                # DNS settings
                "DNS" = "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters"
                # WINS settings
                "WINS" = "HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters"
                # Network profiles
                "Profiles" = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\NetworkList\Profiles"
                # Network connections
                "Connections" = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\NetworkList\Signatures\Unmanaged"
                # Firewall rules
                "Firewall" = "HKLM:\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy"
                # VPN connections
                "VPN" = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\NetworkList\VirtualNetworks"
            }

            # Restore network settings
            Write-Host "Checking network components..." -ForegroundColor Yellow
            $networkServices = @(
                "Dhcp", "Dnscache", "NlaSvc", "netprofm",
                "LanmanWorkstation", "LanmanServer"
            )
            
            foreach ($service in $networkServices) {
                if ((Get-Service -Name $service -ErrorAction SilentlyContinue).Status -ne "Running") {
                    Start-Service -Name $service
                }
            }

            # Restore registry settings
            foreach ($config in $networkConfigs.GetEnumerator()) {
                $backupItem = Join-Path $backupPath $config.Key
                if (Test-Path $backupItem) {
                    Write-Host "Restoring $($config.Key) settings..." -ForegroundColor Yellow
                    if ((Get-Item $backupItem) -is [System.IO.DirectoryInfo]) {
                        # Skip temporary files during restore
                        $excludeFilter = @("*.tmp", "~*.*", "*.bak", "*.old")
                        Copy-Item $backupItem $config.Value -Recurse -Force -Exclude $excludeFilter
                    } else {
                        Copy-Item $backupItem $config.Value -Force
                    }
                    Write-Host "Restored configuration: $($config.Key)" -ForegroundColor Green
                }
            }

            # Restore network adapter configurations
            $adaptersFile = Join-Path $backupPath "network_adapters.json"
            if (Test-Path $adaptersFile) {
                $adapters = Get-Content $adaptersFile | ConvertFrom-Json
                foreach ($adapter in $adapters) {
                    $netAdapter = Get-NetAdapter | Where-Object { $_.MacAddress -eq $adapter.MacAddress }
                    if ($netAdapter) {
                        # Restore IP configuration
                        if ($adapter.IPAddress) {
                            Set-NetIPAddress -InterfaceIndex $netAdapter.ifIndex `
                                -IPAddress $adapter.IPAddress -PrefixLength $adapter.SubnetMask
                        }
                        # Restore DNS settings
                        if ($adapter.DNSServers) {
                            Set-DnsClientServerAddress -InterfaceIndex $netAdapter.ifIndex `
                                -ServerAddresses $adapter.DNSServers
                        }
                        # Restore other settings
                        Set-NetAdapter -Name $netAdapter.Name `
                            -MediaType $adapter.MediaType `
                            -MacAddress $adapter.MacAddress
                    }
                }
            }

            # Restore network shares
            $sharesFile = Join-Path $backupPath "network_shares.json"
            if (Test-Path $sharesFile) {
                $shares = Get-Content $sharesFile | ConvertFrom-Json
                foreach ($share in $shares) {
                    if (!(Get-SmbShare -Name $share.Name -ErrorAction SilentlyContinue)) {
                        New-SmbShare -Name $share.Name -Path $share.Path -FullAccess $share.FullAccess
                    }
                }
            }

            # Restore network profiles
            $profilesFile = "$backupPath\network_profiles.json"
            if (Test-Path $profilesFile) {
                $profiles = Get-Content $profilesFile | ConvertFrom-Json
                
                # Restore network connection profiles
                foreach ($profile in $profiles.NetConnectionProfiles) {
                    $interface = Get-NetConnectionProfile | Where-Object { $_.InterfaceAlias -eq $profile.InterfaceAlias }
                    if ($interface) {
                        Set-NetConnectionProfile -InterfaceAlias $profile.InterfaceAlias `
                            -NetworkCategory $profile.NetworkCategory `
                            -Name $profile.Name
                    }
                }

                # Restore firewall profiles
                foreach ($profile in $profiles.FirewallProfiles) {
                    Set-NetFirewallProfile -Name $profile.Name `
                        -Enabled $profile.Enabled `
                        -DefaultInboundAction $profile.DefaultInboundAction `
                        -DefaultOutboundAction $profile.DefaultOutboundAction
                }
            }

            # Restore firewall rules
            $firewallFile = "$backupPath\firewall_rules.json"
            if (Test-Path $firewallFile) {
                $rules = Get-Content $firewallFile | ConvertFrom-Json
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

            # Restore proxy settings
            $proxyFile = "$backupPath\proxy_settings.json"
            if (Test-Path $proxyFile) {
                $proxySettings = Get-Content $proxyFile | ConvertFrom-Json
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" `
                    -Name ProxyEnable -Value $proxySettings.ProxyEnable
                if ($proxySettings.ProxyServer) {
                    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" `
                        -Name ProxyServer -Value $proxySettings.ProxyServer
                }
            }

            # Restore hosts file
            $hostsFile = "$backupPath\hosts"
            if (Test-Path $hostsFile) {
                Copy-Item -Path $hostsFile -Destination "$env:SystemRoot\System32\drivers\etc\hosts" -Force
            }

            # Restart network services
            $services = @(
                "Dnscache",
                "NlaSvc",
                "LanmanServer",
                "LanmanWorkstation"
            )
            
            foreach ($service in $services) {
                if (Get-Service -Name $service -ErrorAction SilentlyContinue) {
                    Restart-Service -Name $service -Force -ErrorAction SilentlyContinue
                }
            }
            
            Write-Host "Network Settings restored successfully from: $backupPath" -ForegroundColor Green
            return $true
        }
        return $false
    } catch {
        Write-Host "Failed to restore Network Settings: $_" -ForegroundColor Red
        return $false
    }
}

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Restore-NetworkSettings -BackupRootPath $BackupRootPath
} 