function Update-WindowsMelodyRecovery {
    [OutputType([bool], [System.Collections.Hashtable])]
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    # Get configuration from the module
    $config = Get-WindowsMelodyRecovery
    if (!$config.BackupRoot) {
        Write-Warning -Message "Configuration not initialized. Please run Initialize-WindowsMelodyRecovery first."
        return $false
    }

    # Load scripts on demand if needed
    Import-PrivateScript -Category 'scripts'

    # Define proper backup paths using config values
    $WINDOWS_CONFIG_PATH = $config.WindowsMelodyRecoveryPath

    # Collect any errors during update
    $updateErrors = @()

    # Create a temporary file for capturing console output
    $tempLogFile = [System.IO.Path]::GetTempFileName()

    try {
        # Start transcript to capture all console output
        Start-Transcript -Path $tempLogFile -Append

        Write-Information -MessageData "Starting system updates..." -InformationAction Continue

        # Update Windows Store apps
        Write-Warning -Message "`nChecking for Windows Store app updates..."
        try {
            Get-CimInstance -Namespace "Root\cimv2\mdm\dmmap" -ClassName "MDM_EnterpriseModernAppManagement_AppManagement01" |
                Invoke-CimMethod -MethodName UpdateScanMethod
            Write-Information -MessageData "Windows Store apps check completed" -InformationAction Continue
        }
        catch {
            $errorMessage = "Failed to check Windows Store apps: $_"
            Write-Information -MessageData $errorMessage  -InformationAction Continue-ForegroundColor Red
            $updateErrors += $errorMessage
        }

        # Update Winget packages
        Write-Warning -Message "`nUpdating Winget packages..."
        try {
            winget upgrade --all --accept-source-agreements --accept-package-agreements --include-unknown --silent
            Write-Information -MessageData "Winget packages updated successfully" -InformationAction Continue
        }
        catch {
            $errorMessage = "Failed to update Winget packages: $_"
            Write-Information -MessageData $errorMessage  -InformationAction Continue-ForegroundColor Red
            $updateErrors += $errorMessage
        }

        # Update Chocolatey packages if installed
        if (Get-Command choco -ErrorAction SilentlyContinue) {
            Write-Warning -Message "`nUpdating Chocolatey packages..."
            try {
                choco upgrade all -y
                Write-Information -MessageData "Chocolatey packages updated successfully" -InformationAction Continue
            }
            catch {
                $errorMessage = "Failed to update Chocolatey packages: $_"
                Write-Information -MessageData $errorMessage  -InformationAction Continue-ForegroundColor Red
                $updateErrors += $errorMessage
            }
        }

        # Update Scoop packages if installed
        if (Get-Command scoop -ErrorAction SilentlyContinue) {
            Write-Warning -Message "`nUpdating Scoop packages..."
            try {
                scoop update
                scoop update *
                Write-Information -MessageData "Scoop packages updated successfully" -InformationAction Continue
            }
            catch {
                $errorMessage = "Failed to update Scoop packages: $_"
                Write-Information -MessageData $errorMessage  -InformationAction Continue-ForegroundColor Red
                $updateErrors += $errorMessage
            }
        }

        # Update PowerShell modules
        Write-Warning -Message "`nUpdating PowerShell modules..."
        try {
            $modules = Get-InstalledModule
            foreach ($module in $modules) {
                try {
                    $latest = Find-Module -Name $module.Name
                    if ($latest.Version -gt $module.Version) {
                        Write-Warning -Message "Updating $($module.Name) from $($module.Version) to $($latest.Version)..."
                        Update-Module -Name $module.Name -Force
                        # Clean up older versions
                        Get-InstalledModule -Name $module.Name -AllVersions |
                            Where-Object Version -lt $latest.Version |
                            Uninstall-Module -Force
                    }
                }
                catch {
                    $errorMessage = "Failed to update module $($module.Name): $_"
                    Write-Information -MessageData $errorMessage  -InformationAction Continue-ForegroundColor Red
                    $updateErrors += $errorMessage
                }
            }
            Write-Information -MessageData "PowerShell modules updated successfully" -InformationAction Continue
        }
        catch {
            $errorMessage = "Failed to update PowerShell modules: $_"
            Write-Information -MessageData $errorMessage  -InformationAction Continue-ForegroundColor Red
            $updateErrors += $errorMessage
        }

        Write-Information -MessageData "`nSystem update completed!" -InformationAction Continue
        Write-Warning -Message "Note: Some updates may require a system restart to take effect"

    }
    finally {
        # Stop transcript
        Stop-Transcript

        # Read the console output and look for error patterns
        if (Test-Path $tempLogFile) {
            $consoleOutput = Get-Content -Path $tempLogFile -Raw
            $errorPatterns = @('error', 'exception', 'failed', 'failure', 'unable to')

            foreach ($pattern in $errorPatterns) {
                if ($consoleOutput -match "(?im)$pattern") {
                    $errorMatches = [regex]::Matches($consoleOutput, "(?im).*$pattern.*")
                    foreach ($match in $errorMatches) {
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











