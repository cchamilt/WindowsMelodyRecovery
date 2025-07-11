function Initialize-EAGames {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$GamesListPath = $null,
        [Parameter(Mandatory=$false)]
        [switch]$Install
    )

    # Load environment configuration (optional - module will use fallback configuration)
    try {
        Import-Environment | Out-Null
    } catch {
        Write-Verbose "Using module configuration fallback"
    }

    function Install-EAApp {
        $eaPath = "$env:LOCALAPPDATA\Electronic Arts\EA Desktop\EA Desktop\EADesktop.exe"
        if (Test-Path $eaPath) {
            return $true
        }

        Write-Warning -Message "EA app not found. Would you like to install it? (Y/N)"
        $response = Read-Host
        if ($response -eq 'Y' -or $response -eq 'y') {
            try {
                # Download EA app installer
                $installerUrl = "https://origin-a.akamaihd.net/EA-Desktop-Client-Download/installer-releases/EAappInstaller.exe"
                $installerPath = Join-Path $env:TEMP "EAappInstaller.exe"

                Write-Warning -Message "Downloading EA app installer..."
                Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath

                # Install EA app
                Write-Warning -Message "Installing EA app..."
                Start-Process -FilePath $installerPath -ArgumentList "/silent" -Wait

                Remove-Item $installerPath
                return $true
            }
            catch {
                Write-Error -Message "Failed to install EA app: $($_.Exception.Message)"
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
                    Write-Error -Message "Error reading EA game info: $($_.Exception.Message)"
                }
            }
        }

        return $installedGames
    }

    try {
        Write-Information -MessageData "Setting up EA Games..." -InformationAction Continue

        # Determine games list path
        if (!$GamesListPath) {
            $backupPath = Join-Path $env:BACKUP_ROOT $env:MACHINE_NAME "Applications"
            $backupGamesPath = Join-Path $backupPath "ea-applications.json"

            if (Test-Path $backupGamesPath) {
                $applications = Get-Content $backupGamesPath | ConvertFrom-Json
                if ($applications.EA) {
                    $gamesList = $applications.EA
                } else {
                    Write-Warning -Message "No EA games found in backup"
                    $gamesList = @()
                }
            } else {
                Write-Warning -Message "No games list found in backup location"
                $gamesList = @()
            }
        } else {
            if (!(Test-Path $GamesListPath)) {
                Write-Error -Message "Games list not found at: $GamesListPath"
                return $false
            }
            $gamesList = Get-Content $GamesListPath | ConvertFrom-Json
        }

        # Install EA app if needed
        if (!(Install-EAApp)) {
            Write-Error -Message "EA app is required to install games"
            return $false
        }

        $installedGames = Get-InstalledGames

        # Show current status
        Write-Information -MessageData "`nInstalled EA Games:" -InformationAction Continue
        if ($installedGames.Count -gt 0) {
            $installedGames | ForEach-Object {
                Write-Information -MessageData "- $($_.Name) (ID: $($_.Id))" -InformationAction Continue
            }
        } else {
            Write-Verbose -Message "No EA games currently installed"
        }

        if ($gamesList.Count -gt 0) {
            Write-Information -MessageData "`nGames to Install:" -InformationAction Continue
            $gamesToInstall = $gamesList | Where-Object { $_.Id -notin $installedGames.Id }
            if ($gamesToInstall.Count -gt 0) {
                $gamesToInstall | ForEach-Object {
                    Write-Warning -Message "- $($_.Name) (ID: $($_.Id))"
                }
            } else {
                Write-Information -MessageData "All games from backup are already installed!" -InformationAction Continue
            }

            if ($Install -and $gamesToInstall.Count -gt 0) {
                # Launch EA app for installation
                Write-Warning -Message "`nLaunching EA app..."
                Write-Warning -Message "Please install the following games manually:"
                $gamesToInstall | ForEach-Object {
                    Write-Information -MessageData "- $($_.Name)" -InformationAction Continue
                }

                Start-Process "$env:LOCALAPPDATA\Electronic Arts\EA Desktop\EA Desktop\EADesktop.exe"
            }
            elseif (!$Install -and $gamesToInstall.Count -gt 0) {
                Write-Warning -Message "`nRun with -Install to begin installation process"
            }
        } else {
            Write-Verbose -Message "`nNo games list found to install from"
        }

        Write-Information -MessageData "`nEA Games setup completed!" -InformationAction Continue
        return $true

    } catch {
        Write-Error -Message "Failed to setup EA Games: $($_.Exception.Message)"
        return $false
    }
}











