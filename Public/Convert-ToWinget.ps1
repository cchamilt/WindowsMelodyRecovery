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
    $config = Get-WindowsMissingRecovery
    if (!$config.BackupRoot) {
        Write-Host "Configuration not initialized. Please run Initialize-WindowsMissingRecovery first." -ForegroundColor Yellow
        return $false
    }

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
    } catch {
        Write-Host "Failed to search for $AppName in winget: $_" -ForegroundColor Red
    }
    return $null
}

try {
    Write-Host "Scanning for installed applications..." -ForegroundColor Blue
    
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
        Write-Host "No applications found that need conversion to winget" -ForegroundColor Green
        exit 0
    }

    # Create conversion report arrays
    $convertible = @()
    $nonConvertible = @()

    # Check each application for winget availability
    foreach ($app in $nonWingetApps) {
        Write-Host "`nChecking $($app.DisplayName)..." -ForegroundColor Yellow
        $wingetInfo = Get-WingetId -AppName $app.DisplayName

        if ($wingetInfo) {
            $convertible += @{
                Name = $app.DisplayName
                CurrentVersion = $app.DisplayVersion
                WingetId = $wingetInfo.Id
                Source = $wingetInfo.Source
                UninstallString = $app.UninstallString
            }
            Write-Host "Found in winget: $($wingetInfo.Id) from $($wingetInfo.Source)" -ForegroundColor Green
        } else {
            $nonConvertible += $app
            Write-Host "Not found in winget" -ForegroundColor Red
        }
    }

    # Display summary and prompt for action
    Write-Host "`nConversion Summary:" -ForegroundColor Blue
    Write-Host "Convertible to winget: $($convertible.Count)" -ForegroundColor Green
    Write-Host "Non-convertible: $($nonConvertible.Count)" -ForegroundColor Yellow

    if ($convertible.Count -gt 0) {
        $response = Read-Host "`nWould you like to convert the available applications to winget? (Y/N)"
        if ($response -eq "Y" -or $response -eq "y") {
            foreach ($app in $convertible) {
                Write-Host "`nProcessing $($app.Name)..." -ForegroundColor Blue
                
                # Attempt uninstallation
                try {
                    Write-Host "Uninstalling current version..." -ForegroundColor Yellow
                    if ($app.UninstallString -match "msiexec") {
                        $uninstallString = $app.UninstallString -replace "msiexec.exe", "" -replace "/I", "/X" -replace "/i", "/x"
                        Start-Process "msiexec.exe" -ArgumentList "$uninstallString /quiet" -Wait
                    } else {
                        $uninstallProcess = Start-Process $app.UninstallString -Wait -PassThru
                        if ($uninstallProcess.ExitCode -ne 0) {
                            throw "Uninstall process exited with code: $($uninstallProcess.ExitCode)"
                        }
                    }

                    # Install via winget
                    Write-Host "Installing via winget..." -ForegroundColor Yellow
                    winget install --id $app.WingetId --source $app.Source --accept-package-agreements --accept-source-agreements

                    Write-Host "Successfully converted $($app.Name) to winget" -ForegroundColor Green
                } catch {
                    Write-Host "Failed to convert $($app.Name): $_" -ForegroundColor Red
                }
            }
        }
    }

    if ($nonConvertible.Count -gt 0) {
        Write-Host "`nThe following applications cannot be converted to winget:" -ForegroundColor Yellow
        foreach ($app in $nonConvertible) {
            Write-Host "- $($app.DisplayName) ($($app.DisplayVersion))" -ForegroundColor White
        }
    }

    } catch {
        Write-Host "Failed to convert applications to winget: $_" -ForegroundColor Red
        return $false
    }
    
    return $true
}