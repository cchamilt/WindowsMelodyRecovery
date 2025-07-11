# See Andrew S Taylor's blog for more information: https://andrewstaylor.com/2022/08/09/removing-bloatware-from-windows-10-11-via-script/
# This does some of the same stuff but not all of it.
# But want to keep copilot and some others

# Remove-Bloat.ps1 - Remove unwanted pre-installed Windows applications and features

function Remove-Bloat {
    [CmdletBinding()]
    param()

    # Check for admin privileges
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Warning "This function requires administrator privileges. Please run PowerShell as Administrator."
        return $false
    }

    # Load environment configuration (optional - module will use fallback configuration)
    try {
        Import-Environment | Out-Null
    } catch {
        Write-Verbose "Using module configuration fallback"
    }

    try {
        Write-Information -MessageData "Starting Windows bloatware removal..." -InformationAction Continue

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
                    Write-Warning -Message "Removing $app..."
                    $package | Remove-AppxPackage -ErrorAction Stop | Out-Null

                    # Also remove provisioned package if it exists
                    $provPackage = Get-AppxProvisionedPackage -Online | Where-Object DisplayName -like $app
                    if ($provPackage) {
                        $provPackage | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Out-Null
                    }
                    Write-Information -MessageData "Successfully removed $app" -InformationAction Continue
                    $removedCount++
                } else {
                    Write-Verbose -Message "Skipping $app (not installed)"
                }
            } catch {
                Write-Error -Message "Failed to remove $app : $($_.Exception.Message)"
                continue
            }
        }

        # Disable Windows features
        Write-Warning -Message "`nDisabling unnecessary Windows features..."
        $windowsFeatures = @(
            #"WindowsMediaPlayer"
            "Internet-Explorer-Optional-*"
            "WorkFolders-Client"
        )

        $disabledFeatures = 0
        foreach ($feature in $windowsFeatures) {
            try {
                Write-Warning -Message "Disabling Windows feature: $feature..."
                $result = Disable-WindowsOptionalFeature -Online -FeatureName $feature -NoRestart -ErrorAction Stop
                if ($result.RestartNeeded) {
                    Write-Warning -Message "Restart required after disabling $feature"
                } else {
                    Write-Information -MessageData "Successfully disabled $feature" -InformationAction Continue
                }
                $disabledFeatures++
            } catch {
                Write-Error -Message "Failed to disable feature $feature : $($_.Exception.Message)"
                continue
            }
        }

        # Disable telemetry tasks
        Write-Warning -Message "`nDisabling telemetry tasks..."
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
                    Write-Warning -Message "Disabling scheduled task: $task..."
                    Disable-ScheduledTask -TaskPath (Split-Path $task) -TaskName (Split-Path $task -Leaf) -ErrorAction Stop | Out-Null
                    Write-Information -MessageData "Successfully disabled $task" -InformationAction Continue
                    $disabledTasks++
                } else {
                    Write-Verbose -Message "Skipping task $task (not found)"
                }
            } catch {
                Write-Error -Message "Failed to disable task $task : $($_.Exception.Message)"
                continue
            }
        }

        # Remove third-party bloatware
        Write-Warning -Message "`nRemoving third-party bloatware..."
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
                Write-Warning -Message "Checking for $program..."
                $app = Get-WmiObject -Class Win32_Product -ErrorAction Stop |
                    Where-Object { $_.Name -like "*$program*" }
                if ($app) {
                    Write-Warning -Message "Removing $program..."
                    $result = $app.Uninstall()
                    if ($result.ReturnValue -eq 0) {
                        Write-Information -MessageData "Successfully removed $program" -InformationAction Continue
                        $removedPrograms++
                    } else {
                        throw "Uninstall returned error code: $($result.ReturnValue)"
                    }
                } else {
                    Write-Verbose -Message "Skipping $program (not installed)"
                }
            } catch {
                Write-Error -Message "Failed to remove $program : $($_.Exception.Message)"
                continue
            }
        }

        # Remove Lenovo bloatware specifically
        Write-Information -MessageData "`nRemoving Lenovo bloatware..." -InformationAction Continue
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
                    Write-Warning -Message "Removing Lenovo app: $app..."
                    $package | Remove-AppxPackage -ErrorAction Stop | Out-Null

                    # Also remove provisioned package
                    $provPackage = Get-AppxProvisionedPackage -Online | Where-Object DisplayName -eq $app
                    if ($provPackage) {
                        $provPackage | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Out-Null
                    }
                    Write-Information -MessageData "Successfully removed $app" -InformationAction Continue
                    $removedLenovo++
                } else {
                    Write-Verbose -Message "Skipping $app (not installed)"
                }
            } catch {
                Write-Error -Message "Failed to remove $app : $($_.Exception.Message)"
                continue
            }
        }

        # Additional Lenovo program removal
        Write-Warning -Message "`nRemoving additional Lenovo programs..."
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
            Write-Warning -Message "Warning: Could not enumerate all installed programs"
        }

        # Uninstall programs
        foreach ($program in $installedPrograms) {
            if ($program.Name -in $lenovoPrograms -or $program.DisplayName -in $lenovoPrograms) {
                Write-Warning -Message "Uninstalling: $($program.Name)$($program.DisplayName)"

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
                        Write-Information -MessageData "Successfully uninstalled $($program.Name)$($program.DisplayName)" -InformationAction Continue
                    }
                } catch {
                    Write-Error -Message "Failed to uninstall $($program.Name)$($program.DisplayName) : $($_.Exception.Message)"
                }
            }
        }

        # Stop and disable Lenovo services
        Write-Warning -Message "`nDisabling Lenovo services..."
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
                    Write-Information -MessageData "Disabled service: $service" -InformationAction Continue
                }
            } catch {
                Write-Error -Message "Failed to disable service $service : $($_.Exception.Message)"
            }
        }

        # Remove Lenovo scheduled tasks
        Write-Warning -Message "`nRemoving Lenovo scheduled tasks..."
        $lenovoTasks = @(
            "\Lenovo\*",
            "\ImController\*"
        )

        foreach ($taskPath in $lenovoTasks) {
            try {
                $tasks = Get-ScheduledTask -TaskPath $taskPath -ErrorAction SilentlyContinue
                if ($tasks) {
                    foreach ($task in $tasks) {
                        Write-Warning -Message "Removing task: $($task.TaskName)..."
                        Unregister-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -Confirm:$false -ErrorAction Stop
                        Write-Information -MessageData "Successfully removed task: $($task.TaskName)" -InformationAction Continue
                    }
                }
            } catch {
                Write-Error -Message "Failed to remove tasks from $taskPath : $($_.Exception.Message)"
                continue
            }
        }

        # Remove Lenovo folders
        Write-Warning -Message "`nRemoving Lenovo folders..."
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
                    Write-Warning -Message "Removing folder: $folder..."
                    Remove-Item -Path $folder -Recurse -Force -ErrorAction Stop
                    Write-Information -MessageData "Successfully removed folder: $folder" -InformationAction Continue
                }
            } catch {
                Write-Error -Message "Failed to remove folder $folder : $($_.Exception.Message)"
                continue
            }
        }

        # Remove Lenovo UDC Service
        Write-Warning -Message "`nRemoving Lenovo UDC Service..."
        try {
            if (Get-Service -Name "UDCService" -ErrorAction SilentlyContinue) {
                Stop-Service -Name "UDCService" -Force -ErrorAction Stop
                Set-Service -Name "UDCService" -StartupType Disabled -ErrorAction Stop
                Write-Information -MessageData "Disabled UDCService" -InformationAction Continue
            }
        } catch {
            Write-Verbose -Message "UDCService not found or already disabled"
        }

        # Remove UDCService from registry
        try {
            if (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Services\UDCService") {
                Remove-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Services\UDCService" -Recurse -Force -ErrorAction Stop
                Write-Information -MessageData "Removed UDCService registry entries" -InformationAction Continue
            }
        } catch {
            Write-Verbose -Message "UDCService registry entries not found"
        }

        # Disable Lenovo Universal Device Client devices
        Write-Warning -Message "`nDisabling Lenovo UDC devices..."
        try {
            $lenovoDevices = Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object {
                $_.FriendlyName -like "*Lenovo Universal Device*" -or
                $_.InstanceId -like "*VEN_17EF*" -or  # Lenovo's Vendor ID
                $_.HardwareID -like "*LenovoUDC*"
            }

            foreach ($device in $lenovoDevices) {
                try {
                    Write-Warning -Message "Disabling device: $($device.FriendlyName)"
                    $device | Disable-PnpDevice -Confirm:$false -ErrorAction Stop

                    # Prevent Windows from re-enabling it
                    $instanceId = $device.InstanceId -replace "\\", "\\"
                    $registryPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$instanceId"
                    if (Test-Path $registryPath) {
                        Set-ItemProperty -Path $registryPath -Name "ConfigFlags" -Value 0x1 -Type DWord -ErrorAction SilentlyContinue
                    }
                    Write-Information -MessageData "Successfully disabled $($device.FriendlyName)" -InformationAction Continue
                } catch {
                    Write-Error -Message "Failed to disable device $($device.FriendlyName) : $($_.Exception.Message)"
                }
            }

            if ($lenovoDevices.Count -eq 0) {
                Write-Verbose -Message "No Lenovo UDC devices found"
            } else {
                Write-Information -MessageData "Lenovo UDC devices processing completed" -InformationAction Continue
            }
        } catch {
            Write-Error -Message "Failed to process Lenovo UDC devices: $($_.Exception.Message)"
        }

        # Disable suggestion notifications
        Write-Warning -Message "`nDisabling suggestion notifications..."
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
                    Write-Information -MessageData "Disabled $name" -InformationAction Continue
                    $disabledSuggestions++
                }
            }
            catch {
                Write-Error -Message "Failed to set suggestion settings for $path : $($_.Exception.Message)"
                continue
            }
        }

        # Disable Windows Spotlight
        Write-Warning -Message "`nDisabling Windows Spotlight..."
        try {
            Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "RotatingLockScreenEnabled" -Value 0 -Type DWord -ErrorAction Stop
            Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "RotatingLockScreenOverlayEnabled" -Value 0 -Type DWord -ErrorAction Stop
            Write-Information -MessageData "Windows Spotlight disabled" -InformationAction Continue
        }
        catch {
            Write-Error -Message "Failed to disable Windows Spotlight: $($_.Exception.Message)"
        }

        Write-Information -MessageData "`nBloatware removal completed!" -InformationAction Continue
        Write-Information -MessageData "Summary:" -InformationAction Continue
        Write-Information -MessageData " -InformationAction Continue- Removed $removedCount Windows Store apps" -ForegroundColor White
        Write-Information -MessageData " -InformationAction Continue- Disabled $disabledFeatures Windows features" -ForegroundColor White
        Write-Information -MessageData " -InformationAction Continue- Disabled $disabledTasks telemetry tasks" -ForegroundColor White
        Write-Information -MessageData " -InformationAction Continue- Removed $removedPrograms third-party programs" -ForegroundColor White
        Write-Information -MessageData " -InformationAction Continue- Removed $removedLenovo Lenovo apps" -ForegroundColor White
        Write-Information -MessageData " -InformationAction Continue- Disabled $disabledSuggestions suggestion settings" -ForegroundColor White
        Write-Information -MessageData " -InformationAction Continue- Processed Lenovo services, tasks, folders, and devices" -ForegroundColor White
        Write-Warning -Message "Note: Some changes may require a system restart to take effect"
        return $true

    } catch {
        Write-Error -Message "Failed to remove bloatware: $($_.Exception.Message)"
        return $false
    }
}














