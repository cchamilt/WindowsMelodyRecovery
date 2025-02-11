# Requires admin privileges
#Requires -RunAsAdministrator

# At the start after admin check
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path (Split-Path $scriptPath -Parent) "scripts\load-environment.ps1")

if (!(Load-Environment)) {
    Write-Host "Failed to load environment configuration" -ForegroundColor Red
    exit 1
}

try {
    Write-Host "Configuring Windows Defender..." -ForegroundColor Blue

    # Enable Windows Defender features
    Write-Host "Enabling Windows Defender features..." -ForegroundColor Yellow
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
    Write-Host "Configuring scan settings..." -ForegroundColor Yellow
    Set-MpPreference -ScanScheduleDay 0 # Every day
    Set-MpPreference -ScanScheduleTime 2 # 2 AM
    Set-MpPreference -ScanParameters 2 # Full scan
    Set-MpPreference -RemediationScheduleDay 0 # Every day
    Set-MpPreference -RemediationScheduleTime 2 # 2 AM
    Set-MpPreference -CheckForSignaturesBeforeRunningScan $true

    # Configure cloud protection
    Write-Host "Configuring cloud protection..." -ForegroundColor Yellow
    Set-MpPreference -MAPSReporting Advanced
    Set-MpPreference -SubmitSamplesConsent 1 # Send safe samples automatically

    # # Configure threat protection
    # Write-Host "Configuring threat protection..." -ForegroundColor Yellow
    # Set-MpPreference -HighThreatDefaultAction Remove
    # Set-MpPreference -ModerateThreatDefaultAction Remove
    # Set-MpPreference -LowThreatDefaultAction Remove
    # Set-MpPreference -SevereThreatDefaultAction Remove

    # Configure network protection
    Write-Host "Configuring network protection..." -ForegroundColor Yellow
    Set-MpPreference -EnableNetworkProtection Enabled

    # Configure controlled folder access
    Write-Host "Configuring controlled folder access..." -ForegroundColor Yellow
    Set-MpPreference -EnableControlledFolderAccess Enabled

    # # Configure attack surface reduction rules
    # Write-Host "Configuring attack surface reduction rules..." -ForegroundColor Yellow
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
    Write-Host "Updating Windows Defender signatures..." -ForegroundColor Yellow
    Update-MpSignature

    Write-Host "Windows Defender configuration completed!" -ForegroundColor Green
} catch {
    Write-Host "Failed to configure Windows Defender: $_" -ForegroundColor Red
    exit 1
}

# Minimize defender notifications
Write-Host "Minimizing defender notifications..." -ForegroundColor Yellow
Set-MpPreference -DisableNotifications $true

Write-Host "Windows Defender configuration completed!" -ForegroundColor Green

