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

function Restore-SSHSettings {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath
    )
    
    try {
        Write-Host "Restoring SSH Settings..." -ForegroundColor Blue
        $backupPath = Test-BackupPath -Path "SSH" -BackupType "SSH Settings"
        
        if ($backupPath) {
            # Import registry settings first
            $regFiles = Get-ChildItem -Path $backupPath -Filter "*.reg"
            foreach ($regFile in $regFiles) {
                reg import $regFile.FullName | Out-Null
            }

            # SSH config locations
            $sshConfigs = @{
                # Main SSH configuration
                "Config" = "$env:USERPROFILE\.ssh\config"
                # Known hosts
                "KnownHosts" = "$env:USERPROFILE\.ssh\known_hosts"
                # Private keys
                "Keys" = "$env:USERPROFILE\.ssh\id_*"
                # Public keys
                "PublicKeys" = "$env:USERPROFILE\.ssh\*.pub"
                # Authorized keys
                "AuthorizedKeys" = "$env:USERPROFILE\.ssh\authorized_keys"
                # SSH agent configuration
                "SshAgent" = "$env:USERPROFILE\.ssh\agent.conf"
                # Custom key configurations
                "KeyConfig" = "$env:USERPROFILE\.ssh\config.d"
                # System-wide SSH configuration
                "SystemConfig" = "$env:ProgramData\ssh\sshd_config"
            }

            # Restore SSH settings
            Write-Host "Checking SSH service installation..." -ForegroundColor Yellow
            $sshFeatures = @(
                "OpenSSH.Client~~~~0.0.1.0",
                "OpenSSH.Server~~~~0.0.1.0"
            )
            
            foreach ($feature in $sshFeatures) {
                if (!(Get-WindowsCapability -Online -Name $feature).State -eq "Installed") {
                    Add-WindowsCapability -Online -Name $feature
                }
            }

            # Restore config files
            foreach ($config in $sshConfigs.GetEnumerator()) {
                $backupItem = Join-Path $backupPath $config.Key
                if (Test-Path $backupItem) {
                    # Create parent directory if it doesn't exist
                    $parentDir = Split-Path $config.Value -Parent
                    if (!(Test-Path $parentDir)) {
                        New-Item -ItemType Directory -Force -Path $parentDir | Out-Null
                    }

                    if ((Get-Item $backupItem) -is [System.IO.DirectoryInfo]) {
                        # Skip temporary files during restore
                        $excludeFilter = @("*.tmp", "~*.*", "*.old", "*.bak")
                        Copy-Item $backupItem $config.Value -Recurse -Force -Exclude $excludeFilter
                    } else {
                        Copy-Item $backupItem $config.Value -Force
                    }
                    Write-Host "Restored configuration: $($config.Key)" -ForegroundColor Green

                    # Set correct permissions
                    if ($config.Key -like "*Keys*" -or $config.Key -eq "AuthorizedKeys") {
                        icacls $config.Value /inheritance:r
                        icacls $config.Value /grant:r "${env:USERNAME}:(R,W)"
                    }
                }
            }

            # Restore SSH service configuration
            $sshService = Get-Service -Name "sshd" -ErrorAction SilentlyContinue
            if ($sshService) {
                # Apply system-wide configuration
                $systemConfigFile = Join-Path $backupPath "SystemConfig\sshd_config"
                if (Test-Path $systemConfigFile) {
                    Copy-Item $systemConfigFile -Destination "$env:ProgramData\ssh\sshd_config" -Force
                    Write-Host "Restored system SSH configuration" -ForegroundColor Green
                }

                # Restart SSH service to apply changes
                Restart-Service -Name "sshd" -Force
            }
            
            Write-Host "SSH Settings restored successfully from: $backupPath" -ForegroundColor Green
            return $true
        }
        return $false
    } catch {
        Write-Host "Failed to restore SSH Settings: $_" -ForegroundColor Red
        return $false
    }
}

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Restore-SSHSettings -BackupRootPath $BackupRootPath
} 