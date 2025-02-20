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

function Backup-WindowsFeatures {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath
    )
    
    try {
        Write-Host "Backing up Windows Features Settings..." -ForegroundColor Blue
        $backupPath = Initialize-BackupDirectory -Path "WindowsFeatures" -BackupType "Windows Features Settings" -BackupRootPath $BackupRootPath
        
        if ($backupPath) {
            # Export Windows Features registry settings
            $regPaths = @(
                # Windows Features settings
                "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OptionalFeatures",
                "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\OptionalComponents",
                
                # Component settings
                "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing",
                "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Features",
                
                # Feature staging and services
                "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\FeatureStaging",
                "HKLM\SYSTEM\CurrentControlSet\Services\TrustedInstaller"
            )

            foreach ($regPath in $regPaths) {
                # Check if registry key exists before trying to export
                $keyExists = $false
                if ($regPath -match '^HKCU\\') {
                    $keyExists = Test-Path "Registry::HKEY_CURRENT_USER\$($regPath.Substring(5))"
                } elseif ($regPath -match '^HKLM\\') {
                    $keyExists = Test-Path "Registry::HKEY_LOCAL_MACHINE\$($regPath.Substring(5))"
                }
                
                if ($keyExists) {
                    try {
                        $regFile = "$backupPath\$($regPath.Split('\')[-1]).reg"
                        $result = reg export $regPath $regFile /y 2>&1
                        if ($LASTEXITCODE -ne 0) {
                            Write-Host "Warning: Could not export registry key: $regPath" -ForegroundColor Yellow
                        }
                    } catch {
                        Write-Host "Warning: Failed to export registry key: $regPath" -ForegroundColor Yellow
                    }
                } else {
                    Write-Host "Registry key not found: $regPath" -ForegroundColor Yellow
                }
            }

            # Export Windows Optional Features
            try {
                # Get all features but save enabled ones separately for restore
                $allFeatures = Get-WindowsOptionalFeature -Online | Select-Object FeatureName, State
                $enabledFeatures = $allFeatures | Where-Object { $_.State -eq "Enabled" }
                
                $allFeatures | ConvertTo-Json | Out-File "$backupPath\optional_features.json" -Force
                $enabledFeatures | ConvertTo-Json | Out-File "$backupPath\enabled_features.json" -Force
                Write-Host "Windows Optional Features backed up successfully" -ForegroundColor Green
            } catch {
                Write-Host "Warning: Could not retrieve Windows Optional Features" -ForegroundColor Yellow
            }

            # Export Windows Capabilities
            try {
                # Get all capabilities but save installed ones separately for restore
                $allCapabilities = Get-WindowsCapability -Online | Select-Object Name, State
                $enabledCapabilities = $allCapabilities | Where-Object { $_.State -eq "Installed" }
                
                $allCapabilities | ConvertTo-Json | Out-File "$backupPath\capabilities.json" -Force
                $enabledCapabilities | ConvertTo-Json | Out-File "$backupPath\enabled_capabilities.json" -Force
                Write-Host "Windows Capabilities backed up successfully" -ForegroundColor Green
            } catch {
                Write-Host "Warning: Could not retrieve Windows Capabilities" -ForegroundColor Yellow
            }

            # Export Windows Features (Server)
            if ((Get-WmiObject -Class Win32_OperatingSystem).ProductType -ne 1) {
                $serverFeatures = Get-WindowsFeature | Where-Object { $_.Installed -eq $true }
                $serverFeatures | Select-Object Name, InstallState | ConvertTo-Json | Out-File "$backupPath\server_features.json" -Force
                Write-Host "Windows Server Features backed up successfully" -ForegroundColor Green
            }

            # Export DISM packages info
            $dismPackages = dism /online /get-packages /format:table
            $dismPackages | Out-File "$backupPath\dism_packages.txt" -Force

            # Export feature configuration
            $featureConfig = @{
                LastBackupDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                OptionalFeatureCount = ($allFeatures | Measure-Object).Count
                CapabilitiesCount = ($allCapabilities | Measure-Object).Count
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
        $errorRecord = $_
        $errorMessage = @(
            "Failed to backup [Feature]"
            "Error Message: $($errorRecord.Exception.Message)"
            "Error Type: $($errorRecord.Exception.GetType().FullName)"
            "Script Line Number: $($errorRecord.InvocationInfo.ScriptLineNumber)"
            "Script Name: $($errorRecord.InvocationInfo.ScriptName)"
            "Statement: $($errorRecord.InvocationInfo.Line.Trim())"
            if ($errorRecord.Exception.StackTrace) { "Stack Trace: $($errorRecord.Exception.StackTrace)" }
            if ($errorRecord.Exception.InnerException) { "Inner Exception: $($errorRecord.Exception.InnerException.Message)" }
        ) -join "`n"
        
        Write-Host $errorMessage -ForegroundColor Red
        return $false
    }
}

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Backup-WindowsFeaturesSettings -BackupRootPath $BackupRootPath
} 