param(
    [Parameter(Mandatory=$true)]
    [string]$BackupRootPath
)

try {
    Write-Host "Backing up Network settings..." -ForegroundColor Blue
    $backupPath = Initialize-BackupDirectory -Path "Network" -BackupType "Network" -BackupRootPath $BackupRootPath
    
    if ($backupPath) {
        # Export network profiles
        $netshOutput = netsh wlan export profile key=clear folder="$backupPath"
        if ($LASTEXITCODE -eq 0) {
            Write-Host "WiFi profiles exported successfully" -ForegroundColor Green
        } else {
            Write-Host "Failed to export WiFi profiles: $netshOutput" -ForegroundColor Red
        }
        
        # Export network adapter settings
        $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
        $adapterConfig = $adapters | ForEach-Object {
            @{
                Name = $_.Name
                InterfaceDescription = $_.InterfaceDescription
                MacAddress = $_.MacAddress
                IPAddresses = (Get-NetIPAddress -InterfaceIndex $_.ifIndex).IPAddress
                DNSServers = (Get-DnsClientServerAddress -InterfaceIndex $_.ifIndex).ServerAddresses
            }
        }
        
        $adapterConfig | ConvertTo-Json | Out-File "$backupPath\network_adapters.json" -Force
        Write-Host "Network adapter settings backed up successfully to: $backupPath" -ForegroundColor Green
    }
} catch {
    Write-Host "Failed to backup Network settings: $_" -ForegroundColor Red
} 