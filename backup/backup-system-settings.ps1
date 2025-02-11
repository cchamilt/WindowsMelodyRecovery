param(
    [Parameter(Mandatory=$true)]
    [string]$BackupRootPath
)

try {
    Write-Host "Backing up additional system settings..." -ForegroundColor Blue
    $backupPath = Initialize-BackupDirectory -Path "SystemSettings" -BackupType "System Settings" -BackupRootPath $BackupRootPath
    
    if ($backupPath) {
        # Backup browser profiles
        $browserProfiles = @{
            "Chrome" = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default"
            "Edge" = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default"
            "Firefox" = "$env:APPDATA\Mozilla\Firefox\Profiles"
            "Brave" = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default"
            "Vivaldi" = "$env:LOCALAPPDATA\Vivaldi\User Data\Default"
        }

        foreach ($browser in $browserProfiles.GetEnumerator()) {
            if (Test-Path $browser.Value) {
                # Only backup bookmarks and settings, not cache/cookies
                $browserBackupPath = Join-Path $backupPath "Browsers\$($browser.Key)"
                New-Item -ItemType Directory -Force -Path $browserBackupPath | Out-Null
                
                switch ($browser.Key) {
                    { $_ -in "Chrome", "Edge", "Brave", "Vivaldi" } {
                        Copy-Item "$($browser.Value)\Bookmarks" $browserBackupPath -ErrorAction SilentlyContinue
                        Copy-Item "$($browser.Value)\Preferences" $browserBackupPath -ErrorAction SilentlyContinue
                    }
                    "Firefox" {
                        Copy-Item "$($browser.Value)\*.default*\bookmarkbackups" $browserBackupPath -Recurse -ErrorAction SilentlyContinue
                        Copy-Item "$($browser.Value)\*.default*\prefs.js" $browserBackupPath -ErrorAction SilentlyContinue
                    }
                }
            }
        }

        # Backup printer settings
        $printerPath = Join-Path $backupPath "Printers"
        New-Item -ItemType Directory -Force -Path $printerPath | Out-Null
        Get-Printer | Export-Clixml "$printerPath\printers.xml"
        Get-PrintConfiguration | Export-Clixml "$printerPath\printer-configs.xml"

        # Backup network profiles
        $networkPath = Join-Path $backupPath "Network"
        New-Item -ItemType Directory -Force -Path $networkPath | Out-Null
        Get-NetAdapter | Export-Clixml "$networkPath\adapters.xml"
        Get-NetIPAddress | Export-Clixml "$networkPath\ip-addresses.xml"
        netsh wlan export profile folder="$networkPath" key=clear

        # Backup scheduled tasks (custom only)
        $tasksPath = Join-Path $backupPath "ScheduledTasks"
        New-Item -ItemType Directory -Force -Path $tasksPath | Out-Null
        Get-ScheduledTask | Where-Object { $_.TaskPath -like "\Custom Tasks\*" } | 
            ForEach-Object {
                Export-ScheduledTask -TaskName $_.TaskName -TaskPath $_.TaskPath | 
                Out-File "$tasksPath\$($_.TaskName).xml"
            }

        # Backup environment variables (user only)
        [Environment]::GetEnvironmentVariables('User') | 
            ConvertTo-Json | 
            Out-File (Join-Path $backupPath "user-environment-variables.json")

        # Backup mapped drives
        Get-PSDrive -PSProvider FileSystem | 
            Where-Object { $_.DisplayRoot } | 
            Export-Clixml (Join-Path $backupPath "mapped-drives.xml")

        # Backup KeePassXC settings
        $keepassPath = Join-Path $backupPath "KeePassXC"
        New-Item -ItemType Directory -Force -Path $keepassPath | Out-Null
        
        # KeePassXC config locations
        $keepassConfigs = @{
            "Config" = "$env:APPDATA\KeePassXC\keepassxc.ini"
            "LastDatabase" = "$env:APPDATA\KeePassXC\lastdatabase"
            "CustomIcons" = "$env:APPDATA\KeePassXC\CustomIcons"
        }
        
        foreach ($config in $keepassConfigs.GetEnumerator()) {
            if (Test-Path $config.Value) {
                if ((Get-Item $config.Value) -is [System.IO.DirectoryInfo]) {
                    Copy-Item $config.Value $keepassPath -Recurse -Force
                } else {
                    Copy-Item $config.Value $keepassPath -Force
                }
            }
        }
        
        # Save database location if provided
        $dbLocation = [Environment]::GetEnvironmentVariable('KEEPASSXC_DB', 'User')
        if ($dbLocation) {
            $dbLocation | Out-File (Join-Path $keepassPath "database_location.txt")
        }

        Write-Host "System settings backed up successfully to: $backupPath" -ForegroundColor Green
    }
} catch {
    Write-Host "Failed to backup system settings: $_" -ForegroundColor Red
} 