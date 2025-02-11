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

function Backup-KeyboardSettings {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath
    )
    
    try {
        Write-Host "Backing up Keyboard Settings..." -ForegroundColor Blue
        $backupPath = Initialize-BackupDirectory -Path "Keyboard" -BackupType "Keyboard Settings" -BackupRootPath $BackupRootPath
        
        if ($backupPath) {
            # Export keyboard registry settings
            $regPaths = @(
                # Keyboard layouts and input methods
                "HKCU\Keyboard Layout",
                "HKCU\Software\Microsoft\CTF",
                "HKCU\Software\Microsoft\Input",
                "HKLM\SYSTEM\CurrentControlSet\Control\Keyboard Layout",
                "HKLM\SYSTEM\CurrentControlSet\Control\Keyboard Layouts",
                
                # Input method preferences
                "HKCU\Software\Microsoft\Windows\CurrentVersion\CPSS\InputMethod",
                "HKCU\Software\Microsoft\Windows\CurrentVersion\IME",
                
                # Keyboard hardware settings
                "HKLM\SYSTEM\CurrentControlSet\Services\i8042prt",
                "HKLM\SYSTEM\CurrentControlSet\Services\kbdclass",
                
                # AutoHotkey and keyboard macros
                "HKCU\Software\AutoHotkey",
                
                # Keyboard accessibility options
                "HKCU\Control Panel\Accessibility\Keyboard Response",
                "HKCU\Control Panel\Accessibility\StickyKeys",
                "HKCU\Control Panel\Accessibility\ToggleKeys",
                "HKCU\Control Panel\Accessibility\FilterKeys"
            )

            foreach ($regPath in $regPaths) {
                $regFile = "$backupPath\$($regPath.Split('\')[-1]).reg"
                reg export $regPath $regFile /y 2>$null
            }

            # Export keyboard devices using WMI
            $keyboardDevices = Get-WmiObject Win32_Keyboard | Select-Object -Property *
            $keyboardDevices | ConvertTo-Json -Depth 10 | Out-File "$backupPath\keyboard_devices.json" -Force

            # Export input language settings
            $inputSettings = @{
                Languages = Get-WinUserLanguageList
                DefaultInputMethod = (Get-WinDefaultInputMethodOverride).InputMethodTip
                Hotkeys = Get-WinLanguageBarOption
            }
            $inputSettings | ConvertTo-Json -Depth 10 | Out-File "$backupPath\input_settings.json" -Force

            # Export keyboard scan code mappings
            $scanCodeMappings = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layout" -Name "Scancode Map" -ErrorAction SilentlyContinue
            if ($scanCodeMappings) {
                $scanCodeMappings | ConvertTo-Json | Out-File "$backupPath\scancode_mappings.json" -Force
            }

            # Export keyboard repeat delay and speed
            $keyboardSpeed = Get-ItemProperty -Path "HKCU:\Control Panel\Keyboard"
            $keyboardSpeed | ConvertTo-Json | Out-File "$backupPath\keyboard_speed.json" -Force
            
            Write-Host "Keyboard Settings backed up successfully to: $backupPath" -ForegroundColor Green
            return $true
        }
        return $false
    } catch {
        Write-Host "Failed to backup Keyboard Settings: $_" -ForegroundColor Red
        return $false
    }
}

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Backup-KeyboardSettings -BackupRootPath $BackupRootPath
} 