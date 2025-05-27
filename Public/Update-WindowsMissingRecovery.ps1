# Update Installed Apps/Tools/etc.

# At the start of the script
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path

# Get configuration from the module
$config = Get-WindowsMissingRecovery
if (!$config.BackupRoot) {
    Write-Host "Configuration not initialized. Please run Initialize-WindowsMissingRecovery first." -ForegroundColor Yellow
    return
}

# Now load environment with configuration available
. (Join-Path $scriptPath "scripts\load-environment.ps1")

# Define proper backup paths using config values
$BACKUP_ROOT = $config.BackupRoot
$MACHINE_NAME = $config.MachineName
$WINDOWS_CONFIG_PATH = $config.WindowsMissingRecoveryPath

# Collect any errors during update
$updateErrors = @()

# Create a temporary file for capturing console output
$tempLogFile = [System.IO.Path]::GetTempFileName()

try {
    # Start transcript to capture all console output
    Start-Transcript -Path $tempLogFile -Append

    Write-Host "Starting system updates..." -ForegroundColor Blue

    # Update Windows Store apps
    Write-Host "`nChecking for Windows Store app updates..." -ForegroundColor Yellow
    try {
        Get-CimInstance -Namespace "Root\cimv2\mdm\dmmap" -ClassName "MDM_EnterpriseModernAppManagement_AppManagement01" | 
            Invoke-CimMethod -MethodName UpdateScanMethod
        Write-Host "Windows Store apps check completed" -ForegroundColor Green
    } catch {
        $errorMessage = "Failed to check Windows Store apps: $_"
        Write-Host $errorMessage -ForegroundColor Red
        $updateErrors += $errorMessage
    }

    # Update Winget packages
    Write-Host "`nUpdating Winget packages..." -ForegroundColor Yellow
    try {
        winget upgrade --all --accept-source-agreements --accept-package-agreements --include-unknown
        Write-Host "Winget packages updated successfully" -ForegroundColor Green
    } catch {
        $errorMessage = "Failed to update Winget packages: $_"
        Write-Host $errorMessage -ForegroundColor Red
        $updateErrors += $errorMessage
    }

    # Update Chocolatey packages if installed
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        Write-Host "`nUpdating Chocolatey packages..." -ForegroundColor Yellow
        try {
            choco upgrade all -y
            Write-Host "Chocolatey packages updated successfully" -ForegroundColor Green
        } catch {
            $errorMessage = "Failed to update Chocolatey packages: $_"
            Write-Host $errorMessage -ForegroundColor Red
            $updateErrors += $errorMessage
        }
    }

    # Update Scoop packages if installed
    if (Get-Command scoop -ErrorAction SilentlyContinue) {
        Write-Host "`nUpdating Scoop packages..." -ForegroundColor Yellow
        try {
            scoop update
            scoop update *
            Write-Host "Scoop packages updated successfully" -ForegroundColor Green
        } catch {
            $errorMessage = "Failed to update Scoop packages: $_"
            Write-Host $errorMessage -ForegroundColor Red
            $updateErrors += $errorMessage
        }
    }

    # Update PowerShell modules
    Write-Host "`nUpdating PowerShell modules..." -ForegroundColor Yellow
    try {
        # Update PowerShellGet itself first if needed
        $psgModule = Get-Module PowerShellGet -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
        $psgLatest = Find-Module PowerShellGet
        if ($psgModule.Version -lt $psgLatest.Version) {
            Write-Host "Updating PowerShellGet..." -ForegroundColor Yellow
            Install-Module PowerShellGet -Force -AllowClobber
            Write-Host "PowerShellGet updated. Please restart PowerShell to use the new version." -ForegroundColor Green
        }

        # Update all installed modules
        $modules = Get-InstalledModule
        foreach ($module in $modules) {
            try {
                $latest = Find-Module -Name $module.Name
                if ($latest.Version -gt $module.Version) {
                    Write-Host "Updating $($module.Name) from $($module.Version) to $($latest.Version)..." -ForegroundColor Yellow
                    Update-Module -Name $module.Name -Force
                    # Clean up older versions
                    Get-InstalledModule -Name $module.Name -AllVersions | 
                        Where-Object Version -lt $latest.Version | 
                        Uninstall-Module -Force
                }
            } catch {
                $errorMessage = "Failed to update module $($module.Name): $_"
                Write-Host $errorMessage -ForegroundColor Red
                $updateErrors += $errorMessage
            }
        }
        Write-Host "PowerShell modules updated successfully" -ForegroundColor Green
    } catch {
        $errorMessage = "Failed to update PowerShell modules: $_"
        Write-Host $errorMessage -ForegroundColor Red
        $updateErrors += $errorMessage
    }

    # Update NuGet packages
    Write-Host "`nUpdating NuGet packages..." -ForegroundColor Yellow
    try {
        # Check if NuGet provider is installed, install if missing
        $nugetProvider = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
        
        if (-not $nugetProvider) {
            Write-Host "NuGet provider not found. Installing NuGet provider..." -ForegroundColor Yellow
            Install-PackageProvider -Name NuGet -Force -Scope CurrentUser
            $nugetProvider = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
        } else {
            # Try to check for updates if NuGet is already installed
            try {
                $nugetLatest = Find-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
                if ($nugetLatest -and $nugetProvider.Version -lt $nugetLatest.Version) {
                    Write-Host "Updating NuGet provider..." -ForegroundColor Yellow
                    Install-PackageProvider -Name NuGet -Force -Scope CurrentUser
                }
            } catch {
                Write-Host "Unable to check for NuGet provider updates: $_" -ForegroundColor Yellow
            }
        }

        # Update all installed NuGet packages
        try {
            $packages = Get-Package -ProviderName NuGet -ErrorAction SilentlyContinue
            
            if ($packages) {
                foreach ($package in $packages) {
                    try {
                        $latest = Find-Package -Name $package.Name -ProviderName NuGet -ErrorAction SilentlyContinue
                        if ($latest -and $latest.Version -gt $package.Version) {
                            Write-Host "Updating $($package.Name) from $($package.Version) to $($latest.Version)..." -ForegroundColor Yellow
                            Install-Package -Name $package.Name -ProviderName NuGet -Force
                        }
                    } catch {
                        $errorMessage = "Failed to update package $($package.Name): $_"
                        Write-Host $errorMessage -ForegroundColor Red
                        $updateErrors += $errorMessage
                    }
                }
            } else {
                Write-Host "No NuGet packages found to update" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "Unable to enumerate NuGet packages: $_" -ForegroundColor Yellow
        }
        
        Write-Host "NuGet packages updated successfully" -ForegroundColor Green
    } catch {
        $errorMessage = "Failed to update NuGet packages: $_"
        Write-Host $errorMessage -ForegroundColor Red
        $updateErrors += $errorMessage
    }

    # Update WSL distributions
    Write-Host "`nUpdating WSL distributions..." -ForegroundColor Yellow
    try {
        # Get all installed WSL distributions
        $wslDistros = wsl --list --quiet

        foreach ($distro in $wslDistros) {
            $distro = $distro.Trim()
            if ($distro -ne "") {
                Write-Host "Updating $distro..." -ForegroundColor Yellow
                
                # Update package lists and upgrade packages based on distribution
                try {
                    # Get distribution info
                    $distroInfo = wsl -d $distro cat /etc/os-release
                    $isUbuntu = $distroInfo -match "Ubuntu"
                    $isDebian = $distroInfo -match "Debian"
                    $isFedora = $distroInfo -match "Fedora"
                    $isOpenSUSE = $distroInfo -match "openSUSE"
                    
                    if ($isUbuntu -or $isDebian) {
                        # Ubuntu/Debian-based distributions
                        wsl -d $distro sudo apt update
                        wsl -d $distro sudo apt upgrade -y
                        wsl -d $distro sudo apt autoremove -y
                    }
                    elseif ($isFedora) {
                        # Fedora-based distributions
                        wsl -d $distro sudo dnf upgrade -y
                        wsl -d $distro sudo dnf autoremove -y
                    }
                    elseif ($isOpenSUSE) {
                        # openSUSE
                        wsl -d $distro sudo zypper refresh
                        wsl -d $distro sudo zypper update -y
                        wsl -d $distro sudo zypper clean --all
                    }
                    
                    # Update specific package managers if installed
                    # Check for and update Snap packages
                    wsl -d $distro which snap 2>&1 | Out-Null
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "Updating Snap packages in $distro..." -ForegroundColor Yellow
                        wsl -d $distro sudo snap refresh
                    }

                    # Check for and update Flatpak packages
                    wsl -d $distro which flatpak 2>&1 | Out-Null
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "Updating Flatpak packages in $distro..." -ForegroundColor Yellow
                        wsl -d $distro flatpak update -y
                    }

                    # Check for and update npm global packages
                    wsl -d $distro which npm 2>&1 | Out-Null
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "Updating npm global packages in $distro..." -ForegroundColor Yellow
                        wsl -d $distro sudo npm update -g
                    }

                    # Check for and update pip packages
                    wsl -d $distro which pip3 2>&1 | Out-Null
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "Updating pip packages in $distro..." -ForegroundColor Yellow
                        wsl -d $distro pip3 list --outdated --format=json | 
                            wsl -d $distro python3 -c "import json, sys; print('\n'.join([p['name'] for p in json.load(sys.stdin)]))" |
                            ForEach-Object { wsl -d $distro pip3 install -U $_ }
                    }

                    Write-Host "$distro updates completed successfully" -ForegroundColor Green
                } catch {
                    $errorMessage = "Failed to update $distro : $_"
                    Write-Host $errorMessage -ForegroundColor Red
                    $updateErrors += $errorMessage
                }
            }
        }
        Write-Host "WSL updates completed" -ForegroundColor Green
    } catch {
        $errorMessage = "Failed to update WSL distributions: $_"
        Write-Host $errorMessage -ForegroundColor Red
        $updateErrors += $errorMessage
    }

    Write-Host "`nSystem update completed!" -ForegroundColor Green
    Write-Host "Note: Some updates may require a system restart to take effect" -ForegroundColor Yellow

} finally {
    # Stop transcript
    Stop-Transcript

    # Read the console output and look for error patterns
    $consoleOutput = Get-Content -Path $tempLogFile -Raw
    $errorPatterns = @(
        'error',
        'exception',
        'failed',
        'failure',
        'unable to'
    )

    foreach ($pattern in $errorPatterns) {
        if ($consoleOutput -match "(?im)$pattern") {
            $matchs = [regex]::Matches($consoleOutput, "(?im).*$pattern.*")
            foreach ($match in $matchs) {
                $errorMessage = "Console output error: $($match.Value.Trim())"
                if ($updateErrors -notcontains $errorMessage) {
                    $updateErrors += $errorMessage
                }
            }
        }
    }

    # Clean up temporary file
    Remove-Item -Path $tempLogFile -Force
}

# Email notification function
function Send-UpdateNotification {
    param (
        [string[]]$Errors,
        [string]$Subject,
        [string]$SmtpServer = "smtp.office365.com",
        [int]$Port = 587
    )
    
    # Email configuration - load from environment variables for security
    $fromAddress = $env:BACKUP_EMAIL_FROM
    $toAddress = $env:BACKUP_EMAIL_TO
    $emailPassword = $env:BACKUP_EMAIL_PASSWORD
    
    # Check if email configuration exists
    if (!$fromAddress -or !$toAddress -or !$emailPassword) {
        Write-Host "Email notification skipped - environment variables not configured" -ForegroundColor Yellow
        return
    }
    
    try {
        # Create email body with more detailed information
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $body = @"
System Update Status Report from $env:COMPUTERNAME
Timestamp: $timestamp

Summary:
- Total Errors: $($Errors.Count)

Errors encountered during update:
$($Errors | ForEach-Object { "- $_`n" })

This is an automated message.
"@
        
        # Create credential object
        $securePassword = ConvertTo-SecureString $emailPassword -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential ($fromAddress, $securePassword)
        
        # Send email
        Send-MailMessage `
            -From $fromAddress `
            -To $toAddress `
            -Subject $Subject `
            -Body $body `
            -SmtpServer $SmtpServer `
            -Port $Port `
            -UseSsl `
            -Credential $credential
            
        Write-Host "Update notification email sent successfully" -ForegroundColor Green
    } catch {
        Write-Host "Failed to send email notification: $_" -ForegroundColor Red
    }
}

# Send email notification if there were any errors
if ($updateErrors.Count -gt 0) {
    $subject = "⚠️ System Update Failed on $env:COMPUTERNAME ($($updateErrors.Count) errors)"
    Send-UpdateNotification -Errors $updateErrors -Subject $subject
}

