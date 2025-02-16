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

function Restore-BrowserSettings {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath
    )
    
    try {
        Write-Host "Restoring Browser Settings..." -ForegroundColor Blue
        $backupPath = Test-BackupPath -Path "Browsers" -BackupType "Browser Settings"
        
        if ($backupPath) {
            # Browser config locations
            $browserProfiles = @{
                # Chrome settings and profiles
                "Chrome" = @{
                    "Settings" = "$env:LOCALAPPDATA\Google\Chrome\User Data"
                    "Extensions" = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Extensions"
                    "Bookmarks" = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Bookmarks"
                    "Preferences" = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Preferences"
                    "Shortcuts" = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Chrome Apps"
                }
                # Firefox settings and profiles
                "Firefox" = @{
                    "Profiles" = "$env:APPDATA\Mozilla\Firefox\Profiles"
                    "Extensions" = "$env:APPDATA\Mozilla\Firefox\Extensions"
                    "Chrome" = "$env:APPDATA\Mozilla\Firefox\Chrome"  # userChrome.css etc
                    "Preferences" = "$env:APPDATA\Mozilla\Firefox\profiles.ini"
                }
                # Edge settings and profiles
                "Edge" = @{
                    "Settings" = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"
                    "Extensions" = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Extensions"
                    "Bookmarks" = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Bookmarks"
                    "Preferences" = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Preferences"
                    "Collections" = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Collections"
                }
            }

            # Import registry settings first
            Get-ChildItem -Path $backupPath -Filter "*.reg" | ForEach-Object {
                Write-Host "Importing registry file: $($_.Name)" -ForegroundColor Yellow
                reg import $_.FullName | Out-Null
            }

            # Restore browser settings
            foreach ($browser in $browserProfiles.GetEnumerator()) {
                Write-Host "`nRestoring $($browser.Key) settings..." -ForegroundColor Yellow
                
                # Close browser processes before restore
                $browserProcesses = @{
                    "Chrome" = "chrome"
                    "Firefox" = "firefox"
                    "Edge" = "msedge"
                }
                
                if ($browserProcesses[$browser.Key]) {
                    Stop-Process -Name $browserProcesses[$browser.Key] -Force -ErrorAction SilentlyContinue
                }

                foreach ($setting in $browser.Value.GetEnumerator()) {
                    $backupItem = Join-Path $backupPath "$($browser.Key)\$($setting.Key)"
                    if (Test-Path $backupItem) {
                        # Create parent directory if it doesn't exist
                        $parentDir = Split-Path $setting.Value -Parent
                        if (!(Test-Path $parentDir)) {
                            New-Item -ItemType Directory -Force -Path $parentDir | Out-Null
                        }

                        if ((Get-Item $backupItem) -is [System.IO.DirectoryInfo]) {
                            # Skip temporary files and cache during restore
                            $excludeFilter = @(
                                "*.tmp", "~*.*", "Cache*", "*cache*",
                                "*.ldb", "*.log", "*.old", "Crash Reports",
                                "GPUCache", "Code Cache", "Service Worker"
                            )
                            Copy-Item $backupItem $setting.Value -Recurse -Force -Exclude $excludeFilter
                        } else {
                            Copy-Item $backupItem $setting.Value -Force
                        }
                        Write-Host "Restored $($setting.Key) for $($browser.Key)" -ForegroundColor Green
                    }
                }
            }

            Write-Host "`nBrowser Settings Restore Summary:" -ForegroundColor Green
            foreach ($browser in $browserProfiles.GetEnumerator()) {
                $status = Test-Path (Join-Path $backupPath $browser.Key)
                Write-Host "$($browser.Key): $(if ($status) { 'Restored' } else { 'Not found in backup' })" -ForegroundColor Yellow
            }
            
            Write-Host "`nNote: Browser restart may be required for settings to take effect" -ForegroundColor Yellow
            Write-Host "Browser Settings restored successfully from: $backupPath" -ForegroundColor Green
            return $true
        }
        return $false
    } catch {
        Write-Host "Failed to restore Browser Settings: $_" -ForegroundColor Red
        return $false
    }
}

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Restore-BrowserSettings -BackupRootPath $BackupRootPath
} 