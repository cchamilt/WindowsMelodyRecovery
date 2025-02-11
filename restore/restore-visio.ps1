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

function Restore-VisioSettings {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath
    )
    
    try {
        Write-Host "Restoring Visio Settings..." -ForegroundColor Blue
        $backupPath = Test-BackupPath -Path "Visio" -BackupType "Visio Settings"
        
        if ($backupPath) {
            # Visio config locations
            $visioConfigs = @{
                "Settings" = "$env:APPDATA\Microsoft\Visio"
                "Templates" = "$env:APPDATA\Microsoft\Templates"
                "RecentFiles" = "$env:APPDATA\Microsoft\Office\Recent"
                "Stencils" = "$env:MYDOCUMENTS\My Shapes"
                "AddIns" = "$env:APPDATA\Microsoft\Visio\AddOns"
                "Ribbons" = "$env:APPDATA\Microsoft\Office\16.0\Visio\Ribbons"
                "Themes" = "$env:APPDATA\Microsoft\Visio\Themes"
                "Workspace" = "$env:APPDATA\Microsoft\Visio\Workspace"
                "Macros" = "$env:APPDATA\Microsoft\Visio\Macros"
            }

            # Restore registry settings first
            $registryPath = Join-Path $backupPath "Registry"
            if (Test-Path $registryPath) {
                Get-ChildItem -Path $registryPath -Filter "*.reg" | ForEach-Object {
                    Write-Host "Importing registry file: $($_.Name)" -ForegroundColor Yellow
                    reg import $_.FullName | Out-Null
                }
            }

            # Restore config files
            foreach ($config in $visioConfigs.GetEnumerator()) {
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

            Write-Host "`nVisio Settings Restore Summary:" -ForegroundColor Green
            Write-Host "Registry Settings: Restored" -ForegroundColor Yellow
            foreach ($configName in $visioConfigs.Keys) {
                $configPath = Join-Path $backupPath $configName
                Write-Host ("$configName" + ": $(if (Test-Path $configPath) { 'Restored' } else { 'Not found in backup' })") -ForegroundColor Yellow
            }

            Write-Host "Visio Settings restored successfully from: $backupPath" -ForegroundColor Green
            Write-Host "`nNote: Visio restart may be required for settings to take effect" -ForegroundColor Yellow
            return $true
        }
        return $false
    } catch {
        Write-Host "Failed to restore Visio Settings: $_" -ForegroundColor Red
        return $false
    }
}

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Restore-VisioSettings -BackupRootPath $BackupRootPath
} 