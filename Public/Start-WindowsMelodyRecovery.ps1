function Start-WindowsMelodyRecovery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$InstallPath = "$env:USERPROFILE\Scripts\WindowsMelodyRecovery",
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
        Write-Information -MessageData "Starting Windows Recovery Setup..." -InformationAction Continue

        # Check if configuration is already initialized
        $config = Get-WindowsMelodyRecovery
        if (!$config.BackupRoot -or $Force) {
            Write-Warning -Message "Configuration not found or Force specified. Please run Initialize-WindowsMelodyRecovery first."
            if (!$NoPrompt) {
                $response = Read-Host "Would you like to run initialization now? (Y/N)"
                if ($response -eq 'Y') {
                    $config = Initialize-WindowsMelodyRecovery -InstallPath $InstallPath -NoPrompt:$NoPrompt -Force:$Force
                    if (!$config) {
                        throw "Failed to initialize Windows Recovery configuration"
                    }
                } else {
                    throw "Setup requires initialization. Please run Initialize-WindowsMelodyRecovery first."
                }
            } else {
                throw "Setup requires initialization. Please run Initialize-WindowsMelodyRecovery first."
            }
        } else {
            Write-Information -MessageData "Using existing configuration" -InformationAction Continue
        }

        # Load setup scripts on demand
        Write-Warning -Message "Loading setup scripts..."
        Import-PrivateScripts -Category 'setup'

        # Verify setup functions are loaded
        $loadedFunctions = Get-Command -Name "Setup-*" -ErrorAction SilentlyContinue
        Write-Information -MessageData "Found $($loadedFunctions.Count) setup functions: $($loadedFunctions.Name -join ', ')" -InformationAction Continue

        # Step 2: Run setup scripts (configurable)
        $setupFunctions = Get-ScriptsConfig -Category 'setup'
        if ($setupFunctions) {
            Write-Information -MessageData "`nAvailable Setup Scripts:" -InformationAction Continue
            foreach ($setup in $setupFunctions) {
                if ($setup.enabled) {
                    if ($NoPrompt -or $Force) {
                        $response = 'Y'
                    } else {
                        $response = Read-Host "Run $($setup.name)? $($setup.description) (Y/N)"
                    }

                    if ($response -eq 'Y') {
                        Write-Warning -Message "Running $($setup.name)..."
                        try {
                            if (Get-Command $setup.function -ErrorAction SilentlyContinue) {
                                & $setup.function
                                Write-Information -MessageData "✅ Completed $($setup.name)" -InformationAction Continue
                            } else {
                                Write-Warning "Setup function $($setup.function) not available"
                            }
                        } catch {
                            Write-Warning "Failed to run $($setup.name): $_"
                        }
                    } else {
                        Write-Verbose -Message "⏭️ Skipped $($setup.name)"
                    }
                } else {
                    Write-Verbose "Setup script $($setup.name) is disabled in configuration"
                }
            }
        } else {
            Write-Warning -Message "No setup scripts configured or available."
        }

        # Step 3: Install scheduled tasks (if not disabled)
        if (!$NoScheduledTasks) {
            if ($Force -or !$NoPrompt) {
                $response = if ($NoPrompt) { 'Y' } else { Read-Host "Would you like to install scheduled tasks for backup and updates? (Y/N)" }

                if ($response -eq 'Y') {
                    Write-Warning -Message "Installing scheduled tasks..."
                    if (!(Install-WindowsMelodyRecoveryTasks -NoPrompt:$NoPrompt)) {
                        Write-Warning "Failed to install scheduled tasks"
                    }
                }
            }
        }

        # Step 4: Verify installation
        Write-Information -MessageData "`nVerifying installation..." -InformationAction Continue
        $verificationResults = @{
            Config = Test-Path (Join-Path $InstallPath "config.env")
            Tasks = if (!$NoScheduledTasks) {
                @(
                    Get-ScheduledTask -TaskName "WindowsMelodyRecovery_Backup" -ErrorAction SilentlyContinue,
                    Get-ScheduledTask -TaskName "WindowsMelodyRecovery_Update" -ErrorAction SilentlyContinue
                ) | Where-Object { $_ }
            } else { $null }
        }

        # Display verification results
        Write-Information -MessageData "`nSetup Verification:" -InformationAction Continue
        Write-Information -MessageData "Configuration: $(if ($verificationResults.Config) { 'OK' } else { 'Missing' })"  -InformationAction Continue-ForegroundColor $(if ($verificationResults.Config) { 'Green' } else { 'Red' })
        if (!$NoScheduledTasks) {
            Write-Information -MessageData "Scheduled Tasks: $($verificationResults.Tasks.Count) installed"  -InformationAction Continue-ForegroundColor $(if ($verificationResults.Tasks.Count -eq 2) { 'Green' } else { 'Yellow' })
        }

        Write-Information -MessageData "`nWindows Recovery setup completed successfully!" -InformationAction Continue
        return $true
    } catch {
        Write-Error -Message "`nSetup failed: $_"
        return $false
    }
}









