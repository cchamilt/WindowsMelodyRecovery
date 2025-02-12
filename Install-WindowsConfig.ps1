# Requires admin privileges
#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$InstallPath = "$env:USERPROFILE\Scripts\WindowsConfig",
    [switch]$NoScheduledTasks,
    [switch]$NoPrompt
)

try {
    # At the start of the script
    $scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
    . (Join-Path $scriptPath "scripts\load-environment.ps1")

    if (!(Load-Environment)) {
        Write-Host "Failed to load environment configuration" -ForegroundColor Red
        exit 1
    }

    # Check if running from installed location
    if ($scriptPath -eq $env:WINDOWS_CONFIG_PATH) {
        Write-Host "Running from installed location: $env:WINDOWS_CONFIG_PATH" -ForegroundColor Green
        $InstallPath = $env:WINDOWS_CONFIG_PATH
    } else {
        # Prompt for install location if not using default
        if (!$NoPrompt) {
            $response = Read-Host "Install to [$InstallPath]"
            if ($response) {
                $InstallPath = $response
            }
        }

        # Create and validate installation directory
        if (!(Test-Path $InstallPath)) {
            New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
        }
        
        # Only copy files if installing to a different location
        $currentDir = (Get-Item -Path (Get-Location).Path).FullName
        $targetDir = (Get-Item -Path $InstallPath).FullName
        if ($targetDir -ne $currentDir) {
            # Get source and destination root paths
            $sourceRoot = $currentDir
            $destRoot = $targetDir
            
            # Only proceed if paths are completely different
            if (!$destRoot.StartsWith($sourceRoot) -and !$sourceRoot.StartsWith($destRoot)) {
                # Create required directories first
                $directories = @("backup", "restore", "setup", "tasks", "templates", "scripts")
                foreach ($dir in $directories) {
                    $destDir = Join-Path $InstallPath $dir
                    if (!(Test-Path $destDir)) {
                        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                    }
                }
                
                # Copy files from each directory
                foreach ($dir in $directories) {
                    $sourcePath = Join-Path $sourceRoot $dir
                    $destPath = Join-Path $destRoot $dir
                    if (Test-Path $sourcePath) {
                        Get-ChildItem -Path $sourcePath -File | ForEach-Object {
                            Copy-Item -Path $_.FullName -Destination $destPath -Force
                        }
                    }
                }
                
                # Copy root files
                Get-ChildItem -Path $sourceRoot -File | Where-Object { $_.Name -notlike ".*" } | ForEach-Object {
                    Copy-Item -Path $_.FullName -Destination $destRoot -Force
                }

                Write-Host "Copied files to installation directory" -ForegroundColor Green
            } else {
                Write-Host "Source and destination paths overlap, skipping copy" -ForegroundColor Yellow
            }
        } else {
            Write-Host "Already in installation directory, skipping copy" -ForegroundColor Yellow
        }
    }
    
    # Detect possible OneDrive locations
    $possibleOneDrives = @(
        "$env:USERPROFILE\OneDrive",
        "$env:USERPROFILE\OneDrive - *"
    )
    $onedriveLocations = Get-Item -Path $possibleOneDrives -ErrorAction SilentlyContinue
    
    # Prompt for backup location
    $backupRoot = ""
    if ($onedriveLocations.Count -gt 0) {
        Write-Host "`nDetected OneDrive locations:" -ForegroundColor Blue
        for ($i=0; $i -lt $onedriveLocations.Count; $i++) {
            Write-Host "[$i] $($onedriveLocations[$i].FullName)"
        }
        $selection = Read-Host "`nSelect OneDrive location [0-$($onedriveLocations.Count-1)]"
        $onedrivePath = $onedriveLocations[$selection].FullName
    } else {
        $onedrivePath = Read-Host "Enter OneDrive location"
    }

    # Prompt for backup subdirectory
    $backupDir = Read-Host "Enter backup directory name [backup]"
    if ([string]::IsNullOrWhiteSpace($backupDir)) {
        $backupDir = "backup"
    }
    $backupRoot = Join-Path $onedrivePath $backupDir

    # Create and populate windows.env
    $windowsEnv = @"
# Windows Configuration Environment Variables
BACKUP_ROOT="$backupRoot"
WINDOWS_CONFIG_PATH="$InstallPath"
MACHINE_NAME="$env:COMPUTERNAME"
"@
    $windowsEnv | Out-File (Join-Path $InstallPath "windows.env") -Force

    # Create config.env with email settings
    $machineConfigPath = Join-Path $machineBackupDir "config.env"
    $sharedConfigPath = Join-Path $sharedBackupDir "config.env"
    
    # Check for existing configs
    $machineConfigExists = Test-Path $machineConfigPath
    $sharedConfigExists = Test-Path $sharedConfigPath
    
    if ($sharedConfigExists) {
        if ($machineConfigExists) {
            $response = Read-Host "`nMachine-specific config.env exists. Would you like to overwrite it with shared config? (Y/N)"
            if ($response -eq "Y" -or $response -eq "y") {
                Copy-Item $sharedConfigPath $machineConfigPath -Force
                Write-Host "Copied shared config.env to machine directory" -ForegroundColor Green
                return
            }
        } else {
            $response = Read-Host "`nShared config.env found. Would you like to use it instead of creating a new one? (Y/N)"
            if ($response -eq "Y" -or $response -eq "y") {
                Copy-Item $sharedConfigPath $machineConfigPath -Force
                Write-Host "Copied shared config.env to machine directory" -ForegroundColor Green
                return
            }
        }
    }

    Write-Host "`nConfigure email notification settings:" -ForegroundColor Blue
    $fromAddress = Read-Host "Enter sender email address (Office 365)"
    $toAddress = Read-Host "Enter recipient email address"
    $emailPassword = Read-Host "Enter email app password" -AsSecureString
    
    # Convert secure string to plain text
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($emailPassword)
    $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    
    # Create config.env content
    $configEnv = @"
# Email notification settings
BACKUP_EMAIL_FROM="$fromAddress"
BACKUP_EMAIL_TO="$toAddress"
BACKUP_EMAIL_PASSWORD="$plainPassword"
"@
    
    # Create machine-specific and shared backup directories
    $machineBackupDir = Join-Path $backupRoot $env:COMPUTERNAME
    $sharedBackupDir = Join-Path $backupRoot "shared"
    
    foreach ($dir in @($machineBackupDir, $sharedBackupDir)) {
        if (!(Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }
    
    # Save config.env to machine-specific backup directory
    $configEnv | Out-File (Join-Path $machineBackupDir "config.env") -Force

    # Change to installation directory for remaining operations
    Set-Location $InstallPath

    # Set initial environment variables
    $env:BACKUP_ROOT = $backupRoot
    $env:WINDOWS_CONFIG_PATH = $InstallPath
    $env:MACHINE_NAME = $env:COMPUTERNAME

    # Now load the environment
    . (Join-Path $InstallPath "scripts\load-environment.ps1")
    if (!(Load-Environment)) {
        Write-Host "Failed to load environment configuration" -ForegroundColor Red
        exit 1
    }

    Write-Host "Installing Windows Configuration Scripts..." -ForegroundColor Blue

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
            if (Test-Path $setupScript) {
                Write-Host "Configuring WSL fonts..." -ForegroundColor Blue
                & $setupScript
            } else {
                Write-Host "WSL fonts setup script not found at: $setupScript" -ForegroundColor Red
            }
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

    if (Test-Path $PROFILE) {
        if (!(Get-Content $PROFILE | Select-String "WINDOWS_CONFIG_PATH")) {
            Add-Content $PROFILE $profileContent
        }
    } else {
        Set-Content $PROFILE $profileContent
    }

    Write-Host "`nInstallation completed successfully!" -ForegroundColor Green
    Write-Host "Installation path: $InstallPath" -ForegroundColor Yellow
    Write-Host "Please restart PowerShell for PATH changes to take effect" -ForegroundColor Yellow

} catch {
    Write-Host "Installation failed: $_" -ForegroundColor Red
    exit 1
}