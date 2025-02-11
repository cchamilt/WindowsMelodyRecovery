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

function Backup-WSLSSHSettings {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath
    )
    
    try {
        Write-Host "Backing up WSL SSH Settings..." -ForegroundColor Blue
        $backupPath = Initialize-BackupDirectory -Path "WSLSSH" -BackupType "WSL SSH Settings" -BackupRootPath $BackupRootPath
        
        if ($backupPath) {
            # Create SSH backup directory
            New-Item -ItemType Directory -Path "$backupPath\ssh" -Force | Out-Null

            # Backup WSL SSH configurations
            wsl -e bash -c @"
                # Backup SSH config and keys
                if [ -d ~/.ssh ]; then
                    echo "Backing up SSH configurations..."
                    cd ~/.ssh
                    
                    # Save permissions
                    getfacl -R . > /mnt/c/Users/$env:USERNAME/.wsl_ssh_perms_temp
                    
                    # Backup public keys and config
                    tar czf /mnt/c/Users/$env:USERNAME/.wsl_ssh_public_temp.tar.gz \
                        --exclude='id_*' \
                        --exclude='*.pub' \
                        --exclude='known_hosts' \
                        .

                    # Backup known_hosts separately
                    if [ -f known_hosts ]; then
                        cp known_hosts /mnt/c/Users/$env:USERNAME/.wsl_known_hosts_temp
                    fi

                    # Backup public keys separately
                    tar czf /mnt/c/Users/$env:USERNAME/.wsl_ssh_pubkeys_temp.tar.gz *.pub

                    # Encrypt and backup private keys
                    for key in id_rsa id_dsa id_ecdsa id_ed25519; do
                        if [ -f \$key ]; then
                            echo "Backing up \$key..."
                            openssl enc -aes-256-cbc -salt -pbkdf2 \
                                -in \$key \
                                -out /mnt/c/Users/$env:USERNAME/.wsl_\${key}_temp.enc \
                                -pass pass:temp
                        fi
                    done
                fi

                # Backup system-wide SSH configuration
                if [ -d /etc/ssh ]; then
                    echo "Backing up system SSH configurations..."
                    sudo tar czf /mnt/c/Users/$env:USERNAME/.wsl_ssh_system_temp.tar.gz \
                        /etc/ssh/ssh_config \
                        /etc/ssh/sshd_config \
                        /etc/ssh/ssh_config.d \
                        /etc/ssh/sshd_config.d \
                        2>/dev/null
                fi
"@ -u root

            # Move files from temp to backup location
            if (Test-Path "$env:USERPROFILE\.wsl_ssh_perms_temp") {
                Move-Item "$env:USERPROFILE\.wsl_ssh_perms_temp" "$backupPath\ssh\permissions.acl" -Force
            }
            
            if (Test-Path "$env:USERPROFILE\.wsl_ssh_public_temp.tar.gz") {
                Move-Item "$env:USERPROFILE\.wsl_ssh_public_temp.tar.gz" "$backupPath\ssh\config.tar.gz" -Force
            }
            
            if (Test-Path "$env:USERPROFILE\.wsl_known_hosts_temp") {
                Move-Item "$env:USERPROFILE\.wsl_known_hosts_temp" "$backupPath\ssh\known_hosts" -Force
            }
            
            if (Test-Path "$env:USERPROFILE\.wsl_ssh_pubkeys_temp.tar.gz") {
                Move-Item "$env:USERPROFILE\.wsl_ssh_pubkeys_temp.tar.gz" "$backupPath\ssh\public_keys.tar.gz" -Force
            }

            # Move encrypted private keys
            Get-ChildItem "$env:USERPROFILE\.wsl_id_*_temp.enc" -ErrorAction SilentlyContinue | ForEach-Object {
                $newName = $_.Name -replace '_temp\.enc$','.enc'
                Move-Item $_.FullName "$backupPath\ssh\$newName" -Force
            }

            if (Test-Path "$env:USERPROFILE\.wsl_ssh_system_temp.tar.gz") {
                Move-Item "$env:USERPROFILE\.wsl_ssh_system_temp.tar.gz" "$backupPath\ssh\system_config.tar.gz" -Force
            }

            # Output summary
            Write-Host "`nWSL SSH Backup Summary:" -ForegroundColor Green
            Write-Host "SSH Config: $(Test-Path "$backupPath\ssh\config.tar.gz")" -ForegroundColor Yellow
            Write-Host "Public Keys: $(Test-Path "$backupPath\ssh\public_keys.tar.gz")" -ForegroundColor Yellow
            Write-Host "Known Hosts: $(Test-Path "$backupPath\ssh\known_hosts")" -ForegroundColor Yellow
            Write-Host "System Config: $(Test-Path "$backupPath\ssh\system_config.tar.gz")" -ForegroundColor Yellow
            Write-Host "Private Keys: $((Get-ChildItem "$backupPath\ssh\id_*.enc").Count) found" -ForegroundColor Yellow
            
            Write-Host "WSL SSH Settings backed up successfully to: $backupPath" -ForegroundColor Green
            return $true
        }
        return $false
    } catch {
        Write-Host "Failed to backup WSL SSH Settings: $_" -ForegroundColor Red
        return $false
    }
}

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Backup-WSLSSHSettings -BackupRootPath $BackupRootPath
} 