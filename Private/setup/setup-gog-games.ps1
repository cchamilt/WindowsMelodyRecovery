function Initialize-GOGGame {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$GamesListPath = $null,
        [Parameter(Mandatory = $false)]
        [switch]$Install
    )

    # Import required modules
    Import-Module WindowsMelodyRecovery -ErrorAction Stop

    function Install-GogGalaxy {
        $gogPath = "C:\Program Files (x86)\GOG Galaxy\GalaxyClient.exe"
        if (Test-Path $gogPath) {
            return $true
        }

        Write-Warning -Message "GOG Galaxy not found. Would you like to install it? (Y/N)"
        $response = Read-Host
        if ($response -eq 'Y' -or $response -eq 'y') {
            try {
                # Download GOG Galaxy installer
                $installerUrl = "https://content-system.gog.com/open_link/download?path=/open/galaxy/client/2.0.0/setup_galaxy_2.0.0.exe"
                $installerPath = Join-Path $env:TEMP "setup_galaxy.exe"

                Write-Warning -Message "Downloading GOG Galaxy installer..."
                Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath

                # Install GOG Galaxy
                Write-Warning -Message "Installing GOG Galaxy..."
                Start-Process -FilePath $installerPath -ArgumentList "/SILENT" -Wait

                Remove-Item $installerPath
                return $true
            }
            catch {
                Write-Error -Message "Failed to install GOG Galaxy: $($_.Exception.Message)"
                return $false
            }
        }
        return $false
    }

    function Get-InstalledGame {
        $installedGames = @()

        $gogPath = "C:\Program Files (x86)\GOG Galaxy"
        if (Test-Path $gogPath) {
            try {
                # Query GOG Galaxy database
                $dbPath = "$env:ProgramData\GOG.com\Galaxy\storage\galaxy-2.0.db"
                if (Test-Path $dbPath) {
                    if (!(Get-Command sqlite3 -ErrorAction SilentlyContinue)) {
                        Write-Warning -Message "Installing SQLite..."
                        if (Get-Command scoop -ErrorAction SilentlyContinue) {
                            scoop install sqlite
                        }
                        else {
                            Write-Warning -Message "SQLite not available. Cannot read GOG Galaxy database."
                            return $installedGames
                        }
                    }

                    $query = "SELECT gamePieceId, title FROM GamePieces WHERE gamePieceTypeId = 'original_title'"
                    $games = sqlite3 $dbPath $query

                    foreach ($game in $games) {
                        $id, $title = $game -split '\|'
                        $installedGames += @{
                            Name = $title
                            Id = $id
                        }
                    }
                }
            }
            catch {
                Write-Error -Message "Error reading GOG Galaxy database: $($_.Exception.Message)"
            }
        }

        return $installedGames
    }

    try {
        Write-Information -MessageData "Setting up GOG games..." -InformationAction Continue

        # Determine games list path
        if (!$GamesListPath) {
            $backupPath = Join-Path $env:BACKUP_ROOT $env:MACHINE_NAME "Applications"
            $backupGamesPath = Join-Path $backupPath "gog-applications.json"

            if (Test-Path $backupGamesPath) {
                $applications = Get-Content $backupGamesPath | ConvertFrom-Json
                if ($applications.GOG) {
                    $gamesList = $applications.GOG
                }
                else {
                    Write-Warning -Message "No GOG games found in backup"
                    $gamesList = @()
                }
            }
            else {
                Write-Warning -Message "No games list found in backup location"
                $gamesList = @()
            }
        }
        else {
            if (!(Test-Path $GamesListPath)) {
                Write-Error -Message "Games list not found at: $GamesListPath"
                return $false
            }
            $gamesList = Get-Content $GamesListPath | ConvertFrom-Json
        }

        # Install GOG Galaxy if needed
        if (!(Install-GogGalaxy)) {
            Write-Error -Message "GOG Galaxy is required to install games"
            Write-Warning -Message "You can install it manually from: https://www.gog.com/galaxy"
            return $false
        }

        $installedGames = Get-InstalledGames

        # Show current status
        Write-Information -MessageData "`nInstalled GOG Games:" -InformationAction Continue
        if ($installedGames.Count -gt 0) {
            $installedGames | ForEach-Object {
                Write-Information -MessageData "- $($_.Name) (ID: $($_.Id))" -InformationAction Continue
            }
        }
        else {
            Write-Verbose -Message "No GOG games currently installed"
        }

        if ($gamesList.Count -gt 0) {
            Write-Information -MessageData "`nGames to Install:" -InformationAction Continue
            $gamesToInstall = $gamesList | Where-Object { $_.Id -notin $installedGames.Id }
            if ($gamesToInstall.Count -gt 0) {
                $gamesToInstall | ForEach-Object {
                    Write-Warning -Message "- $($_.Name) (ID: $($_.Id))"
                }
            }
            else {
                Write-Information -MessageData "All games from backup are already installed!" -InformationAction Continue
            }

            if ($Install -and $gamesToInstall.Count -gt 0) {
                # Launch GOG Galaxy for installation
                Write-Warning -Message "`nLaunching GOG Galaxy..."
                Write-Warning -Message "Please install the following games manually:"
                $gamesToInstall | ForEach-Object {
                    Write-Information -MessageData "- $($_.Name)" -InformationAction Continue
                }

                Start-Process "C:\Program Files (x86)\GOG Galaxy\GalaxyClient.exe"
            }
            elseif (!$Install -and $gamesToInstall.Count -gt 0) {
                Write-Warning -Message "`nRun with -Install to begin installation process"
            }
        }
        else {
            Write-Verbose -Message "`nNo games list found to install from"
        }

        Write-Information -MessageData "`nGOG Games setup completed!" -InformationAction Continue
        return $true

    }
    catch {
        Write-Error -Message "Failed to setup GOG Games: $($_.Exception.Message)"
        return $false
    }
}












