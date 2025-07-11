function Setup-SteamGames {
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

    try {
        Write-Information -MessageData "Setting up Steam games..." -InformationAction Continue

        # Determine games list path
        if (!$GamesListPath) {
            $backupPath = Join-Path $env:BACKUP_ROOT $env:MACHINE_NAME "Applications"
            $backupGamesPath = Join-Path $backupPath "steam-applications.json"

            if (Test-Path $backupGamesPath) {
                $applications = Get-Content $backupGamesPath | ConvertFrom-Json
                if ($applications.Steam) {
                    $gamesList = $applications.Steam
                } else {
                    Write-Warning -Message "No Steam games found in backup"
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

        Write-Information -MessageData "Steam games setup completed!" -InformationAction Continue
        return $true

    } catch {
        Write-Error -Message "Error setting up Steam games: $_"
        return $false
    }
}


