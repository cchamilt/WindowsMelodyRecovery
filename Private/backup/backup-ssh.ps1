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

function Backup-SSHSettings {
    param(
        [Parameter(Mandatory=$true)]
        [string]$MachineBackupPath,
        [Parameter(Mandatory=$true)]
        [string]$SharedBackupPath
    )
    
    try {
        Write-Host "Backing up SSH Settings..." -ForegroundColor Blue
        $backupPath = Initialize-BackupDirectory -Path "SSH" -BackupType "SSH Settings" -BackupRootPath $MachineBackupPath
        
        if ($backupPath) {
            # Export SSH registry settings
            $regPaths = @(
                # OpenSSH settings
                "HKLM\SOFTWARE\OpenSSH",
                "HKCU\Software\OpenSSH",
                
                # PuTTY settings
                "HKCU\Software\SimonTatham\PuTTY",
                
                # WinSCP settings
                "HKCU\Software\Martin Prikryl\WinSCP 2",
                "HKLM\SYSTEM\CurrentControlSet\Services\OpenSSHd",
                "HKLM\SYSTEM\CurrentControlSet\Services\ssh-agent"
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

            # Export SSH config files if they exist
            $sshPaths = @{
                "User" = "$env:USERPROFILE\.ssh"
                "System" = "$env:ProgramData\ssh"
            }

            foreach ($sshPath in $sshPaths.GetEnumerator()) {
                if (Test-Path $sshPath.Value) {
                    $destPath = Join-Path $backupPath $sshPath.Key
                    New-Item -ItemType Directory -Path $destPath -Force | Out-Null
                    Copy-Item -Path "$($sshPath.Value)\*" -Destination $destPath -Force -Exclude "*.key"
                }
            }

            # Backup SSH config and keys
            $sshPaths = @{
                "User" = "$env:USERPROFILE\.ssh"
                "System" = "$env:ProgramData\ssh"
            }

            foreach ($ssh in $sshPaths.GetEnumerator()) {
                if (Test-Path $ssh.Value) {
                    $destPath = Join-Path $backupPath $ssh.Key
                    New-Item -ItemType Directory -Path $destPath -Force | Out-Null
                    
                    # Set proper initial permissions on backup directory
                    icacls $destPath /inheritance:r
                    icacls $destPath /grant:r "${env:USERNAME}:(OI)(CI)F"
                    
                    # Copy all files except private keys (we'll handle those separately)
                    Get-ChildItem -Path $ssh.Value -Exclude "*_rsa","*_dsa","*_ed25519","*_ecdsa" | 
                        ForEach-Object {
                            Copy-Item -Path $_.FullName -Destination $destPath -Force -Recurse
                            # Preserve original permissions
                            icacls "$($_.FullName)" /save "$destPath\$($_.Name).acl"
                        }
                    
                    # Backup private keys with encryption and proper permissions
                    $privateKeys = Get-ChildItem -Path $ssh.Value -Include "*_rsa","*_dsa","*_ed25519","*_ecdsa" -Force
                    foreach ($key in $privateKeys) {
                        $encryptedKey = "$destPath\$($key.Name).enc"
                        # Encrypt private key with machine-specific key
                        $keyBytes = [System.IO.File]::ReadAllBytes($key.FullName)
                        $encryptedBytes = Protect-CmsMessage -Content $keyBytes -To "cn=PowerShell Backup"
                        [System.IO.File]::WriteAllBytes($encryptedKey, $encryptedBytes)
                        
                        # Save original permissions
                        icacls "$($key.FullName)" /save "$destPath\$($key.Name).acl"
                        
                        # Set restrictive permissions on encrypted key
                        icacls $encryptedKey /inheritance:r
                        icacls $encryptedKey /grant:r "${env:USERNAME}:F"
                    }
                }
            }

            # Backup known_hosts files
            $knownHostsPaths = @(
                "$env:USERPROFILE\.ssh\known_hosts",
                "$env:ProgramData\ssh\known_hosts"
            )

            foreach ($knownHosts in $knownHostsPaths) {
                if (Test-Path $knownHosts) {
                    $destFile = Join-Path $backupPath "known_hosts_$((Split-Path $knownHosts -Parent).Replace(':', '').Replace('\', '_'))"
                    Copy-Item -Path $knownHosts -Destination $destFile -Force
                }
            }

            # Backup PuTTY sessions and host keys
            $puttyPath = "$env:APPDATA\PuTTY"
            if (Test-Path $puttyPath) {
                $puttyBackupPath = Join-Path $backupPath "PuTTY"
                New-Item -ItemType Directory -Path $puttyBackupPath -Force | Out-Null
                Copy-Item -Path "$puttyPath\*" -Destination $puttyBackupPath -Force -Recurse
            }

            # Backup WinSCP configuration and stored sessions
            $winscpPath = "$env:APPDATA\WinSCP"
            if (Test-Path $winscpPath) {
                $winscpBackupPath = Join-Path $backupPath "WinSCP"
                New-Item -ItemType Directory -Path $winscpBackupPath -Force | Out-Null
                Copy-Item -Path "$winscpPath\*.ini" -Destination $winscpBackupPath -Force
                Copy-Item -Path "$winscpPath\WinSCP.rnd" -Destination $winscpBackupPath -Force -ErrorAction SilentlyContinue
            }

            # Output summary
            Write-Host "`nSSH Backup Summary:" -ForegroundColor Green
            Write-Host "User SSH Config: $(Test-Path "$env:USERPROFILE\.ssh")" -ForegroundColor Yellow
            Write-Host "System SSH Config: $(Test-Path "$env:ProgramData\ssh")" -ForegroundColor Yellow
            Write-Host "PuTTY Settings: $(Test-Path $puttyPath)" -ForegroundColor Yellow
            Write-Host "WinSCP Settings: $(Test-Path $winscpPath)" -ForegroundColor Yellow
            
            Write-Host "SSH Settings backed up successfully to: $backupPath" -ForegroundColor Green
            return $true
        }
        return $false
    } catch {
        $errorRecord = $_
        $errorMessage = @(
            "Failed to backup SSH Settings"
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
    Backup-SSHSettings -MachineBackupPath $MachineBackupPath -SharedBackupPath $SharedBackupPath
} 