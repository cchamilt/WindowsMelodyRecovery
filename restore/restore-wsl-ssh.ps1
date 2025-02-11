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
            # Copy files to temp location for WSL access
            if (Test-Path "$backupPath\ssh\permissions.acl") {
                Copy-Item "$backupPath\ssh\permissions.acl" "$env:USERPROFILE\.wsl_ssh_perms_temp" -Force
            }
            if (Test-Path "$backupPath\ssh\config.tar.gz") {
                Copy-Item "$backupPath\ssh\config.tar.gz" "$env:USERPROFILE\.wsl_ssh_public_temp.tar.gz" -Force
            }
            if (Test-Path "$backupPath\ssh\known_hosts") {
                Copy-Item "$backupPath\ssh\known_hosts" "$env:USERPROFILE\.wsl_known_hosts_temp" -Force
            }
            if (Test-Path "$backupPath\ssh\public_keys.tar.gz") {
                Copy-Item "$backupPath\ssh\public_keys.tar.gz" "$env:USERPROFILE\.wsl_ssh_pubkeys_temp.tar.gz" -Force
            }
            if (Test-Path "$backupPath\ssh\system_config.tar.gz") {
                Copy-Item "$backupPath\ssh\system_config.tar.gz" "$env:USERPROFILE\.wsl_ssh_system_temp.tar.gz" -Force
            }

            # Copy encrypted private keys
            Get-ChildItem "$backupPath\ssh\id_*.enc" -ErrorAction SilentlyContinue | ForEach-Object {
                $tempName = $_.Name -replace '\.enc$','_temp.enc'
                Copy-Item $_.FullName "$env:USERPROFILE\.$tempName" -Force
            }

            # Restore configurations inside WSL
            wsl -e bash -c @"
                # Create SSH directory if it doesn't exist
                mkdir -p ~/.ssh
                chmod 700 ~/.ssh

                # Restore SSH config and public keys
                if [ -f /mnt/c/Users/$env:USERNAME/.wsl_ssh_public_temp.tar.gz ]; then
                    cd ~/.ssh
                    tar xzf /mnt/c/Users/$env:USERNAME/.wsl_ssh_public_temp.tar.gz
                    echo "Restored SSH config files"
                fi

                # Restore known_hosts
                if [ -f /mnt/c/Users/$env:USERNAME/.wsl_known_hosts_temp ]; then
                    cp /mnt/c/Users/$env:USERNAME/.wsl_known_hosts_temp ~/.ssh/known_hosts
                    echo "Restored known_hosts"
                fi

                # Restore public keys
                if [ -f /mnt/c/Users/$env:USERNAME/.wsl_ssh_pubkeys_temp.tar.gz ]; then
                    cd ~/.ssh
                    tar xzf /mnt/c/Users/$env:USERNAME/.wsl_ssh_pubkeys_temp.tar.gz
                    echo "Restored public keys"
                fi

                # Decrypt and restore private keys
                for key in id_rsa id_dsa id_ecdsa id_ed25519; do
                    if [ -f /mnt/c/Users/$env:USERNAME/.wsl_\${key}_temp.enc ]; then
                        echo "Restoring \$key..."
                        openssl enc -aes-256-cbc -d -salt -pbkdf2 \
                            -in /mnt/c/Users/$env:USERNAME/.wsl_\${key}_temp.enc \
                            -out ~/.ssh/\$key \
                            -pass pass:temp
                        chmod 600 ~/.ssh/\$key
                    fi
                done

                # Restore system-wide SSH configuration
                if [ -f /mnt/c/Users/$env:USERNAME/.wsl_ssh_system_temp.tar.gz ]; then
                    echo "Restoring system SSH configurations..."
                    sudo tar xzf /mnt/c/Users/$env:USERNAME/.wsl_ssh_system_temp.tar.gz -C /
                fi

                # Restore permissions
                if [ -f /mnt/c/Users/$env:USERNAME/.wsl_ssh_perms_temp ]; then
                    cd ~/.ssh
                    setfacl --restore=/mnt/c/Users/$env:USERNAME/.wsl_ssh_perms_temp
                    echo "Restored SSH permissions"
                fi

                # Set standard permissions if no ACL file
                if [ ! -f /mnt/c/Users/$env:USERNAME/.wsl_ssh_perms_temp ]; then
                    chmod 700 ~/.ssh
                    chmod 600 ~/.ssh/config 2>/dev/null
                    chmod 644 ~/.ssh/*.pub 2>/dev/null
                    chmod 600 ~/.ssh/id_* 2>/dev/null
                    chmod 644 ~/.ssh/known_hosts 2>/dev/null
                fi

                # Restart SSH service if it exists
                if systemctl status ssh >/dev/null 2>&1; then
                    sudo systemctl restart ssh
                fi
"@ -u root

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