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
                # Main settings
                "Settings" = "$env:APPDATA\Microsoft\OneNote"
                # OneNote 2016 settings
                "Settings2016" = "$env:APPDATA\Microsoft\OneNote\16.0"
                # OneNote UWP settings
                "SettingsUWP" = "$env:LOCALAPPDATA\Packages\Microsoft.Office.OneNote_8wekyb3d8bbwe\LocalState"
                # Templates and custom content
                "Templates" = "$env:APPDATA\Microsoft\Templates"
                # Quick access and recent items
                "QuickAccess" = "$env:APPDATA\Microsoft\Windows\Recent\OneNote.lnk"
                # Recent files
                "RecentFiles" = "$env:APPDATA\Microsoft\Office\Recent"
                # Custom dictionaries
                "Custom Dictionary" = "$env:APPDATA\Microsoft\UProof"
                # AutoCorrect entries
                "AutoCorrect" = "$env:APPDATA\Microsoft\Office"
                # Custom toolbars and ribbons
                "Ribbons" = "$env:APPDATA\Microsoft\Office\16.0\OneNote\Ribbons"
                # Add-ins
                "AddIns" = "$env:APPDATA\Microsoft\OneNote\AddIns"
            }

            # Restore registry settings first
            $registryPath = Join-Path $backupPath "Registry"
            if (Test-Path $registryPath) {
                # Import each registry file found
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
                        # Skip temporary files during restore
                        $excludeFilter = @("*.tmp", "~*.*")
                        Copy-Item $backupItem $config.Value -Recurse -Force -Exclude $excludeFilter
                    } else {
                        Copy-Item $backupItem $config.Value -Force
                    }
                    Write-Host "Restored configuration: $($config.Key)" -ForegroundColor Green
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