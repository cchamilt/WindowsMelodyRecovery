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

function Backup-OutlookSettings {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath
    )
    
    try {
        Write-Host "Backing up Outlook Settings..." -ForegroundColor Blue
        $backupPath = Initialize-BackupDirectory -Path "Outlook" -BackupType "Outlook Settings" -BackupRootPath $BackupRootPath
        
        if ($backupPath) {
            # Outlook config locations
            $outlookConfigs = @{
                # Main settings and profiles
                "Settings" = "$env:APPDATA\Microsoft\Outlook"
                # Signatures
                "Signatures" = "$env:APPDATA\Microsoft\Signatures"
                # Quick Access and recent items
                "RecentFiles" = "$env:APPDATA\Microsoft\Office\Recent"
                # Templates
                "Templates" = "$env:APPDATA\Microsoft\Templates"
                # Custom dictionaries
                "Dictionaries" = "$env:APPDATA\Microsoft\UProof"
                # AutoCorrect entries
                "AutoCorrect" = "$env:APPDATA\Microsoft\Office"
                # Rules and alerts
                "Rules" = "$env:APPDATA\Microsoft\Outlook\RoamCache"
            }

            # Registry paths to backup
            $regPaths = @(
                # Outlook main settings
                "HKCU\Software\Microsoft\Office\16.0\Outlook",
                # Account settings
                "HKCU\Software\Microsoft\Office\16.0\Outlook\Profiles",
                # AutoComplete settings
                "HKCU\Software\Microsoft\Office\16.0\Outlook\AutoNameCheck",
                # View settings
                "HKCU\Software\Microsoft\Office\16.0\Outlook\Preferences",
                # Search settings
                "HKCU\Software\Microsoft\Office\16.0\Outlook\Search",
                # Security settings
                "HKCU\Software\Microsoft\Office\16.0\Outlook\Security"
            )

            # Create registry backup directory
            $registryPath = Join-Path $backupPath "Registry"
            New-Item -ItemType Directory -Force -Path $registryPath | Out-Null

            # Backup registry settings
            foreach ($regPath in $regPaths) {
                $regFile = Join-Path $registryPath "$($regPath.Split('\')[-1]).reg"
                reg export $regPath $regFile /y 2>$null
            }
            
            # Backup config files
            foreach ($config in $outlookConfigs.GetEnumerator()) {
                if (Test-Path $config.Value) {
                    $targetPath = Join-Path $backupPath $config.Key
                    if ((Get-Item $config.Value) -is [System.IO.DirectoryInfo]) {
                        # Skip NK2 files (autocomplete cache) and PST files
                        $excludeFilter = @("*.nk2", "*.pst", "*.ost")
                        Copy-Item $config.Value $targetPath -Recurse -Force -Exclude $excludeFilter
                    } else {
                        Copy-Item $config.Value $targetPath -Force
                    }
                }
            }

            Write-Host "`nOutlook Settings Backup Summary:" -ForegroundColor Green
            Write-Host "Registry Settings: $(Test-Path $registryPath)" -ForegroundColor Yellow
            foreach ($configName in $outlookConfigs.Keys) {
                $configPath = Join-Path $backupPath $configName
                Write-Host ("$configName" + ": $(Test-Path $configPath)") -ForegroundColor Yellow
            }
            
            Write-Host "Outlook Settings backed up successfully to: $backupPath" -ForegroundColor Green
            return $true
        }
        return $false
    } catch {
        Write-Host "Failed to backup Outlook Settings: $_" -ForegroundColor Red
        return $false
    }
}

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Backup-OutlookSettings -BackupRootPath $BackupRootPath
} 