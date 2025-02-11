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

function Restore-RDPSettings {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath
    )
    
    try {
        Write-Host "Restoring RDP Settings..." -ForegroundColor Blue
        $backupPath = Test-BackupPath -Path "RDP" -BackupType "RDP Settings"
        
        if ($backupPath) {
            # Import registry settings first
            $regFiles = Get-ChildItem -Path $backupPath -Filter "*.reg"
            foreach ($regFile in $regFiles) {
                reg import $regFile.FullName | Out-Null
            }

            # Restore RDP connection files
            $rdpBackupPath = Join-Path $backupPath "Connections"
            if (Test-Path $rdpBackupPath) {
                $rdpDestPaths = @{
                    "Documents" = "$env:USERPROFILE\Documents"
                    "Recent" = "$env:APPDATA\Microsoft\Windows\Recent\AutomaticDestinations"
                    "RDCMan" = "$env:USERPROFILE\Documents\Remote Desktop Connection Manager"
                }

                foreach ($dest in $rdpDestPaths.GetEnumerator()) {
                    if (!(Test-Path $dest.Value)) {
                        New-Item -ItemType Directory -Path $dest.Value -Force | Out-Null
                    }
                }

                # Copy RDP files to appropriate locations
                Get-ChildItem -Path $rdpBackupPath -Filter "*.rdp" | ForEach-Object {
                    if ($_.Name -match "AutomaticDestinations") {
                        Copy-Item -Path $_.FullName -Destination $rdpDestPaths["Recent"] -Force
                    } elseif ($_.Name -match "Remote Desktop Connection Manager") {
                        Copy-Item -Path $_.FullName -Destination $rdpDestPaths["RDCMan"] -Force
                    } else {
                        Copy-Item -Path $_.FullName -Destination $rdpDestPaths["Documents"] -Force
                    }
                }
            }

            # Restore RDP certificates
            $certsPath = Join-Path $backupPath "Certificates"
            if (Test-Path $certsPath) {
                $certFiles = Get-ChildItem -Path $certsPath -Filter "*.pfx"
                foreach ($certFile in $certFiles) {
                    Import-PfxCertificate -FilePath $certFile.FullName `
                        -CertStoreLocation "Cert:\LocalMachine\Remote Desktop" `
                        -Password (ConvertTo-SecureString -String "temp" -Force -AsPlainText)
                }
            }

            # Restore RDP listener configuration
            $listenersFile = "$backupPath\rdp_listeners.json"
            if (Test-Path $listenersFile) {
                $listeners = Get-Content $listenersFile | ConvertFrom-Json
                $currentListeners = Get-WmiObject -Namespace root\cimv2\TerminalServices -Class Win32_TSGeneralSetting
                
                foreach ($listener in $currentListeners) {
                    $saved = $listeners | Where-Object { $_.TerminalName -eq $listener.TerminalName }
                    if ($saved) {
                        $listener.SetUserAuthenticationRequired($saved.UserAuthenticationRequired)
                        $listener.SetMinEncryptionLevel($saved.MinEncryptionLevel)
                    }
                }
            }

            # Restore RDP authorized hosts
            $hostsFile = "$backupPath\authorized_hosts.json"
            if (Test-Path $hostsFile) {
                $hosts = Get-Content $hostsFile | ConvertFrom-Json
                Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" `
                    -Name "SecurityLayer" -Value $hosts.SecurityLayer
            }

            # Restart Terminal Services
            $services = @(
                "TermService",
                "UmRdpService",
                "SessionEnv"
            )
            
            foreach ($service in $services) {
                if (Get-Service -Name $service -ErrorAction SilentlyContinue) {
                    Restart-Service -Name $service -Force -ErrorAction SilentlyContinue
                }
            }
            
            Write-Host "RDP Settings restored successfully from: $backupPath" -ForegroundColor Green
            return $true
        }
        return $false
    } catch {
        Write-Host "Failed to restore RDP Settings: $_" -ForegroundColor Red
        return $false
    }
}

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Restore-RDPSettings -BackupRootPath $BackupRootPath
} 