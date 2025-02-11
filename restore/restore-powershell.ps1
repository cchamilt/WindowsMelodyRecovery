[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$BackupRootPath = $null
)

# Load environment if not provided
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path (Split-Path $scriptPath -Parent) "scripts\load-environment.ps1")

if (!$BackupRootPath) {
    if (!(Load-Environment)) {
        Write-Host "Failed to load environment configuration" -ForegroundColor Red
        exit 1
    }
    $BackupRootPath = "$env:BACKUP_ROOT\$env:MACHINE_NAME"
}

function Restore-PowerShellSettings {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath
    )
    
    try {
        Write-Host "Restoring PowerShell Settings..." -ForegroundColor Blue
        $backupPath = Test-BackupPath -Path "PowerShell" -BackupType "PowerShell Settings"
        
        if ($backupPath) {
            # Import registry settings first
            $regFiles = Get-ChildItem -Path $backupPath -Filter "*.reg"
            foreach ($regFile in $regFiles) {
                reg import $regFile.FullName | Out-Null
            }

            # Restore PowerShell profiles with unique names
            $profilePaths = @{
                $PROFILE.AllUsersAllHosts = "AllUsers_AllHosts_profile.ps1"
                $PROFILE.AllUsersCurrentHost = "AllUsers_CurrentHost_profile.ps1"
                $PROFILE.CurrentUserAllHosts = "CurrentUser_AllHosts_profile.ps1"
                $PROFILE.CurrentUserCurrentHost = "CurrentUser_CurrentHost_profile.ps1"
            }

            foreach ($profile in $profilePaths.GetEnumerator()) {
                $sourcePath = Join-Path $backupPath $profile.Value
                if (Test-Path $sourcePath) {
                    $targetDir = Split-Path $profile.Key -Parent
                    if (!(Test-Path $targetDir)) {
                        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
                    }
                    Copy-Item -Path $sourcePath -Destination $profile.Key -Force
                    Write-Host "Restored profile: $($profile.Value)" -ForegroundColor Green
                }
            }

            # Restore NuGet package sources
            $nugetSourcesFile = "$backupPath\nuget_sources.json"
            if (Test-Path $nugetSourcesFile) {
                $nugetSources = Get-Content $nugetSourcesFile | ConvertFrom-Json
                foreach ($source in $nugetSources) {
                    # Remove existing source if it exists
                    Unregister-PackageSource -Name $source.Name -ErrorAction SilentlyContinue
                    # Register the package source
                    Register-PackageSource -Name $source.Name -Location $source.Location -ProviderName $source.ProviderName -Trusted:$source.IsTrusted
                }
                Write-Host "NuGet package sources restored successfully" -ForegroundColor Green
            }

            # Restore PSRepository settings
            $psRepositoriesFile = "$backupPath\ps_repositories.json"
            if (Test-Path $psRepositoriesFile) {
                $psRepositories = Get-Content $psRepositoriesFile | ConvertFrom-Json
                foreach ($repo in $psRepositories) {
                    # Unregister existing repository if it exists
                    Unregister-PSRepository -Name $repo.Name -ErrorAction SilentlyContinue
                    # Register the repository
                    Register-PSRepository -Name $repo.Name -SourceLocation $repo.SourceLocation -PublishLocation $repo.PublishLocation -InstallationPolicy $repo.InstallationPolicy
                }
                Write-Host "PowerShell repositories restored successfully" -ForegroundColor Green
            }

            # Restore installed modules
            $modulesFile = "$backupPath\installed_modules.json"
            if (Test-Path $modulesFile) {
                $modules = Get-Content $modulesFile | ConvertFrom-Json
                foreach ($module in $modules) {
                    if (!(Get-InstalledModule -Name $module.Name -ErrorAction SilentlyContinue)) {
                        Install-Module -Name $module.Name -RequiredVersion $module.Version -Repository $module.Repository -Force
                        Write-Host "Installed module: $($module.Name) v$($module.Version)" -ForegroundColor Green
                    }
                }
            }

            # Restore PSReadLine history
            $historyFile = "$backupPath\ConsoleHost_history.txt"
            if (Test-Path $historyFile) {
                $historyPath = "$env:APPDATA\Microsoft\Windows\PowerShell\PSReadLine"
                if (!(Test-Path $historyPath)) {
                    New-Item -ItemType Directory -Path $historyPath -Force | Out-Null
                }
                Copy-Item -Path $historyFile -Destination "$historyPath\ConsoleHost_history.txt" -Force
            }

            # Restore custom formats and types
            $customPaths = @{
                "Types" = "$env:USERPROFILE\Documents\WindowsPowerShell\Types"
                "Formats" = "$env:USERPROFILE\Documents\WindowsPowerShell\Formats"
            }

            foreach ($path in $customPaths.GetEnumerator()) {
                $sourcePath = Join-Path $backupPath $path.Key
                if (Test-Path $sourcePath) {
                    if (!(Test-Path $path.Value)) {
                        New-Item -ItemType Directory -Path $path.Value -Force | Out-Null
                    }
                    Copy-Item -Path "$sourcePath\*" -Destination $path.Value -Recurse -Force
                }
            }

            # Restore module configurations
            $moduleConfigBackupPath = Join-Path $backupPath "ModuleConfigs"
            if (Test-Path $moduleConfigBackupPath) {
                $moduleConfigPath = "$env:USERPROFILE\Documents\WindowsPowerShell\Modules"
                if (!(Test-Path $moduleConfigPath)) {
                    New-Item -ItemType Directory -Path $moduleConfigPath -Force | Out-Null
                }
                Copy-Item -Path "$moduleConfigBackupPath\*" -Destination $moduleConfigPath -Recurse -Force
            }

            # Restart PowerShell host to apply changes
            Write-Host "`nPlease restart your PowerShell session to apply all changes" -ForegroundColor Yellow
            
            Write-Host "PowerShell Settings restored successfully from: $backupPath" -ForegroundColor Green
            return $true
        }
        return $false
    } catch {
        Write-Host "Failed to restore PowerShell Settings: $_" -ForegroundColor Red
        return $false
    }
}

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Restore-PowerShellSettings -BackupRootPath $BackupRootPath
}