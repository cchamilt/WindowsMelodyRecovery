# Setup-Defender.ps1 - Configure Windows Defender settings

function Enable-Defender {
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
    }
 catch {
        Write-Verbose "Using module configuration fallback"
    }

    try {
        Write-Information -MessageData "Configuring Windows Defender..." -InformationAction Continue

        # Enable Windows Defender features
        Write-Warning -Message "Enabling Windows Defender features..."
        Set-MpPreference -DisableRealtimeMonitoring $false
        Set-MpPreference -DisableIOAVProtection $false
        Set-MpPreference -DisableBehaviorMonitoring $false
        Set-MpPreference -DisableBlockAtFirstSeen $false
        Set-MpPreference -DisableEmailScanning $false
        Set-MpPreference -DisableRemovableDriveScanning $false
        Set-MpPreference -DisableScanningMappedNetworkDrivesForFullScan $false
        Set-MpPreference -DisableScanningNetworkFiles $false
        Set-MpPreference -DisableArchiveScanning $false

        # Configure scan settings
        Write-Warning -Message "Configuring scan settings..."
        Set-MpPreference -ScanScheduleDay 0 # Every day
        Set-MpPreference -ScanScheduleTime 2 # 2 AM
        Set-MpPreference -ScanParameters 2 # Full scan
        Set-MpPreference -RemediationScheduleDay 0 # Every day
        Set-MpPreference -RemediationScheduleTime 2 # 2 AM
        Set-MpPreference -CheckForSignaturesBeforeRunningScan $true

        # Configure cloud protection
        Write-Warning -Message "Configuring cloud protection..."
        Set-MpPreference -MAPSReporting Advanced
        Set-MpPreference -SubmitSamplesConsent 1 # Send safe samples automatically

        # # Configure threat protection
        # Write-Warning -Message "Configuring threat protection..."
        # Set-MpPreference -HighThreatDefaultAction Remove
        # Set-MpPreference -ModerateThreatDefaultAction Remove
        # Set-MpPreference -LowThreatDefaultAction Remove
        # Set-MpPreference -SevereThreatDefaultAction Remove

        # Configure network protection
        Write-Warning -Message "Configuring network protection..."
        Set-MpPreference -EnableNetworkProtection Enabled

        # Configure controlled folder access
        Write-Warning -Message "Configuring controlled folder access..."
        Set-MpPreference -EnableControlledFolderAccess Enabled

        # # Configure attack surface reduction rules
        # Write-Warning -Message "Configuring attack surface reduction rules..."
        # $asrRules = @(
        #     "BE9BA2D9-53EA-4CDC-84E5-9B1EEEE46550" # Block executable content from email client and webmail
        #     "D4F940AB-401B-4EFC-AADC-AD5F3C50688A" # Block Office applications from creating executable content
        #     "3B576869-A4EC-4529-8536-B80A7769E899" # Block Office applications from injecting code into other processes
        #     "75668C1F-73B5-4CF0-BB93-3ECF5CB7CC84" # Block Office applications from creating child processes
        #     "D3E037E1-3EB8-44C8-A917-57927947596D" # Block JavaScript or VBScript from launching downloaded executable content
        #     "5BEB7EFE-FD9A-4556-801D-275E5FFC04CC" # Block execution of potentially obfuscated scripts
        #     "92E97FA1-2EDF-4476-BDD6-9DD0B4DDDC7B" # Block Win32 API calls from Office macros
        #     "01443614-CD74-433A-B99E-2ECDC07BFC25" # Block executable files from running unless they meet a prevalence, age, or trusted list criterion
        #     "C1DB55AB-C21A-4637-BB3F-A12568109D35" # Use advanced protection against ransomware
        # )

        # foreach ($rule in $asrRules) {
        #     Set-MpPreference -AttackSurfaceReductionRules_Ids $rule -AttackSurfaceReductionRules_Actions Enabled
        # }

        # Update signatures
        Write-Warning -Message "Updating Windows Defender signatures..."
        Update-MpSignature

        # Minimize defender notifications
        Write-Warning -Message "Minimizing defender notifications..."
        # Suppress notifications using UI settings registry key
        $path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.SecurityAndMaintenance"
        if (!(Test-Path $path)) {
            New-Item -Path $path -Force | Out-Null
        }
        Set-ItemProperty -Path $path -Name "Enabled" -Value 0 -Type DWord

        # Also disable enhanced notifications if supported
        if ((Get-Command Set-MpPreference).Parameters.Keys -contains "DisableEnhancedNotifications") {
            Set-MpPreference -DisableEnhancedNotifications $true
        }

        Write-Information -MessageData "Windows Defender configuration completed!" -InformationAction Continue
        return $true

    }
 catch {
        Write-Error -Message "Failed to configure Windows Defender: $($_.Exception.Message)"
        return $false
    }
}














