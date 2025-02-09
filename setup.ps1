
$RDP_PATH = "$env:USERPROFILE\OneDrive - Fyber Labs\PCbackup\shared\RDP"
$VPN_PATH = "$env:USERPROFILE\OneDrive - Fyber Labs\PCbackup\shared\VPN"
$SSH_PATH = "$env:USERPROFILE\OneDrive - Fyber Labs\PCbackup\shared\SSH"

# Install the azure vpn xml file from onedrive
try {
    Write-Host "Importing Azure VPN configuration..." -ForegroundColor Blue
    
    # Define paths
    $vpnConfigPath = "$VPN_PATH\*"
    

    if (Test-Path -Path $vpnConfigPath) {
        # Wait for Azure VPN Client service to be ready
        Start-Sleep -Seconds 5
        
        # Import the VPN configuration
        $process = Start-Process -FilePath "$env:ProgramFiles\Microsoft\AzureVpn\AzureVpn.exe" `
            -ArgumentList "-i `"$vpnConfigPath`"" `
            -Wait -PassThru -NoNewWindow
        
        if ($process.ExitCode -eq 0) {
            Write-Host "Azure VPN configuration imported successfully" -ForegroundColor Green
        } else {
            Write-Host "Failed to import Azure VPN configuration. Exit code: $($process.ExitCode)" -ForegroundColor Red
        }
    } else {
        Write-Host "Azure VPN configuration file not found at: $vpnConfigPath" -ForegroundColor Yellow
    }
} catch {
    Write-Host "Failed to import Azure VPN configuration: $_" -ForegroundColor Red
}

#Install Remote desktop profiles
try {
    Write-Host "Installing Remote Desktop profiles..." -ForegroundColor Blue
    
    # Define paths
    $backupPath = "$RDP_PATH"  # Adjust this path to your backup location
    $rdpPath = "$env:USERPROFILE\Documents\Remote Desktop Connection Manager"
    

    # Create the RDP directory if it doesn't exist
    if (!(Test-Path -Path $rdpPath)) {
        New-Item -ItemType Directory -Path $rdpPath -Force
    }
    
    # Copy all RDP files from backup
    if (Test-Path -Path $backupPath) {
        Copy-Item -Path "$backupPath\*.rdp" -Destination $rdpPath -Force
        Write-Host "Remote Desktop profiles copied successfully" -ForegroundColor Green
    } else {
        Write-Host "Backup path not found: $backupPath" -ForegroundColor Yellow
    }
    
    # Import registry settings for saved credentials (if they exist)
    $regBackupPath = "$backupPath\rdp_credentials.reg"
    if (Test-Path -Path $regBackupPath) {
        Start-Process "reg.exe" -ArgumentList "import `"$regBackupPath`"" -Wait
        Write-Host "Remote Desktop credentials imported" -ForegroundColor Green
    }
} catch {
    Write-Host "Failed to install Remote Desktop profiles: $_" -ForegroundColor Red
}

#wsl and powershell ssh setup
try {
    Write-Host "Setting up SSH for Windows and WSL..." -ForegroundColor Blue
    
    # Windows SSH setup
    $windowsSshDir = "$env:USERPROFILE\.ssh"
    if (!(Test-Path -Path $windowsSshDir)) {
        New-Item -ItemType Directory -Path $windowsSshDir -Force
        # Set proper permissions
        icacls $windowsSshDir /inheritance:r
        icacls $windowsSshDir /grant:r "${env:USERNAME}:(OI)(CI)F"
    }
    
    # Copy SSH files from backup if they exist
    $sshBackupPath = "$SSH_PATH"
    if (Test-Path -Path $sshBackupPath) {
        Copy-Item -Path "$sshBackupPath\*" -Destination $windowsSshDir -Force -Recurse
        # Ensure correct permissions on private keys

        Get-ChildItem -Path $windowsSshDir -Filter "id_*" | ForEach-Object {
            icacls $_.FullName /inheritance:r
            icacls $_.FullName /grant:r "${env:USERNAME}:F"
        }
    }
    
    # WSL SSH setup
    Write-Host "Setting up WSL SSH..." -ForegroundColor Blue
    wsl -e bash -c @'
        # Create .ssh directory with proper permissions
        mkdir -p ~/.ssh
        chmod 700 ~/.ssh
        
        # Copy SSH files from Windows to WSL
        cp -r /mnt/c/Users/$USER/.ssh/* ~/.ssh/ 2>/dev/null || true
        
        # Set proper permissions in WSL
        chmod 600 ~/.ssh/id_*
        chmod 644 ~/.ssh/*.pub
        chmod 644 ~/.ssh/known_hosts
        chmod 644 ~/.ssh/config
        
        # Start SSH agent
        eval $(ssh-agent -s)
'@
    
    # Start SSH agent in Windows
    Start-Service ssh-agent
    
    Write-Host "SSH setup completed for both Windows and WSL" -ForegroundColor Green
} catch {
    Write-Host "Failed to setup SSH: $_" -ForegroundColor Red
}

# Create and copy profile
try {
    if (!(Test-Path -Path $PROFILE)) {
        New-Item -ItemType File -Path $PROFILE -Force
    }
    Copy-Item -Path ".\PROFILE" -Destination $PROFILE -Force
    Write-Host "PowerShell profile successfully installed" -ForegroundColor Green
} catch {
    Write-Host "Failed to install PowerShell profile: $_" -ForegroundColor Red
    exit 1
}

# Copy bashrc into wsl
wsl -e bash -c @'
    if [ -f ~/.bashrc ]; then
        cp ~/.bashrc ~/.bashrc.backup
    fi
    cp /mnt/c/Users/$USER/Documents/PROFILE ~/.bashrc
'@
Write-Host "Bash profile successfully installed" -ForegroundColor Green
