function Setup-WindowsMissingRecovery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$InstallPath = "$env:USERPROFILE\Scripts\WindowsMissingRecovery",
        [switch]$NoScheduledTasks,
        [switch]$NoPrompt,
        [switch]$Force
    )

    # Check for admin privileges
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Warning "This function requires administrator privileges. Please run PowerShell as Administrator."
        return $false
    }

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

