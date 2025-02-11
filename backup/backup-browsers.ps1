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

function Backup-BrowserSettings {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath
    )
    
    try {
        Write-Host "Backing up Browser Settings..." -ForegroundColor Blue
        $backupPath = Initialize-BackupDirectory -Path "Browsers" -BackupType "Browser Settings" -BackupRootPath $BackupRootPath
        
        if ($backupPath) {
            # Define browser profiles
            $browserProfiles = @{
                "Chrome" = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default"
                "Edge" = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default"
                "Firefox" = "$env:APPDATA\Mozilla\Firefox\Profiles"
                "Brave" = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default"
                "Vivaldi" = "$env:LOCALAPPDATA\Vivaldi\User Data\Default"
            }

            foreach ($browser in $browserProfiles.GetEnumerator()) {
                if (Test-Path $browser.Value) {
                    Write-Host "Backing up $($browser.Key) settings..." -ForegroundColor Yellow
                    
                    # Create browser-specific backup directory
                    $browserBackupPath = Join-Path $backupPath $browser.Key
                    New-Item -ItemType Directory -Force -Path $browserBackupPath | Out-Null
                    
                    switch ($browser.Key) {
                        { $_ -in "Chrome", "Edge", "Brave", "Vivaldi" } {
                            # Backup Chromium-based browser settings
                            Copy-Item "$($browser.Value)\Bookmarks" $browserBackupPath -ErrorAction SilentlyContinue
                            Copy-Item "$($browser.Value)\Preferences" $browserBackupPath -ErrorAction SilentlyContinue
                            Copy-Item "$($browser.Value)\Favicons" $browserBackupPath -ErrorAction SilentlyContinue
                            Copy-Item "$($browser.Value)\Extensions" $browserBackupPath -Recurse -ErrorAction SilentlyContinue
                            
                            # Export extensions list
                            $extensions = Get-ChildItem "$($browser.Value)\Extensions" -ErrorAction SilentlyContinue |
                                Select-Object Name, LastWriteTime
                            $extensions | ConvertTo-Json | Out-File "$browserBackupPath\extensions.json" -Force
                        }
                        "Firefox" {
                            # Backup Firefox settings
                            Get-ChildItem "$($browser.Value)\*.default*" -ErrorAction SilentlyContinue | ForEach-Object {
                                Copy-Item "$($_.FullName)\bookmarkbackups" $browserBackupPath -Recurse -ErrorAction SilentlyContinue
                                Copy-Item "$($_.FullName)\prefs.js" $browserBackupPath -ErrorAction SilentlyContinue
                                Copy-Item "$($_.FullName)\extensions.json" $browserBackupPath -ErrorAction SilentlyContinue
                                Copy-Item "$($_.FullName)\extensions" $browserBackupPath -Recurse -ErrorAction SilentlyContinue
                            }
                        }
                    }
                }
            }

            # Export browser registry settings
            $regPaths = @(
                # Chrome settings
                "HKCU\Software\Google\Chrome",
                # Edge settings
                "HKCU\Software\Microsoft\Edge",
                # Firefox settings
                "HKCU\Software\Mozilla",
                # Brave settings
                "HKCU\Software\BraveSoftware",
                # Vivaldi settings
                "HKCU\Software\Vivaldi"
            )

            foreach ($regPath in $regPaths) {
                $regFile = "$backupPath\$($regPath.Split('\')[-1]).reg"
                reg export $regPath $regFile /y 2>$null
            }

            Write-Host "`nBrowser Settings Backup Summary:" -ForegroundColor Green
            foreach ($browser in $browserProfiles.GetEnumerator()) {
                $status = Test-Path (Join-Path $backupPath $browser.Key)
                Write-Host "$($browser.Key): $(if ($status) { 'Backed up' } else { 'Not found' })" -ForegroundColor Yellow
            }
            
            Write-Host "Browser Settings backed up successfully to: $backupPath" -ForegroundColor Green
            return $true
        }
        return $false
    } catch {
        Write-Host "Failed to backup Browser Settings: $_" -ForegroundColor Red
        return $false
    }
}

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Backup-BrowserSettings -BackupRootPath $BackupRootPath
} 