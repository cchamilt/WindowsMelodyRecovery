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

function Restore-OneNoteSettings {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath
    )
    
    try {
        Write-Host "Restoring OneNote Settings..." -ForegroundColor Blue
        $backupPath = Test-BackupPath -Path "OneNote" -BackupType "OneNote Settings"
        
        if ($backupPath) {
            # OneNote config locations
            $oneNoteConfigs = @{
                "Settings2016" = "$env:APPDATA\Microsoft\OneNote\16.0"
                "SettingsUWP" = "$env:LOCALAPPDATA\Packages\Microsoft.Office.OneNote_8wekyb3d8bbwe\LocalState"
                "QuickAccess" = "$env:APPDATA\Microsoft\Windows\Recent\OneNote.lnk"
                "RecentFiles" = "$env:APPDATA\Microsoft\Office\Recent"
                "Templates" = "$env:APPDATA\Microsoft\Templates"
            }

            # Restore registry settings
            $registryPath = Join-Path $backupPath "Registry"
            if (Test-Path $registryPath) {
                Get-ChildItem -Path $registryPath -Filter "*.reg" | ForEach-Object {
                    Write-Host "Importing registry file: $($_.Name)" -ForegroundColor Yellow
                    reg import $_.FullName | Out-Null
                }
            }

            # Restore config files
            foreach ($config in $oneNoteConfigs.GetEnumerator()) {
                $backupItem = Join-Path $backupPath $config.Key
                if (Test-Path $backupItem) {
                    # Create parent directory if it doesn't exist
                    $parentDir = Split-Path $config.Value -Parent
                    if (!(Test-Path $parentDir)) {
                        New-Item -ItemType Directory -Force -Path $parentDir | Out-Null
                    }

                    if ((Get-Item $backupItem) -is [System.IO.DirectoryInfo]) {
                        Copy-Item $backupItem $config.Value -Recurse -Force
                    } else {
                        Copy-Item $backupItem $config.Value -Force
                    }
                }
            }

            Write-Host "`nOneNote Settings Restore Summary:" -ForegroundColor Green
            Write-Host "Registry Settings: Restored" -ForegroundColor Yellow
            foreach ($configName in $oneNoteConfigs.Keys) {
                $configPath = Join-Path $backupPath $configName
                Write-Host ("$configName" + ": $(if (Test-Path $configPath) { 'Restored' } else { 'Not found in backup' })") -ForegroundColor Yellow
            }

            Write-Host "OneNote Settings restored successfully from: $backupPath" -ForegroundColor Green
            Write-Host "`nNote: OneNote restart may be required for settings to take effect" -ForegroundColor Yellow
            return $true
        }
        return $false
    } catch {
        Write-Host "Failed to restore OneNote Settings: $_" -ForegroundColor Red
        return $false
    }
}

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Restore-OneNoteSettings -BackupRootPath $BackupRootPath
} 