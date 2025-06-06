function Setup-GOGGames {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$GamesListPath = $null,
        [Parameter(Mandatory=$false)]
        [switch]$Install
    )

    # Load environment configuration
    if (!(Load-Environment)) {
        Write-Warning "Failed to load environment configuration"
        return $false
    }

    function Install-GogGalaxy {
        $gogPath = "C:\Program Files (x86)\GOG Galaxy\GalaxyClient.exe"
        if (Test-Path $gogPath) {
            return $true
        }

        Write-Host "GOG Galaxy not found. Would you like to install it? (Y/N)" -ForegroundColor Yellow
        $response = Read-Host
        if ($response -eq 'Y' -or $response -eq 'y') {
            try {
                # Download GOG Galaxy installer
                $installerUrl = "https://content-system.gog.com/open_link/download?path=/open/galaxy/client/2.0.0/setup_galaxy_2.0.0.exe"
                $installerPath = Join-Path $env:TEMP "setup_galaxy.exe"
                
                Write-Host "Downloading GOG Galaxy installer..." -ForegroundColor Yellow
                Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath
                
                # Install GOG Galaxy
                Write-Host "Installing GOG Galaxy..." -ForegroundColor Yellow
                Start-Process -FilePath $installerPath -ArgumentList "/SILENT" -Wait
                
                Remove-Item $installerPath
                return $true
            }
            catch {
                Write-Host "Failed to install GOG Galaxy: $($_.Exception.Message)" -ForegroundColor Red
                return $false
            }
        }
        return $false
    }

    function Get-InstalledGames {
        $installedGames = @()
        
        $gogPath = "C:\Program Files (x86)\GOG Galaxy"
        if (Test-Path $gogPath) {
            try {
                # Query GOG Galaxy database
                $dbPath = "$env:ProgramData\GOG.com\Galaxy\storage\galaxy-2.0.db"
                if (Test-Path $dbPath) {
                    if (!(Get-Command sqlite3 -ErrorAction SilentlyContinue)) {
                        Write-Host "Installing SQLite..." -ForegroundColor Yellow
                        if (Get-Command scoop -ErrorAction SilentlyContinue) {
                            scoop install sqlite
                        } else {
                            Write-Host "SQLite not available. Cannot read GOG Galaxy database." -ForegroundColor Yellow
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
                Write-Host "Error reading GOG Galaxy database: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        
        return $installedGames
    }

    try {
        Write-Host "Setting up GOG Games..." -ForegroundColor Blue

        # Determine games list path
        if (!$GamesListPath) {
            $backupPath = Join-Path $env:BACKUP_ROOT $env:MACHINE_NAME "Applications"
            $backupGamesPath = Join-Path $backupPath "gog-applications.json"
            
            if (Test-Path $backupGamesPath) {
                $applications = Get-Content $backupGamesPath | ConvertFrom-Json
                if ($applications.GOG) {
                    $gamesList = $applications.GOG
                } else {
                    Write-Host "No GOG games found in backup" -ForegroundColor Yellow
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

        # Install GOG Galaxy if needed
        if (!(Install-GogGalaxy)) {
            Write-Host "GOG Galaxy is required to install games" -ForegroundColor Red
            Write-Host "You can install it manually from: https://www.gog.com/galaxy" -ForegroundColor Yellow
            return $false
        }

        $installedGames = Get-InstalledGames

        # Show current status
        Write-Host "`nInstalled GOG Games:" -ForegroundColor Blue
        if ($installedGames.Count -gt 0) {
            $installedGames | ForEach-Object {
                Write-Host "- $($_.Name) (ID: $($_.Id))" -ForegroundColor Green
            }
        } else {
            Write-Host "No GOG games currently installed" -ForegroundColor Gray
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
                # Launch GOG Galaxy for installation
                Write-Host "`nLaunching GOG Galaxy..." -ForegroundColor Yellow
                Write-Host "Please install the following games manually:" -ForegroundColor Yellow
                $gamesToInstall | ForEach-Object {
                    Write-Host "- $($_.Name)" -ForegroundColor Cyan
                }
                
                Start-Process "C:\Program Files (x86)\GOG Galaxy\GalaxyClient.exe"
            }
            elseif (!$Install -and $gamesToInstall.Count -gt 0) {
                Write-Host "`nRun with -Install to begin installation process" -ForegroundColor Yellow
            }
        } else {
            Write-Host "`nNo games list found to install from" -ForegroundColor Gray
        }

        Write-Host "`nGOG Games setup completed!" -ForegroundColor Green
        return $true

    } catch {
        Write-Host "Failed to setup GOG Games: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
} 