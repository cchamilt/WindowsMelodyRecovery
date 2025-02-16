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

function Restore-VPNSettings {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath
    )
    
    try {
        Write-Host "Restoring VPN Settings..." -ForegroundColor Blue
        $backupPath = Test-BackupPath -Path "VPN" -BackupType "VPN Settings"
        
        if ($backupPath) {
            # VPN config locations
            $vpnConfigs = @{
                # VPN connections
                "Connections" = "HKLM:\SYSTEM\CurrentControlSet\Services\RasMan\Parameters"
                # VPN network settings
                "Network" = "HKLM:\SYSTEM\CurrentControlSet\Services\Rasman\Parameters\Config"
                # VPN security settings
                "Security" = "HKLM:\SYSTEM\CurrentControlSet\Services\PolicyAgent"
                # VPN client settings
                "Client" = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings\Connections"
                # VPN credentials
                "Credentials" = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Credentials"
                # VPN routing
                "Routing" = "HKLM:\SYSTEM\CurrentControlSet\Services\RasMan\Parameters\Routing"
                # VPN protocols
                "Protocols" = "HKLM:\SYSTEM\CurrentControlSet\Services\RasMan\Parameters\Protocols"
            }

            # Restore VPN settings
            Write-Host "Checking VPN components..." -ForegroundColor Yellow
            $vpnServices = @(
                "RasMan",               # Remote Access Connection Manager
                "Tapisrv",             # Telephony
                "IKEv2",               # IKE and AuthIP IPsec Keying Modules
                "PolicyAgent"          # IPsec Policy Agent
            )
            
            foreach ($service in $vpnServices) {
                if ((Get-Service -Name $service -ErrorAction SilentlyContinue).Status -ne "Running") {
                    Start-Service -Name $service
                }
            }

            # Restore registry settings
            foreach ($config in $vpnConfigs.GetEnumerator()) {
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

            # Restore VPN connections
            $connectionsFile = Join-Path $backupPath "vpn_connections.json"
            if (Test-Path $connectionsFile) {
                $connections = Get-Content $connectionsFile | ConvertFrom-Json
                foreach ($connection in $connections) {
                    # Add VPN connection
                    Add-VpnConnection -Name $connection.Name `
                        -ServerAddress $connection.ServerAddress `
                        -TunnelType $connection.TunnelType `
                        -EncryptionLevel $connection.EncryptionLevel `
                        -AuthenticationMethod $connection.AuthenticationMethod `
                        -RememberCredential $connection.RememberCredential `
                        -SplitTunneling $connection.SplitTunneling `
                        -Force

                    # Restore connection-specific settings
                    if ($connection.CustomSettings) {
                        foreach ($setting in $connection.CustomSettings.PSObject.Properties) {
                            Set-VpnConnectionTriggerDnsConfiguration -ConnectionName $connection.Name `
                                -DnsSuffix $setting.Name -DnsIPAddress $setting.Value
                        }
                    }
                }
            }

            # Restore VPN certificates
            $certificatesFile = Join-Path $backupPath "vpn_certificates.pfx"
            if (Test-Path $certificatesFile) {
                # Import VPN certificate
                $certPassword = ConvertTo-SecureString -String "VPNCertPassword" -Force -AsPlainText
                Import-PfxCertificate -FilePath $certificatesFile -CertStoreLocation "Cert:\LocalMachine\My" `
                    -Password $certPassword
            }

            # Restore rasphone.pbk files
            $pbkFiles = Get-ChildItem -Path $backupPath -Filter "*.pbk"
            foreach ($pbkFile in $pbkFiles) {
                $destPath = if ($pbkFile.Name -like "*ProgramData*") {
                    "$env:ProgramData\Microsoft\Network\Connections\Pbk\rasphone.pbk"
                } else {
                    "$env:APPDATA\Microsoft\Network\Connections\Pbk\rasphone.pbk"
                }
                
                New-Item -ItemType Directory -Path (Split-Path $destPath) -Force | Out-Null
                Copy-Item -Path $pbkFile.FullName -Destination $destPath -Force
            }

            # Restore OpenVPN configs
            $openVpnBackupPath = Join-Path $backupPath "OpenVPN"
            if (Test-Path $openVpnBackupPath) {
                $openVpnPath = "$env:ProgramFiles\OpenVPN\config"
                if (!(Test-Path $openVpnPath)) {
                    New-Item -ItemType Directory -Path $openVpnPath -Force | Out-Null
                }
                Copy-Item -Path "$openVpnBackupPath\*" -Destination $openVpnPath -Recurse -Force
            }

            # Restart VPN services
            $services = @(
                "RasMan",
                "RasAuto",
                "Tapisrv",
                "OpenVPNService"
            )
            
            foreach ($service in $services) {
                if (Get-Service -Name $service -ErrorAction SilentlyContinue) {
                    Restart-Service -Name $service -Force -ErrorAction SilentlyContinue
                }
            }
            
            Write-Host "VPN Settings restored successfully from: $backupPath" -ForegroundColor Green
            return $true
        }
        return $false
    } catch {
        Write-Host "Failed to restore VPN Settings: $_" -ForegroundColor Red
        return $false
    }
}

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Restore-VPNSettings -BackupRootPath $BackupRootPath
} 