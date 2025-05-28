[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$MachineBackupPath = $null,
    [Parameter(Mandatory=$false)]
    [string]$SharedBackupPath = $null
)

# Load environment if not provided
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path (Split-Path $scriptPath -Parent) "scripts\load-environment.ps1")

if (!$MachineBackupPath -or !$SharedBackupPath) {
    if (!(Load-Environment)) {
        Write-Host "Failed to load environment configuration" -ForegroundColor Red
        exit 1
    }
    $MachineBackupPath = "$env:BACKUP_ROOT\$env:MACHINE_NAME"
    $SharedBackupPath = "$env:BACKUP_ROOT\shared"
}

function Backup-WSLSettings {
    param(
        [Parameter(Mandatory=$true)]
        [string]$MachineBackupPath,
        [Parameter(Mandatory=$true)]
        [string]$SharedBackupPath
    )
    
    try {
        Write-Host "Backing up WSL Settings..." -ForegroundColor Blue
        $backupPath = Initialize-BackupDirectory -Path "WSL" -BackupType "WSL Settings" -BackupRootPath $MachineBackupPath
        
        if ($backupPath) {
            # Export WSL registry settings
            $regPaths = @(
                # WSL system settings
                "HKLM\SYSTEM\CurrentControlSet\Services\LxssManager",
                # WSL installation settings
                "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppX\AppxAllUserStore\Applications\Microsoft.WSL",
                # WSL user settings
                "HKCU\Software\Microsoft\Windows\CurrentVersion\Lxss",
                # WSL network settings
                "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Lxss"
            )

            # Check if WSL is installed
            $wslInstalled = $false
            foreach ($regPath in $regPaths) {
                if ($regPath -match '^HKLM\\' -and (Test-Path "Registry::HKEY_LOCAL_MACHINE\$($regPath.Substring(5))")) {
                    $wslInstalled = $true
                    break
                }
            }

            # Create registry backup directory
            $registryPath = Join-Path $backupPath "Registry"
            New-Item -ItemType Directory -Force -Path $registryPath | Out-Null

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
                        $regFile = Join-Path $registryPath "$($regPath.Split('\')[-1]).reg"
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

            # Export WSL configuration
            try {
                # Get WSL distribution list
                $wslOutput = wsl --list --verbose 2>&1
                if ($LASTEXITCODE -eq 0) {
                    $wslOutput | Out-File (Join-Path $backupPath "wsl-distributions.txt") -Force
                    
                    # Parse and save as JSON for easier restoration
                    $distros = $wslOutput | Select-Object -Skip 1 | Where-Object { $_ -match '\S' } | ForEach-Object {
                        $parts = -split $_.Trim()
                        if ($parts.Count -ge 3) {
                            @{
                                Name = $parts[0] -replace '\*$',''
                                State = $parts[1]
                                Version = $parts[2]
                                IsDefault = $_.Contains('*')
                            }
                        }
                    }
                    $distros | ConvertTo-Json | Out-File (Join-Path $backupPath "wsl-distributions.json") -Force
                }

                # Export network configuration for each distribution
                $distros | ForEach-Object {
                    $distroName = $_.Name
                    try {
                        $networkConfig = wsl -d $distroName -e ip addr show 2>&1
                        if ($LASTEXITCODE -eq 0) {
                            $networkConfig | Out-File (Join-Path $backupPath "network-config-$distroName.txt") -Force
                        }
                    } catch {
                        Write-Host "Warning: Could not export network config for $distroName" -ForegroundColor Yellow
                    }
                }

                # Export global WSL configuration
                $globalConfig = wsl --status 2>&1
                if ($LASTEXITCODE -eq 0) {
                    $globalConfig | Out-File (Join-Path $backupPath "wsl-status.txt") -Force
                }

                Write-Host "WSL configuration backed up successfully" -ForegroundColor Green

            } catch {
                Write-Host "Warning: Could not export WSL configuration - $($_.Exception.Message)" -ForegroundColor Yellow
            }

            # Export WSL integration settings
            try {
                $wslIntegration = @{}
                
                if (Test-Path "$env:USERPROFILE\.wslconfig") {
                    $wslIntegration.NetworkConfig = Get-Content "$env:USERPROFILE\.wslconfig" -ErrorAction Stop
                }
                
                $wslConfPath = "/etc/wsl.conf"
                if ((wsl.exe test -f $wslConfPath 2>$null) -eq $true) {
                    $wslIntegration.GlobalConfig = wsl.exe cat $wslConfPath 2>$null
                }
                
                if ($wslIntegration.Count -gt 0) {
                    $wslIntegration | ConvertTo-Json | Out-File "$backupPath\wsl_integration.json" -Force
                }
            } catch {
                Write-Host "Warning: Could not retrieve WSL integration settings" -ForegroundColor Yellow
            }

            # Create etc backup directory
            New-Item -ItemType Directory -Path "$backupPath\etc" -Force | Out-Null

            # Backup WSL Linux-side configs
            wsl -e bash -c @"
                if [ -f ~/.bashrc ]; then
                    cp ~/.bashrc /mnt/c/Users/$env:USERNAME/.wsl_bashrc_temp
                    echo "Bashrc copied successfully"
                else
                    echo "No .bashrc found"
                    exit 1
                fi

                # Get list of manually installed packages (excluding dependencies)
                echo "Exporting package list..."
                apt-mark showmanual > /mnt/c/Users/$env:USERNAME/.wsl_packages_temp
                
                # Backup important /etc configurations
                echo "Backing up system configurations..."
                cd /etc
                tar czf /mnt/c/Users/$env:USERNAME/.wsl_etc_temp.tar.gz \
                    apt/ \
                    bash.bashrc \
                    environment \
                    fstab \
                    hosts \
                    locale.gen \
                    passwd \
                    profile \
                    resolv.conf \
                    ssh/ \
                    sudoers \
                    timezone \
                    wsl.conf \
                    X11/ \
                    --exclude='*.old' \
                    --exclude='*.bak' \
                    --exclude='*~' \
                    2>/dev/null

                # Get list of all repositories
                echo "Exporting repository list..."
                cp /etc/apt/sources.list /mnt/c/Users/$env:USERNAME/.wsl_sources_temp
                if [ -d /etc/apt/sources.list.d ]; then
                    tar czf /mnt/c/Users/$env:USERNAME/.wsl_sources_d_temp.tar.gz /etc/apt/sources.list.d/
                fi
"@ -u root

            # Copy files from temp to backup location
            if (Test-Path "$env:USERPROFILE\.wsl_bashrc_temp") {
                Copy-Item "$env:USERPROFILE\.wsl_bashrc_temp" "$backupPath\.bashrc" -Force
                Remove-Item "$env:USERPROFILE\.wsl_bashrc_temp" -Force
            }
            
            if (Test-Path "$env:USERPROFILE\.wsl_packages_temp") {
                Copy-Item "$env:USERPROFILE\.wsl_packages_temp" "$backupPath\packages.list" -Force
                Remove-Item "$env:USERPROFILE\.wsl_packages_temp" -Force
            }
            
            if (Test-Path "$env:USERPROFILE\.wsl_sources_temp") {
                Copy-Item "$env:USERPROFILE\.wsl_sources_temp" "$backupPath\sources.list" -Force
                Remove-Item "$env:USERPROFILE\.wsl_sources_temp" -Force
            }
            
            if (Test-Path "$env:USERPROFILE\.wsl_sources_d_temp.tar.gz") {
                Copy-Item "$env:USERPROFILE\.wsl_sources_d_temp.tar.gz" "$backupPath\sources.list.d.tar.gz" -Force
                Remove-Item "$env:USERPROFILE\.wsl_sources_d_temp.tar.gz" -Force
            }

            if (Test-Path "$env:USERPROFILE\.wsl_etc_temp.tar.gz") {
                Copy-Item "$env:USERPROFILE\.wsl_etc_temp.tar.gz" "$backupPath\etc.tar.gz" -Force
                Remove-Item "$env:USERPROFILE\.wsl_etc_temp.tar.gz" -Force
            }

            # Output summary
            Write-Host "`nWSL Backup Summary:" -ForegroundColor Green
            Write-Host "WSL Version: $($wslConfig.WslVersion)" -ForegroundColor Yellow
            Write-Host "WSL2 Support: $($wslConfig.Wsl2Version)" -ForegroundColor Yellow
            Write-Host "Default Distro: $($wslConfig.DefaultDistro)" -ForegroundColor Yellow
            Write-Host "Installed Distros: $($distros.Count)" -ForegroundColor Yellow
            Write-Host "Systemd Enabled: $($wslIntegration.SystemdEnabled)" -ForegroundColor Yellow
            Write-Host "Linux Configs Backed Up:" -ForegroundColor Yellow
            Write-Host "  - Bashrc: $(Test-Path "$backupPath\.bashrc")" -ForegroundColor Yellow
            Write-Host "  - Package List: $(Test-Path "$backupPath\packages.list")" -ForegroundColor Yellow
            Write-Host "  - Sources List: $(Test-Path "$backupPath\sources.list")" -ForegroundColor Yellow
            Write-Host "  - Etc Config: $(Test-Path "$backupPath\etc.tar.gz")" -ForegroundColor Yellow
            
            Write-Host "WSL Settings backed up successfully to: $backupPath" -ForegroundColor Green
            return $true
        }
        return $false
    } catch {
        $errorRecord = $_
        $errorMessage = @(
            "Failed to backup WSL Settings"
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
    Backup-WSLSettings -MachineBackupPath $MachineBackupPath -SharedBackupPath $SharedBackupPath
} 