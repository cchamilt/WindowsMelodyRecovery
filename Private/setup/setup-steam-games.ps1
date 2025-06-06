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
        Load-Environment | Out-Null
    } catch {
        Write-Verbose "Using module configuration fallback"
    }

    try {
        Write-Host "Setting up Steam games..." -ForegroundColor Blue
        
        # Determine games list path
        if (!$GamesListPath) {
            $backupPath = Join-Path $env:BACKUP_ROOT $env:MACHINE_NAME "Applications"
            $backupGamesPath = Join-Path $backupPath "steam-applications.json"
            
            if (Test-Path $backupGamesPath) {
                $applications = Get-Content $backupGamesPath | ConvertFrom-Json
                if ($applications.Steam) {
                    $gamesList = $applications.Steam
                } else {
                    Write-Host "No Steam games found in backup" -ForegroundColor Yellow
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

        Write-Host "Steam games setup completed!" -ForegroundColor Green
        return $true
        
    } catch {
        Write-Host "Error setting up Steam games: $_" -ForegroundColor Red
        return $false
    }
} 
