function Setup-EpicGames {
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

    function Install-Legendary {
        if (Get-Command legendary -ErrorAction SilentlyContinue) {
            return $true
        }

        Write-Host "Installing Legendary CLI..." -ForegroundColor Yellow
        
        try {
            # Try to install via pip
            if (Get-Command pip -ErrorAction SilentlyContinue) {
                pip install legendary-gl
                return $true
            }
            
            # Alternative: Download from GitHub releases
            $tempPath = Join-Path $env:TEMP "legendary"
            New-Item -ItemType Directory -Path $tempPath -Force | Out-Null
            
            $latestRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/derrod/legendary/releases/latest"
            $windowsAsset = $latestRelease.assets | Where-Object { $_.name -like "*windows.zip" }
            
            if ($windowsAsset) {
                $downloadUrl = $windowsAsset.browser_download_url
                $zipPath = Join-Path $tempPath "legendary.zip"
                
                Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath
                Expand-Archive -Path $zipPath -DestinationPath "$env:LOCALAPPDATA\Programs\legendary" -Force
                
                # Add to PATH
                $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
                if ($userPath -notlike "*legendary*") {
                    [Environment]::SetEnvironmentVariable("Path", "$userPath;$env:LOCALAPPDATA\Programs\legendary", "User")
                    $env:Path = "$env:Path;$env:LOCALAPPDATA\Programs\legendary"
                }
                
                return $true
            }
        }
        catch {
            Write-Host "Failed to install Legendary: $($_.Exception.Message)" -ForegroundColor Red
            return $false
        }
        
        return $false
    }

    function Get-InstalledGames {
        if (!(Get-Command legendary -ErrorAction SilentlyContinue)) {
            Write-Host "Legendary CLI not found" -ForegroundColor Red
            return @()
        }

        $installedGames = @()
        
        try {
            $games = legendary list-installed --json | ConvertFrom-Json
            
            foreach ($game in $games) {
                $installedGames += @{
                    Name = $game.title
                    AppId = $game.app_name
                    Path = $game.install_path
                    Version = $game.version
                }
            }
        }
        catch {
            Write-Host "Error getting installed games: $($_.Exception.Message)" -ForegroundColor Red
        }
        
        return $installedGames
    }

    function Install-EpicGames {
        param(
            [array]$Games
        )

        # Check if logged in
        try {
            $status = legendary status --json | ConvertFrom-Json
            if (!$status.account) {
                Write-Host "`nYou need to login to Epic Games first" -ForegroundColor Yellow
                legendary auth
                if ($LASTEXITCODE -ne 0) {
                    Write-Host "Failed to authenticate with Epic Games" -ForegroundColor Red
                    return
                }
            }
        }
        catch {
            Write-Host "Error checking Epic Games login status: $($_.Exception.Message)" -ForegroundColor Red
            return
        }

        foreach ($game in $Games) {
            Write-Host "Installing $($game.Name) (AppID: $($game.AppId))..." -ForegroundColor Yellow
            
            try {
                # Install game
                legendary install $game.AppId --base-path "C:\Epic Games" --yes
                
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "Successfully installed $($game.Name)" -ForegroundColor Green
                }
                else {
                    Write-Host "Failed to install $($game.Name)" -ForegroundColor Red
                }
            }
            catch {
                Write-Host "Error installing $($game.Name): $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }

    try {
        Write-Host "Setting up Epic Games..." -ForegroundColor Blue

        # Determine games list path
        if (!$GamesListPath) {
            $backupPath = Join-Path $env:BACKUP_ROOT $env:MACHINE_NAME "Applications"
            $backupGamesPath = Join-Path $backupPath "epic-applications.json"
            
            if (Test-Path $backupGamesPath) {
                $applications = Get-Content $backupGamesPath | ConvertFrom-Json
                if ($applications.Epic) {
                    $gamesList = $applications.Epic
                } else {
                    Write-Host "No Epic games found in backup" -ForegroundColor Yellow
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

        # Install Legendary if needed
        if (!(Install-Legendary)) {
            Write-Host "Failed to install Legendary CLI" -ForegroundColor Red
            Write-Host "You can install it manually:" -ForegroundColor Yellow
            Write-Host "  1. Install Python: https://python.org" -ForegroundColor White
            Write-Host "  2. Run: pip install legendary-gl" -ForegroundColor White
            Write-Host "  3. Or download from: https://github.com/derrod/legendary" -ForegroundColor White
            return $false
        }

        $installedGames = Get-InstalledGames

        # Show current status
        Write-Host "`nInstalled Epic Games:" -ForegroundColor Blue
        if ($installedGames.Count -gt 0) {
            $installedGames | ForEach-Object {
                Write-Host "- $($_.Name) (AppID: $($_.AppId))" -ForegroundColor Green
            }
        } else {
            Write-Host "No Epic games currently installed" -ForegroundColor Gray
        }

        if ($gamesList.Count -gt 0) {
            Write-Host "`nGames to Install:" -ForegroundColor Blue
            $gamesToInstall = $gamesList | Where-Object { $_.AppId -notin $installedGames.AppId }
            if ($gamesToInstall.Count -gt 0) {
                $gamesToInstall | ForEach-Object {
                    Write-Host "- $($_.Name) (AppID: $($_.AppId))" -ForegroundColor Yellow
                }
            } else {
                Write-Host "All games from backup are already installed!" -ForegroundColor Green
            }

            if ($Install -and $gamesToInstall.Count -gt 0) {
                # Install games
                Install-EpicGames -Games $gamesToInstall
            }
            elseif (!$Install -and $gamesToInstall.Count -gt 0) {
                Write-Host "`nRun with -Install to install missing games" -ForegroundColor Yellow
            }
        } else {
            Write-Host "`nNo games list found to install from" -ForegroundColor Gray
        }

        Write-Host "`nEpic Games setup completed!" -ForegroundColor Green
        return $true

    } catch {
        Write-Host "Failed to setup Epic Games: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
} 
