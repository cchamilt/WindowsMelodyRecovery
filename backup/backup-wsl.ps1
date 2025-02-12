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

function Backup-WSLSettings {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath
    )
    
    try {
        Write-Host "Backing up WSL Settings..." -ForegroundColor Blue
        $backupPath = Initialize-BackupDirectory -Path "WSL" -BackupType "WSL Settings" -BackupRootPath $BackupRootPath
        
        if ($backupPath) {
            # Export WSL registry settings
            $regPaths = @(
                # WSL settings
                "HKCU\Software\Microsoft\Windows\CurrentVersion\Lxss",
                "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Lxss",
                
                # WSL network settings
                "HKLM\SYSTEM\CurrentControlSet\Services\LxssManager",
                
                # WSL feature settings
                "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppX\AppxAllUserStore\Applications\Microsoft.WSL"
            )

            foreach ($regPath in $regPaths) {
                $regFile = "$backupPath\$($regPath.Split('\')[-1]).reg"
                reg export $regPath $regFile /y 2>$null
            }

            # Export WSL distro list and settings
            $wslDistros = wsl --list --verbose
            $wslDistros | Out-File "$backupPath\wsl_distros.txt" -Force

            # Export WSL global settings
            $wslConfig = @{
                GlobalSettings = wsl --status
                DefaultDistro = wsl --get-default
                WslVersion = (Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux).State
                Wsl2Version = (Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform).State
            }
            $wslConfig | ConvertTo-Json | Out-File "$backupPath\wsl_config.json" -Force

            # Export installed distros details
            $distros = @()
            $wslList = wsl --list --verbose | Select-Object -Skip 1 | ForEach-Object {
                $line = $_ -split '\s+'
                if ($line.Count -ge 3) {
                    $distros += @{
                        Name = $line[-1]
                        State = $line[-2]
                        Version = $line[-3]
                    }
                }
            }
            $distros | ConvertTo-Json | Out-File "$backupPath\distros.json" -Force

            # Export .wslconfig if it exists
            $wslConfigFile = "$env:USERPROFILE\.wslconfig"
            if (Test-Path $wslConfigFile) {
                Copy-Item -Path $wslConfigFile -Destination $backupPath -Force
            }

            # Export WSL network settings
            $wslNetworkConfig = @{
                NetworkingMode = wsl --status | Select-String "Default"
                NetworkAdapter = Get-NetAdapter | Where-Object { $_.InterfaceDescription -like "*WSL*" } | Select-Object Name, Status, MacAddress
            }
            $wslNetworkConfig | ConvertTo-Json | Out-File "$backupPath\wsl_network.json" -Force

            # Export WSL integration settings
            $wslIntegration = @{
                SystemdEnabled = (wsl --status | Select-String "systemd").ToString() -match "enabled"
                WindowsPathEnabled = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss" -ErrorAction SilentlyContinue).AppendWindowsPath
                AutomountEnabled = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss" -ErrorAction SilentlyContinue).DefaultAutomountEnabled
            }
            $wslIntegration | ConvertTo-Json | Out-File "$backupPath\wsl_integration.json" -Force

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
    Backup-WSLSettings -BackupRootPath $BackupRootPath
} 