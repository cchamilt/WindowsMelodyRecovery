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

function Backup-RDPSettings {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath
    )
    
    try {
        Write-Host "Backing up RDP Settings..." -ForegroundColor Blue
        $backupPath = Initialize-BackupDirectory -Path "RDP" -BackupType "RDP Settings" -BackupRootPath $BackupRootPath
        
        if ($backupPath) {
            # Export RDP registry settings
            $regPaths = @(
                # RDP client settings
                "HKCU\Software\Microsoft\Terminal Server Client",
                "HKLM\SOFTWARE\Microsoft\Terminal Server Client",
                
                # RDP server settings
                "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server",
                "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services",
                
                # Remote assistance settings
                "HKLM\SYSTEM\CurrentControlSet\Control\Remote Assistance",
                
                # RDP security settings
                "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp",
                "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\SessionData"
            )

            foreach ($regPath in $regPaths) {
                $regFile = "$backupPath\$($regPath.Split('\')[-1]).reg"
                reg export $regPath $regFile /y 2>$null
            }

            # Export RDP connection files
            $rdpPaths = @(
                "$env:USERPROFILE\Documents\*.rdp",
                "$env:APPDATA\Microsoft\Windows\Recent\AutomaticDestinations\*.rdp",
                "$env:USERPROFILE\Documents\Remote Desktop Connection Manager\*.rdp"
            )

            foreach ($rdpPath in $rdpPaths) {
                if (Test-Path $rdpPath) {
                    $rdpFiles = Get-ChildItem -Path $rdpPath
                    if ($rdpFiles) {
                        $rdpBackupPath = Join-Path $backupPath "Connections"
                        New-Item -ItemType Directory -Path $rdpBackupPath -Force | Out-Null
                        Copy-Item -Path $rdpPath -Destination $rdpBackupPath -Force
                    }
                }
            }

            # Export RDP certificates
            $rdpCerts = Get-ChildItem -Path "Cert:\LocalMachine\Remote Desktop" -ErrorAction SilentlyContinue
            if ($rdpCerts) {
                $certsPath = Join-Path $backupPath "Certificates"
                New-Item -ItemType Directory -Path $certsPath -Force | Out-Null
                
                foreach ($cert in $rdpCerts) {
                    $certFile = Join-Path $certsPath "$($cert.Thumbprint).pfx"
                    Export-PfxCertificate -Cert $cert -FilePath $certFile -Password (ConvertTo-SecureString -String "temp" -Force -AsPlainText) | Out-Null
                }
            }

            # Export RDP configuration
            try {
                # Use registry for RDP settings instead of WMI
                $rdpSettings = @{
                    Enabled = (Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections").fDenyTSConnections -eq 0
                    UserAuthentication = (Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "UserAuthentication").UserAuthentication
                    SecurityLayer = (Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "SecurityLayer").SecurityLayer
                }
                $rdpSettings | ConvertTo-Json | Out-File "$backupPath\rdp_settings.json" -Force
            } catch {
                Write-Host "Warning: Could not retrieve RDP settings" -ForegroundColor Yellow
            }

            # Export RDP authorized hosts
            $authorizedHosts = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "SecurityLayer" -ErrorAction SilentlyContinue
            if ($authorizedHosts) {
                $authorizedHosts | ConvertTo-Json | Out-File "$backupPath\authorized_hosts.json" -Force
            }
            
            Write-Host "RDP Settings backed up successfully to: $backupPath" -ForegroundColor Green
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
    Backup-RDPSettings -BackupRootPath $BackupRootPath
} 