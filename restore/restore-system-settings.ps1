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

function Restore-SystemSettings {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath
    )
    
    try {
        Write-Host "Restoring System Settings..." -ForegroundColor Blue
        $backupPath = Test-BackupPath -Path "SystemSettings" -BackupType "System Settings"
        
        if ($backupPath) {
            # Restore registry settings
            $registryPath = Join-Path $backupPath "Registry"
            if (Test-Path $registryPath) {
                Get-ChildItem -Path $registryPath -Filter "*.reg" | ForEach-Object {
                    Write-Host "Importing registry file: $($_.Name)" -ForegroundColor Yellow
                    reg import $_.FullName | Out-Null
                }
            }

            # Restore system configurations
            $systemConfigPath = Join-Path $backupPath "SystemConfig"
            if (Test-Path $systemConfigPath) {
                # Restore power settings
                $powerSettingsFile = Join-Path $systemConfigPath "power_settings.txt"
                if (Test-Path $powerSettingsFile) {
                    Write-Host "Restoring power settings..." -ForegroundColor Yellow
                    Get-Content $powerSettingsFile | ForEach-Object {
                        if ($_ -match "GUID: (.+)") {
                            $guid = $matches[1]
                            powercfg /setactive $guid
                        }
                    }
                }

                # Restore page file settings
                $pageFileSettings = Join-Path $systemConfigPath "pagefile_settings.json"
                if (Test-Path $pageFileSettings) {
                    Write-Host "Restoring page file settings..." -ForegroundColor Yellow
                    $settings = Get-Content $pageFileSettings | ConvertFrom-Json
                    foreach ($setting in $settings) {
                        Set-CimInstance -Query "SELECT * FROM Win32_PageFileSetting WHERE Name='$($setting.Name)'" -Property @{
                            InitialSize = $setting.InitialSize
                            MaximumSize = $setting.MaximumSize
                        }
                    }
                }

                # Restore time and region settings
                $timeSettingsFile = Join-Path $systemConfigPath "time_settings.json"
                if (Test-Path $timeSettingsFile) {
                    Write-Host "Restoring time and region settings..." -ForegroundColor Yellow
                    $timeSettings = Get-Content $timeSettingsFile | ConvertFrom-Json
                    Set-TimeZone -Id $timeSettings.TimeZone
                    Set-WinHomeLocation -GeoId $timeSettings.Region
                    Set-WinSystemLocale -SystemLocale $timeSettings.SystemLocale
                    $langList = New-WinUserLanguageList $timeSettings.UserLocale
                    Set-WinUserLanguageList $langList -Force
                }
            }

            # Restore printer settings
            Write-Host "Restoring printer settings..." -ForegroundColor Yellow
            $printerPath = Join-Path $backupPath "Printers"
            if (Test-Path "$printerPath\printers.xml") {
                Import-Clixml "$printerPath\printers.xml" | Add-Printer
                Import-Clixml "$printerPath\printer-configs.xml" | Set-PrintConfiguration
            }

            # Restore network profiles
            Write-Host "Restoring network settings..." -ForegroundColor Yellow
            $networkPath = Join-Path $backupPath "Network"
            if (Test-Path $networkPath) {
                Get-ChildItem "$networkPath\*.xml" -Filter "Wi-Fi*.xml" | ForEach-Object {
                    netsh wlan add profile filename="$($_.FullName)" user=all
                }
            }

            # Restore scheduled tasks
            Write-Host "Restoring scheduled tasks..." -ForegroundColor Yellow
            $tasksPath = Join-Path $backupPath "ScheduledTasks"
            if (Test-Path $tasksPath) {
                Get-ChildItem $tasksPath -Filter "*.xml" | ForEach-Object {
                    Register-ScheduledTask -Xml (Get-Content $_.FullName | Out-String) -TaskName $_.BaseName -Force
                }
            }

            # Restore environment variables
            Write-Host "Restoring environment variables..." -ForegroundColor Yellow
            $envVarsFile = Join-Path $backupPath "user-environment-variables.json"
            if (Test-Path $envVarsFile) {
                $envVars = Get-Content $envVarsFile | ConvertFrom-Json
                $envVars.PSObject.Properties | ForEach-Object {
                    [Environment]::SetEnvironmentVariable($_.Name, $_.Value, 'User')
                }
            }

            # Restore mapped drives
            Write-Host "Restoring mapped drives..." -ForegroundColor Yellow
            $mappedDrivesFile = Join-Path $backupPath "mapped-drives.xml"
            if (Test-Path $mappedDrivesFile) {
                Import-Clixml $mappedDrivesFile | ForEach-Object {
                    New-PSDrive -Name $_.Name -PSProvider FileSystem -Root $_.DisplayRoot -Persist
                }
            }

            Write-Host "System Settings restored successfully from: $backupPath" -ForegroundColor Green
            Write-Host "`nNote: Some settings may require a system restart to take effect" -ForegroundColor Yellow
            return $true
        }
        return $false
    } catch {
        Write-Host "Failed to restore System Settings: $_" -ForegroundColor Red
        return $false
    }
}

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Restore-SystemSettings -BackupRootPath $BackupRootPath
} 