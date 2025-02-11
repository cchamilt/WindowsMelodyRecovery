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

function Restore-KeePassXCSettings {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath
    )
    
    try {
        Write-Host "Restoring KeePassXC Settings..." -ForegroundColor Blue
        $backupPath = Test-BackupPath -Path "KeePassXC" -BackupType "KeePassXC Settings"
        
        if ($backupPath) {
            # KeePassXC config locations
            $keepassConfigs = @{
                "Config" = "$env:APPDATA\KeePassXC\keepassxc.ini"
                "LastDatabase" = "$env:APPDATA\KeePassXC\lastdatabase"
                "CustomIcons" = "$env:APPDATA\KeePassXC\CustomIcons"
            }
            
            # Create KeePassXC config directory if it doesn't exist
            New-Item -ItemType Directory -Force -Path "$env:APPDATA\KeePassXC" | Out-Null
            
            foreach ($config in $keepassConfigs.GetEnumerator()) {
                $backupItem = Join-Path $backupPath (Split-Path $config.Value -Leaf)
                if (Test-Path $backupItem) {
                    if ((Get-Item $backupItem) -is [System.IO.DirectoryInfo]) {
                        Copy-Item $backupItem $config.Value -Recurse -Force
                    } else {
                        Copy-Item $backupItem $config.Value -Force
                    }
                }
            }
            
            # Restore database location if saved
            $dbLocationFile = Join-Path $backupPath "database_location.txt"
            if (Test-Path $dbLocationFile) {
                $dbLocation = Get-Content $dbLocationFile
                [Environment]::SetEnvironmentVariable('KEEPASSXC_DB', $dbLocation, 'User')
                
                # Create a shortcut on the desktop
                $WshShell = New-Object -comObject WScript.Shell
                $shortcut = $WshShell.CreateShortcut("$env:USERPROFILE\Desktop\KeePassXC.lnk")
                $shortcut.TargetPath = "C:\Program Files\KeePassXC\KeePassXC.exe"
                $shortcut.Arguments = "`"$dbLocation`""
                $shortcut.Save()
            }

            Write-Host "`nKeePassXC Settings Restore Summary:" -ForegroundColor Green
            Write-Host "Config File: Restored" -ForegroundColor Yellow
            Write-Host "Last Database: Restored" -ForegroundColor Yellow
            Write-Host "Custom Icons: Restored" -ForegroundColor Yellow
            Write-Host "Database Location: Restored" -ForegroundColor Yellow
            Write-Host "Desktop Shortcut: Created" -ForegroundColor Yellow
            
            Write-Host "KeePassXC Settings restored successfully from: $backupPath" -ForegroundColor Green
            return $true
        }
        return $false
    } catch {
        Write-Host "Failed to restore KeePassXC Settings: $_" -ForegroundColor Red
        return $false
    }
}

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Restore-KeePassXCSettings -BackupRootPath $BackupRootPath
} 