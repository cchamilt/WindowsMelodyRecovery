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

function Restore-KeyboardSettings {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath
    )
    
    try {
        Write-Host "Restoring Keyboard Settings..." -ForegroundColor Blue
        $backupPath = Test-BackupPath -Path "Keyboard" -BackupType "Keyboard Settings"
        
        if ($backupPath) {
            # Import registry settings first
            $regFiles = Get-ChildItem -Path $backupPath -Filter "*.reg"
            foreach ($regFile in $regFiles) {
                reg import $regFile.FullName | Out-Null
            }

            # Restore keyboard devices configuration
            $keyboardDevicesFile = "$backupPath\keyboard_devices.json"
            if (Test-Path $keyboardDevicesFile) {
                $savedDevices = Get-Content $keyboardDevicesFile | ConvertFrom-Json
                $currentDevices = Get-WmiObject Win32_Keyboard

                foreach ($current in $currentDevices) {
                    $saved = $savedDevices | Where-Object { $_.DeviceID -eq $current.DeviceID }
                    if ($saved) {
                        # Update supported properties
                        $current.Layout = $saved.Layout
                        $current.NumberOfFunctionKeys = $saved.NumberOfFunctionKeys
                        $current.Put()
                    }
                }
            }

            # Restore input language settings
            $inputSettingsFile = "$backupPath\input_settings.json"
            if (Test-Path $inputSettingsFile) {
                $inputSettings = Get-Content $inputSettingsFile | ConvertFrom-Json
                
                # Set language list
                if ($inputSettings.Languages) {
                    Set-WinUserLanguageList -LanguageList $inputSettings.Languages -Force
                }

                # Set default input method
                if ($inputSettings.DefaultInputMethod) {
                    Set-WinDefaultInputMethodOverride -InputTip $inputSettings.DefaultInputMethod
                }

                # Set language bar options
                if ($inputSettings.Hotkeys) {
                    Set-WinLanguageBarOption -UseLegacySwitchMode $inputSettings.Hotkeys.UseLegacySwitchMode `
                        -UseLegacyLanguageBar $inputSettings.Hotkeys.UseLegacyLanguageBar
                }
            }

            # Restore scan code mappings
            $scanCodeFile = "$backupPath\scancode_mappings.json"
            if (Test-Path $scanCodeFile) {
                $scanCodeMappings = Get-Content $scanCodeFile | ConvertFrom-Json
                Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layout" `
                    -Name "Scancode Map" -Value $scanCodeMappings.'Scancode Map'
            }

            # Restore keyboard speed settings
            $speedFile = "$backupPath\keyboard_speed.json"
            if (Test-Path $speedFile) {
                $keyboardSpeed = Get-Content $speedFile | ConvertFrom-Json
                Set-ItemProperty -Path "HKCU:\Control Panel\Keyboard" -Name "KeyboardDelay" -Value $keyboardSpeed.KeyboardDelay
                Set-ItemProperty -Path "HKCU:\Control Panel\Keyboard" -Name "KeyboardSpeed" -Value $keyboardSpeed.KeyboardSpeed
            }

            # Restart keyboard services
            $services = @(
                "i8042prt",
                "kbdclass"
            )
            
            foreach ($service in $services) {
                if (Get-Service -Name $service -ErrorAction SilentlyContinue) {
                    Restart-Service -Name $service -Force -ErrorAction SilentlyContinue
                }
            }
            
            Write-Host "Keyboard Settings restored successfully from: $backupPath" -ForegroundColor Green
            return $true
        }
        return $false
    } catch {
        Write-Host "Failed to restore Keyboard Settings: $_" -ForegroundColor Red
        return $false
    }
}

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Restore-KeyboardSettings -BackupRootPath $BackupRootPath
} 