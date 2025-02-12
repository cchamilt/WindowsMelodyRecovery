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
                "HKLM\SYSTEM\CurrentControlSet\Services\Rasman",
                "HKLM\SYSTEM\CurrentControlSet\Services\RASTAPI",
                "HKLM\SYSTEM\CurrentControlSet\Services\RasMan\Parameters",
                
                # VPN client settings
                "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\Connections",
                "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings\Connections",
                
                # Network policies
                "HKLM\SOFTWARE\Policies\Microsoft\Windows\NetworkConnections",
                
                # Third-party VPN clients
                "HKLM\SOFTWARE\OpenVPN",
                "HKCU\Software\OpenVPN",
                "HKLM\SOFTWARE\Cisco",
                "HKCU\Software\Cisco",
                
                # Azure VPN settings
                "HKCU\Software\Microsoft\Azure VPN"
            )

            foreach ($regPath in $regPaths) {
                $regFile = "$backupPath\$($regPath.Split('\')[-1]).reg"
                reg export $regPath $regFile /y 2>$null
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

            # Export VPN connections
            $vpnConnections = Get-VpnConnection -AllUserConnection | Select-Object -Property *
            $vpnConnections | ConvertTo-Json -Depth 10 | Out-File "$backupPath\vpn_connections.json" -Force

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
                    $certFile = Join-Path $certsPath "$($cert.Thumbprint).pfx"
                    Export-PfxCertificate -Cert $cert -FilePath $certFile -Password (ConvertTo-SecureString -String "temp" -Force -AsPlainText) | Out-Null
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