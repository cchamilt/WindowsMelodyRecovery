# See Andrew S Taylor's blog for more information: https://andrewstaylor.com/2022/08/09/removing-bloatware-from-windows-10-11-via-script/
# This does some of the same stuff but not all of it.
# But want to keep copilot and some others

# Setup-RemoveBloat.ps1 - Remove unwanted pre-installed Windows applications and features

function Setup-RemoveBloat {
    [CmdletBinding()]
    param()

    # Check for admin privileges
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Warning "This function requires administrator privileges. Please run PowerShell as Administrator."
        return $false
    }

    # Load environment configuration (optional - module will use fallback configuration)
    try {
        Load-Environment | Out-Null
    } catch {
        Write-Verbose "Using module configuration fallback"
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
        $removedCount = 0
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
                    $removedCount++
                } else {
                    Write-Host "Skipping $app (not installed)" -ForegroundColor Gray
                }
            } catch {
                Write-Host "Failed to remove $app : $($_.Exception.Message)" -ForegroundColor Red
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

        $disabledFeatures = 0
        foreach ($feature in $windowsFeatures) {
            try {
                Write-Host "Disabling Windows feature: $feature..." -ForegroundColor Yellow
                $result = Disable-WindowsOptionalFeature -Online -FeatureName $feature -NoRestart -ErrorAction Stop
                if ($result.RestartNeeded) {
                    Write-Host "Restart required after disabling $feature" -ForegroundColor Yellow
                } else {
                    Write-Host "Successfully disabled $feature" -ForegroundColor Green
                }
                $disabledFeatures++
            } catch {
                Write-Host "Failed to disable feature $feature : $($_.Exception.Message)" -ForegroundColor Red
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

        $disabledTasks = 0
        foreach ($task in $tasks) {
            try {
                $taskObj = Get-ScheduledTask -TaskPath (Split-Path $task) -TaskName (Split-Path $task -Leaf) -ErrorAction SilentlyContinue
                if ($taskObj) {
                    Write-Host "Disabling scheduled task: $task..." -ForegroundColor Yellow
                    Disable-ScheduledTask -TaskPath (Split-Path $task) -TaskName (Split-Path $task -Leaf) -ErrorAction Stop | Out-Null
                    Write-Host "Successfully disabled $task" -ForegroundColor Green
                    $disabledTasks++
                } else {
                    Write-Host "Skipping task $task (not found)" -ForegroundColor Gray
                }
            } catch {
                Write-Host "Failed to disable task $task : $($_.Exception.Message)" -ForegroundColor Red
                continue
            }
        }

        # Remove third-party bloatware
        Write-Host "`nRemoving third-party bloatware..." -ForegroundColor Yellow
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

        $removedPrograms = 0
        foreach ($program in $thirdPartyBloat) {
            try {
                Write-Host "Checking for $program..." -ForegroundColor Yellow
                $app = Get-WmiObject -Class Win32_Product -ErrorAction Stop | 
                    Where-Object { $_.Name -like "*$program*" }
                if ($app) {
                    Write-Host "Removing $program..." -ForegroundColor Yellow
                    $result = $app.Uninstall()
                    if ($result.ReturnValue -eq 0) {
                        Write-Host "Successfully removed $program" -ForegroundColor Green
                        $removedPrograms++
                    } else {
                        throw "Uninstall returned error code: $($result.ReturnValue)"
                    }
                } else {
                    Write-Host "Skipping $program (not installed)" -ForegroundColor Gray
                }
            } catch {
                Write-Host "Failed to remove $program : $($_.Exception.Message)" -ForegroundColor Red
                continue
            }
        }

        # Remove Lenovo bloatware specifically
        Write-Host "`nRemoving Lenovo bloatware..." -ForegroundColor Blue
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

        $removedLenovo = 0
        foreach ($app in $lenovoApps) {
            try {
                $package = Get-AppxPackage -Name $app -AllUsers -ErrorAction SilentlyContinue
                if ($package) {
                    Write-Host "Removing Lenovo app: $app..." -ForegroundColor Yellow
                    $package | Remove-AppxPackage -ErrorAction Stop | Out-Null
                    
                    # Also remove provisioned package
                    $provPackage = Get-AppxProvisionedPackage -Online | Where-Object DisplayName -eq $app
                    if ($provPackage) {
                        $provPackage | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Out-Null
                    }
                    Write-Host "Successfully removed $app" -ForegroundColor Green
                    $removedLenovo++
                } else {
                    Write-Host "Skipping $app (not installed)" -ForegroundColor Gray
                }
            } catch {
                Write-Host "Failed to remove $app : $($_.Exception.Message)" -ForegroundColor Red
                continue
            }
        }

        # Additional Lenovo program removal
        Write-Host "`nRemoving additional Lenovo programs..." -ForegroundColor Yellow
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
        $installedPrograms = @()
        try {
            $installedPrograms += Get-WmiObject -Class Win32_Product -ErrorAction SilentlyContinue | Where-Object { $_.Vendor -like "*Lenovo*" }
            $installedPrograms += Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue | Where-Object { $_.Publisher -like "*Lenovo*" }
            $installedPrograms += Get-ItemProperty "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue | Where-Object { $_.Publisher -like "*Lenovo*" }
        } catch {
            Write-Host "Warning: Could not enumerate all installed programs" -ForegroundColor Yellow
        }

        # Uninstall programs
        foreach ($program in $installedPrograms) {
            if ($program.Name -in $lenovoPrograms -or $program.DisplayName -in $lenovoPrograms) {
                Write-Host "Uninstalling: $($program.Name)$($program.DisplayName)" -ForegroundColor Yellow
                
                try {
                    if ($program.UninstallString) {
                        $uninstallString = $program.UninstallString
                        if ($uninstallString -like "MsiExec.exe*") {
                            $productCode = $uninstallString -replace ".*({.*})", '$1'
                            Start-Process "msiexec.exe" -ArgumentList "/x $productCode /qn /norestart" -Wait -NoNewWindow
                        } else {
                            $uninstallString = $uninstallString -replace "/I", "/X"
                            Start-Process "cmd.exe" -ArgumentList "/c $uninstallString /quiet /norestart" -Wait -NoNewWindow
                        }
                        Write-Host "Successfully uninstalled $($program.Name)$($program.DisplayName)" -ForegroundColor Green
                    }
                } catch {
                    Write-Host "Failed to uninstall $($program.Name)$($program.DisplayName) : $($_.Exception.Message)" -ForegroundColor Red
                }
            }
        }

        # Stop and disable Lenovo services
        Write-Host "`nDisabling Lenovo services..." -ForegroundColor Yellow
        $lenovoServices = @(
            "LenovoVantageService",
            "LenovoSystemInterfaceFoundationService",
            "ImControllerService",
            "LenovoPlatformWatchdog",
            "LenovoDeviceExperienceService"
        )

        foreach ($service in $lenovoServices) {
            try {
                if (Get-Service -Name $service -ErrorAction SilentlyContinue) {
                    Stop-Service -Name $service -Force -ErrorAction Stop
                    Set-Service -Name $service -StartupType Disabled -ErrorAction Stop
                    Write-Host "Disabled service: $service" -ForegroundColor Green
                }
            } catch {
                Write-Host "Failed to disable service $service : $($_.Exception.Message)" -ForegroundColor Red
            }
        }

        # Remove Lenovo scheduled tasks
        Write-Host "`nRemoving Lenovo scheduled tasks..." -ForegroundColor Yellow
        $lenovoTasks = @(
            "\Lenovo\*",
            "\ImController\*"
        )

        foreach ($taskPath in $lenovoTasks) {
            try {
                $tasks = Get-ScheduledTask -TaskPath $taskPath -ErrorAction SilentlyContinue
                if ($tasks) {
                    foreach ($task in $tasks) {
                        Write-Host "Removing task: $($task.TaskName)..." -ForegroundColor Yellow
                        Unregister-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -Confirm:$false -ErrorAction Stop
                        Write-Host "Successfully removed task: $($task.TaskName)" -ForegroundColor Green
                    }
                }
            } catch {
                Write-Host "Failed to remove tasks from $taskPath : $($_.Exception.Message)" -ForegroundColor Red
                continue
            }
        }

        # Remove Lenovo folders
        Write-Host "`nRemoving Lenovo folders..." -ForegroundColor Yellow
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
                Write-Host "Failed to remove folder $folder : $($_.Exception.Message)" -ForegroundColor Red
                continue
            }
        }

        # Remove Lenovo UDC Service
        Write-Host "`nRemoving Lenovo UDC Service..." -ForegroundColor Yellow
        try {
            if (Get-Service -Name "UDCService" -ErrorAction SilentlyContinue) {
                Stop-Service -Name "UDCService" -Force -ErrorAction Stop
                Set-Service -Name "UDCService" -StartupType Disabled -ErrorAction Stop
                Write-Host "Disabled UDCService" -ForegroundColor Green
            }
        } catch {
            Write-Host "UDCService not found or already disabled" -ForegroundColor Gray
        }

        # Remove UDCService from registry
        try {
            if (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Services\UDCService") {
                Remove-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Services\UDCService" -Recurse -Force -ErrorAction Stop
                Write-Host "Removed UDCService registry entries" -ForegroundColor Green
            }
        } catch {
            Write-Host "UDCService registry entries not found" -ForegroundColor Gray
        }

        # Disable Lenovo Universal Device Client devices
        Write-Host "`nDisabling Lenovo UDC devices..." -ForegroundColor Yellow
        try {
            $lenovoDevices = Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { 
                $_.FriendlyName -like "*Lenovo Universal Device*" -or 
                $_.InstanceId -like "*VEN_17EF*" -or  # Lenovo's Vendor ID
                $_.HardwareID -like "*LenovoUDC*" 
            }

            foreach ($device in $lenovoDevices) {
                try {
                    Write-Host "Disabling device: $($device.FriendlyName)" -ForegroundColor Yellow
                    $device | Disable-PnpDevice -Confirm:$false -ErrorAction Stop
                    
                    # Prevent Windows from re-enabling it
                    $instanceId = $device.InstanceId -replace "\\", "\\"
                    $registryPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$instanceId"
                    if (Test-Path $registryPath) {
                        Set-ItemProperty -Path $registryPath -Name "ConfigFlags" -Value 0x1 -Type DWord -ErrorAction SilentlyContinue
                    }
                    Write-Host "Successfully disabled $($device.FriendlyName)" -ForegroundColor Green
                } catch {
                    Write-Host "Failed to disable device $($device.FriendlyName) : $($_.Exception.Message)" -ForegroundColor Red
                }
            }

            if ($lenovoDevices.Count -eq 0) {
                Write-Host "No Lenovo UDC devices found" -ForegroundColor Gray
            } else {
                Write-Host "Lenovo UDC devices processing completed" -ForegroundColor Green
            }
        } catch {
            Write-Host "Failed to process Lenovo UDC devices: $($_.Exception.Message)" -ForegroundColor Red
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
            # Notification Settings
            "HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.Suggested" = @{
                "Enabled" = 0                          # System suggested toast notifications
            }
            # Start Menu Suggestions
            "HKCU:\Software\Microsoft\Windows\CurrentVersion\Start" = @{
                "ShowAppsList" = 0                     # App suggestions in Start
            }
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

        $disabledSuggestions = 0
        foreach ($path in $suggestionSettings.Keys) {
            try {
                if (!(Test-Path $path)) {
                    New-Item -Path $path -Force | Out-Null
                }
                
                $settings = $suggestionSettings[$path]
                foreach ($name in $settings.Keys) {
                    Set-ItemProperty -Path $path -Name $name -Value $settings[$name] -Type DWord -ErrorAction Stop
                    Write-Host "Disabled $name" -ForegroundColor Green
                    $disabledSuggestions++
                }
            }
            catch {
                Write-Host "Failed to set suggestion settings for $path : $($_.Exception.Message)" -ForegroundColor Red
                continue
            }
        }

        # Disable Windows Spotlight
        Write-Host "`nDisabling Windows Spotlight..." -ForegroundColor Yellow
        try {
            Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "RotatingLockScreenEnabled" -Value 0 -Type DWord -ErrorAction Stop
            Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "RotatingLockScreenOverlayEnabled" -Value 0 -Type DWord -ErrorAction Stop
            Write-Host "Windows Spotlight disabled" -ForegroundColor Green
        }
        catch {
            Write-Host "Failed to disable Windows Spotlight: $($_.Exception.Message)" -ForegroundColor Red
        }

        Write-Host "`nBloatware removal completed!" -ForegroundColor Green
        Write-Host "Summary:" -ForegroundColor Cyan
        Write-Host "- Removed $removedCount Windows Store apps" -ForegroundColor White
        Write-Host "- Disabled $disabledFeatures Windows features" -ForegroundColor White
        Write-Host "- Disabled $disabledTasks telemetry tasks" -ForegroundColor White
        Write-Host "- Removed $removedPrograms third-party programs" -ForegroundColor White
        Write-Host "- Removed $removedLenovo Lenovo apps" -ForegroundColor White
        Write-Host "- Disabled $disabledSuggestions suggestion settings" -ForegroundColor White
        Write-Host "- Processed Lenovo services, tasks, folders, and devices" -ForegroundColor White
        Write-Host "Note: Some changes may require a system restart to take effect" -ForegroundColor Yellow
        return $true

    } catch {
        Write-Host "Failed to remove bloatware: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

