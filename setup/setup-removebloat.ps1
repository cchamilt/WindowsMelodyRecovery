# Confidence: Low - This script is not fully tested and may remove important Lenovo/ASUS applications.

# See Andrew S Taylor's blog for more information: https://andrewstaylor.com/2022/08/09/removing-bloatware-from-windows-10-11-via-script/
# But want to keep copilot and some other iffy apps


#Remove: Lenovo*, new outlook, etc.
Write-Host "Removing Lenovo bloatware..." -ForegroundColor Blue

try {
    # List of Lenovo app package names to remove
    $lenovoApps = @(
        "E046963F.LenovoCompanion",
        "E046963F.LenovoSettings",
        "E0469640.LenovoUtility",
        "LenovoCorporation.LenovoID",
        "LenovoCorporation.LenovoVantage",
        "LenovoCorporation.LenovoVoiceService",
        "LenovoCorporation.LenovoWelcome",
        "E046963F.LenovoSettingsforEnterprise"
    )

    # Remove Windows Store apps
    foreach ($app in $lenovoApps) {
        Get-AppxPackage -Name $app -AllUsers | Remove-AppxPackage -AllUsers
        Get-AppxProvisionedPackage -Online | Where-Object DisplayName -like $app | Remove-AppxProvisionedPackage -Online
    }

    # List of Lenovo programs to uninstall
    $lenovoPrograms = @(
        "Lenovo Universal Device Client",
        "Lenovo Vantage",
        "Lenovo Vantage Service",
        "Lenovo System Interface Foundation",
        "Lenovo PM Device",
        "Lenovo Hotkeys",
        "Lenovo Device Experience",
        "Lenovo Commercial Vantage",
        "Lenovo Intelligent Thermal Solution",
        "Lenovo Smart Appearance Components",
        "Lenovo Smart Performance Components",
        "Lenovo Voice Service"
    )

    # Get all installed programs
    $installedPrograms = @(
        Get-WmiObject -Class Win32_Product | Where-Object { $_.Vendor -like "*Lenovo*" }
        Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" | Where-Object { $_.Publisher -like "*Lenovo*" }
        Get-ItemProperty "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" | Where-Object { $_.Publisher -like "*Lenovo*" }
    )

    # Uninstall programs
    foreach ($program in $installedPrograms) {
        if ($program.Name -in $lenovoPrograms -or $program.DisplayName -in $lenovoPrograms) {
            Write-Host "Uninstalling: $($program.Name)$($program.DisplayName)" -ForegroundColor Yellow
            
            if ($program.UninstallString) {
                $uninstallString = $program.UninstallString
                if ($uninstallString -like "MsiExec.exe*") {
                    $productCode = $uninstallString -replace ".*({.*})", '$1'
                    Start-Process "msiexec.exe" -ArgumentList "/x $productCode /qn /norestart" -Wait -NoNewWindow
                } else {
                    $uninstallString = $uninstallString -replace "/I", "/X"
                    Start-Process "cmd.exe" -ArgumentList "/c $uninstallString /quiet /norestart" -Wait -NoNewWindow
                }
            }
        }
    }

    # Stop and disable Lenovo services
    $lenovoServices = @(
        "LenovoVantageService",
        "LenovoSystemInterfaceFoundationService",
        "ImControllerService",
        "LenovoPlatformWatchdog",
        "LenovoDeviceExperienceService"
    )

    foreach ($service in $lenovoServices) {
        if (Get-Service -Name $service -ErrorAction SilentlyContinue) {
            Stop-Service -Name $service -Force
            Set-Service -Name $service -StartupType Disabled
            Write-Host "Disabled service: $service" -ForegroundColor Yellow
        }
    }

    # Remove Lenovo scheduled tasks
    $lenovoTasks = @(
        "\Lenovo\*",
        "\ImController\*"
    )

    foreach ($task in $lenovoTasks) {
        Get-ScheduledTask -TaskPath $task -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false
    }

    # Remove Lenovo folders
    $lenovoFolders = @(
        "$env:ProgramFiles\Lenovo",
        "${env:ProgramFiles(x86)}\Lenovo",
        "$env:ProgramData\Lenovo",
        "$env:LOCALAPPDATA\Lenovo",
        "$env:APPDATA\Lenovo"
    )

    foreach ($folder in $lenovoFolders) {
        if (Test-Path $folder) {
            Remove-Item -Path $folder -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Host "Lenovo bloatware removal completed" -ForegroundColor Green
    Write-Host "Note: A system restart may be required" -ForegroundColor Yellow
} catch {
    Write-Host "Failed to remove Lenovo bloatware: $_" -ForegroundColor Red
}

# Remove Lenovo bloatware scammy 'drivers'
Write-Host "Removing Lenovo bloatware scammy 'drivers'..." -ForegroundColor Blue
# Remove Lenove UDCService
Get-Service -Name UDCService | Stop-Service -Force  
Get-Service -Name UDCService | Set-Service -StartupType Disabled

# Remove Lenovo UDCService from registry
Remove-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Services\UDCService" -Recurse -Force

# Disable Lenovo Universal Device Client Device driver from System devices

# Disable Lenovo Universal Device Client Device Plugins drivers from Software Components
Remove-Item -Path "C:\Windows\System32\drivers\Lenovo\udc\Service\UDClientService.exe" -Force

# Remove Lenovo UDCService from services
Get-Service -Name UDCService | Stop-Service -Force
Get-Service -Name UDCService | Set-Service -StartupType Disabled

# Remove new outlook
Write-Host "Removing new outlook..." -ForegroundColor Blue

try {
    # Remove Outlook from the registry
    Write-Host "Removing Outlook from registry..." -ForegroundColor Yellow
    Remove-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft.Office.16.0.Outlook" -Recurse -Force

    # Remove Outlook from the registry
    Write-Host "Removing Outlook from registry..." -ForegroundColor Yellow
    Remove-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft.Office.16.0.Outlook" -Recurse -Force 

    Write-Host "Outlook removal completed" -ForegroundColor Green
} catch {
    Write-Host "Failed to remove Outlook: $_" -ForegroundColor Red
}

# Remove McAfee AV
Write-Host "Removing McAfee AV..." -ForegroundColor Blue

try {
    # Remove McAfee from the registry
    Write-Host "Removing McAfee from registry..." -ForegroundColor Yellow
    Remove-Item -Path "HKLM:\SOFTWARE\McAfee" -Recurse -Force

    # Remove McAfee from the registry
    Write-Host "Removing McAfee from registry..." -ForegroundColor Yellow
    Remove-Item -Path "HKLM:\SOFTWARE\McAfee" -Recurse -Force   

    Write-Host "McAfee removal completed" -ForegroundColor Green
} catch {
    Write-Host "Failed to remove McAfee: $_" -ForegroundColor Red
}

# Remove ASUS bloatware
Write-Host "Removing ASUS bloatware..." -ForegroundColor Blue

try {
    # Remove ASUS from the registry
    Write-Host "Removing ASUS from registry..." -ForegroundColor Yellow 
    Remove-Item -Path "HKLM:\SOFTWARE\ASUS" -Recurse -Force

    # Remove ASUS from the registry
    Write-Host "Removing ASUS from registry..." -ForegroundColor Yellow
    Remove-Item -Path "HKLM:\SOFTWARE\ASUS" -Recurse -Force

    Write-Host "ASUS removal completed" -ForegroundColor Green
} catch {
    Write-Host "Failed to remove ASUS: $_" -ForegroundColor Red
}










