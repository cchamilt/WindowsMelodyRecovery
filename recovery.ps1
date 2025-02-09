
# Setup touchpad
try {
    Write-Host "Restoring Touchpad settings..." -ForegroundColor Blue
    
    $backupPath = "$env:USERPROFILE\OneDrive - Fyber Labs\PCbackup\shared\Touchpad"
    $touchpadRegPath = "$backupPath\touchpad_settings.reg"
    $synapticsRegPath = "$backupPath\synaptics_settings.reg"
    $mouseRegPath = "$backupPath\mouse_settings.reg"
    
    # Import settings if backups exist
    if (Test-Path -Path $touchpadRegPath) {
        # Import Windows Precision Touchpad settings
        reg import $touchpadRegPath
        
        # Import Synaptics settings if they exist
        if (Test-Path -Path $synapticsRegPath) {
            reg import $synapticsRegPath
        }
        
        # Import Mouse settings
        if (Test-Path -Path $mouseRegPath) {
            reg import $mouseRegPath
        }
        
        Write-Host "Touchpad settings restored successfully" -ForegroundColor Green
        
        # Restart Windows Touch Keyboard and Handwriting Panel Service to apply changes
        Restart-Service -Name TabletInputService -Force
    } else {
        Write-Host "No Touchpad settings backup found" -ForegroundColor Yellow
        
        # Set some sensible defaults if no backup exists
        $touchpadKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PrecisionTouchPad'
        
        # Enable tap to click
        Set-ItemProperty -Path $touchpadKey -Name "TapToClickEnabled" -Value 0
        
        # Enable three finger gestures
        Set-ItemProperty -Path $touchpadKey -Name "ThreeFingerSlideEnabled" -Value 0
        
        # Set three finger gestures for app switching
        Set-ItemProperty -Path $touchpadKey -Name "ThreeFingerSlideGesture" -Value 0
        
        Write-Host "Applied default Touchpad settings" -ForegroundColor Yellow
    }
} catch {
    Write-Host "Failed to restore Touchpad settings: $_" -ForegroundColor Red
}

#disable touchscreen
try {
    Write-Host "Configuring touchscreen..." -ForegroundColor Blue
    
    $backupPath = "$env:USERPROFILE\OneDrive - Fyber Labs\PCbackup\shared\Touchscreen"
    $stateFile = "$backupPath\touchscreen_state.json"
    
    if (Test-Path $stateFile) {
        $savedStates = Get-Content $stateFile | ConvertFrom-Json
        
        foreach ($savedState in $savedStates) {
            $device = Get-PnpDevice -InstanceId $savedState.InstanceId -ErrorAction SilentlyContinue
            if ($device) {
                if ($savedState.Status -eq "OK") {
                    Enable-PnpDevice -InstanceId $device.InstanceId -Confirm:$false
                } else {
                    Disable-PnpDevice -InstanceId $device.InstanceId -Confirm:$false
                }
                Write-Host "Restored state for touchscreen device: $($savedState.FriendlyName)" -ForegroundColor Green
            }
        }
    } else {
        # Default behavior: disable all touchscreen devices
        $touchscreenDevices = Get-PnpDevice | Where-Object { 
            $_.Class -eq "HIDClass" -and 
            $_.FriendlyName -match "touch screen|touchscreen|touch input"
        }
        
        if ($touchscreenDevices) {
            foreach ($device in $touchscreenDevices) {
                Disable-PnpDevice -InstanceId $device.InstanceId -Confirm:$false
                Write-Host "Disabled touchscreen device: $($device.FriendlyName)" -ForegroundColor Green
            }
        } else {
            Write-Host "No touchscreen devices found" -ForegroundColor Yellow
        }
    }
} catch {
    Write-Host "Failed to configure touchscreen: $_" -ForegroundColor Red
}

# power settings
try {
    Write-Host "Configuring power settings..." -ForegroundColor Blue
    
    $backupPath = "$env:USERPROFILE\OneDrive - Fyber Labs\PCbackup\shared\Power"
    $powerSchemesFile = "$backupPath\power_schemes.pow"
    $activeSchemeFile = "$backupPath\active_scheme.txt"
    $hibernateSettingsFile = "$backupPath\hibernate_settings.json"
    
    if (Test-Path $powerSchemesFile) {
        # Import power schemes
        powercfg /import "$powerSchemesFile"
        
        # Set active scheme if saved
        if (Test-Path $activeSchemeFile) {
            $activeScheme = Get-Content $activeSchemeFile
            powercfg /setactive $activeScheme
        }
        
        # Restore hibernate settings if saved
        if (Test-Path $hibernateSettingsFile) {
            $hibernateSettings = Get-Content $hibernateSettingsFile | ConvertFrom-Json
            if ($hibernateSettings.HibernateEnabled) {
                powercfg /hibernate on
                if ($hibernateSettings.HibernateDiskSize) {
                    powercfg /hibernatesize $hibernateSettings.HibernateDiskSize
                }
            } else {
                powercfg /hibernate off
            }
        }
        
        Write-Host "Power settings restored successfully" -ForegroundColor Green
    } else {
        Write-Host "No power settings backup found, applying defaults..." -ForegroundColor Yellow
        
        # Set some sensible defaults
        # High performance plan
        powercfg /setactive SCHEME_MIN
        
        # Never sleep when plugged in
        powercfg /change standby-timeout-ac 0
        
        # Sleep after 30 minutes on battery
        powercfg /change standby-timeout-dc 30
        
        # Never hibernate
        powercfg /hibernate off
        
        # Screen off after 10 minutes on battery, 20 minutes when plugged in
        powercfg /change monitor-timeout-ac 20
        powercfg /change monitor-timeout-dc 10
        
        Write-Host "Default power settings applied" -ForegroundColor Green
    }
} catch {
    Write-Host "Failed to configure power settings: $_" -ForegroundColor Red
}

# Setup terminal settings
try {
    Write-Host "Setting up Windows Terminal settings..." -ForegroundColor Blue
    
    $terminalSettingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
    $terminalBackupPath = "$env:USERPROFILE\OneDrive - Fyber Labs\PCbackup\shared\Terminal\settings.json"
    
    # Check if backup exists
    if (Test-Path -Path $terminalBackupPath) {
        # Create settings directory if it doesn't exist
        $terminalSettingsDir = Split-Path -Path $terminalSettingsPath -Parent
        if (!(Test-Path -Path $terminalSettingsDir)) {
            New-Item -ItemType Directory -Path $terminalSettingsDir -Force
        }
        
        # Copy settings from backup
        Copy-Item -Path $terminalBackupPath -Destination $terminalSettingsPath -Force
        Write-Host "Windows Terminal settings restored from backup" -ForegroundColor Green
    } else {
        Write-Host "Windows Terminal settings backup not found at: $terminalBackupPath" -ForegroundColor Yellow
    }
} catch {
    Write-Host "Failed to setup Windows Terminal settings: $_" -ForegroundColor Red
}

# Setup explorer settings
try {
    Write-Host "Restoring Explorer settings..." -ForegroundColor Blue
    
    $backupPath = "$env:USERPROFILE\OneDrive - Fyber Labs\PCbackup\shared\Explorer"
    $explorerRegPath = "$backupPath\explorer_settings.reg"
    $bagsMRURegPath = "$backupPath\explorer_bagsmru.reg"
    $bagsRegPath = "$backupPath\explorer_bags.reg"
    
    # Import settings if backups exist
    if (Test-Path -Path $explorerRegPath) {
        reg import $explorerRegPath
        reg import $bagsMRURegPath
        reg import $bagsRegPath
        
        # Restart Explorer to apply changes
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
        Start-Process explorer
        
        Write-Host "Explorer settings restored successfully" -ForegroundColor Green
    } else {
        # Apply default settings if no backup exists
        # (Previous explorer settings code here)
        Write-Host "No Explorer settings backup found, applying defaults..." -ForegroundColor Yellow
    }
} catch {
    Write-Host "Failed to restore Explorer settings: $_" -ForegroundColor Red
}

# other settings

# Restore display settings
try {
    # ... display settings restore code
}

# Restore sound settings
try {
    # ... sound settings restore code
}

# Restore keyboard settings
try {
    # ... keyboard settings restore code
}

# etc...
