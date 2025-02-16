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

function Restore-WSLSettings {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath
    )
    
    try {
        Write-Host "Restoring WSL Settings..." -ForegroundColor Blue
        $backupPath = Test-BackupPath -Path "WSL" -BackupType "WSL Settings"
        
        if ($backupPath) {
            # WSL config locations
            $wslConfigs = @{
                # Base WSL configuration
                "Config" = "/etc/wsl.conf"
                # Network configuration
                "Resolv" = "/etc/resolv.conf"
                # Host configuration
                "Hosts" = "/etc/hosts"
                # System configuration
                "Sysctl" = "/etc/sysctl.conf"
                # Package sources
                "Sources" = "/etc/apt/sources.list"
                # Package preferences
                "Preferences" = "/etc/apt/preferences"
                # Additional sources
                "SourcesD" = "/etc/apt/sources.list.d"
                # Package keyring
                "Keyring" = "/etc/apt/trusted.gpg"
                # Shell configuration
                "Bashrc" = "~/.bashrc"
                # Shell profile
                "Profile" = "~/.profile"
                # Shell aliases
                "Aliases" = "~/.bash_aliases"
                # Shell functions
                "Functions" = "~/.bash_functions"
            }

            # Restore WSL settings
            Write-Host "Checking WSL installation..." -ForegroundColor Yellow
            $wslFeatures = @(
                "Microsoft-Windows-Subsystem-Linux",
                "VirtualMachinePlatform"
            )
            
            foreach ($feature in $wslFeatures) {
                if (!(Get-WindowsOptionalFeature -Online -FeatureName $feature).State -eq "Enabled") {
                    Enable-WindowsOptionalFeature -Online -FeatureName $feature -NoRestart
                }
            }

            # Restore config files
            foreach ($config in $wslConfigs.GetEnumerator()) {
                $backupItem = Join-Path $backupPath $config.Key
                if (Test-Path $backupItem) {
                    # Create parent directory if needed
                    $parentDir = Split-Path -Parent $config.Value
                    wsl --exec mkdir -p $parentDir 2>/dev/null

                    if ((Get-Item $backupItem) -is [System.IO.DirectoryInfo]) {
                        # Skip temporary files during restore
                        $excludeFilter = @("*.tmp", "~*.*", "*.bak", "*.old")
                        Copy-Item $backupItem $config.Value -Recurse -Force -Exclude $excludeFilter
                    } else {
                        Copy-Item $backupItem $config.Value -Force
                    }
                    Write-Host "Restored configuration: $($config.Key)" -ForegroundColor Green

                    # Set correct permissions
                    if ($config.Key -like "*Sources*" -or $config.Key -eq "Keyring") {
                        wsl --exec chmod 644 $config.Value
                    } elseif ($config.Key -like "*rc" -or $config.Key -like "*Profile") {
                        wsl --exec chmod 600 $config.Value
                    }
                }
            }

            # Restore installed packages
            $packagesFile = Join-Path $backupPath "packages.list"
            if (Test-Path $packagesFile) {
                Write-Host "Restoring installed packages..." -ForegroundColor Yellow
                $packages = Get-Content $packagesFile
                wsl --exec apt-get update
                wsl --exec apt-get install -y $packages
            }

            # Restore WSL version and default distro settings
            $wslConfigFile = Join-Path $backupPath "wsl-config.json"
            if (Test-Path $wslConfigFile) {
                $wslConfig = Get-Content $wslConfigFile | ConvertFrom-Json
                if ($wslConfig.DefaultDistro) {
                    wsl --set-default $wslConfig.DefaultDistro
                }
                if ($wslConfig.Version -eq 2) {
                    wsl --set-version $wslConfig.DefaultDistro 2
                }
            }

            # Restore .wslconfig if it exists
            $wslConfigFile = "$backupPath\.wslconfig"
            if (Test-Path $wslConfigFile) {
                Copy-Item -Path $wslConfigFile -Destination "$env:USERPROFILE\.wslconfig" -Force
            }

            # Load WSL configuration
            $wslConfig = Get-Content "$backupPath\wsl_config.json" | ConvertFrom-Json

            # Ensure WSL features are enabled
            if ($wslConfig.WslVersion -eq "Enabled") {
                Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -NoRestart
            }
            if ($wslConfig.Wsl2Version -eq "Enabled") {
                Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart
            }

            # Restore Linux-side configurations
            Write-Host "Restoring Linux configurations..." -ForegroundColor Yellow
            
            # Copy files to temp location for WSL access
            if (Test-Path "$backupPath\.bashrc") {
                Copy-Item "$backupPath\.bashrc" "$env:USERPROFILE\.wsl_bashrc_temp" -Force
            }
            if (Test-Path "$backupPath\packages.list") {
                Copy-Item "$backupPath\packages.list" "$env:USERPROFILE\.wsl_packages_temp" -Force
            }
            if (Test-Path "$backupPath\sources.list") {
                Copy-Item "$backupPath\sources.list" "$env:USERPROFILE\.wsl_sources_temp" -Force
            }
            if (Test-Path "$backupPath\sources.list.d.tar.gz") {
                Copy-Item "$backupPath\sources.list.d.tar.gz" "$env:USERPROFILE\.wsl_sources_d_temp.tar.gz" -Force
            }
            if (Test-Path "$backupPath\etc.tar.gz") {
                Copy-Item "$backupPath\etc.tar.gz" "$env:USERPROFILE\.wsl_etc_temp.tar.gz" -Force
            }

            # Restore configurations inside WSL
            wsl -e bash -c @"
                # Restore bashrc
                if [ -f /mnt/c/Users/$env:USERNAME/.wsl_bashrc_temp ]; then
                    cp /mnt/c/Users/$env:USERNAME/.wsl_bashrc_temp ~/.bashrc
                    echo "Restored .bashrc"
                fi

                # Restore sources.list
                if [ -f /mnt/c/Users/$env:USERNAME/.wsl_sources_temp ]; then
                    sudo cp /mnt/c/Users/$env:USERNAME/.wsl_sources_temp /etc/apt/sources.list
                    echo "Restored sources.list"
                fi

                # Restore sources.list.d
                if [ -f /mnt/c/Users/$env:USERNAME/.wsl_sources_d_temp.tar.gz ]; then
                    sudo tar xzf /mnt/c/Users/$env:USERNAME/.wsl_sources_d_temp.tar.gz -C /
                    echo "Restored sources.list.d"
                fi

                # Restore etc configurations
                if [ -f /mnt/c/Users/$env:USERNAME/.wsl_etc_temp.tar.gz ]; then
                    sudo tar xzf /mnt/c/Users/$env:USERNAME/.wsl_etc_temp.tar.gz -C /etc
                    echo "Restored etc configurations"
                fi

                # Update package list
                sudo apt-get update

                # Install packages from backup list
                if [ -f /mnt/c/Users/$env:USERNAME/.wsl_packages_temp ]; then
                    echo "Installing backed up packages..."
                    while read package; do
                        if [ ! -z "\$package" ]; then
                            echo "Installing \$package..."
                            sudo apt-get install -y \$package || echo "Failed to install \$package"
                        fi
                    done < /mnt/c/Users/$env:USERNAME/.wsl_packages_temp
                fi
"@ -u root

            # Clean up temp files
            Remove-Item "$env:USERPROFILE\.wsl_*" -Force -ErrorAction SilentlyContinue

            # Restore WSL integration settings
            $wslIntegration = Get-Content "$backupPath\wsl_integration.json" | ConvertFrom-Json
            if ($wslIntegration.SystemdEnabled) {
                Write-Host "Enabling systemd..." -ForegroundColor Yellow
                wsl --update
                wsl --shutdown
            }

            # Set default distro if specified
            if ($wslConfig.DefaultDistro) {
                wsl --set-default $wslConfig.DefaultDistro
            }

            Write-Host "`nWSL Restore Summary:" -ForegroundColor Green
            Write-Host "WSL Version: Restored" -ForegroundColor Yellow
            Write-Host "WSL2 Support: Restored" -ForegroundColor Yellow
            Write-Host "Default Distro: $($wslConfig.DefaultDistro)" -ForegroundColor Yellow
            Write-Host "Linux Configs Restored:" -ForegroundColor Yellow
            Write-Host "  - Bashrc: Restored" -ForegroundColor Yellow
            Write-Host "  - Package List: Restored" -ForegroundColor Yellow
            Write-Host "  - Sources List: Restored" -ForegroundColor Yellow
            Write-Host "  - Etc Config: Restored" -ForegroundColor Yellow

            Write-Host "`nNote: A system restart may be required to complete WSL feature installation" -ForegroundColor Yellow
            Write-Host "WSL Settings restored successfully from: $backupPath" -ForegroundColor Green
            return $true
        }
        return $false
    } catch {
        Write-Host "Failed to restore WSL Settings: $_" -ForegroundColor Red
        return $false
    }
}

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Restore-WSLSettings -BackupRootPath $BackupRootPath
} 