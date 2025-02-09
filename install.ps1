# In an admin powershell run the following:

$RDP_PATH = "$env:USERPROFILE\OneDrive - Fyber Labs\PCbackup\shared\RDP"
$VPN_PATH = "$env:USERPROFILE\OneDrive - Fyber Labs\PCbackup\shared\VPN"
$SSH_PATH = "$env:USERPROFILE\OneDrive - Fyber Labs\PCbackup\shared\SSH"

# Install PowerShell
winget install Microsoft.PowerShell
# Install Package Managers
winget install Git.Git
winget install Microsoft.WindowsTerminal

winget install Microsoft.VisualStudioCode
winget install Docker.DockerDesktop

winget install CoreyButler.NVMforWindows

# Install Azure CLI
winget install Microsoft.AzureCLI

# Install AWS CLI
winget install Amazon.AWSCLI

# Install Node.js
winget install OpenJS.NodeJS

#npm and yarn?
winget install pnpm.pnpm
winget install yarn.yarn


# Install Python
winget install Python.Python.3.12

# # Install Go
# winget install GoLang.Go

# # Install Rust
# winget install Rustlang.Rust

# Instal VSCode
winget install Microsoft.VisualStudioCode

# Install Chrome
winget install Google.Chrome

# # Install Firefox
# winget install Mozilla.Firefox

# Install 7zip
winget install 7zip.7zip

# Install VLC
winget install VideoLAN.VLC
winget install x264.x264

# Install Vivaldi
winget install Vivaldi.Vivaldi

# Install Notepad++
winget install Notepad++.Notepad++

# Install KeepassXC
winget install KeePassXCTeam.KeePassXC

# Install chocolatey
winget install Chocolatey.Chocolatey

choco install -y kdiff3 grepwin

# Install tailscale
winget install Tailscale.Tailscale

# Install rambox
winget install Rambox.Rambox.Community

# Install CAD software
# Install Freecad
winget install FreeCAD.FreeCAD

# Install Blender
winget install BlenderFoundation.Blender

# Instal OpenSCAD
winget install OpenSCAD.OpenSCAD

# Install KiCad
winget install KiCad.KiCad

# Install gEDA
winget install gEDA.gEDA

# Install Graphics software
# Install gimp
winget install GIMP.GIMP

# Install Inkscape
winget install Inkscape.Inkscape 

# Install Krita
winget install -e --id KDE.Krita

#Install video editing software
# Install OBS Studio
winget install OBSProject.OBSStudio

# Install OpenShot
winget install -e --id OpenShot.OpenShot

# Install Kdenlive
winget install -e --id KDE.Kdenlive

# Install Handbrake
winget install HandBrake.HandBrake

# Install steam
winget install -e --id Valve.Steam

# Install epic games
winget install EpicGames.EpicGamesLauncher

# Install WSL
wsl --install -d Ubuntu

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

# Write profile
Set-Content -Path $PROFILE -Stream StandardOutput -Value (Get-Content .\PROFILE)

# Install nuget
Install-PackageProvider -Name NuGet -Force

# Set execution policy
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser

# Set PSGallery as trusted
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

# Install posh-git
Install-Module posh-git -Scope CurrentUser

# Install Terminal-Icons
Install-Module Terminal-Icons -Scope CurrentUser

# Install PSReadLine
Install-Module PSReadLine -Scope CurrentUser

# Install DockerCompletion
Install-Module DockerCompletion -Scope CurrentUser

# Install Az
Install-Module Az -Scope CurrentUser

# Install AWS Tools
Install-Module AWS.Tools.Common -Scope CurrentUser

#Initiliaze windows license
#slmgr /ipk W269N-WFGWX-YVC9B-4J6C8-T7EY7

# Login to office 365
#Connect-MsolService

# Install Microsoft 365 Apps for enterprise
winget install Microsoft.365Apps

# sweet home
winget install -e --id eTeks.SweetHome3D

# Install things that are not available in winget
# Download and install Cursor
$cursorUrl = "https://download.cursor.sh/windows/Cursor-Setup.exe"
$cursorInstaller = "$env:TEMP\Cursor-Setup.exe"
try {
    Write-Host "Downloading Cursor..." -ForegroundColor Blue
    Invoke-WebRequest -Uri $cursorUrl -OutFile $cursorInstaller
    Write-Host "Installing Cursor..." -ForegroundColor Blue
    Start-Process -FilePath $cursorInstaller -ArgumentList "/S" -Wait
    Remove-Item $cursorInstaller -Force
    Write-Host "Cursor installation completed" -ForegroundColor Green
} catch {
    Write-Host "Failed to install Cursor: $_" -ForegroundColor Red
}

# # Download and install Webull
# $webullUrl = "https://u1sweb.webullfintech.com/us/Webull-win-latest.exe"
# $webullInstaller = "$env:TEMP\Webull-Setup.exe"
# try {
#     Write-Host "Downloading Webull..." -ForegroundColor Blue
#     Invoke-WebRequest -Uri $webullUrl -OutFile $webullInstaller
#     Write-Host "Installing Webull..." -ForegroundColor Blue
#     Start-Process -FilePath $webullInstaller -ArgumentList "/S" -Wait
#     Remove-Item $webullInstaller -Force
#     Write-Host "Webull installation completed" -ForegroundColor Green
# } catch {
#     Write-Host "Failed to install Webull: $_" -ForegroundColor Red
# }

# # Download and install Interactive Brokers TWS
# $ibkrVersion = "1040.2j" # You may want to update this version number periodically
# $ibkrUrl = "https://download2.interactivebrokers.com/installers/tws/$ibkrVersion/tws-$ibkrVersion-standalone-windows-x64.exe"
# $ibkrInstaller = "$env:TEMP\IBKR-TWS-Setup.exe"
# try {
#     Write-Host "Downloading Interactive Brokers TWS..." -ForegroundColor Blue
#     Invoke-WebRequest -Uri $ibkrUrl -OutFile $ibkrInstaller
#     Write-Host "Installing Interactive Brokers TWS..." -ForegroundColor Blue
#     # IBKR installer uses /MODE=Unattended for silent installation
#     Start-Process -FilePath $ibkrInstaller -ArgumentList "/MODE=Unattended /TYPE=USER /PREFIX=`"$env:ProgramFiles\Trader Workstation`"" -Wait
#     Remove-Item $ibkrInstaller -Force
#     Write-Host "Interactive Brokers TWS installation completed" -ForegroundColor Green
# } catch {
#     Write-Host "Failed to install Interactive Brokers TWS: $_" -ForegroundColor Red
# }

# Fritzing
# DipTrace

# Output to console
Write-Host "Need to install Webull and Interactive Brokers TWS" -ForegroundColor Yellow
Write-Host "Need to install Fritzing and DipTrace" -ForegroundColor Yellow

#Remove: Lenovo*, new outlook, etc.
Write-Host "Removing Lenovo bloatware..." -ForegroundColor Blue

try {
    # $excludeApps = @(
    #     "LenovoVantage",  # Example of an app you might want to keep
    #     "LenovoUtility"
    # )

    $lenovoApps = Get-AppxPackage -AllUsers | Where-Object { 
        $_.Name -like "*Lenovo*" -and $_.Name -notin $excludeApps 
    }
    
    # Remove each Lenovo app
    foreach ($app in $lenovoApps) {
        Write-Host "Removing $($app.Name)..." -ForegroundColor Yellow
        Remove-AppxPackage -Package $app.PackageFullName
        Remove-AppxProvisionedPackage -Online -PackageName $app.Name
    }

    # Remove Lenovo programs using WMI
    Get-WmiObject -Class Win32_Product | Where-Object { 
        $_.Name -like "*Lenovo*" 
    } | ForEach-Object {
        Write-Host "Removing $($_.Name)..." -ForegroundColor Yellow
        $_.Uninstall()
    }
    
    Write-Host "Lenovo bloatware removal completed" -ForegroundColor Green
} catch {
    Write-Host "Failed to remove some Lenovo applications: $_" -ForegroundColor Red
}

#Azure VPN
try {
    Write-Host "Installing Azure VPN Client..." -ForegroundColor Blue
    
    # Download Azure VPN Client
    $vpnUrl = "https://go.microsoft.com/fwlink/?linkid=2117554"
    $vpnInstaller = "$env:TEMP\AzureVPNClient.msi"
    
    Invoke-WebRequest -Uri $vpnUrl -OutFile $vpnInstaller
    
    # Install silently
    Start-Process msiexec.exe -ArgumentList "/i `"$vpnInstaller`" /quiet /norestart" -Wait
    
    # Cleanup
    Remove-Item $vpnInstaller -Force
    
    Write-Host "Azure VPN Client installation completed" -ForegroundColor Green
} catch {
    Write-Host "Failed to install Azure VPN Client: $_" -ForegroundColor Red
}

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

# Setup touchpad, touchscreen, power settings, and other settings




















