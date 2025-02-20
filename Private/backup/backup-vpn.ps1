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

function Backup-VPNSettings {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath
    )
    
    try {
        Write-Host "Backing up VPN Settings..." -ForegroundColor Blue
        $backupPath = Initialize-BackupDirectory -Path "VPN" -BackupType "VPN Settings" -BackupRootPath $BackupRootPath
        
        if ($backupPath) {
            # Export VPN registry settings
            $regPaths = @(
                # RAS/VPN settings
                "HKLM\SYSTEM\CurrentControlSet\Services\RasMan",
                "HKLM\SYSTEM\CurrentControlSet\Services\RASTAPI",
                "HKLM\SYSTEM\CurrentControlSet\Services\RasMan\Parameters",
                "HKLM\SOFTWARE\Microsoft\RasCredentials",
                "HKCU\Software\Microsoft\RasCredentials",
               
                # VPN client settings
                "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\Connections",
                "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings\Connections",
               
                # Network Connections
                "HKLM\SOFTWARE\Policies\Microsoft\Windows\NetworkConnections",
               
                # OpenVPN settings
                "HKLM\SOFTWARE\OpenVPN",
                "HKCU\Software\OpenVPN",
               
                # Cisco VPN settings
                "HKLM\SOFTWARE\Cisco",
                "HKCU\Software\Cisco",
               
                # Azure VPN settings
                "HKCU\Software\Microsoft\Azure VPN"
            )

            # Create registry backup directory
            $registryPath = Join-Path $backupPath "Registry"
            New-Item -ItemType Directory -Force -Path $registryPath | Out-Null

            foreach ($regPath in $regPaths) {
                # Check if registry key exists before trying to export
                $keyExists = $false
                if ($regPath -match '^HKCU\\') {
                    $keyExists = Test-Path "Registry::HKEY_CURRENT_USER\$($regPath.Substring(5))"
                } elseif ($regPath -match '^HKLM\\') {
                    $keyExists = Test-Path "Registry::HKEY_LOCAL_MACHINE\$($regPath.Substring(5))"
                }
                
                if ($keyExists) {
                    try {
                        $regFile = Join-Path $registryPath "$($regPath.Split('\')[-1]).reg"
                        $result = reg export $regPath $regFile /y 2>&1
                        if ($LASTEXITCODE -ne 0) {
                            Write-Host "Warning: Could not export registry key: $regPath" -ForegroundColor Yellow
                        }
                    } catch {
                        Write-Host "Warning: Failed to export registry key: $regPath" -ForegroundColor Yellow
                    }
                } else {
                    Write-Host "Registry key not found: $regPath" -ForegroundColor Yellow
                }
            }

            # Export Azure VPN configurations
            $azureVpnPath = "$env:ProgramFiles\Microsoft\AzureVpn"
            if (Test-Path $azureVpnPath) {
                Write-Host "Backing up Azure VPN configurations..." -ForegroundColor Blue
                $process = Start-Process -FilePath "$azureVpnPath\AzureVpn.exe" `
                    -ArgumentList "-e `"$backupPath\azure_vpn_config.xml`"" `
                    -Wait -PassThru -NoNewWindow
                
                if ($process.ExitCode -eq 0) {
                    Write-Host "Azure VPN configurations exported successfully" -ForegroundColor Green
                }
            }

            # Export VPN connections if any exist
            try {
                $vpnConnections = Get-VpnConnection -AllUserConnection | Select-Object -Property *
                if ($vpnConnections) {
                    $vpnConnections | ConvertTo-Json -Depth 10 | Out-File "$backupPath\vpn_connections.json" -Force
                }
            } catch {
                Write-Host "Warning: Could not retrieve VPN connections" -ForegroundColor Yellow
            }

            # Export rasphone.pbk files
            $pbkPaths = @(
                "$env:APPDATA\Microsoft\Network\Connections\Pbk\rasphone.pbk",
                "$env:ProgramData\Microsoft\Network\Connections\Pbk\rasphone.pbk"
            )

            foreach ($pbkPath in $pbkPaths) {
                if (Test-Path $pbkPath) {
                    $pbkName = Split-Path -Leaf (Split-Path -Parent $pbkPath)
                    Copy-Item -Path $pbkPath -Destination "$backupPath\$pbkName.pbk" -Force
                }
            }

            # Export VPN certificates
            $certPath = "Cert:\CurrentUser\My"
            $vpnCerts = Get-ChildItem -Path $certPath | Where-Object {
                $_.EnhancedKeyUsageList.FriendlyName -match "Client Authentication" -or
                $_.Subject -match "VPN" -or
                $_.FriendlyName -match "VPN"
            }

            if ($vpnCerts) {
                $certsPath = Join-Path $backupPath "Certificates"
                New-Item -ItemType Directory -Path $certsPath -Force | Out-Null
                
                foreach ($cert in $vpnCerts) {
                    $certFile = Join-Path $certsPath "$($cert.Thumbprint).cer"
                    # Try to export as CER first (public key only)
                    try {
                        $cert | Export-Certificate -FilePath $certFile -Force | Out-Null
                        Write-Host "Exported certificate $($cert.Subject) as CER" -ForegroundColor Green
                    } catch {
                        Write-Host "Warning: Could not export certificate $($cert.Subject) - $($_.Exception.Message)" -ForegroundColor Yellow
                    }

                    # Try to export as PFX only if private key is exportable
                    if ($cert.HasPrivateKey) {
                        try {
                            $pfxFile = Join-Path $certsPath "$($cert.Thumbprint).pfx"
                            if ($cert.PrivateKey.CspKeyContainerInfo.Exportable) {
                                Export-PfxCertificate -Cert $cert -FilePath $pfxFile `
                                    -Password (ConvertTo-SecureString -String "temp" -Force -AsPlainText) | Out-Null
                                Write-Host "Exported certificate $($cert.Subject) with private key" -ForegroundColor Green
                            } else {
                                Write-Host "Warning: Certificate $($cert.Subject) private key is not exportable" -ForegroundColor Yellow
                            }
                        } catch {
                            Write-Host "Warning: Could not export certificate $($cert.Subject) with private key - $($_.Exception.Message)" -ForegroundColor Yellow
                        }
                    }
                }
            }

            # Export OpenVPN configs if they exist
            $openVpnPath = "$env:ProgramFiles\OpenVPN\config"
            if (Test-Path $openVpnPath) {
                $openVpnBackupPath = Join-Path $backupPath "OpenVPN"
                New-Item -ItemType Directory -Path $openVpnBackupPath -Force | Out-Null
                Copy-Item -Path "$openVpnPath\*" -Destination $openVpnBackupPath -Recurse -Force
            }
            
            Write-Host "VPN Settings backed up successfully to: $backupPath" -ForegroundColor Green
            return $true
        }
        return $false
    } catch {
        $errorRecord = $_
        $errorMessage = @(
            "Failed to backup [Feature]"
            "Error Message: $($errorRecord.Exception.Message)"
            "Error Type: $($errorRecord.Exception.GetType().FullName)"
            "Script Line Number: $($errorRecord.InvocationInfo.ScriptLineNumber)"
            "Script Name: $($errorRecord.InvocationInfo.ScriptName)"
            "Statement: $($errorRecord.InvocationInfo.Line.Trim())"
            if ($errorRecord.Exception.StackTrace) { "Stack Trace: $($errorRecord.Exception.StackTrace)" }
            if ($errorRecord.Exception.InnerException) { "Inner Exception: $($errorRecord.Exception.InnerException.Message)" }
        ) -join "`n"
        
        Write-Host $errorMessage -ForegroundColor Red
        return $false
    }
}

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Backup-VPNSettings -BackupRootPath $BackupRootPath
} 