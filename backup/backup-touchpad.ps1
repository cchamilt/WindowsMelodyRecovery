param(
    [Parameter(Mandatory=$true)]
    [string]$BackupRootPath
)

try {
    Write-Host "Backing up Touchpad settings..." -ForegroundColor Blue
    $backupPath = Initialize-BackupDirectory -Path "Touchpad" -BackupType "Touchpad" -BackupRootPath $BackupRootPath
    
    if ($backupPath) {
        # Export touchpad registry settings
        $regPaths = @(
            # Windows Precision Touchpad settings
            "HKCU\Software\Microsoft\Windows\CurrentVersion\PrecisionTouchPad",
            "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\PrecisionTouchPad",
            
            # Mouse properties (affects touchpad)
            "HKCU\Control Panel\Mouse",
            "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\ControlPanel\Mouse",
            
            # Synaptics settings
            "HKLM\SOFTWARE\Synaptics",
            "HKCU\Software\Synaptics",
            
            # Elan settings
            "HKLM\SOFTWARE\Elantech",
            "HKCU\Software\Elantech",
            
            # General input settings
            "HKLM\SYSTEM\CurrentControlSet\Services\MouseLikeTouchPad",
            "HKLM\SYSTEM\CurrentControlSet\Services\SynTP",
            "HKLM\SYSTEM\CurrentControlSet\Services\ETD"
        )
        
        foreach ($regPath in $regPaths) {
            $regFile = "$backupPath\$($regPath.Split('\')[-1]).reg"
            reg export $regPath $regFile /y 2>$null
        }
        
        # Get all touchpad devices, including disabled ones
        $touchpadDevices = Get-PnpDevice | Where-Object { 
            ($_.Class -eq "Mouse" -or $_.Class -eq "HIDClass") -and 
            ($_.FriendlyName -match "touchpad|synaptics|elan|precision" -or
             $_.Manufacturer -match "synaptics|elan|alps")
        } | Select-Object -Property @(
            'InstanceId',
            'FriendlyName',
            'Manufacturer',
            'Status',
            @{Name='IsEnabled'; Expression={$_.Status -eq 'OK'}}
        )
        
        if ($touchpadDevices) {
            $touchpadDevices | ConvertTo-Json | Out-File "$backupPath\touchpad_devices.json" -Force
        }
        
        Write-Host "Touchpad settings backed up successfully to: $backupPath" -ForegroundColor Green
    }
} catch {
    Write-Host "Failed to backup Touchpad settings: $_" -ForegroundColor Red
} 