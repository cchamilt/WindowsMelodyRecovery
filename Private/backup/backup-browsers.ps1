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
            $regPaths = @{
                Chrome = @(
                    "HKCU\Software\Google\Chrome",
                    "HKLM\SOFTWARE\Google\Chrome",
                    "HKLM\SOFTWARE\Policies\Google\Chrome"
                )
                Edge = @(
                    "HKCU\Software\Microsoft\Edge",
                    "HKLM\SOFTWARE\Microsoft\Edge",
                    "HKLM\SOFTWARE\Policies\Microsoft\Edge"
                )
                Vivaldi = @(
                    "HKCU\Software\Vivaldi",
                    "HKLM\SOFTWARE\Vivaldi"
                )
                Firefox = @(
                    "HKCU\Software\Mozilla",
                    "HKLM\SOFTWARE\Mozilla",
                    "HKLM\SOFTWARE\Policies\Mozilla"
                )
                Brave = @(
                    "HKCU\Software\BraveSoftware",
                    "HKLM\SOFTWARE\BraveSoftware",
                    "HKLM\SOFTWARE\Policies\BraveSoftware"
                )
            }

            # Add Firefox and Brave to browser data paths
            $browserData = @{
                Chrome = "$env:LOCALAPPDATA\Google\Chrome\User Data"
                Edge = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"
                Vivaldi = "$env:LOCALAPPDATA\Vivaldi\User Data"
                Firefox = "$env:APPDATA\Mozilla\Firefox\Profiles"
                Brave = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data"
            }

            foreach ($browser in $regPaths.Keys) {
                Write-Host "Backing up $browser settings..." -ForegroundColor Blue
                $browserPath = Join-Path $backupPath $browser
                New-Item -ItemType Directory -Path $browserPath -Force | Out-Null

                foreach ($regPath in $regPaths[$browser]) {
                    # Check if registry key exists before trying to export
                    $keyExists = $false
                    if ($regPath -match '^HKCU\\') {
                        $keyExists = Test-Path "Registry::HKEY_CURRENT_USER\$($regPath.Substring(5))"
                    } elseif ($regPath -match '^HKLM\\') {
                        $keyExists = Test-Path "Registry::HKEY_LOCAL_MACHINE\$($regPath.Substring(5))"
                    }
                    
                    if ($keyExists) {
                        try {
                            $regFile = "$browserPath\$($regPath.Split('\')[-1]).reg"
                            $result = reg export $regPath $regFile /y 2>&1
                            if ($LASTEXITCODE -ne 0) {
                                Write-Host "Warning: Could not export registry key: $regPath" -ForegroundColor Yellow
                            }
                        } catch {
                            Write-Host "Warning: Failed to export registry key: $regPath" -ForegroundColor Yellow
                        }
                    } else {
                        Write-Host "Registry key not found: $regPath" -ForegroundColor Yellow
                    }
                }

                # Backup browser profiles and data
                if (Test-Path $browserData[$browser]) {
                    # Export bookmarks, extensions, and preferences
                    $dataPath = Join-Path $browserPath "UserData"
                    New-Item -ItemType Directory -Path $dataPath -Force | Out-Null

                    # Copy specific files instead of entire profile
                    $filesToCopy = @(
                        "Bookmarks",
                        "Preferences",
                        "Extensions",
                        "Favicons",
                        "History",
                        "Login Data",
                        "Shortcuts",
                        "Top Sites"
                    )

                    foreach ($file in $filesToCopy) {
                        $sourcePath = Join-Path $browserData[$browser] "Default\$file"
                        if (Test-Path $sourcePath) {
                            Copy-Item -Path $sourcePath -Destination "$dataPath\$file" -Force
                        }
                    }
                }
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
        $errorRecord = $_
        $errorMessage = @(
            "Failed to backup [Feature]"
            "Error Message: $($errorRecord.Exception.Message)"
            "Error Type: $($errorRecord.Exception.GetType().FullName)"
            "Script Line Number: $($errorRecord.InvocationInfo.ScriptLineNumber)"
            "Script Name: $($errorRecord.InvocationInfo.ScriptName)"
            "Statement: $($errorRecord.InvocationInfo.Line.Trim())"
            if ($errorRecord.Exception.StackTrace) { "Stack Trace: $($errorRecord.Exception.StackTrace)" }
            if ($errorRecord.Exception.InnerException) { "Inner Exception: $($errorRecord.Exception.InnerException.Message)" }
        ) -join "`n"
        
        Write-Host $errorMessage -ForegroundColor Red
        return $false
    }
}

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Backup-BrowserSettings -BackupRootPath $BackupRootPath
} 