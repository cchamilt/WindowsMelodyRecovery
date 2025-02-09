function Restore-VPNSettings {
    try {
        Write-Host "Restoring Azure VPN configurations..." -ForegroundColor Blue
        $vpnPath = Test-BackupPath -Path "VPN" -BackupType "Azure VPN"
        
        if ($vpnPath) {
            # Check if Azure VPN Client is installed
            $azureVpnPath = "$env:ProgramFiles\Microsoft\AzureVpn"
            if (Test-Path $azureVpnPath) {
                # Wait for Azure VPN Client service to be ready
                Start-Sleep -Seconds 5
                
                # Import VPN configurations
                $configFile = "$vpnPath\vpn_config.xml"
                if (Test-Path $configFile) {
                    $process = Start-Process -FilePath "$azureVpnPath\AzureVpn.exe" `
                        -ArgumentList "-i `"$configFile`"" `
                        -Wait -PassThru -NoNewWindow
                    
                    if ($process.ExitCode -eq 0) {
                        Write-Host "Azure VPN configurations imported successfully" -ForegroundColor Green
                        
                        # Restore registry settings
                        $regFile = "$vpnPath\vpn_settings.reg"
                        if (Test-Path $regFile) {
                            reg import $regFile
                            Write-Host "Azure VPN registry settings restored" -ForegroundColor Green
                        }
                    } else {
                        Write-Host "Failed to import Azure VPN configurations. Exit code: $($process.ExitCode)" -ForegroundColor Red
                    }
                } else {
                    Write-Host "VPN configuration file not found at: $configFile" -ForegroundColor Yellow
                }
            } else {
                Write-Host "Azure VPN Client not installed. Please install it first." -ForegroundColor Yellow
            }
        }
    } catch {
        Write-Host "Failed to restore Azure VPN configurations: $_" -ForegroundColor Red
    }
} 