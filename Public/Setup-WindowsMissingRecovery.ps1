# Requires admin privileges
#Requires -RunAsAdministrator

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

        # Check if configuration is already initialized
        $config = Get-WindowsMissingRecovery
        if (!$config.BackupRoot -or $Force) {
            Write-Host "Configuration not found or Force specified. Please run Initialize-WindowsMissingRecovery first." -ForegroundColor Yellow
            if (!$NoPrompt) {
                $response = Read-Host "Would you like to run initialization now? (Y/N)"
                if ($response -eq 'Y') {
                    $config = Initialize-WindowsMissingRecovery -InstallPath $InstallPath -NoPrompt:$NoPrompt -Force:$Force
                    if (!$config) {
                        throw "Failed to initialize Windows Recovery configuration"
                    }
                } else {
                    throw "Setup requires initialization. Please run Initialize-WindowsMissingRecovery first."
                }
            } else {
                throw "Setup requires initialization. Please run Initialize-WindowsMissingRecovery first."
            }
        } else {
            Write-Host "Using existing configuration" -ForegroundColor Green
        }

        # Load setup scripts on demand
        Import-PrivateScripts -Category 'setup'

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

        # Optional setup components
        $setupOptions = @(
            @{ Name = "Package Managers"; Function = "Setup-PackageManagers"; Prompt = "Would you like to set up Package Managers? (Y/N)" },
            @{ Name = "KeePassXC"; Function = "Setup-KeePassXC"; Prompt = "Would you like to set up KeePassXC? (Y/N)" },
            @{ Name = "Bloatware Removal"; Function = "Setup-RemoveBloat"; Prompt = "Would you like to remove Windows bloatware? (Y/N)" },
            @{ Name = "Windows Defender"; Function = "Setup-Defender"; Prompt = "Would you like to configure Windows Defender? (Y/N)" },
            @{ Name = "WSL Fonts"; Function = "Setup-WSLFonts"; Prompt = "Would you like to configure WSL fonts? (Y/N)" },
            @{ Name = "System Restore"; Function = "Setup-RestorePoints"; Prompt = "Would you like to configure System Restore points? (Y/N)" }
        )

        foreach ($option in $setupOptions) {
            if (!$NoPrompt) {
                $response = Read-Host $option.Prompt
                if ($response -eq "Y" -or $response -eq "y") {
                    if (Get-Command $option.Function -ErrorAction SilentlyContinue) {
                        try {
                            Write-Host "Running $($option.Name) setup..." -ForegroundColor Blue
                            & $option.Function
                            Write-Host "$($option.Name) setup completed." -ForegroundColor Green
                        } catch {
                            Write-Host "Failed to run $($option.Name) setup: $_" -ForegroundColor Red
                        }
                    } else {
                        Write-Host "$($option.Name) setup function not available." -ForegroundColor Yellow
                    }
                }
            }
        }