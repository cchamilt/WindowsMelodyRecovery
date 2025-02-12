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

function Backup-PowerShellSettings {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath
    )
    
    try {
        Write-Host "Backing up PowerShell Settings..." -ForegroundColor Blue
        $backupPath = Initialize-BackupDirectory -Path "PowerShell" -BackupType "PowerShell Settings" -BackupRootPath $BackupRootPath
        
        if ($backupPath) {
            # Export PowerShell registry settings
            $regPaths = @(
                # PowerShell execution policy
                "HKLM\SOFTWARE\Microsoft\PowerShell\1\ShellIds\Microsoft.PowerShell",
                "HKLM\SOFTWARE\Microsoft\PowerShell\3\ShellIds\Microsoft.PowerShell",
                "HKLM\SOFTWARE\Wow6432Node\Microsoft\PowerShell\1\ShellIds\Microsoft.PowerShell",
                
                # PowerShell module logging
                "HKLM\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging",
                "HKLM\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging",
                
                # PowerShell transcription
                "HKLM\SOFTWARE\Policies\Microsoft\Windows\PowerShell\Transcription",
                
                # PSReadLine settings
                "HKCU\Console",
                "HKCU\Software\Microsoft\PowerShell"
            )

            foreach ($regPath in $regPaths) {
                $regFile = "$backupPath\$($regPath.Split('\')[-1]).reg"
                reg export $regPath $regFile /y 2>$null
            }

            # Backup PowerShell profiles with unique names
            $profilePaths = @{
                $PROFILE.AllUsersAllHosts = "AllUsers_AllHosts_profile.ps1"
                $PROFILE.AllUsersCurrentHost = "AllUsers_CurrentHost_profile.ps1"
                $PROFILE.CurrentUserAllHosts = "CurrentUser_AllHosts_profile.ps1"
                $PROFILE.CurrentUserCurrentHost = "CurrentUser_CurrentHost_profile.ps1"
            }

            foreach ($profile in $profilePaths.GetEnumerator()) {
                if (Test-Path $profile.Key) {
                    Copy-Item -Path $profile.Key -Destination "$backupPath\$($profile.Value)" -Force
                    Write-Host "Backed up profile: $($profile.Value)" -ForegroundColor Green
                }
            }

            # Backup installed modules list (including version and source)
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

            # Backup PSReadLine history
            $historyPath = "$env:APPDATA\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt"
            if (Test-Path $historyPath) {
                Copy-Item -Path $historyPath -Destination "$backupPath\ConsoleHost_history.txt" -Force
            }

            # Backup custom formats and types
            $customPaths = @(
                "$env:USERPROFILE\Documents\WindowsPowerShell\Types",
                "$env:USERPROFILE\Documents\WindowsPowerShell\Formats"
            )

            foreach ($path in $customPaths) {
                if (Test-Path $path) {
                    $folderName = Split-Path $path -Leaf
                    $destPath = Join-Path $backupPath $folderName
                    Copy-Item -Path $path -Destination $destPath -Recurse -Force
                }
            }

            # Backup module configurations
            $moduleConfigPath = "$env:USERPROFILE\Documents\WindowsPowerShell\Modules"
            if (Test-Path $moduleConfigPath) {
                $moduleConfigBackupPath = Join-Path $backupPath "ModuleConfigs"
                New-Item -ItemType Directory -Path $moduleConfigBackupPath -Force | Out-Null
                Copy-Item -Path "$moduleConfigPath\*" -Destination $moduleConfigBackupPath -Recurse -Force
            }

            # Output summary
            Write-Host "`nPowerShell Backup Summary:" -ForegroundColor Green
            Write-Host "Profiles: $($profilePaths.Count) found" -ForegroundColor Yellow
            Write-Host "Installed Modules: $($installedModules.Count)" -ForegroundColor Yellow
            Write-Host "NuGet Sources: $($nugetSources.Count)" -ForegroundColor Yellow
            Write-Host "PS Repositories: $($psRepositories.Count)" -ForegroundColor Yellow
            
            Write-Host "PowerShell Settings backed up successfully to: $backupPath" -ForegroundColor Green
            return $true
        }
        return $false
    } catch {
        $errorRecord = $_
        $errorMessage = @(
            "Failed to backup [Feature]"
            "Error Message: $($errorRecord.Exception.Message)"
            "Error Type: $($errorRecord.Exception.GetType().FullName)"
            "Script Line Number: $($errorRecord.InvocationInfo.ScriptLineNumber)"
            "Script Name: $($errorRecord.InvocationInfo.ScriptName)"
            "Statement: $($errorRecord.InvocationInfo.Line.Trim())"
            if ($errorRecord.Exception.StackTrace) { "Stack Trace: $($errorRecord.Exception.StackTrace)" }
            if ($errorRecord.Exception.InnerException) { "Inner Exception: $($errorRecord.Exception.InnerException.Message)" }
        ) -join "`n"
        
        Write-Host $errorMessage -ForegroundColor Red
        return $false
    }
}

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Backup-PowerShellSettings -BackupRootPath $BackupRootPath
} 