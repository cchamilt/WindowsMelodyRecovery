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
            # Import registry settings first
            $regFiles = Get-ChildItem -Path $backupPath -Filter "*.reg"
            foreach ($regFile in $regFiles) {
                reg import $regFile.FullName | Out-Null
            }

            # Restore network adapter configurations
            $adapterConfigsFile = "$backupPath\adapter_configs.json"
            if (Test-Path $adapterConfigsFile) {
                $savedConfigs = Get-Content $adapterConfigsFile | ConvertFrom-Json
                $currentConfigs = Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled }

                foreach ($current in $currentConfigs) {
                    $saved = $savedConfigs | Where-Object { $_.SettingID -eq $current.SettingID }
                    if ($saved) {
                        # Restore IP configuration
                        if ($saved.IPAddress) {
                            $current.EnableStatic($saved.IPAddress, $saved.IPSubnet)
                        }
                        
                        # Restore DNS settings
                        if ($saved.DNSServerSearchOrder) {
                            $current.SetDNSServerSearchOrder($saved.DNSServerSearchOrder)
                        }
                        
                        # Restore WINS settings
                        if ($saved.WINSPrimaryServer) {
                            $current.SetWINSServer($saved.WINSPrimaryServer, $saved.WINSSecondaryServer)
                        }
                        
                        # Restore gateway settings
                        if ($saved.DefaultIPGateway) {
                            $current.SetGateways($saved.DefaultIPGateway, $saved.GatewayCostMetric)
                        }
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

            # Restore network shares
            $sharesFile = "$backupPath\network_shares.json"
            if (Test-Path $sharesFile) {
                $shares = Get-Content $sharesFile | ConvertFrom-Json
                foreach ($share in $shares) {
                    if (!(Get-WmiObject Win32_Share -Filter "Name='$($share.Name)'")) {
                        $null = [WmiClass]"Win32_Share"
                        $null = $wmi.Create($share.Path, $share.Name, $share.Type)
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