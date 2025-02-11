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
            # Define browser profiles
            $browserProfiles = @{
                "Chrome" = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default"
                "Edge" = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default"
                "Firefox" = "$env:APPDATA\Mozilla\Firefox\Profiles"
                "Brave" = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default"
                "Vivaldi" = "$env:LOCALAPPDATA\Vivaldi\User Data\Default"
            }

            # Import registry settings first
            Get-ChildItem -Path $backupPath -Filter "*.reg" | ForEach-Object {
                Write-Host "Importing registry file: $($_.Name)" -ForegroundColor Yellow
                reg import $_.FullName | Out-Null
            }

            foreach ($browser in $browserProfiles.GetEnumerator()) {
                $browserBackupPath = Join-Path $backupPath $browser.Key
                if (Test-Path $browserBackupPath) {
                    Write-Host "Restoring $($browser.Key) settings..." -ForegroundColor Yellow

                    # Create browser profile directory if it doesn't exist
                    if (!(Test-Path $browser.Value)) {
                        New-Item -ItemType Directory -Force -Path $browser.Value | Out-Null
                    }
                    
                    switch ($browser.Key) {
                        { $_ -in "Chrome", "Edge", "Brave", "Vivaldi" } {
                            # Restore Chromium-based browser settings
                            Copy-Item "$browserBackupPath\Bookmarks" $browser.Value -ErrorAction SilentlyContinue
                            Copy-Item "$browserBackupPath\Preferences" $browser.Value -ErrorAction SilentlyContinue
                            Copy-Item "$browserBackupPath\Favicons" $browser.Value -ErrorAction SilentlyContinue
                            
                            # Restore extensions
                            if (Test-Path "$browserBackupPath\Extensions") {
                                Copy-Item "$browserBackupPath\Extensions\*" "$($browser.Value)\Extensions" -Recurse -Force -ErrorAction SilentlyContinue
                            }
                        }
                        "Firefox" {
                            # Restore Firefox settings
                            Get-ChildItem "$($browser.Value)\*.default*" -ErrorAction SilentlyContinue | ForEach-Object {
                                $profilePath = $_.FullName
                                if (Test-Path "$browserBackupPath\bookmarkbackups") {
                                    Copy-Item "$browserBackupPath\bookmarkbackups" $profilePath -Recurse -Force -ErrorAction SilentlyContinue
                                }
                                if (Test-Path "$browserBackupPath\prefs.js") {
                                    Copy-Item "$browserBackupPath\prefs.js" $profilePath -Force -ErrorAction SilentlyContinue
                                }
                                if (Test-Path "$browserBackupPath\extensions.json") {
                                    Copy-Item "$browserBackupPath\extensions.json" $profilePath -Force -ErrorAction SilentlyContinue
                                }
                                if (Test-Path "$browserBackupPath\extensions") {
                                    Copy-Item "$browserBackupPath\extensions\*" "$profilePath\extensions" -Recurse -Force -ErrorAction SilentlyContinue
                                }
                            }
                        }
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