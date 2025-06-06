# See Andrew S Taylor's blog for more information: https://andrewstaylor.com/2022/08/09/removing-bloatware-from-windows-10-11-via-script/
# This does some of the same stuff but not all of it.
# But want to keep copilot and some others

# Setup-RemoveBloat.ps1 - Remove unwanted pre-installed Windows applications and features
# Requires admin privileges

# At the start after admin check
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path (Split-Path $scriptPath -Parent) "scripts\load-environment.ps1")

if (!(Load-Environment)) {
    Write-Host "Failed to load environment configuration" -ForegroundColor Red
    exit 1
}

try {
    Write-Host "Starting Windows bloatware removal..." -ForegroundColor Blue

    # List of Windows 10/11 bloatware app packages to remove
    $bloatwareApps = @(
        "Microsoft.3DBuilder"
        "Microsoft.BingFinance"
        "Microsoft.BingNews"
        "Microsoft.BingSports"
        "Microsoft.BingWeather"
        "Microsoft.GetHelp"
        "Microsoft.Getstarted"
        "Microsoft.MicrosoftOfficeHub"
        "Microsoft.MicrosoftSolitaireCollection"
        "Microsoft.MixedReality.Portal"
        "Microsoft.People"
        "Microsoft.SkypeApp"
        "Microsoft.WindowsAlarms"
        "Microsoft.WindowsFeedbackHub"
        "Microsoft.WindowsMaps"
        "Microsoft.ZuneMusic"
        "Microsoft.ZuneVideo"
        "*EclipseManager*"
        "*ActiproSoftwareLLC*"
        "*AdobeSystemsIncorporated.AdobePhotoshopExpress*"
        "*Duolingo-LearnLanguagesforFree*"
        "*PandoraMediaInc*"
        "*CandyCrush*"
        "*BubbleWitch3Saga*"
        "*Wunderlist*"
        "*Flipboard*"
        "*Twitter*"
        "*Facebook*"
        "*Spotify*"
        "*Minecraft*"
        "*Royal Revolt*"
        "*Sway*"
        "*Speed Test*"
        "*Dolby*"
        "*Disney*"
        "*.Netflix*"
        "*McAfee*"
        "*Lenovo*"
        "*ASUS*"
        "*Dell*"
        "*HP*"
    )

    # Remove Windows Store apps
    foreach ($app in $bloatwareApps) {
        try {
            $package = Get-AppxPackage -Name $app -ErrorAction SilentlyContinue
            if ($package) {
                Write-Host "Removing $app..." -ForegroundColor Yellow
                $package | Remove-AppxPackage -ErrorAction Stop | Out-Null
                
                # Also remove provisioned package if it exists
                $provPackage = Get-AppxProvisionedPackage -Online | Where-Object DisplayName -like $app
                if ($provPackage) {
                    $provPackage | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Out-Null
                }
                Write-Host "Successfully removed $app" -ForegroundColor Green
            } else {
                Write-Host "Skipping $app (not installed)" -ForegroundColor Gray
            }
        } catch {
            Write-Host "Failed to remove $app : $_" -ForegroundColor Red
            continue
        }
    }

    # Disable Windows features
    Write-Host "`nDisabling unnecessary Windows features..." -ForegroundColor Yellow
    $windowsFeatures = @(
        #"WindowsMediaPlayer"
        "Internet-Explorer-Optional-*"
        "WorkFolders-Client"
    )

    foreach ($feature in $windowsFeatures) {
        try {
            Write-Host "Disabling Windows feature: $feature..." -ForegroundColor Yellow
            $result = Disable-WindowsOptionalFeature -Online -FeatureName $feature -NoRestart -ErrorAction Stop
            if ($result.RestartNeeded) {
                Write-Host "Restart required after disabling $feature" -ForegroundColor Yellow
            } else {
                Write-Host "Successfully disabled $feature" -ForegroundColor Green
            }
        } catch {
            Write-Host "Failed to disable feature $feature : $_" -ForegroundColor Red
            continue
        }
    }

    # Disable telemetry tasks
    Write-Host "`nDisabling telemetry tasks..." -ForegroundColor Yellow
    $tasks = @(
        "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser"
        "\Microsoft\Windows\Application Experience\ProgramDataUpdater"
        "\Microsoft\Windows\Application Experience\StartupAppTask"
        "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator"
        "\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip"
        "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector"
    )

    foreach ($task in $tasks) {
        try {
            $taskObj = Get-ScheduledTask -TaskPath (Split-Path $task) -TaskName (Split-Path $task -Leaf) -ErrorAction SilentlyContinue
            if ($taskObj) {
                Write-Host "Disabling scheduled task: $task..." -ForegroundColor Yellow
                Disable-ScheduledTask -TaskPath (Split-Path $task) -TaskName (Split-Path $task -Leaf) -ErrorAction Stop | Out-Null
                Write-Host "Successfully disabled $task" -ForegroundColor Green
            } else {
                Write-Host "Skipping task $task (not found)" -ForegroundColor Gray
            }
        } catch {
            Write-Host "Failed to disable task $task : $_" -ForegroundColor Red
            continue
        }
    }

    # Remove third-party bloatware
    $thirdPartyBloat = @(
        "McAfee Security"
        "McAfee LiveSafe"
        "HP Support Assistant"
        "HP Customer Experience Enhancements"
        "HP Registration Service"
        "HP System Event Utility"
        "Lenovo Vantage"
        "Lenovo System Interface Foundation"
        "ASUS GiftBox"
        "ASUS WebStorage"
        "ASUS Live Update"
        "Dell Digital Delivery"
        "Dell Customer Connect"
        "Dell Update"
        "SupportAssist"
        "Dell SupportAssist OS Recovery"
    )

    foreach ($program in $thirdPartyBloat) {
        try {
            Write-Host "Removing $program..." -ForegroundColor Yellow
            $app = Get-WmiObject -Class Win32_Product -ErrorAction Stop | 
                Where-Object { $_.Name -like "*$program*" }
            if ($app) {
                $result = $app.Uninstall()
                if ($result.ReturnValue -eq 0) {
                    Write-Host "Successfully removed $program" -ForegroundColor Green
                } else {
                    throw "Uninstall returned error code: $($result.ReturnValue)"
                }
            } else {
                Write-Host "Skipping $program (not installed)" -ForegroundColor Gray
            }
        } catch {
            Write-Host "Failed to remove $program : $_" -ForegroundColor Red
            continue
        }
    }

    Write-Host "`nBloatware removal completed!" -ForegroundColor Green
    Write-Host "Note: Some changes may require a system restart to take effect" -ForegroundColor Yellow

} catch {
    Write-Host "Failed to remove bloatware: $_" -ForegroundColor Red
    exit 1
}

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
        try {
            Write-Host "Removing $app..." -ForegroundColor Yellow
            $package = Get-AppxPackage $app -AllUsers -ErrorAction Stop
            if ($package) {
                $package | Remove-AppxPackage -ErrorAction Stop | Out-Null
                Write-Host "Successfully removed $app" -ForegroundColor Green
            } else {
                Write-Host "Skipping $app (not installed)" -ForegroundColor Gray
            }
        } catch {
            Write-Host "Failed to remove $app : $_" -ForegroundColor Red
            continue
        }
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
        try {
            $tasks = Get-ScheduledTask -TaskPath $task -ErrorAction SilentlyContinue
            if ($tasks) {
                foreach ($t in $tasks) {
                    Write-Host "Removing task: $($t.TaskName)..." -ForegroundColor Yellow
                    Unregister-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -Confirm:$false -ErrorAction Stop
                    Write-Host "Successfully removed task: $($t.TaskName)" -ForegroundColor Green
                }
            }
        } catch {
            Write-Host "Failed to remove task $task : $_" -ForegroundColor Red
            continue
        }
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
        try {
            if (Test-Path $folder) {
                Write-Host "Removing folder: $folder..." -ForegroundColor Yellow
                Remove-Item -Path $folder -Recurse -Force -ErrorAction Stop
                Write-Host "Successfully removed folder: $folder" -ForegroundColor Green
            }
        } catch {
            Write-Host "Failed to remove folder $folder : $_" -ForegroundColor Red
            continue
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

# Disable Lenovo Universal Device Client Device drivers...
Write-Host "Disabling Lenovo Universal Device Client Device drivers..." -ForegroundColor Blue
try {
    # Get Lenovo UDC devices
    $lenovoDevices = Get-PnpDevice | Where-Object { 
        $_.FriendlyName -like "*Lenovo Universal Device*" -or 
        $_.InstanceId -like "*VEN_17EF*" -or  # Lenovo's Vendor ID
        $_.HardwareID -like "*LenovoUDC*" 
    }

    foreach ($device in $lenovoDevices) {
        Write-Host "Disabling device: $($device.FriendlyName)" -ForegroundColor Yellow
        $device | Disable-PnpDevice -Confirm:$false
        
        # Optionally prevent Windows from re-enabling it
        $instanceId = $device.InstanceId -replace "\\", "\\"
        $registryPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$instanceId"
        if (Test-Path $registryPath) {
            Set-ItemProperty -Path $registryPath -Name "ConfigFlags" -Value 0x1 -Type DWord
        }
    }

    Write-Host "Lenovo UDC devices disabled successfully" -ForegroundColor Green
} catch {
    Write-Host "Failed to disable Lenovo UDC devices: $_" -ForegroundColor Red
}

# Disable suggestion notifications
Write-Host "`nDisabling suggestion notifications..." -ForegroundColor Yellow

$suggestionSettings = @{
    # Windows Suggestions
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" = @{
        "SubscribedContent-338388Enabled" = 0  # Suggestions on Start
        "SubscribedContent-338389Enabled" = 0  # Suggestions in Settings
        "SubscribedContent-353694Enabled" = 0  # Timeline suggestions
        "SubscribedContent-353696Enabled" = 0  # Tips and tricks
        "SubscribedContent-338387Enabled" = 0  # App suggestions
        "SubscribedContent-310093Enabled" = 0  # General suggestions
        "SystemPaneSuggestionsEnabled" = 0     # System suggestions
        "SoftLandingEnabled" = 0               # Feature highlights
        "FeatureManagementEnabled" = 0         # Feature suggestions
        "ShowSyncProviderNotifications" = 0    # OneDrive suggestions
        "PreInstalledAppsEnabled" = 0          # Pre-installed apps suggestions
        "OemPreInstalledAppsEnabled" = 0       # OEM pre-installed apps suggestions
    }
    # Windows Explorer Suggestions
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" = @{
        "ShowSyncProviderNotifications" = 0    # OneDrive notifications
        "Start_TrackProgs" = 0                 # App launch tracking
        "ShowInfoTip" = 0                      # Item tooltips
    }
    # # Notification Settings
    # "HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings" = @{
    #     "NOC_GLOBAL_SETTING_ALLOW_TOASTS_ABOVE_LOCK" = 0  # Notifications above lock screen
    #     "NOC_GLOBAL_SETTING_ALLOW_CRITICAL_TOASTS_ABOVE_LOCK" = 0  # Critical notifications above lock screen
    #     "NOC_GLOBAL_SETTING_ALLOW_NOTIFICATION_SOUND" = 0  # Notification sounds
    # }
    # Notification Settings
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.Suggested" = @{
        "Enabled" = 0                          # System suggested toast notifications
    }
    # # System Notifications
    # "HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications" = @{
    #     "ToastEnabled" = 0                     # Toast notifications
    #     "NoToastApplicationNotification" = 1    # App notifications
    #     "NoTileApplicationNotification" = 1     # Tile notifications
    # }
    # Start Menu Suggestions
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Start" = @{
        "ShowAppsList" = 0                     # App suggestions in Start
    }
    # # Lock Screen Suggestions
    # "HKCU:\Software\Microsoft\Windows\CurrentVersion\Lock Screen" = @{
    #     "SlideshowEnabled" = 0                 # Lock screen slideshow
    # }
    # Microsoft Store Suggestions
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Store" = @{
        "AutoDownload" = 2                     # Disable automatic app updates
    }
    # Edge Browser Suggestions
    "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppContainer\Storage\microsoft.microsoftedge_8wekyb3d8bbwe\MicrosoftEdge\ServiceUI" = @{
        "EnableCortana" = 0                    # Cortana in Edge
        "ShowSearchSuggestionsGlobal" = 0      # Search suggestions
    }
    # Windows Tips
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\SuggestedApps" = @{
        "DisableAutoInstall" = 1               # Disable auto-install of suggested apps
    }
}

foreach ($path in $suggestionSettings.Keys) {
    try {
        if (!(Test-Path $path)) {
            New-Item -Path $path -Force | Out-Null
        }
        
        $settings = $suggestionSettings[$path]
        foreach ($name in $settings.Keys) {
            Set-ItemProperty -Path $path -Name $name -Value $settings[$name] -Type DWord -ErrorAction Stop
            Write-Host "Disabled $name" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "Failed to set suggestion settings for $path : $_" -ForegroundColor Red
        continue
    }
}

# Disable Windows Spotlight
Write-Host "`nDisabling Windows Spotlight..." -ForegroundColor Yellow
try {
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "RotatingLockScreenEnabled" -Value 0 -Type DWord
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "RotatingLockScreenOverlayEnabled" -Value 0 -Type DWord
    Write-Host "Windows Spotlight disabled" -ForegroundColor Green
}
catch {
    Write-Host "Failed to disable Windows Spotlight: $_" -ForegroundColor Red
}
