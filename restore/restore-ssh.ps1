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

            # Restore SSH config and keys
            $sshPaths = @{
                "User" = "$env:USERPROFILE\.ssh"
                "System" = "$env:ProgramData\ssh"
            }

            foreach ($ssh in $sshPaths.GetEnumerator()) {
                $sourcePath = Join-Path $backupPath $ssh.Key
                if (Test-Path $sourcePath) {
                    if (!(Test-Path $ssh.Value)) {
                        New-Item -ItemType Directory -Path $ssh.Value -Force | Out-Null
                    }

                    # Restore non-private key files with their permissions
                    Get-ChildItem -Path $sourcePath -Exclude "*.enc","*.acl" | ForEach-Object {
                        Copy-Item -Path $_.FullName -Destination $ssh.Value -Force
                        $aclFile = "$sourcePath\$($_.Name).acl"
                        if (Test-Path $aclFile) {
                            icacls "$($ssh.Value)\$($_.Name)" /restore $aclFile
                        }
                    }

                    # Restore private keys with decryption and proper permissions
                    $encryptedKeys = Get-ChildItem -Path $sourcePath -Filter "*.enc"
                    foreach ($encKey in $encryptedKeys) {
                        $keyName = $encKey.Name -replace '\.enc$',''
                        $keyPath = Join-Path $ssh.Value $keyName
                        
                        # Decrypt and restore the key
                        $encryptedBytes = [System.IO.File]::ReadAllBytes($encKey.FullName)
                        $decryptedBytes = Unprotect-CmsMessage -Content $encryptedBytes
                        [System.IO.File]::WriteAllBytes($keyPath, $decryptedBytes)

                        # Restore original permissions
                        $aclFile = "$sourcePath\$keyName.acl"
                        if (Test-Path $aclFile) {
                            icacls $keyPath /restore $aclFile
                        } else {
                            # Set default restrictive permissions if no ACL file exists
                            icacls $keyPath /inheritance:r
                            icacls $keyPath /grant:r "${env:USERNAME}:F"
                        }
                    }
                }
            }

            # Restore known_hosts files
            $knownHostsFiles = Get-ChildItem -Path $backupPath -Filter "known_hosts_*"
            foreach ($file in $knownHostsFiles) {
                $originalPath = if ($file.Name -match "ProgramData") {
                    "$env:ProgramData\ssh\known_hosts"
                } else {
                    "$env:USERPROFILE\.ssh\known_hosts"
                }
                
                if (!(Test-Path (Split-Path $originalPath -Parent))) {
                    New-Item -ItemType Directory -Path (Split-Path $originalPath -Parent) -Force | Out-Null
                }
                Copy-Item -Path $file.FullName -Destination $originalPath -Force
            }

            # Restore PuTTY settings
            $puttyBackupPath = Join-Path $backupPath "PuTTY"
            if (Test-Path $puttyBackupPath) {
                $puttyPath = "$env:APPDATA\PuTTY"
                if (!(Test-Path $puttyPath)) {
                    New-Item -ItemType Directory -Path $puttyPath -Force | Out-Null
                }
                Copy-Item -Path "$puttyBackupPath\*" -Destination $puttyPath -Force -Recurse
            }

            # Restore WinSCP settings
            $winscpBackupPath = Join-Path $backupPath "WinSCP"
            if (Test-Path $winscpBackupPath) {
                $winscpPath = "$env:APPDATA\WinSCP"
                if (!(Test-Path $winscpPath)) {
                    New-Item -ItemType Directory -Path $winscpPath -Force | Out-Null
                }
                Copy-Item -Path "$winscpBackupPath\*.ini" -Destination $winscpPath -Force
                Copy-Item -Path "$winscpBackupPath\WinSCP.rnd" -Destination $winscpPath -Force -ErrorAction SilentlyContinue
            }

            # Restart SSH service if it exists
            $sshService = Get-Service -Name "sshd" -ErrorAction SilentlyContinue
            if ($sshService) {
                Restart-Service -Name "sshd" -Force -ErrorAction SilentlyContinue
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