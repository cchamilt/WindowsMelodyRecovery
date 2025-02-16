[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$GamesListPath = $null,
    [Parameter(Mandatory=$false)]
    [switch]$Install
)

# Load environment
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path (Split-Path $scriptPath -Parent) "scripts\load-environment.ps1")

if (!(Load-Environment)) {
    Write-Host "Failed to load environment configuration" -ForegroundColor Red
    exit 1
}

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
        $GamesListPath = "config\gog-games.json"
        if (!(Test-Path $GamesListPath)) {
            Write-Host "No games list found at default or backup location" -ForegroundColor Red
            exit 1
        }
        $gamesList = Get-Content $GamesListPath | ConvertFrom-Json
    }
} else {
    if (!(Test-Path $GamesListPath)) {
        Write-Host "Games list not found at: $GamesListPath" -ForegroundColor Red
        exit 1
    }
    $gamesList = Get-Content $GamesListPath | ConvertFrom-Json
}

function Install-GogGalaxy {
    $gogPath = "C:\Program Files (x86)\GOG Galaxy\GalaxyClient.exe"
    if (Test-Path $gogPath) {
        return $true
    }

    Write-Host "GOG Galaxy not found. Would you like to install it? (Y/N)" -ForegroundColor Yellow
    $response = Read-Host
    if ($response -eq 'Y') {
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
            Write-Host "Failed to install GOG Galaxy: $_" -ForegroundColor Red
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
                    scoop install sqlite
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
            Write-Host "Error reading GOG Galaxy database: $_" -ForegroundColor Red
        }
    }
    
    return $installedGames
}

# Main script
try {
    # Install GOG Galaxy if needed
    if (!(Install-GogGalaxy)) {
        Write-Host "GOG Galaxy is required to install games" -ForegroundColor Red
        exit 1
    }

    $installedGames = Get-InstalledGames

    # Show current status
    Write-Host "`nInstalled GOG Games:" -ForegroundColor Blue
    $installedGames | ForEach-Object {
        Write-Host "- $($_.Name) (ID: $($_.Id))" -ForegroundColor Green
    }

    Write-Host "`nGames to Install:" -ForegroundColor Blue
    $gamesToInstall = $gamesList | Where-Object { $_.Id -notin $installedGames.Id }
    $gamesToInstall | ForEach-Object {
        Write-Host "- $($_.Name) (ID: $($_.Id))" -ForegroundColor Yellow
    }

    if ($Install) {
        if ($gamesToInstall.Count -eq 0) {
            Write-Host "`nAll games are already installed!" -ForegroundColor Green
            exit 0
        }

        # Launch GOG Galaxy for installation
        Write-Host "`nLaunching GOG Galaxy..." -ForegroundColor Yellow
        Write-Host "Please install the following games manually:" -ForegroundColor Yellow
        $gamesToInstall | ForEach-Object {
            Write-Host "- $($_.Name)" -ForegroundColor Cyan
        }
        
        Start-Process "C:\Program Files (x86)\GOG Galaxy\GalaxyClient.exe"
    }
    else {
        Write-Host "`nRun with -Install to begin installation process" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "Error: $_" -ForegroundColor Red
    exit 1
} 