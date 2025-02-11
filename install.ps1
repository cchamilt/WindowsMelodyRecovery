# In an admin powershell run the following:

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

# Install Go
winget install GoLang.Go

# Install Rust
winget install Rustlang.Rust

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

# Install Ubuntu fonts
try {
    Write-Host "Installing Ubuntu fonts..." -ForegroundColor Blue
    
    # Download Ubuntu fonts
    $fontUrl = "https://assets.ubuntu.com/v1/fad7939b-ubuntu-font-family-0.83.zip"
    $fontZip = "$env:TEMP\ubuntu-fonts.zip"
    $fontExtract = "$env:TEMP\ubuntu-fonts"
    
    # Create extraction directory if it doesn't exist
    if (!(Test-Path $fontExtract)) {
        New-Item -ItemType Directory -Path $fontExtract -Force | Out-Null
    }
    
    # Download and extract
    Invoke-WebRequest -Uri $fontUrl -OutFile $fontZip
    Expand-Archive -Path $fontZip -DestinationPath $fontExtract -Force
    
    # Install all Ubuntu fonts for all users
    $fontFiles = Get-ChildItem -Path "$fontExtract\ubuntu-font-family-0.83" -Filter "*.ttf"
    foreach ($font in $fontFiles) {
        $fontDestination = "C:\Windows\Fonts\$($font.Name)"
        Copy-Item -Path $font.FullName -Destination $fontDestination -Force
        
        # Add font to registry
        $regValue = @{
            'Name' = $font.BaseName
            'Type' = "REG_SZ"
            'Value' = $font.Name
            'Path' = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
        }
        Set-ItemProperty @regValue
    }
    
    # Also install Nerd Font version of Ubuntu Mono for dev icons
    $nerdFontUrl = "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.1.1/UbuntuMono.zip"
    $nerdFontZip = "$env:TEMP\ubuntu-nerd-fonts.zip"
    
    Invoke-WebRequest -Uri $nerdFontUrl -OutFile $nerdFontZip
    Expand-Archive -Path $nerdFontZip -DestinationPath "$fontExtract\nerd-fonts" -Force
    
    $nerdFontFiles = Get-ChildItem -Path "$fontExtract\nerd-fonts" -Filter "*.ttf"
    foreach ($font in $nerdFontFiles) {
        $fontDestination = "C:\Windows\Fonts\$($font.Name)"
        Copy-Item -Path $font.FullName -Destination $fontDestination -Force
        
        # Add font to registry
        $regValue = @{
            'Name' = $font.BaseName
            'Type' = "REG_SZ"
            'Value' = $font.Name
            'Path' = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
        }
        Set-ItemProperty @regValue
    }
    
    # Cleanup
    Remove-Item $fontZip -Force
    Remove-Item $nerdFontZip -Force
    Remove-Item $fontExtract -Recurse -Force
    
    Write-Host "Ubuntu fonts installed successfully" -ForegroundColor Green
} catch {
    Write-Host "Failed to install Ubuntu fonts: $_" -ForegroundColor Red
}

# Quickbooks