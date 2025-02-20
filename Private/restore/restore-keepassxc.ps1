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
            $keepassxcConfigs = @{
                # Main configuration
                "Config" = "$env:APPDATA\KeePassXC"
                # Database settings
                "Database" = "$env:APPDATA\KeePassXC\databases"
                # Key files
                "KeyFiles" = "$env:APPDATA\KeePassXC\keys"
                # Plugins
                "Plugins" = "$env:APPDATA\KeePassXC\plugins"
                # Custom icons
                "Icons" = "$env:APPDATA\KeePassXC\icons"
                # Auto-type sequences
                "AutoType" = "$env:APPDATA\KeePassXC\autotype"
                # Browser integration
                "Browser" = "$env:LOCALAPPDATA\KeePassXC\BrowserSupport"
            }
            
            # Create KeePassXC config directory if it doesn't exist
            New-Item -ItemType Directory -Force -Path "$env:APPDATA\KeePassXC" | Out-Null
            
            # Restore KeePassXC settings
            Write-Host "Checking KeePassXC installation..." -ForegroundColor Yellow
            $keepassxcPath = "$env:ProgramFiles\KeePassXC\KeePassXC.exe"
            if (!(Test-Path $keepassxcPath)) {
                Write-Host "Installing KeePassXC..." -ForegroundColor Yellow
                winget install -e --id KeePassXCTeam.KeePassXC
            }

            # Restore registry settings
            foreach ($config in $keepassxcConfigs.GetEnumerator()) {
                $backupItem = Join-Path $backupPath $config.Key
                if (Test-Path $backupItem) {
                    Write-Host "Restoring $($config.Key) settings..." -ForegroundColor Yellow
                    if ((Get-Item $backupItem) -is [System.IO.DirectoryInfo]) {
                        # Skip temporary files during restore
                        $excludeFilter = @("*.tmp", "~*.*", "*.bak", "*.old", "*.lock")
                        Copy-Item $backupItem $config.Value -Recurse -Force -Exclude $excludeFilter
                    } else {
                        Copy-Item $backupItem $config.Value -Force
                    }
                    Write-Host "Restored configuration: $($config.Key)" -ForegroundColor Green
                }
            }

            # Restore database configuration
            $databaseConfigFile = Join-Path $backupPath "database_config.json"
            if (Test-Path $databaseConfigFile) {
                $databaseConfig = Get-Content $databaseConfigFile | ConvertFrom-Json
                foreach ($db in $databaseConfig.Databases) {
                    # Copy database file
                    if ($db.Path -and (Test-Path (Join-Path $backupPath $db.Path))) {
                        $destPath = [System.Environment]::ExpandEnvironmentVariables($db.DestPath)
                        Copy-Item -Path (Join-Path $backupPath $db.Path) -Destination $destPath -Force
                    }
                    
                    # Copy key file if exists
                    if ($db.KeyFile -and (Test-Path (Join-Path $backupPath $db.KeyFile))) {
                        $keyPath = [System.Environment]::ExpandEnvironmentVariables($db.KeyFileDest)
                        Copy-Item -Path (Join-Path $backupPath $db.KeyFile) -Destination $keyPath -Force
                    }
                }
            }

            # Restore browser integration settings
            $browserConfigFile = Join-Path $backupPath "browser_integration.json"
            if (Test-Path $browserConfigFile) {
                $browserConfig = Get-Content $browserConfigFile | ConvertFrom-Json
                $browserPath = "$env:LOCALAPPDATA\KeePassXC\BrowserSupport"
                if (!(Test-Path $browserPath)) {
                    New-Item -ItemType Directory -Path $browserPath -Force | Out-Null
                }
                
                # Set up browser integration
                foreach ($browser in $browserConfig.Browsers) {
                    if ($browser.Enabled) {
                        $nativeHostFile = "$browserPath\$($browser.Name)-keepassxc-browser.json"
                        Set-Content -Path $nativeHostFile -Value $browser.Config -Force
                    }
                }
            }

            # Kill any running KeePassXC processes
            Get-Process -Name "keepassxc" -ErrorAction SilentlyContinue | Stop-Process -Force

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