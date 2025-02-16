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

function Restore-WindowsFeaturesSettings {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath
    )
    
    try {
        Write-Host "Restoring Windows Features Settings..." -ForegroundColor Blue
        $backupPath = Test-BackupPath -Path "WindowsFeatures" -BackupType "Windows Features Settings"
        
        if ($backupPath) {
            # Windows Features config locations
            $featureConfigs = @{
                # Windows Optional Features
                "OptionalFeatures" = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OptionalFeatures"
                # Windows Capabilities
                "Capabilities" = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\Packages"
                # Windows Subsystems
                "Subsystems" = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\Packages"
            }

            # Restore Windows Features
            Write-Host "Loading Windows Features configuration..." -ForegroundColor Yellow
            $featuresFile = Join-Path $backupPath "windows_features.json"
            if (Test-Path $featuresFile) {
                $features = Get-Content $featuresFile | ConvertFrom-Json

                # Install Windows Optional Features
                Write-Host "`nInstalling Windows Optional Features..." -ForegroundColor Yellow
                foreach ($feature in $features.OptionalFeatures) {
                    if ($feature.State -eq "Enabled") {
                        Write-Host "Enabling feature: $($feature.FeatureName)" -ForegroundColor Yellow
                        Enable-WindowsOptionalFeature -Online -FeatureName $feature.FeatureName -NoRestart
                    }
                }

                # Install Windows Capabilities
                Write-Host "`nInstalling Windows Capabilities..." -ForegroundColor Yellow
                foreach ($capability in $features.Capabilities) {
                    if ($capability.State -eq "Installed") {
                        Write-Host "Installing capability: $($capability.Name)" -ForegroundColor Yellow
                        Add-WindowsCapability -Online -Name $capability.Name
                    }
                }
            }

            # Restore registry settings
            foreach ($config in $featureConfigs.GetEnumerator()) {
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

            # Check for pending reboot
            $rebootPending = $false
            if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") {
                $rebootPending = $true
            }
            if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") {
                $rebootPending = $true
            }

            if ($rebootPending) {
                Write-Host "`nWARNING: A system restart is required to complete feature installation" -ForegroundColor Yellow
            }

            # Output summary
            Write-Host "`nWindows Features Restore Summary:" -ForegroundColor Green
            Write-Host "Windows Features Settings restored successfully from: $backupPath" -ForegroundColor Green
            return $true
        }
        return $false
    } catch {
        Write-Host "Failed to restore Windows Features Settings: $_" -ForegroundColor Red
        return $false
    }
}

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Restore-WindowsFeaturesSettings -BackupRootPath $BackupRootPath
} 