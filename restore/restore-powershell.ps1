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
                    # Create directory if it doesn't exist
                    $profileDir = Split-Path $profile.Value -Parent
                    if (!(Test-Path $profileDir)) {
                        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
                    }
                    
                    Copy-Item -Path $backupFile -Destination $profile.Value -Force
                    Write-Host "Restored profile: $($profile.Key)" -ForegroundColor Green
                    $profilesRestored = $true
                }
            }

            # Restore NuGet package sources
            $nugetSourcesFile = "$powershellPath\nuget_sources.json"
            if (Test-Path $nugetSourcesFile) {
                $nugetSources = Get-Content $nugetSourcesFile | ConvertFrom-Json
                foreach ($source in $nugetSources) {
                    if (!(Get-PackageSource -Name $source.Name -ErrorAction SilentlyContinue)) {
                        Register-PackageSource -Name $source.Name -Location $source.Location -ProviderName $source.ProviderName
                        if ($source.IsTrusted) {
                            Set-PackageSource -Name $source.Name -Trusted $true
                        }
                    }
                }
                Write-Host "NuGet package sources restored successfully" -ForegroundColor Green
            }

            # Restore PS repositories
            $psReposFile = "$powershellPath\ps_repositories.json"
            if (Test-Path $psReposFile) {
                $psRepositories = Get-Content $psReposFile | ConvertFrom-Json
                foreach ($repo in $psRepositories) {
                    if (!(Get-PSRepository -Name $repo.Name -ErrorAction SilentlyContinue)) {
                        Register-PSRepository -Name $repo.Name -SourceLocation $repo.SourceLocation -PublishLocation $repo.PublishLocation
                        Set-PSRepository -Name $repo.Name -InstallationPolicy $repo.InstallationPolicy
                    }
                }
                Write-Host "PowerShell repositories restored successfully" -ForegroundColor Green
            }

            # Restore modules
            $modulesFile = "$powershellPath\installed_modules.json"
            if (Test-Path $modulesFile) {
                $modules = Get-Content $modulesFile | ConvertFrom-Json
                foreach ($module in $modules) {
                    if (!(Get-InstalledModule -Name $module.Name -ErrorAction SilentlyContinue)) {
                        Write-Host "Installing module: $($module.Name)" -ForegroundColor Yellow
                        Install-Module -Name $module.Name -Repository $module.Repository -Force -AllowClobber
                    }
                }
                Write-Host "PowerShell modules restored successfully" -ForegroundColor Green
            }

            # Restore module files
            $modulesBackup = "$powershellPath\Modules"
            if (Test-Path $modulesBackup) {
                $modulesDestination = "$HOME\Documents\PowerShell\Modules"
                if (!(Test-Path $modulesDestination)) {
                    New-Item -ItemType Directory -Path $modulesDestination -Force | Out-Null
                }
                
                Copy-Item -Path "$modulesBackup\*" -Destination $modulesDestination -Recurse -Force
                Write-Host "PowerShell module files restored successfully" -ForegroundColor Green
            }
            
            Write-Host "PowerShell settings restored successfully" -ForegroundColor Green
            Write-Host "Note: You may need to restart PowerShell for changes to take effect" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "Failed to restore PowerShell settings: $_" -ForegroundColor Red
    }
} 