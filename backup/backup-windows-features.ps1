param(
    [Parameter(Mandatory=$true)]
    [string]$BackupRootPath
)

try {
    Write-Host "Backing up Windows Features..." -ForegroundColor Blue
    $backupPath = Initialize-BackupDirectory -Path "WindowsFeatures" -BackupType "Windows Features" -BackupRootPath $BackupRootPath
    
    if ($backupPath) {
        # Get enabled Windows features
        $enabledFeatures = Get-WindowsOptionalFeature -Online | 
            Where-Object { $_.State -eq "Enabled" } |
            Select-Object -Property FeatureName, State

        # Get enabled Windows capabilities
        $enabledCapabilities = Get-WindowsCapability -Online | 
            Where-Object { $_.State -eq "Installed" } |
            Select-Object -Property Name, State

        # Save to JSON files
        $enabledFeatures | ConvertTo-Json | Out-File "$backupPath\enabled_features.json" -Force
        $enabledCapabilities | ConvertTo-Json | Out-File "$backupPath\enabled_capabilities.json" -Force

        Write-Host "Windows Features backed up successfully to: $backupPath" -ForegroundColor Green
    }
} catch {
    Write-Host "Failed to backup Windows Features: $_" -ForegroundColor Red
} 