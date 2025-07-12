# Script to uninstall existing applications and reinstall them via winget

function Convert-ToWinget {
    [CmdletBinding()]
    param()

    # Check for admin privileges
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Warning "This function requires administrator privileges. Please run PowerShell as Administrator."
        return $false
    }

    # Get configuration from the module
    $config = Get-WindowsMelodyRecovery
    if (!$config.BackupRoot) {
        Write-Warning -Message "Configuration not initialized. Please run Initialize-WindowsMelodyRecovery first."
        return $false
    }

    # Helper function to get winget ID for an application
    function Get-WingetId {
        param (
            [string]$AppName
        )

        try {
            $wingetSearch = winget search --exact $AppName | Out-String

            # Escape special regex characters in the app name
            $escapedAppName = [regex]::Escape($AppName)

            if ($wingetSearch -match "$escapedAppName\s+(\S+)\s+.*?(\w+)$") {
                return @{
                    Id = $matches[1]
                    Source = $matches[2]
                }
            }
        }
        catch {
            Write-Error -Message "Failed to search for $AppName in winget: $_"
        }
        return $null
    }

    try {
        Write-Information -MessageData "Scanning for installed applications..." -InformationAction Continue

        # Get all installed programs from registry
        $regPaths = @(
            'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
        )

        $applications = @()
        foreach ($path in $regPaths) {
            $applications += Get-ItemProperty $path |
                Where-Object { $_.DisplayName -and $_.UninstallString } |
                Select-Object DisplayName, Publisher, DisplayVersion, UninstallString
        }

        # Filter out already winget-managed applications
        $wingetList = winget list --accept-source-agreements | Out-String
        $wingetApps = $wingetList -split "`n" |
            Select-Object -Skip 2 |
            Where-Object { $_ -match '\S' } |
            ForEach-Object {
                if ($_ -match '^(.*?)\s+\d') { $matches[1].Trim() }
            }

        $nonWingetApps = $applications | Where-Object { $_.DisplayName -notin $wingetApps }

        if ($nonWingetApps.Count -eq 0) {
            Write-Information -MessageData "No applications found that need conversion to winget" -InformationAction Continue
            return $true
        }

        # Create conversion report arrays
        $convertible = @()
        $nonConvertible = @()

        # Check each application for winget availability
        foreach ($app in $nonWingetApps) {
            Write-Warning -Message "`nChecking $($app.DisplayName)..."
            $wingetInfo = Get-WingetId -AppName $app.DisplayName

            if ($wingetInfo) {
                $convertible += @{
                    Name = $app.DisplayName
                    CurrentVersion = $app.DisplayVersion
                    WingetId = $wingetInfo.Id
                    Source = $wingetInfo.Source
                    UninstallString = $app.UninstallString
                }
                Write-Information -MessageData "Found in winget: $($wingetInfo.Id) from $($wingetInfo.Source)" -InformationAction Continue
            }
            else {
                $nonConvertible += $app
                Write-Error -Message "Not found in winget"
            }
        }

        # Display summary and prompt for action
        Write-Information -MessageData "`nConversion Summary:" -InformationAction Continue
        Write-Information -MessageData "Convertible to winget: $($convertible.Count)" -InformationAction Continue
        Write-Warning -Message "Non-convertible: $($nonConvertible.Count)"

        if ($convertible.Count -gt 0) {
            $response = Read-Host "`nWould you like to convert the available applications to winget? (Y/N)"
            if ($response -eq "Y" -or $response -eq "y") {
                foreach ($app in $convertible) {
                    Write-Information -MessageData "`nProcessing $($app.Name)..." -InformationAction Continue

                    # Attempt uninstallation
                    try {
                        Write-Warning -Message "Uninstalling current version..."
                        if ($app.UninstallString -match "msiexec") {
                            $uninstallString = $app.UninstallString -replace "msiexec.exe", "" -replace "/I", "/X" -replace "/i", "/x"
                            Start-Process "msiexec.exe" -ArgumentList "$uninstallString /quiet" -Wait
                        }
                        else {
                            $uninstallProcess = Start-Process $app.UninstallString -Wait -PassThru
                            if ($uninstallProcess.ExitCode -ne 0) {
                                throw "Uninstall process exited with code: $($uninstallProcess.ExitCode)"
                            }
                        }

                        # Install via winget
                        Write-Warning -Message "Installing via winget..."
                        winget install --id $app.WingetId --source $app.Source --accept-package-agreements --accept-source-agreements

                        Write-Information -MessageData "Successfully converted $($app.Name) to winget" -InformationAction Continue
                    }
                    catch {
                        Write-Error -Message "Failed to convert $($app.Name): $_"
                    }
                }
            }
        }

        if ($nonConvertible.Count -gt 0) {
            Write-Warning -Message "`nThe following applications cannot be converted to winget:"
            foreach ($app in $nonConvertible) {
                Write-Information -MessageData " -InformationAction Continue- $($app.DisplayName) ($($app.DisplayVersion))" -ForegroundColor White
            }
        }

        return $true
    }
    catch {
        Write-Error -Message "Failed to convert applications to winget: $_"
        return $false
    }
}







