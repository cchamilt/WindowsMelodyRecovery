param(
    [Parameter(Mandatory=$true)]
    [string]$BackupRootPath
)

try {
    Write-Host "Backing up Azure VPN configurations..." -ForegroundColor Blue
    $backupPath = Initialize-BackupDirectory -Path "VPN" -BackupType "Azure VPN" -BackupRootPath $BackupRootPath
    
    if ($backupPath) {
        # Check if Azure VPN Client is installed
        $vpnPath = "$env:ProgramFiles\Microsoft\AzureVpn"
        if (Test-Path $vpnPath) {
            # Export VPN configurations using Azure VPN CLI
            $process = Start-Process -FilePath "$vpnPath\AzureVpn.exe" `
                -ArgumentList "-e `"$backupPath\vpn_config.xml`"" `
                -Wait -PassThru -NoNewWindow
            
            if ($process.ExitCode -eq 0) {
                Write-Host "Azure VPN configurations exported successfully to: $backupPath" -ForegroundColor Green
                
                # Backup registry settings
                $regPath = "HKCU:\Software\Microsoft\Azure VPN"
                if (Test-Path $regPath) {
                    reg export $regPath "$backupPath\vpn_settings.reg" /y
                    Write-Host "Azure VPN registry settings backed up" -ForegroundColor Green
                }
            } else {
                Write-Host "Failed to export Azure VPN configurations. Exit code: $($process.ExitCode)" -ForegroundColor Red
            }
        } else {
            Write-Host "Azure VPN Client not found at: $vpnPath" -ForegroundColor Yellow
        }
    }
} catch {
    Write-Host "Failed to backup Azure VPN configurations: $_" -ForegroundColor Red
} 