function Setup-EAGames {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$GamesListPath = $null,
        [Parameter(Mandatory=$false)]
        [switch]$Install
    )

    # Load environment configuration (optional - module will use fallback configuration)
    try {
        Load-Environment | Out-Null
    } catch {
        Write-Verbose "Using module configuration fallback"
    }

    function Install-EAApp {
        $eaPath = "$env:LOCALAPPDATA\Electronic Arts\EA Desktop\EA Desktop\EADesktop.exe"
        if (Test-Path $eaPath) {
            return $true
        }

        Write-Host "EA app not found. Would you like to install it? (Y/N)" -ForegroundColor Yellow
        $response = Read-Host
        if ($response -eq 'Y' -or $response -eq 'y') {
            try {
                # Download EA app installer
                $installerUrl = "https://origin-a.akamaihd.net/EA-Desktop-Client-Download/installer-releases/EAappInstaller.exe"
                $installerPath = Join-Path $env:TEMP "EAappInstaller.exe"

                Write-Host "Downloading EA app installer..." -ForegroundColor Yellow
                Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath

                # Install EA app
                Write-Host "Installing EA app..." -ForegroundColor Yellow
                Start-Process -FilePath $installerPath -ArgumentList "/silent" -Wait

                Remove-Item $installerPath
                return $true
            }
            catch {
                Write-Host "Failed to install EA app: $($_.Exception.Message)" -ForegroundColor Red
                return $false
            }
        }
        return $false
    }

    function Get-InstalledGames {
        $installedGames = @()

        # Check EA app installation
        $contentPath = "$env:PROGRAMDATA\Electronic Arts\EA Desktop\Downloaded"
        $manifestPath = "$env:LOCALAPPDATA\Electronic Arts\EA Desktop\Downloaded"

        if (Test-Path $contentPath) {
            Get-ChildItem $contentPath -Filter "*.json" | ForEach-Object {
                try {
                    $content = Get-Content $_.FullName | ConvertFrom-Json
                    if ($content.gameTitle) {
                        $installedGames += @{
                            Name = $content.gameTitle
                            Id = $content.gameId
                            InstallPath = $content.installPath
                        }
                    }
                }
                catch {
                    Write-Host "Error reading EA game info: $($_.Exception.Message)" -ForegroundColor Red
                }
            }
        }

        return $installedGames
    }

    try {
        Write-Host "Setting up EA Games..." -ForegroundColor Blue

        # Determine games list path
        if (!$GamesListPath) {
            $backupPath = Join-Path $env:BACKUP_ROOT $env:MACHINE_NAME "Applications"
            $backupGamesPath = Join-Path $backupPath "ea-applications.json"

            if (Test-Path $backupGamesPath) {
                $applications = Get-Content $backupGamesPath | ConvertFrom-Json
                if ($applications.EA) {
                    $gamesList = $applications.EA
                } else {
                    Write-Host "No EA games found in backup" -ForegroundColor Yellow
                    $gamesList = @()
                }
            } else {
                Write-Host "No games list found in backup location" -ForegroundColor Yellow
                $gamesList = @()
            }
        } else {
            if (!(Test-Path $GamesListPath)) {
                Write-Host "Games list not found at: $GamesListPath" -ForegroundColor Red
                return $false
            }
            $gamesList = Get-Content $GamesListPath | ConvertFrom-Json
        }

        # Install EA app if needed
        if (!(Install-EAApp)) {
            Write-Host "EA app is required to install games" -ForegroundColor Red
            return $false
        }

        $installedGames = Get-InstalledGames

        # Show current status
        Write-Host "`nInstalled EA Games:" -ForegroundColor Blue
        if ($installedGames.Count -gt 0) {
            $installedGames | ForEach-Object {
                Write-Host "- $($_.Name) (ID: $($_.Id))" -ForegroundColor Green
            }
        } else {
            Write-Host "No EA games currently installed" -ForegroundColor Gray
        }

        if ($gamesList.Count -gt 0) {
            Write-Host "`nGames to Install:" -ForegroundColor Blue
            $gamesToInstall = $gamesList | Where-Object { $_.Id -notin $installedGames.Id }
            if ($gamesToInstall.Count -gt 0) {
                $gamesToInstall | ForEach-Object {
                    Write-Host "- $($_.Name) (ID: $($_.Id))" -ForegroundColor Yellow
                }
            } else {
                Write-Host "All games from backup are already installed!" -ForegroundColor Green
            }

            if ($Install -and $gamesToInstall.Count -gt 0) {
                # Launch EA app for installation
                Write-Host "`nLaunching EA app..." -ForegroundColor Yellow
                Write-Host "Please install the following games manually:" -ForegroundColor Yellow
                $gamesToInstall | ForEach-Object {
                    Write-Host "- $($_.Name)" -ForegroundColor Cyan
                }

                Start-Process "$env:LOCALAPPDATA\Electronic Arts\EA Desktop\EA Desktop\EADesktop.exe"
            }
            elseif (!$Install -and $gamesToInstall.Count -gt 0) {
                Write-Host "`nRun with -Install to begin installation process" -ForegroundColor Yellow
            }
        } else {
            Write-Host "`nNo games list found to install from" -ForegroundColor Gray
        }

        Write-Host "`nEA Games setup completed!" -ForegroundColor Green
        return $true

    } catch {
        Write-Host "Failed to setup EA Games: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}
