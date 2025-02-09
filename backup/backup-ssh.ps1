param(
    [Parameter(Mandatory=$true)]
    [string]$BackupRootPath
)

try {
    Write-Host "Backing up SSH configurations..." -ForegroundColor Blue
    $backupPath = Initialize-BackupDirectory -Path "SSH" -BackupType "SSH" -BackupRootPath $BackupRootPath
    
    if ($backupPath) {
        # Source SSH directory
        $sshSourcePath = "$env:USERPROFILE\.ssh"
        
        if (Test-Path $sshSourcePath) {
            # Create backup directory with proper permissions
            icacls $backupPath /inheritance:r
            icacls $backupPath /grant:r "${env:USERNAME}:(OI)(CI)F"
            
            # Copy all SSH files
            Copy-Item -Path "$sshSourcePath\*" -Destination $backupPath -Force -Recurse
            
            # Set proper permissions on backed up private keys
            Get-ChildItem -Path $backupPath -Filter "id_*" | ForEach-Object {
                if ($_.Name -notmatch '\.pub$') {
                    icacls $_.FullName /inheritance:r
                    icacls $_.FullName /grant:r "${env:USERNAME}:F"
                }
            }
            
            Write-Host "SSH configurations backed up successfully to: $backupPath" -ForegroundColor Green
        } else {
            Write-Host "No SSH configurations found to backup" -ForegroundColor Yellow
        }
    }
} catch {
    Write-Host "Failed to backup SSH configurations: $_" -ForegroundColor Red
} 