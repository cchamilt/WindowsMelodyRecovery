param(
    [Parameter(Mandatory=$true)]
    [string]$BackupRootPath
)

try {
    Write-Host "Backing up Default Apps settings..." -ForegroundColor Blue
    $backupPath = Initialize-BackupDirectory -Path "DefaultApps" -BackupType "Default Apps" -BackupRootPath $BackupRootPath
    
    if ($backupPath) {
        # Export default apps associations
        $exportPath = "$backupPath\defaultapps.xml"
        $process = Start-Process -FilePath "dism.exe" `
            -ArgumentList "/Online /Export-DefaultAppAssociations:`"$exportPath`"" `
            -Wait -PassThru -NoNewWindow
        
        if ($process.ExitCode -eq 0) {
            Write-Host "Default Apps settings backed up successfully to: $backupPath" -ForegroundColor Green
        } else {
            Write-Host "Failed to export Default Apps settings. Exit code: $($process.ExitCode)" -ForegroundColor Red
        }
    }
} catch {
    Write-Host "Failed to backup Default Apps settings: $_" -ForegroundColor Red
} 