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

# Requires admin privileges
#Requires -RunAsAdministrator

param(
    [string]$InstallPath = "$env:USERPROFILE\Scripts\WindowsConfig",
    [switch]$NoScheduledTasks,
    [switch]$NoPrompt
)

try {
    Write-Host "Installing Windows Configuration Scripts..." -ForegroundColor Blue

    # Create installation directory
    if (!(Test-Path $InstallPath)) {
        New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
        Write-Host "Created installation directory: $InstallPath" -ForegroundColor Green
    }

    # Copy all script files to installation directory
    $scriptDirs = @("backup", "restore", "setup", "tasks", "templates", "scripts")
    foreach ($dir in $scriptDirs) {
        $targetDir = Join-Path $InstallPath $dir
        if (!(Test-Path $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        }
        Copy-Item -Path ".\$dir\*" -Destination $targetDir -Recurse -Force
    }
    Copy-Item -Path ".\*.ps1" -Destination $InstallPath -Exclude "install.ps1" -Force

    # Add installation directory to user's PATH
    $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if ($userPath -notlike "*$InstallPath*") {
        [Environment]::SetEnvironmentVariable("PATH", "$userPath;$InstallPath", "User")
        Write-Host "Added installation directory to PATH" -ForegroundColor Green
    }

    # Create PowerShell profile directory if it doesn't exist
    $profileDir = Split-Path $PROFILE -Parent
    if (!(Test-Path $profileDir)) {
        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    }

    # Add script directory to PowerShell profile
    $profileContent = @"
# Windows Configuration Scripts
`$env:WINDOWS_CONFIG_PATH = "$InstallPath"
"@

    if (Test-Path $PROFILE) {
        if (!(Get-Content $PROFILE | Select-String "WINDOWS_CONFIG_PATH")) {
            Add-Content $PROFILE $profileContent
        }
    } else {
        Set-Content $PROFILE $profileContent
    }

    # Register scheduled tasks if not disabled
    if (!$NoScheduledTasks) {
        $registerTasks = $true
        if (!$NoPrompt) {
            $response = Read-Host "Would you like to register scheduled tasks for backup and update? (Y/N)"
            $registerTasks = $response -eq "Y" -or $response -eq "y"
        }

        if ($registerTasks) {
            # Register backup task
            $backupScript = Join-Path $InstallPath "tasks\register-backup-task.ps1"
            if (Test-Path $backupScript) {
                Write-Host "`nRegistering backup task..." -ForegroundColor Blue
                & $backupScript
            }

            # Register update task
            $updateScript = Join-Path $InstallPath "tasks\register-update-task.ps1"
            if (Test-Path $updateScript) {
                Write-Host "`nRegistering update task..." -ForegroundColor Blue
                & $updateScript
            }
        }
    }

    # Setup KeePassXC if requested
    if (!$NoPrompt) {
        $response = Read-Host "Would you like to set up KeePassXC? (Y/N)"
        if ($response -eq "Y" -or $response -eq "y") {
            $setupScript = Join-Path $InstallPath "setup\setup-keepassxc.ps1"
            if (Test-Path $setupScript) {
                & $setupScript
            }
        }
    }

    # Add to install.ps1 after creating installation directory
    # Create windows.env from template
    $envTemplate = Get-Content (Join-Path $InstallPath "templates\windows.env.template")
    $envFile = Join-Path $InstallPath "windows.env"
    Set-Content -Path $envFile -Value $envTemplate

    # Update PowerShell profile to load windows.env
    $profileContent = @"
# Windows Configuration Scripts
`$envFile = "$envFile"
if (Test-Path `$envFile) {
    Get-Content `$envFile | Where-Object { `$_ -match '^[^#]' } | ForEach-Object {
        `$name, `$value = `$_.split('=')
        `$value = `$value.Trim('"')
        [Environment]::SetEnvironmentVariable(`$name.Trim(), `$ExecutionContext.InvokeCommand.ExpandString(`$value), 'Process')
    }
}
"@

    Write-Host "`nInstallation completed successfully!" -ForegroundColor Green
    Write-Host "Installation path: $InstallPath" -ForegroundColor Yellow
    Write-Host "Please restart PowerShell for PATH changes to take effect" -ForegroundColor Yellow

    # After creating windows.env
    $configTemplate = Get-Content (Join-Path $InstallPath "templates\config.env.template")
    $sharedConfigPath = Join-Path "$env:BACKUP_ROOT\shared" "config.env"
    $machineConfigPath = Join-Path "$env:BACKUP_ROOT\$env:MACHINE_NAME" "config.env"

    # Function to create config file
    function New-ConfigurationFile {
        param (
            [string]$ConfigPath,
            [string]$ConfigType
        )
        
        # Create directory if it doesn't exist
        $configDir = Split-Path $ConfigPath -Parent
        if (!(Test-Path $configDir)) {
            New-Item -ItemType Directory -Path $configDir -Force | Out-Null
        }

        # Prompt for email configuration
        Write-Host "`nConfigure $ConfigType email notifications:" -ForegroundColor Blue
        $fromAddress = Read-Host "Enter sender email address (Office 365)"
        $toAddress = Read-Host "Enter recipient email address"
        $emailPassword = Read-Host "Enter email app password" -AsSecureString

        # Convert secure string to plain text
        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($emailPassword)
        $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)

        # Update template with provided values
        $configContent = $configTemplate -replace 'your-email@domain.com', $fromAddress
        $configContent = $configContent -replace 'your-app-password', $plainPassword
        $configContent = $configContent -replace 'BACKUP_EMAIL_TO=".*"', "BACKUP_EMAIL_TO=`"$toAddress`""

        # Save config.env
        $configContent | Out-File $ConfigPath -Force
        Write-Host "Configuration file created at: $ConfigPath" -ForegroundColor Green
    }

    # Check for existing configurations
    if (!(Test-Path $sharedConfigPath)) {
        Write-Host "`nNo shared configuration found." -ForegroundColor Yellow
        $response = Read-Host "Would you like to create a shared configuration? (Y/N)"
        
        if ($response -eq "Y" -or $response -eq "y") {
            New-ConfigurationFile -ConfigPath $sharedConfigPath -ConfigType "shared"
        } else {
            $response = Read-Host "Would you like to create a machine-specific configuration? (Y/N)"
            if ($response -eq "Y" -or $response -eq "y") {
                New-ConfigurationFile -ConfigPath $machineConfigPath -ConfigType "machine-specific"
            } else {
                Write-Host "No configuration file created. Some features may be limited." -ForegroundColor Yellow
            }
        }
    } else {
        Write-Host "`nShared configuration found at: $sharedConfigPath" -ForegroundColor Green
        $response = Read-Host "Would you like to create a machine-specific configuration? (Y/N)"
        
        if ($response -eq "Y" -or $response -eq "y") {
            if (Test-Path $machineConfigPath) {
                Write-Host "Machine-specific configuration already exists at: $machineConfigPath" -ForegroundColor Yellow
                $response = Read-Host "Would you like to overwrite it? (Y/N)"
                if ($response -eq "Y" -or $response -eq "y") {
                    New-ConfigurationFile -ConfigPath $machineConfigPath -ConfigType "machine-specific"
                }
            } else {
                New-ConfigurationFile -ConfigPath $machineConfigPath -ConfigType "machine-specific"
            }
        } else {
            Write-Host "Using shared configuration file" -ForegroundColor Green
        }
    }

} catch {
    Write-Host "Installation failed: $_" -ForegroundColor Red
    exit 1
}