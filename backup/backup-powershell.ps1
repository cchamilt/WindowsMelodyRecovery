param(
    [Parameter(Mandatory=$true)]
    [string]$BackupRootPath
)

try {
    Write-Host "Backing up PowerShell settings..." -ForegroundColor Blue
    $backupPath = Initialize-BackupDirectory -Path "PowerShell" -BackupType "PowerShell" -BackupRootPath $BackupRootPath
    
    if ($backupPath) {
        # Define profile paths with unique backup names
        $profilePaths = @{
            $PROFILE.AllUsersAllHosts = "AllUsers_AllHosts_profile.ps1"
            $PROFILE.AllUsersCurrentHost = "AllUsers_CurrentHost_profile.ps1"
            $PROFILE.CurrentUserAllHosts = "CurrentUser_AllHosts_profile.ps1"
            $PROFILE.CurrentUserCurrentHost = "CurrentUser_CurrentHost_profile.ps1"
        }
        
        $profilesFound = $false
        
        foreach ($profile in $profilePaths.GetEnumerator()) {
            if (Test-Path $profile.Key) {
                Copy-Item -Path $profile.Key -Destination "$backupPath\$($profile.Value)" -Force
                Write-Host "Backed up profile: $($profile.Value)" -ForegroundColor Green
                $profilesFound = $true
            }
        }
        
        # Backup PowerShell modules if they exist
        $modulesPath = "$HOME\Documents\PowerShell\Modules"
        if (Test-Path $modulesPath) {
            Copy-Item -Path $modulesPath -Destination "$backupPath\Modules" -Recurse -Force
            Write-Host "PowerShell modules backed up successfully" -ForegroundColor Green
            $profilesFound = $true
        }
        
        if ($profilesFound) {
            Write-Host "PowerShell settings backed up successfully to: $backupPath" -ForegroundColor Green
        } else {
            Write-Host "No PowerShell profiles or modules found to backup" -ForegroundColor Yellow
        }
    }
} catch {
    Write-Host "Failed to backup PowerShell settings: $_" -ForegroundColor Red
} 