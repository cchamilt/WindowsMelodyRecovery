# Requires admin privileges
#Requires -RunAsAdministrator

function Install-WindowsConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$InstallPath = "$env:USERPROFILE\Scripts\WindowsConfig",
        [switch]$NoScheduledTasks,
        [switch]$NoPrompt
    )

    # Verify running as admin
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "This function requires elevation. Please run PowerShell as Administrator."
    }

    try {
        # Get module base path
        $scriptPath = $PSScriptRoot
        $moduleBase = Split-Path -Parent (Split-Path -Parent $scriptPath)

        # Try to load environment
        $envLoaded = Load-Environment

        # If environment not loaded and script is run from installation directory
        if (!$envLoaded -and (Test-Path (Join-Path $scriptPath "config.env.template"))) {
            Write-Host "No config.env found. Would you like to create one now? (Y/N)" -ForegroundColor Yellow
            $response = Read-Host
            if ($response -eq 'Y' -or $response -eq 'y') {
                # Get required values from user
                $backupRoot = Read-Host "Enter backup root directory path"
                $machineName = Read-Host "Enter machine name"
                
                # Create config.env
                $configContent = @"
BACKUP_ROOT=$backupRoot
MACHINE_NAME=$machineName
"@
                Set-Content -Path (Join-Path $scriptPath "config.env") -Value $configContent
                
                # Try loading again
                $envLoaded = Load-Environment
            }
        }

        if (!$envLoaded) {
            Write-Host "Failed to load environment configuration. Please ensure config.env exists and is properly configured." -ForegroundColor Red
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

            # Load existing windows.env if it exists
            $windowsEnvPath = Join-Path $InstallPath "windows.env"
            $existingBackupRoot = $null
            if (Test-Path $windowsEnvPath) {
                Get-Content $windowsEnvPath | ForEach-Object {
                    if ($_ -match '^BACKUP_ROOT="(.*)"$') {
                        $existingBackupRoot = $matches[1]
                    }
                }
            }

            # Create and validate installation directory
            if (!(Test-Path $InstallPath)) {
                New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
            }

            # Only copy files if installing to a different location
            $currentDir = Split-Path -Path $MyInvocation.MyCommand.Definition
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

            # Prompt for backup location
            $backupRoot = ""
            if ($existingBackupRoot) {
                Write-Host "Current backup location: $existingBackupRoot" -ForegroundColor Yellow
                $response = Read-Host "Keep current backup location? (Y/N)"
                if ($response -eq "Y" -or $response -eq "y") {
                    $backupRoot = $existingBackupRoot
                }
            }

            if (!$backupRoot) {
                # Detect possible OneDrive locations
                $possibleOneDrives = @(
                    "$env:USERPROFILE\OneDrive",
                    "$env:USERPROFILE\OneDrive - *"
                )
                $onedriveLocations = Get-Item -Path $possibleOneDrives -ErrorAction SilentlyContinue
                
                if ($onedriveLocations.Count -gt 0) {
                    Write-Host "`nDetected OneDrive locations:" -ForegroundColor Blue
                    for ($i=0; $i -lt $onedriveLocations.Count; $i++) {
                        Write-Host "[$i] $($onedriveLocations[$i].FullName)"
                    }
                    Write-Host "[C] Custom location"
                    
                    do {
                        $selection = Read-Host "`nSelect OneDrive location [0-$($onedriveLocations.Count-1)] or [C]"
                        if ($selection -eq "C") {
                            $backupRoot = Read-Host "Enter custom backup location"
                        } elseif ($selection -match '^\d+$' -and [int]$selection -lt $onedriveLocations.Count) {
                            $backupRoot = Join-Path $onedriveLocations[$selection].FullName "WindowsConfig"
                        }
                    } while (!$backupRoot)
                } else {
                    do {
                        $backupRoot = Read-Path "Enter backup root directory path"
                    } while (!$backupRoot)
                }
            }

            # Create machine-specific backup directory
            $machineBackupDir = Join-Path $backupRoot $env:COMPUTERNAME
            if (!(Test-Path $machineBackupDir)) {
                New-Item -ItemType Directory -Path $machineBackupDir -Force | Out-Null
            }

            # Only update windows.env if backup location changed
            if (!$existingBackupRoot -or ($existingBackupRoot -ne $backupRoot)) {
                $windowsEnv = @"
# Windows Configuration Environment Variables
BACKUP_ROOT="$backupRoot"
WINDOWS_CONFIG_PATH="$InstallPath"
MACHINE_NAME="$env:COMPUTERNAME"
"@
                $windowsEnv | Out-File $windowsEnvPath -Force
                Write-Host "Updated windows.env with new backup location" -ForegroundColor Green
            }
        }
        
        # Prompt for backup subdirectory
        $backupDir = Read-Host "Enter backup directory name [backup]"
        if ([string]::IsNullOrWhiteSpace($backupDir)) {
            $backupDir = "backup"
        }
        $backupRoot = Join-Path $backupRoot $backupDir

        # Create backup root if it doesn't exist
        if (!(Test-Path $backupRoot)) {
            New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
        }

        # Create machine-specific backup directory
        $machineBackupDir = Join-Path $backupRoot $env:COMPUTERNAME
        if (!(Test-Path $machineBackupDir)) {
            New-Item -ItemType Directory -Path $machineBackupDir -Force | Out-Null
        }

        # Set module configuration
        $emailParams = @{
            BackupRoot = $backupRoot
        }
        
        # Only prompt for email settings if we need to create a new machine config
        Write-Host "`nConfigure email notification settings:" -ForegroundColor Blue
        $fromAddress = Read-Host "Enter sender email address (Office 365)"
        $toAddress = Read-Host "Enter recipient email address"
        $emailPassword = Read-Host "Enter email app password" -AsSecureString
        
        # Convert secure string to plain text
        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($emailPassword)
        $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)

        if ($fromAddress) {
            $emailParams['FromAddress'] = $fromAddress
            $emailParams['ToAddress'] = $toAddress
            $emailParams['EmailPassword'] = $emailPassword
        }
        
        Set-WindowsConfig @emailParams

        # Create shared backup directory
        $sharedBackupDir = Join-Path $backupRoot "shared"
        if (!(Test-Path $sharedBackupDir)) {
            New-Item -ItemType Directory -Path $sharedBackupDir -Force | Out-Null
        }
        
        # Create config.env with email settings
        $machineConfigPath = Join-Path $machineBackupDir "config.env"
        $sharedConfigPath = Join-Path $sharedBackupDir "config.env"
        
        # Check for existing configs
        $machineConfigExists = Test-Path $machineConfigPath
        $sharedConfigExists = Test-Path $sharedConfigPath
        
        $createConfig = $true
        if ($machineConfigExists) {
            $response = Read-Host "`nMachine-specific config.env exists. Would you like to recreate it? (Y/N)"
            $createConfig = $response -eq "Y" -or $response -eq "y"
        } elseif ($sharedConfigExists) {
            Write-Host "`nShared config.env exists." -ForegroundColor Yellow
            $response = Read-Host "Would you like to create a machine-specific config? (Y/N)"
            $createConfig = $response -eq "Y" -or $response -eq "y"
        }

        if ($createConfig) {
            # Only prompt for email settings if we need to create a new machine config
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
            
            # Save config.env to machine-specific backup directory
            $configEnv | Out-File $machineConfigPath -Force
        }

        # Change to installation directory for remaining operations
        Set-Location $InstallPath

        # Set initial environment variables
        $env:BACKUP_ROOT = $backupRoot
        $env:WINDOWS_CONFIG_PATH = $InstallPath
        $env:MACHINE_NAME = $env:COMPUTERNAME

        # Verify backup root exists
        if (!(Test-Path $env:BACKUP_ROOT)) {
            Write-Host "Backup root directory not found: $env:BACKUP_ROOT" -ForegroundColor Red
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

        # Offer to run the backup now
        $response = Read-Host "Would you like to run the backup now? (Y/N)"
        if ($response -eq "Y" -or $response -eq "y") {
            try {
                $backupScript = Join-Path $InstallPath "Backup-WindowsConfig.ps1"
                Write-Host "Running backup..." -ForegroundColor Blue
                & $backupScript
            } catch {
                Write-Host "Failed to run backup: $_" -ForegroundColor Red
            }
        } 

        # Setup Package Managers
        if (!$NoPrompt) {
            $response = Read-Host "Would you like to set up Package Managers? (Y/N)"
            if ($response -eq "Y" -or $response -eq "y") {
                $setupScript = Join-Path $InstallPath "setup\setup-packagemanagers.ps1"
                if (Test-Path $setupScript) {
                    & $setupScript
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

        return $true
    } catch {
        Write-Error "Failed to install Windows Configuration: $_"
        return $false
    }
}