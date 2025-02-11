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

function Backup-KeePassXCSettings {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath
    )
    
    try {
        Write-Host "Backing up KeePassXC Settings..." -ForegroundColor Blue
        $backupPath = Initialize-BackupDirectory -Path "KeePassXC" -BackupType "KeePassXC Settings" -BackupRootPath $BackupRootPath
        
        if ($backupPath) {
            # KeePassXC config locations
            $keepassConfigs = @{
                "Config" = "$env:APPDATA\KeePassXC\keepassxc.ini"
                "LastDatabase" = "$env:APPDATA\KeePassXC\lastdatabase"
                "CustomIcons" = "$env:APPDATA\KeePassXC\CustomIcons"
            }
            
            foreach ($config in $keepassConfigs.GetEnumerator()) {
                if (Test-Path $config.Value) {
                    if ((Get-Item $config.Value) -is [System.IO.DirectoryInfo]) {
                        Copy-Item $config.Value $backupPath -Recurse -Force
                    } else {
                        Copy-Item $config.Value $backupPath -Force
                    }
                }
            }
            
            # Save database location if provided
            $dbLocation = [Environment]::GetEnvironmentVariable('KEEPASSXC_DB', 'User')
            if ($dbLocation) {
                $dbLocation | Out-File (Join-Path $backupPath "database_location.txt")
            }

            Write-Host "`nKeePassXC Settings Backup Summary:" -ForegroundColor Green
            Write-Host "Config File: $(Test-Path "$backupPath\keepassxc.ini")" -ForegroundColor Yellow
            Write-Host "Last Database: $(Test-Path "$backupPath\lastdatabase")" -ForegroundColor Yellow
            Write-Host "Custom Icons: $(Test-Path "$backupPath\CustomIcons")" -ForegroundColor Yellow
            Write-Host "Database Location: $(Test-Path "$backupPath\database_location.txt")" -ForegroundColor Yellow
            
            Write-Host "KeePassXC Settings backed up successfully to: $backupPath" -ForegroundColor Green
            return $true
        }
        return $false
    } catch {
        Write-Host "Failed to backup KeePassXC Settings: $_" -ForegroundColor Red
        return $false
    }
}

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Backup-KeePassXCSettings -BackupRootPath $BackupRootPath
} 