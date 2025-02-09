param(
    [Parameter(Mandatory=$true)]
    [string]$BackupRootPath
)

try {
    Write-Host "Backing up Windows Terminal settings..." -ForegroundColor Blue
    $backupPath = Initialize-BackupDirectory -Path "Terminal" -BackupType "Terminal" -BackupRootPath $BackupRootPath
    
    if ($backupPath) {
        $terminalSettingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
        
        if (Test-Path -Path $terminalSettingsPath) {
            Copy-Item -Path $terminalSettingsPath -Destination "$backupPath\settings.json" -Force
            Write-Host "Windows Terminal settings backed up successfully" -ForegroundColor Green
        } else {
            Write-Host "No Windows Terminal settings found to backup" -ForegroundColor Yellow
        }
    }
} catch {
    Write-Host "Failed to backup Windows Terminal settings: $_" -ForegroundColor Red
} 