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

function Restore-OutlookSettings {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath
    )
    
    try {
        Write-Host "Restoring Outlook Settings..." -ForegroundColor Blue
        $backupPath = Test-BackupPath -Path "Outlook" -BackupType "Outlook Settings"
        
        if ($backupPath) {
            # Outlook config locations
            $outlookConfigs = @{
                "Settings" = "$env:APPDATA\Microsoft\Outlook"
                "Settings2016" = "$env:APPDATA\Microsoft\Outlook\16.0"
                "Templates" = "$env:APPDATA\Microsoft\Templates"
                "QuickAccess" = "$env:APPDATA\Microsoft\Windows\Recent\Outlook.lnk"
                "RecentFiles" = "$env:APPDATA\Microsoft\Office\Recent"
                "Custom Dictionary" = "$env:APPDATA\Microsoft\UProof"
                "AutoCorrect" = "$env:APPDATA\Microsoft\Office"
                "Ribbons" = "$env:APPDATA\Microsoft\Office\16.0\Outlook\Ribbons"
                "AddIns" = "$env:APPDATA\Microsoft\Outlook\AddIns"
                "Signatures" = "$env:APPDATA\Microsoft\Signatures"
                "Rules" = "$env:APPDATA\Microsoft\Outlook\Rules"
                "Forms" = "$env:APPDATA\Microsoft\Forms"
                "Quick Parts" = "$env:APPDATA\Microsoft\Outlook\QuickParts"
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
            foreach ($config in $outlookConfigs.GetEnumerator()) {
                $backupItem = Join-Path $backupPath $config.Key
                if (Test-Path $backupItem) {
                    # Create parent directory if it doesn't exist
                    $parentDir = Split-Path $config.Value -Parent
                    if (!(Test-Path $parentDir)) {
                        New-Item -ItemType Directory -Force -Path $parentDir | Out-Null
                    }

                    if ((Get-Item $backupItem) -is [System.IO.DirectoryInfo]) {
                        $excludeFilter = @("*.tmp", "~*.*", "*.ost", "*.pst")
                        Copy-Item $backupItem $config.Value -Recurse -Force -Exclude $excludeFilter
                    } else {
                        Copy-Item $backupItem $config.Value -Force
                    }
                    Write-Host "Restored configuration: $($config.Key)" -ForegroundColor Green
                }
            }

            Write-Host "`nOutlook Settings Restore Summary:" -ForegroundColor Green
            Write-Host "Registry Settings: Restored" -ForegroundColor Yellow
            foreach ($configName in $outlookConfigs.Keys) {
                $configPath = Join-Path $backupPath $configName
                Write-Host ("$configName" + ": $(if (Test-Path $configPath) { 'Restored' } else { 'Not found in backup' })") -ForegroundColor Yellow
            }

            Write-Host "Outlook Settings restored successfully from: $backupPath" -ForegroundColor Green
            Write-Host "`nNote: Outlook restart may be required for settings to take effect" -ForegroundColor Yellow
            return $true
        }
        return $false
    } catch {
        Write-Host "Failed to restore Outlook Settings: $_" -ForegroundColor Red
        return $false
    }
}

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Restore-OutlookSettings -BackupRootPath $BackupRootPath
} 