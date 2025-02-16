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

function Restore-PowerSettings {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath
    )
    
    try {
        Write-Host "Restoring Power Settings..." -ForegroundColor Blue
        $backupPath = Test-BackupPath -Path "Power" -BackupType "Power Settings"
        
        if ($backupPath) {
            # Power config locations
            $powerConfigs = @{
                # Power schemes
                "Schemes" = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes"
                # Power settings
                "Settings" = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\PowerSettings"
                # Power buttons
                "Buttons" = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\4f971e89-eebd-4455-a8de-9e59040e7347"
                # Sleep settings
                "Sleep" = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\238C9FA8-0AAD-41ED-83F4-97BE242C8F20"
                # Battery settings
                "Battery" = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\9D7815A6-7EE4-497E-8888-515A05F02364"
                # Display settings
                "Display" = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\7516B95F-F776-4464-8C53-06167F40CC99"
                # Hard disk settings
                "HardDisk" = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\0012EE47-9041-4B5D-9B77-535FBA8B1442"
                # USB settings
                "USB" = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\2A737441-1930-4402-8D77-B2BEBBA308A3"
            }

            # Restore power settings
            Write-Host "Checking power components..." -ForegroundColor Yellow
            $powerServices = @(
                "Power",                # Power Service
                "BatteryService",       # Battery Service
                "UPS",                  # Uninterruptible Power Supply Service
                "SysMain"              # Superfetch (impacts power settings)
            )
            
            foreach ($service in $powerServices) {
                if ((Get-Service -Name $service -ErrorAction SilentlyContinue).Status -ne "Running") {
                    Start-Service -Name $service
                }
            }

            # Restore registry settings
            foreach ($config in $powerConfigs.GetEnumerator()) {
                $backupItem = Join-Path $backupPath $config.Key
                if (Test-Path $backupItem) {
                    Write-Host "Restoring $($config.Key) settings..." -ForegroundColor Yellow
                    if ((Get-Item $backupItem) -is [System.IO.DirectoryInfo]) {
                        # Skip temporary files during restore
                        $excludeFilter = @("*.tmp", "~*.*", "*.bak", "*.old")
                        Copy-Item $backupItem $config.Value -Recurse -Force -Exclude $excludeFilter
                    } else {
                        Copy-Item $backupItem $config.Value -Force
                    }
                    Write-Host "Restored configuration: $($config.Key)" -ForegroundColor Green
                }
            }

            # Restore power schemes
            $schemesFile = Join-Path $backupPath "power_schemes.json"
            if (Test-Path $schemesFile) {
                $schemes = Get-Content $schemesFile | ConvertFrom-Json
                foreach ($scheme in $schemes) {
                    # Import power scheme
                    powercfg /import "$backupPath\$($scheme.GUID).pow"
                    
                    # Set as active if it was active in backup
                    if ($scheme.IsActive) {
                        powercfg /setactive $scheme.GUID
                    }
                }
            }

            # Restore advanced power settings
            $advancedSettingsFile = Join-Path $backupPath "advanced_power_settings.json"
            if (Test-Path $advancedSettingsFile) {
                $advancedSettings = Get-Content $advancedSettingsFile | ConvertFrom-Json
                foreach ($setting in $advancedSettings) {
                    powercfg /setacvalueindex $setting.SchemeGUID $setting.SubGroupGUID $setting.SettingGUID $setting.ACValue
                    powercfg /setdcvalueindex $setting.SchemeGUID $setting.SubGroupGUID $setting.SettingGUID $setting.DCValue
                }
            }

            # Restore button actions
            $buttonFile = "$backupPath\button_settings.json"
            if (Test-Path $buttonFile) {
                $buttonSettings = Get-Content $buttonFile | ConvertFrom-Json
                
                # Apply button settings using powercfg
                foreach ($setting in $buttonSettings.PSObject.Properties) {
                    $action = $setting.Value
                    if ($action) {
                        switch ($setting.Name) {
                            "PowerButton" { powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS PBUTTONACTION $action.Value }
                            "SleepButton" { powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS SBUTTONACTION $action.Value }
                            "LidClose" { powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION $action.Value }
                        }
                    }
                }
            }
            
            Write-Host "Power Settings restored successfully from: $backupPath" -ForegroundColor Green
            return $true
        }
        return $false
    } catch {
        Write-Host "Failed to restore Power Settings: $_" -ForegroundColor Red
        return $false
    }
}

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Restore-PowerSettings -BackupRootPath $BackupRootPath
} 