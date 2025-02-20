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

function Restore-WSLSSHSettings {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath
    )
    
    try {
        Write-Host "Restoring WSL SSH Settings..." -ForegroundColor Blue
        $backupPath = Test-BackupPath -Path "WSLSSH" -BackupType "WSL SSH Settings"
        
        if ($backupPath) {
            # WSL-SSH config locations
            $wslSshConfigs = @{
                # WSL SSH configuration
                "Config" = "/etc/ssh/ssh_config"
                # WSL SSH server configuration
                "SshdConfig" = "/etc/ssh/sshd_config"
                # WSL SSH host keys
                "HostKeys" = "/etc/ssh/ssh_host_*"
                # WSL SSH known hosts
                "KnownHosts" = "~/.ssh/known_hosts"
                # WSL SSH authorized keys
                "AuthorizedKeys" = "~/.ssh/authorized_keys"
                # WSL SSH private keys
                "Keys" = "~/.ssh/id_*"
                # WSL SSH public keys
                "PublicKeys" = "~/.ssh/*.pub"
                # WSL SSH config directory
                "ConfigDir" = "~/.ssh/config.d"
            }

            # Restore WSL-SSH settings
            Write-Host "Checking WSL and SSH installation..." -ForegroundColor Yellow
            
            # Check WSL installation
            $wslFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux
            if ($wslFeature.State -ne "Enabled") {
                Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -NoRestart
            }

            # Check SSH service in WSL
            wsl --exec service ssh status
            if ($LASTEXITCODE -ne 0) {
                Write-Host "Installing SSH server in WSL..." -ForegroundColor Yellow
                wsl --exec apt-get update
                wsl --exec apt-get install -y openssh-server
            }

            # Restore config files
            foreach ($config in $wslSshConfigs.GetEnumerator()) {
                $backupItem = Join-Path $backupPath $config.Key
                if (Test-Path $backupItem) {
                    Write-Host "Restoring $($config.Key) settings..." -ForegroundColor Yellow
                    
                    # Create parent directory in WSL
                    $parentDir = Split-Path -Parent $config.Value
                    wsl --exec mkdir -p $parentDir 2>/dev/null

                    if ((Get-Item $backupItem) -is [System.IO.DirectoryInfo]) {
                        # Skip temporary files during restore
                        $excludeFilter = @("*.tmp", "~*.*", "*.old", "*.bak")
                        Copy-Item $backupItem $config.Value -Recurse -Force -Exclude $excludeFilter
                    } else {
                        Copy-Item $backupItem $config.Value -Force
                    }

                    # Set correct permissions
                    if ($config.Key -like "*Keys*" -or $config.Key -eq "AuthorizedKeys") {
                        wsl --exec chmod 600 $config.Value
                    } elseif ($config.Key -like "Config*") {
                        wsl --exec chmod 644 $config.Value
                    }

                    Write-Host "Restored configuration: $($config.Key)" -ForegroundColor Green
                }
            }

            # Restart SSH service in WSL
            Write-Host "Restarting SSH service in WSL..." -ForegroundColor Yellow
            wsl --exec service ssh restart

            # Clean up temp files
            Remove-Item "$env:USERPROFILE\.wsl_*" -Force -ErrorAction SilentlyContinue

            Write-Host "`nWSL SSH Restore Summary:" -ForegroundColor Green
            Write-Host "SSH Config: Restored" -ForegroundColor Yellow
            Write-Host "Public Keys: Restored" -ForegroundColor Yellow
            Write-Host "Private Keys: Restored" -ForegroundColor Yellow
            Write-Host "Known Hosts: Restored" -ForegroundColor Yellow
            Write-Host "System Config: Restored" -ForegroundColor Yellow
            Write-Host "Permissions: Restored" -ForegroundColor Yellow
            
            Write-Host "WSL SSH Settings restored successfully from: $backupPath" -ForegroundColor Green
            return $true
        }
        return $false
    } catch {
        Write-Host "Failed to restore WSL SSH Settings: $_" -ForegroundColor Red
        return $false
    }
}

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Restore-WSLSSHSettings -BackupRootPath $BackupRootPath
} 