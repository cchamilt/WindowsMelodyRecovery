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
            # Keyboard config locations
            $keyboardConfigs = @{
                # Keyboard layout settings
                "Layout" = "HKCU:\Keyboard Layout\Preload"
                # Input method settings
                "InputMethod" = "HKCU:\Software\Microsoft\CTF\Assemblies"
                # Keyboard preferences
                "Preferences" = "HKCU:\Control Panel\Keyboard"
                # Key remapping
                "KeyRemap" = "HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layout"
                # Hotkey settings
                "Hotkeys" = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
                # Typing settings
                "Typing" = "HKCU:\Software\Microsoft\TabletTip\1.7"
                # Language preferences
                "Language" = "HKCU:\Software\Microsoft\Input\Settings"
                # Text prediction settings
                "TextPrediction" = "HKCU:\Software\Microsoft\Input\Settings\TextPrediction"
            }

            # Restore keyboard settings
            Write-Host "Checking keyboard components..." -ForegroundColor Yellow
            $keyboardServices = @(
                "TabletInputService",     # Touch Keyboard and Handwriting Panel Service
                "i8042prt",              # PS/2 Keyboard and Mouse Driver
                "kbdhid"                 # Keyboard HID Driver
            )
            
            foreach ($service in $keyboardServices) {
                if ((Get-Service -Name $service -ErrorAction SilentlyContinue).Status -ne "Running") {
                    Start-Service -Name $service
                }
            }

            # Restore registry settings
            foreach ($config in $keyboardConfigs.GetEnumerator()) {
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

            # Restore keyboard layouts
            $layoutsFile = Join-Path $backupPath "keyboard_layouts.json"
            if (Test-Path $layoutsFile) {
                $layouts = Get-Content $layoutsFile | ConvertFrom-Json
                foreach ($layout in $layouts) {
                    # Add keyboard layout
                    $languageId = [System.Globalization.CultureInfo]::GetCultureInfo($layout.LCID).KeyboardLayoutId
                    Set-WinUserLanguageList -LanguageList @($layout.LCID) -Force
                }
            }

            # Restore key remapping
            $remapFile = Join-Path $backupPath "key_remap.json"
            if (Test-Path $remapFile) {
                $remaps = Get-Content $remapFile | ConvertFrom-Json
                $scanCodeMap = New-Object byte[] ($remaps.Count * 4 + 16)
                # Header
                $scanCodeMap[0] = 0x00; $scanCodeMap[1] = 0x00
                $scanCodeMap[2] = 0x00; $scanCodeMap[3] = 0x00
                $scanCodeMap[4] = 0x00; $scanCodeMap[5] = 0x00
                $scanCodeMap[6] = 0x00; $scanCodeMap[7] = 0x00
                $scanCodeMap[8] = [byte]($remaps.Count + 1)
                $scanCodeMap[9] = 0x00; $scanCodeMap[10] = 0x00; $scanCodeMap[11] = 0x00

                $offset = 12
                foreach ($remap in $remaps) {
                    $scanCodeMap[$offset] = [byte]($remap.From -band 0xFF)
                    $scanCodeMap[$offset + 1] = [byte](($remap.From -shr 8) -band 0xFF)
                    $scanCodeMap[$offset + 2] = [byte]($remap.To -band 0xFF)
                    $scanCodeMap[$offset + 3] = [byte](($remap.To -shr 8) -band 0xFF)
                    $offset += 4
                }

                Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layout" `
                    -Name "Scancode Map" -Value $scanCodeMap -Type Binary
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