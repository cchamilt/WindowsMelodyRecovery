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

        # Backup installed modules list
        $installedModules = Get-InstalledModule | Select-Object Name, Version, Repository
        $installedModules | ConvertTo-Json | Out-File "$backupPath\installed_modules.json" -Force
        Write-Host "PowerShell module list backed up successfully" -ForegroundColor Green

        # Backup NuGet package sources
        $nugetSources = Get-PackageSource | Select-Object Name, Location, ProviderName, IsTrusted
        $nugetSources | ConvertTo-Json | Out-File "$backupPath\nuget_sources.json" -Force
        Write-Host "NuGet package sources backed up successfully" -ForegroundColor Green

        # Backup PSRepository settings
        $psRepositories = Get-PSRepository | Select-Object Name, SourceLocation, PublishLocation, InstallationPolicy
        $psRepositories | ConvertTo-Json | Out-File "$backupPath\ps_repositories.json" -Force
        Write-Host "PowerShell repositories backed up successfully" -ForegroundColor Green

        # Output summary
        Write-Host "`nPowerShell Backup Summary:" -ForegroundColor Green
        Write-Host "Profiles: $($profilePaths.Count) found" -ForegroundColor Yellow
        Write-Host "Installed Modules: $($installedModules.Count)" -ForegroundColor Yellow
        Write-Host "NuGet Sources: $($nugetSources.Count)" -ForegroundColor Yellow
        Write-Host "PS Repositories: $($psRepositories.Count)" -ForegroundColor Yellow
        
        Write-Host "PowerShell settings backed up successfully to: $backupPath" -ForegroundColor Green
    }
} catch {
    Write-Host "Failed to backup PowerShell settings: $_" -ForegroundColor Red
} 