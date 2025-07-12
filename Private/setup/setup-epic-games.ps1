function Initialize-EpicGame {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$GamesListPath = $null,
        [Parameter(Mandatory = $false)]
        [switch]$Install
    )

    # Load environment configuration (optional - module will use fallback configuration)
    try {
        Import-Environment | Out-Null
    }
 catch {
        Write-Verbose "Using module configuration fallback"
    }

    function Install-Legendary {
        if (Get-Command legendary -ErrorAction SilentlyContinue) {
            return $true
        }

        Write-Warning -Message "Installing Legendary CLI..."

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
            Write-Error -Message "Failed to install Legendary: $($_.Exception.Message)"
            return $false
        }

        return $false
    }

    function Get-InstalledGame {
        if (!(Get-Command legendary -ErrorAction SilentlyContinue)) {
            Write-Error -Message "Legendary CLI not found"
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
            Write-Error -Message "Error getting installed games: $($_.Exception.Message)"
        }

        return $installedGames
    }

    function Install-EpicGame {
        param(
            [array]$Games
        )

        # Check if logged in
        try {
            $status = legendary status --json | ConvertFrom-Json
            if (!$status.account) {
                Write-Warning -Message "`nYou need to login to Epic Games first"
                legendary auth
                if ($LASTEXITCODE -ne 0) {
                    Write-Error -Message "Failed to authenticate with Epic Games"
                    return
                }
            }
        }
        catch {
            Write-Error -Message "Error checking Epic Games login status: $($_.Exception.Message)"
            return
        }

        foreach ($game in $Games) {
            Write-Warning -Message "Installing $($game.Name) (AppID: $($game.AppId))..."

            try {
                # Install game
                legendary install $game.AppId --base-path "C:\Epic Games" --yes

                if ($LASTEXITCODE -eq 0) {
                    Write-Information -MessageData "Successfully installed $($game.Name)" -InformationAction Continue
                }
                else {
                    Write-Error -Message "Failed to install $($game.Name)"
                }
            }
            catch {
                Write-Error -Message "Error installing $($game.Name): $($_.Exception.Message)"
            }
        }
    }

    try {
        Write-Information -MessageData "Setting up Epic Games..." -InformationAction Continue

        # Determine games list path
        if (!$GamesListPath) {
            $backupPath = Join-Path $env:BACKUP_ROOT $env:MACHINE_NAME "Applications"
            $backupGamesPath = Join-Path $backupPath "epic-applications.json"

            if (Test-Path $backupGamesPath) {
                $applications = Get-Content $backupGamesPath | ConvertFrom-Json
                if ($applications.Epic) {
                    $gamesList = $applications.Epic
                }
 else {
                    Write-Warning -Message "No Epic games found in backup"
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

        # Install Legendary if needed
        if (!(Install-Legendary)) {
            Write-Error -Message "Failed to install Legendary CLI"
            Write-Warning -Message "You can install it manually:"
            Write-Information -MessageData "  1. Install Python: https://python.org"  -InformationAction Continue-ForegroundColor White
            Write-Information -MessageData "  2. Run: pip install legendary -InformationAction Continue-gl" -ForegroundColor White
            Write-Information -MessageData "  3. Or download from: https://github.com/derrod/legendary"  -InformationAction Continue-ForegroundColor White
            return $false
        }

        $installedGames = Get-InstalledGames

        # Show current status
        Write-Information -MessageData "`nInstalled Epic Games:" -InformationAction Continue
        if ($installedGames.Count -gt 0) {
            $installedGames | ForEach-Object {
                Write-Information -MessageData "- $($_.Name) (AppID: $($_.AppId))" -InformationAction Continue
            }
        }
 else {
            Write-Verbose -Message "No Epic games currently installed"
        }

        if ($gamesList.Count -gt 0) {
            Write-Information -MessageData "`nGames to Install:" -InformationAction Continue
            $gamesToInstall = $gamesList | Where-Object { $_.AppId -notin $installedGames.AppId }
            if ($gamesToInstall.Count -gt 0) {
                $gamesToInstall | ForEach-Object {
                    Write-Warning -Message "- $($_.Name) (AppID: $($_.AppId))"
                }
            }
 else {
                Write-Information -MessageData "All games from backup are already installed!" -InformationAction Continue
            }

            if ($Install -and $gamesToInstall.Count -gt 0) {
                # Install games
                Install-EpicGames -Games $gamesToInstall
            }
            elseif (!$Install -and $gamesToInstall.Count -gt 0) {
                Write-Warning -Message "`nRun with -Install to install missing games"
            }
        }
 else {
            Write-Verbose -Message "`nNo games list found to install from"
        }

        Write-Information -MessageData "`nEpic Games setup completed!" -InformationAction Continue
        return $true

    }
 catch {
        Write-Error -Message "Failed to setup Epic Games: $($_.Exception.Message)"
        return $false
    }
}












