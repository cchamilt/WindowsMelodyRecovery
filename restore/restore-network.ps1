function Restore-NetworkSettings {
    try {
        Write-Host "Restoring Network settings..." -ForegroundColor Blue
        $networkPath = Test-BackupPath -Path "Network" -BackupType "Network"
        
        if ($networkPath) {
            # Import WiFi profiles
            $wifiProfiles = Get-ChildItem -Path $networkPath -Filter "*.xml"
            foreach ($profile in $wifiProfiles) {
                $output = netsh wlan add profile filename="$($profile.FullName)" user=all
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "Imported WiFi profile: $($profile.BaseName)" -ForegroundColor Green
                } else {
                    Write-Host "Failed to import WiFi profile: $($profile.BaseName) with output: $output" -ForegroundColor Red
                }
            }
            
            # Restore network adapter configuration if it exists
            $adapterConfig = "$networkPath\network_adapters.json"
            if (Test-Path $adapterConfig) {
                $adapters = Get-Content $adapterConfig | ConvertFrom-Json
                foreach ($adapter in $adapters) {
                    $existingAdapter = Get-NetAdapter | Where-Object { $_.MacAddress -eq $adapter.MacAddress }
                    if ($existingAdapter) {
                        # Configure IP addresses
                        foreach ($ip in $adapter.IPAddresses) {
                            New-NetIPAddress -InterfaceIndex $existingAdapter.ifIndex -IPAddress $ip -ErrorAction SilentlyContinue
                        }
                        
                        # Configure DNS servers
                        Set-DnsClientServerAddress -InterfaceIndex $existingAdapter.ifIndex -ServerAddresses $adapter.DNSServers
                    }
                }
            }
            
            Write-Host "Network settings restored successfully" -ForegroundColor Green
        }
    } catch {
        Write-Host "Failed to restore Network settings: $_" -ForegroundColor Red
    }
} 