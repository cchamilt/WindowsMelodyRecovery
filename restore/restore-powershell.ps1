function Restore-PowerShellSettings {
    try {
        Write-Host "Restoring PowerShell settings..." -ForegroundColor Blue
        $powershellPath = Test-BackupPath -Path "PowerShell" -BackupType "PowerShell"
        
        if ($powershellPath) {
            # Define profile paths with unique backup names
            $profilePaths = @{
                "AllUsers_AllHosts_profile.ps1" = $PROFILE.AllUsersAllHosts
                "AllUsers_CurrentHost_profile.ps1" = $PROFILE.AllUsersCurrentHost
                "CurrentUser_AllHosts_profile.ps1" = $PROFILE.CurrentUserAllHosts
                "CurrentUser_CurrentHost_profile.ps1" = $PROFILE.CurrentUserCurrentHost
            }
            
            $profilesRestored = $false
            
            # Restore profiles
            foreach ($profile in $profilePaths.GetEnumerator()) {
                $backupFile = Join-Path $powershellPath $profile.Key
                if (Test-Path $backupFile) {
                    # Create profile directory if it doesn't exist
                    $profileDir = Split-Path $profile.Value -Parent
                    if (!(Test-Path $profileDir)) {
                        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
                    }
                    
                    Copy-Item -Path $backupFile -Destination $profile.Value -Force
                    Write-Host "Restored profile: $($profile.Key)" -ForegroundColor Green
                    $profilesRestored = $true
                }
            }
            
            # Restore modules
            $modulesBackup = "$powershellPath\Modules"
            if (Test-Path $modulesBackup) {
                $modulesDestination = "$HOME\Documents\PowerShell\Modules"
                if (!(Test-Path $modulesDestination)) {
                    New-Item -ItemType Directory -Path $modulesDestination -Force | Out-Null
                }
                
                Copy-Item -Path "$modulesBackup\*" -Destination $modulesDestination -Recurse -Force
                Write-Host "PowerShell modules restored successfully" -ForegroundColor Green
                $profilesRestored = $true
            }
            
            if ($profilesRestored) {
                Write-Host "PowerShell settings restored successfully" -ForegroundColor Green
                Write-Host "Note: You may need to restart PowerShell for changes to take effect" -ForegroundColor Yellow
            } else {
                Write-Host "No PowerShell profiles or modules found to restore" -ForegroundColor Yellow
            }
        }
    } catch {
        Write-Host "Failed to restore PowerShell settings: $_" -ForegroundColor Red
    }
} 