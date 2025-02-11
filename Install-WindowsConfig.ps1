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

    # Bloatware removal
    if (!$NoPrompt) {
        $response = Read-Host "`nWould you like to remove Windows bloatware? (Y/N)"
        if ($response -eq "Y" -or $response -eq "y") {
            $setupScript = Join-Path $InstallPath "setup\setup-removebloat.ps1"
            if (Test-Path $setupScript) {
                Write-Host "Running bloatware removal..." -ForegroundColor Blue
                & $setupScript
            } else {
                Write-Host "Bloatware removal script not found at: $setupScript" -ForegroundColor Red
            }
        }
    }

    # Setup Defender
    if (!$NoPrompt) {
        $response = Read-Host "`nWould you like to configure Windows Defender? (Y/N)"
        if ($response -eq "Y" -or $response -eq "y") {
            $setupScript = Join-Path $InstallPath "setup\setup-defender.ps1"
            if (Test-Path $setupScript) {
                Write-Host "Configuring Windows Defender..." -ForegroundColor Blue
                & $setupScript
            } else {
                Write-Host "Windows Defender setup script not found at: $setupScript" -ForegroundColor Red
            }
        }
    }

    # Setup WSL Fonts
    if (!$NoPrompt) {
        $response = Read-Host "`nWould you like to configure WSL fonts? (Y/N)"
        if ($response -eq "Y" -or $response -eq "y") {
            $setupScript = Join-Path $InstallPath "setup\setup-wsl-fonts.ps1"
        }
    }

    # Setup System Restore
    if (!$NoPrompt) {
        $response = Read-Host "`nWould you like to configure System Restore points? (Y/N)"
        if ($response -eq "Y" -or $response -eq "y") {
            $setupScript = Join-Path $InstallPath "setup\setup-restorepoints.ps1"
            if (Test-Path $setupScript) {
                Write-Host "Configuring System Restore..." -ForegroundColor Blue
                & $setupScript
            } else {
                Write-Host "System Restore setup script not found at: $setupScript" -ForegroundColor Red
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