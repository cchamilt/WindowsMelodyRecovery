# Requires admin privileges
#Requires -RunAsAdministrator

# Import necessary functions
. $PSScriptRoot\..\Scripts\load-environment.ps1
. $PSScriptRoot\Initialize-WindowsMissingRecovery.ps1
. $PSScriptRoot\Install-WindowsMissingRecoveryTasks.ps1
. $PSScriptRoot\Remove-WindowsMissingRecoveryTasks.ps1

function Setup-WindowsMissingRecovery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$InstallPath = "$env:USERPROFILE\Scripts\WindowsMissingRecovery",
        [switch]$NoScheduledTasks,
        [switch]$NoPrompt,
        [switch]$Force
    )

    try {
        Write-Host "Starting Windows Recovery Setup..." -ForegroundColor Blue

        # Step 1: Initialize configuration
        if (!(Initialize-WindowsMissingRecovery -InstallPath $InstallPath -NoPrompt:$NoPrompt)) {
            throw "Failed to initialize Windows Recovery configuration"
        }

        # Step 2: Install scheduled tasks (if not disabled)
        if (!$NoScheduledTasks) {
            if ($Force -or !$NoPrompt) {
                $response = if ($NoPrompt) { 'Y' } else { Read-Host "Would you like to install scheduled tasks for backup and updates? (Y/N)" }
                
                if ($response -eq 'Y') {
                    Write-Host "Installing scheduled tasks..." -ForegroundColor Yellow
                    if (!(Install-WindowsMissingRecoveryTasks -InstallPath $InstallPath -Force:$Force)) {
                        Write-Warning "Failed to install scheduled tasks"
                    }
                }
            }
        }

        # Step 3: Verify installation
        Write-Host "`nVerifying installation..." -ForegroundColor Blue
        $verificationResults = @{
            Config = Test-Path (Join-Path $InstallPath "config.env")
            Tasks = if (!$NoScheduledTasks) {
                @(
                    Get-ScheduledTask -TaskName "WindowsMissingRecovery_Backup" -ErrorAction SilentlyContinue,
                    Get-ScheduledTask -TaskName "WindowsMissingRecovery_Update" -ErrorAction SilentlyContinue
                ) | Where-Object { $_ }
            } else { $null }
        }

        # Display verification results
        Write-Host "`nSetup Verification:" -ForegroundColor Green
        Write-Host "Configuration: $(if ($verificationResults.Config) { 'OK' } else { 'Missing' })" -ForegroundColor $(if ($verificationResults.Config) { 'Green' } else { 'Red' })
        if (!$NoScheduledTasks) {
            Write-Host "Scheduled Tasks: $($verificationResults.Tasks.Count) installed" -ForegroundColor $(if ($verificationResults.Tasks.Count -eq 2) { 'Green' } else { 'Yellow' })
        }

        Write-Host "`nWindows Recovery setup completed successfully!" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "`nSetup failed: $_" -ForegroundColor Red
        return $false
    }
}

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    Setup-WindowsMissingRecovery @PSBoundParameters
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