function Restore-SystemSettings {
    try {
        Write-Host "Restoring system settings..." -ForegroundColor Blue
        $settingsPath = Test-BackupPath -Path "SystemSettings" -BackupType "System Settings"
        
        if ($settingsPath) {
            # Restore browser profiles
            $browserProfiles = @{
                "Chrome" = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default"
                "Edge" = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default"
                "Firefox" = "$env:APPDATA\Mozilla\Firefox\Profiles"
                "Brave" = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default"
                "Vivaldi" = "$env:LOCALAPPDATA\Vivaldi\User Data\Default"
            }

            foreach ($browser in $browserProfiles.GetEnumerator()) {
                $browserBackupPath = Join-Path $settingsPath "Browsers\$($browser.Key)"
                if (Test-Path $browserBackupPath) {
                    switch ($browser.Key) {
                        { $_ -in "Chrome", "Edge", "Brave", "Vivaldi" } {
                            Copy-Item "$browserBackupPath\Bookmarks" $browser.Value -ErrorAction SilentlyContinue
                            Copy-Item "$browserBackupPath\Preferences" $browser.Value -ErrorAction SilentlyContinue
                        }
                        "Firefox" {
                            Get-ChildItem "$browser.Value\*.default*" | ForEach-Object {
                                Copy-Item "$browserBackupPath\bookmarkbackups" $_.FullName -Recurse -ErrorAction SilentlyContinue
                                Copy-Item "$browserBackupPath\prefs.js" $_.FullName -ErrorAction SilentlyContinue
                            }
                        }
                    }
                }
            }

            # Restore printer settings
            $printerPath = Join-Path $settingsPath "Printers"
            if (Test-Path "$printerPath\printers.xml") {
                $printers = Import-Clixml "$printerPath\printers.xml"
                foreach ($printer in $printers) {
                    Add-Printer -Name $printer.Name -DriverName $printer.DriverName -PortName $printer.PortName
                }
            }

            # Restore network profiles
            $networkPath = Join-Path $settingsPath "Network"
            Get-ChildItem "$networkPath\*.xml" -Filter "Wi-Fi*.xml" | ForEach-Object {
                netsh wlan add profile filename="$($_.FullName)" user=all
            }

            # Restore scheduled tasks
            $tasksPath = Join-Path $settingsPath "ScheduledTasks"
            if (Test-Path $tasksPath) {
                Get-ChildItem "$tasksPath\*.xml" | ForEach-Object {
                    Register-ScheduledTask -Xml (Get-Content $_.FullName | Out-String) -TaskName $_.BaseName -Force
                }
            }

            # Restore environment variables
            $envVarsFile = Join-Path $settingsPath "user-environment-variables.json"
            if (Test-Path $envVarsFile) {
                $envVars = Get-Content $envVarsFile | ConvertFrom-Json
                foreach ($var in $envVars.PSObject.Properties) {
                    [Environment]::SetEnvironmentVariable($var.Name, $var.Value, 'User')
                }
            }

            # Restore mapped drives
            $mappedDrivesFile = Join-Path $settingsPath "mapped-drives.xml"
            if (Test-Path $mappedDrivesFile) {
                $drives = Import-Clixml $mappedDrivesFile
                foreach ($drive in $drives) {
                    New-PSDrive -Name $drive.Name -PSProvider FileSystem -Root $drive.DisplayRoot -Persist
                }
            }

            # Restore KeePassXC settings
            $keepassPath = Join-Path $settingsPath "KeePassXC"
            if (Test-Path $keepassPath) {
                # KeePassXC config locations
                $keepassConfigs = @{
                    "Config" = "$env:APPDATA\KeePassXC\keepassxc.ini"
                    "LastDatabase" = "$env:APPDATA\KeePassXC\lastdatabase"
                    "CustomIcons" = "$env:APPDATA\KeePassXC\CustomIcons"
                }
                
                # Create KeePassXC config directory if it doesn't exist
                New-Item -ItemType Directory -Force -Path "$env:APPDATA\KeePassXC" | Out-Null
                
                foreach ($config in $keepassConfigs.GetEnumerator()) {
                    $backupItem = Join-Path $keepassPath (Split-Path $config.Value -Leaf)
                    if (Test-Path $backupItem) {
                        if ((Get-Item $backupItem) -is [System.IO.DirectoryInfo]) {
                            Copy-Item $backupItem $config.Value -Recurse -Force
                        } else {
                            Copy-Item $backupItem $config.Value -Force
                        }
                    }
                }
                
                # Restore database location if saved
                $dbLocationFile = Join-Path $keepassPath "database_location.txt"
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
            }

            Write-Host "System settings restored successfully" -ForegroundColor Green
        }
    } catch {
        Write-Host "Failed to restore system settings: $_" -ForegroundColor Red
    }
} 