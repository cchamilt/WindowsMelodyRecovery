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
            # Import registry settings first
            $regFiles = Get-ChildItem -Path $backupPath -Filter "*.reg"
            foreach ($regFile in $regFiles) {
                reg import $regFile.FullName | Out-Null
            }

            # Restore Azure VPN configurations
            $azureVpnConfig = "$backupPath\azure_vpn_config.xml"
            if (Test-Path $azureVpnConfig) {
                Write-Host "Restoring Azure VPN configurations..." -ForegroundColor Blue
                $azureVpnPath = "$env:ProgramFiles\Microsoft\AzureVpn"
                if (Test-Path $azureVpnPath) {
                    $process = Start-Process -FilePath "$azureVpnPath\AzureVpn.exe" `
                        -ArgumentList "-i `"$azureVpnConfig`"" `
                        -Wait -PassThru -NoNewWindow
                    
                    if ($process.ExitCode -eq 0) {
                        Write-Host "Azure VPN configurations imported successfully" -ForegroundColor Green
                    }
                }
            }

            # Restore VPN connections
            $vpnConnectionsFile = "$backupPath\vpn_connections.json"
            if (Test-Path $vpnConnectionsFile) {
                $vpnConnections = Get-Content $vpnConnectionsFile | ConvertFrom-Json
                foreach ($vpn in $vpnConnections) {
                    # Remove existing connection if it exists
                    Remove-VpnConnection -Name $vpn.Name -Force -ErrorAction SilentlyContinue
                    
                    # Add VPN connection
                    Add-VpnConnection -Name $vpn.Name `
                        -ServerAddress $vpn.ServerAddress `
                        -TunnelType $vpn.TunnelType `
                        -EncryptionLevel $vpn.EncryptionLevel `
                        -AuthenticationMethod $vpn.AuthenticationMethod `
                        -SplitTunneling:$vpn.SplitTunneling `
                        -RememberCredential:$vpn.RememberCredential `
                        -Force
                }
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

            # Restore VPN certificates
            $certsPath = Join-Path $backupPath "Certificates"
            if (Test-Path $certsPath) {
                $certFiles = Get-ChildItem -Path $certsPath -Filter "*.pfx"
                foreach ($certFile in $certFiles) {
                    Import-PfxCertificate -FilePath $certFile.FullName `
                        -CertStoreLocation "Cert:\CurrentUser\My" `
                        -Password (ConvertTo-SecureString -String "temp" -Force -AsPlainText)
                }
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