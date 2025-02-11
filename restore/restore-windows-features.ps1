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
            # Import registry settings first
            $regFiles = Get-ChildItem -Path $backupPath -Filter "*.reg"
            foreach ($regFile in $regFiles) {
                reg import $regFile.FullName | Out-Null
            }

            # Load feature configuration
            $featureConfig = Get-Content "$backupPath\feature_config.json" | ConvertFrom-Json
            $isServer = ((Get-WmiObject -Class Win32_OperatingSystem).ProductType -ne 1)

            # Verify OS compatibility
            if ($isServer -ne $featureConfig.IsServer) {
                Write-Host "Warning: Backup was made on a different Windows edition (Server/Client mismatch)" -ForegroundColor Yellow
            }

            # Restore Windows Optional Features
            $featuresFile = "$backupPath\enabled_features.json"
            if (Test-Path $featuresFile) {
                $features = Get-Content $featuresFile | ConvertFrom-Json
                foreach ($feature in $features) {
                    $currentState = Get-WindowsOptionalFeature -Online -FeatureName $feature.FeatureName
                    if ($currentState.State -ne "Enabled") {
                        Write-Host "Enabling feature: $($feature.FeatureName)" -ForegroundColor Yellow
                        Enable-WindowsOptionalFeature -Online -FeatureName $feature.FeatureName -NoRestart
                    }
                }
                Write-Host "Windows Optional Features restored successfully" -ForegroundColor Green
            }

            # Restore Windows Capabilities
            $capabilitiesFile = "$backupPath\enabled_capabilities.json"
            if (Test-Path $capabilitiesFile) {
                $capabilities = Get-Content $capabilitiesFile | ConvertFrom-Json
                foreach ($capability in $capabilities) {
                    $currentState = Get-WindowsCapability -Online -Name $capability.Name
                    if ($currentState.State -ne "Installed") {
                        Write-Host "Adding capability: $($capability.Name)" -ForegroundColor Yellow
                        Add-WindowsCapability -Online -Name $capability.Name -NoRestart
                    }
                }
                Write-Host "Windows Capabilities restored successfully" -ForegroundColor Green
            }

            # Restore Windows Server Features if applicable
            if ($isServer) {
                $serverFeaturesFile = "$backupPath\server_features.json"
                if (Test-Path $serverFeaturesFile) {
                    $serverFeatures = Get-Content $serverFeaturesFile | ConvertFrom-Json
                    $featuresToInstall = $serverFeatures | Where-Object { $_.InstallState -eq "Installed" } | Select-Object -ExpandProperty Name
                    if ($featuresToInstall) {
                        Write-Host "Installing Server Features..." -ForegroundColor Yellow
                        Install-WindowsFeature -Name $featuresToInstall -NoRestart
                    }
                    Write-Host "Windows Server Features restored successfully" -ForegroundColor Green
                }
            }

            # Output summary
            Write-Host "`nWindows Features Restore Summary:" -ForegroundColor Green
            Write-Host "Optional Features Processed: $($features.Count)" -ForegroundColor Yellow
            Write-Host "Capabilities Processed: $($capabilities.Count)" -ForegroundColor Yellow
            if ($isServer) {
                Write-Host "Server Features Processed: $($serverFeatures.Count)" -ForegroundColor Yellow
            }

            Write-Host "`nNote: A system restart may be required to complete the feature installation" -ForegroundColor Yellow
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