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

function Restore-ExcelSettings {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath
    )
    
    try {
        Write-Host "Restoring Excel Settings..." -ForegroundColor Blue
        $backupPath = Test-BackupPath -Path "Excel" -BackupType "Excel Settings"
        
        if ($backupPath) {
            # Excel config locations
            $excelConfigs = @{
                "Settings" = "$env:APPDATA\Microsoft\Excel"
                "Templates" = "$env:APPDATA\Microsoft\Templates"
                "RecentFiles" = "$env:APPDATA\Microsoft\Office\Recent"
                "Dictionaries" = "$env:APPDATA\Microsoft\UProof"
                "AutoCorrect" = "$env:APPDATA\Microsoft\Office"
                "AddIns" = "$env:APPDATA\Microsoft\AddIns"
                "Ribbons" = "$env:APPDATA\Microsoft\Office\16.0\Excel\Ribbons"
                "Views" = "$env:APPDATA\Microsoft\Excel\Views"
                "Personal" = "$env:APPDATA\Microsoft\Excel\XLSTART"
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
            foreach ($config in $excelConfigs.GetEnumerator()) {
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

            Write-Host "`nExcel Settings Restore Summary:" -ForegroundColor Green
            Write-Host "Registry Settings: Restored" -ForegroundColor Yellow
            foreach ($configName in $excelConfigs.Keys) {
                $configPath = Join-Path $backupPath $configName
                Write-Host ("$configName" + ": $(if (Test-Path $configPath) { 'Restored' } else { 'Not found in backup' })") -ForegroundColor Yellow
            }

            Write-Host "Excel Settings restored successfully from: $backupPath" -ForegroundColor Green
            Write-Host "`nNote: Excel restart may be required for settings to take effect" -ForegroundColor Yellow
            return $true
        }
        return $false
    } catch {
        Write-Host "Failed to restore Excel Settings: $_" -ForegroundColor Red
        return $false
    }
}

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Restore-ExcelSettings -BackupRootPath $BackupRootPath
} 