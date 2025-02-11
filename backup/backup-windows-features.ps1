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

function Backup-WindowsFeaturesSettings {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath
    )
    
    try {
        Write-Host "Backing up Windows Features Settings..." -ForegroundColor Blue
        $backupPath = Initialize-BackupDirectory -Path "WindowsFeatures" -BackupType "Windows Features Settings" -BackupRootPath $BackupRootPath
        
        if ($backupPath) {
            # Export enabled Windows Features
            $enabledFeatures = Get-WindowsOptionalFeature -Online | Where-Object { $_.State -eq "Enabled" }
            $enabledFeatures | Select-Object FeatureName, State | ConvertTo-Json | Out-File "$backupPath\enabled_features.json" -Force
            Write-Host "Windows Optional Features backed up successfully" -ForegroundColor Green

            # Export enabled Windows Capabilities
            $enabledCapabilities = Get-WindowsCapability -Online | Where-Object { $_.State -eq "Installed" }
            $enabledCapabilities | Select-Object Name, State | ConvertTo-Json | Out-File "$backupPath\enabled_capabilities.json" -Force
            Write-Host "Windows Capabilities backed up successfully" -ForegroundColor Green

            # Export Windows Features (Server)
            if ((Get-WmiObject -Class Win32_OperatingSystem).ProductType -ne 1) {
                $serverFeatures = Get-WindowsFeature | Where-Object { $_.Installed -eq $true }
                $serverFeatures | Select-Object Name, InstallState | ConvertTo-Json | Out-File "$backupPath\server_features.json" -Force
                Write-Host "Windows Server Features backed up successfully" -ForegroundColor Green
            }

            # Export registry settings for features
            $regPaths = @(
                # Windows Features settings
                "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OptionalFeatures",
                "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\OptionalComponents",
                
                # Component settings
                "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing",
                
                # Feature store
                "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Features"
            )

            foreach ($regPath in $regPaths) {
                $regFile = "$backupPath\$($regPath.Split('\')[-1]).reg"
                reg export $regPath $regFile /y 2>$null
            }

            # Export DISM packages info
            $dismPackages = dism /online /get-packages /format:table
            $dismPackages | Out-File "$backupPath\dism_packages.txt" -Force

            # Export feature configuration
            $featureConfig = @{
                LastBackupDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                OptionalFeatureCount = ($enabledFeatures | Measure-Object).Count
                CapabilitiesCount = ($enabledCapabilities | Measure-Object).Count
                ServerFeaturesCount = if ($serverFeatures) { ($serverFeatures | Measure-Object).Count } else { 0 }
                OSVersion = [System.Environment]::OSVersion.Version.ToString()
                IsServer = ((Get-WmiObject -Class Win32_OperatingSystem).ProductType -ne 1)
            }
            $featureConfig | ConvertTo-Json | Out-File "$backupPath\feature_config.json" -Force

            # Output summary
            Write-Host "`nWindows Features Backup Summary:" -ForegroundColor Green
            Write-Host "Optional Features: $($featureConfig.OptionalFeatureCount)" -ForegroundColor Yellow
            Write-Host "Capabilities: $($featureConfig.CapabilitiesCount)" -ForegroundColor Yellow
            if ($featureConfig.IsServer) {
                Write-Host "Server Features: $($featureConfig.ServerFeaturesCount)" -ForegroundColor Yellow
            }
            
            Write-Host "Windows Features Settings backed up successfully to: $backupPath" -ForegroundColor Green
            return $true
        }
        return $false
    } catch {
        Write-Host "Failed to backup Windows Features Settings: $_" -ForegroundColor Red
        return $false
    }
}

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Backup-WindowsFeaturesSettings -BackupRootPath $BackupRootPath
} 