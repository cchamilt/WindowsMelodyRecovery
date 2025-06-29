function Update-WindowsMelodyRecovery {
    [CmdletBinding()]
    param()

    # Get configuration from the module
    $config = Get-WindowsMelodyRecovery
    if (!$config.BackupRoot) {
        Write-Host "Configuration not initialized. Please run Initialize-WindowsMelodyRecovery first." -ForegroundColor Yellow
        return $false
    }

    # Load scripts on demand if needed
    Import-PrivateScripts -Category 'scripts'

    # Define proper backup paths using config values
    $BACKUP_ROOT = $config.BackupRoot
    $MACHINE_NAME = $config.MachineName
    $WINDOWS_CONFIG_PATH = $config.WindowsMelodyRecoveryPath

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
            winget upgrade --all --accept-source-agreements --accept-package-agreements --include-unknown --silent
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

        Write-Host "`nSystem update completed!" -ForegroundColor Green
        Write-Host "Note: Some updates may require a system restart to take effect" -ForegroundColor Yellow

    } finally {
        # Stop transcript
        Stop-Transcript

        # Read the console output and look for error patterns
        if (Test-Path $tempLogFile) {
            $consoleOutput = Get-Content -Path $tempLogFile -Raw
            $errorPatterns = @('error', 'exception', 'failed', 'failure', 'unable to')

            foreach ($pattern in $errorPatterns) {
                if ($consoleOutput -match "(?im)$pattern") {
                    $matches = [regex]::Matches($consoleOutput, "(?im).*$pattern.*")
                    foreach ($match in $matches) {
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
    }

    # Return results
    return @{
        Success = $updateErrors.Count -eq 0
        Errors = $updateErrors
    }
}



