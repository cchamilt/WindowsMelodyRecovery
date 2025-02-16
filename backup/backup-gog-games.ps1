[CmdletBinding()]
param()

# Load environment
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path (Split-Path $scriptPath -Parent) "scripts\load-environment.ps1")

if (!(Load-Environment)) {
    Write-Host "Failed to load environment configuration" -ForegroundColor Red
    exit 1
}

function Get-GogGames {
    $gogGames = @()
    
    # Check for GOG Galaxy installation
    $gogPath = "C:\Program Files (x86)\GOG Galaxy"
    if (Test-Path $gogPath) {
        Write-Host "Found GOG Galaxy installation" -ForegroundColor Green
        
        # Get installed games from GOG Galaxy database
        $dbPath = "$env:ProgramData\GOG.com\Galaxy\storage\galaxy-2.0.db"
        if (Test-Path $dbPath) {
            try {
                # We need SQLite to read the database
                if (!(Get-Command sqlite3 -ErrorAction SilentlyContinue)) {
                    Write-Host "Installing SQLite..." -ForegroundColor Yellow
                    scoop install sqlite
                }

                $query = "SELECT gamePieceId, title FROM GamePieces WHERE gamePieceTypeId = 'original_title'"
                $games = sqlite3 $dbPath $query

                foreach ($game in $games) {
                    $id, $title = $game -split '\|'
                    $gogGames += @{
                        Name = $title
                        Id = $id
                        Platform = "GOG"
                    }
                }
            }
            catch {
                Write-Host "Error reading GOG Galaxy database: $_" -ForegroundColor Red
            }
        }
    }

    return $gogGames
}

# Main backup logic
try {
    $backupPath = Join-Path $env:BACKUP_ROOT $env:MACHINE_NAME "Applications"
    if (!(Test-Path $backupPath)) {
        New-Item -Path $backupPath -ItemType Directory -Force | Out-Null
    }

    # Get GOG games
    Write-Host "Scanning for GOG games..." -ForegroundColor Blue
    $gogGames = Get-GogGames

    # Update applications.json
    $applicationsPath = Join-Path $backupPath "gog-applications.json"
    if (Test-Path $applicationsPath) {
        $applications = Get-Content $applicationsPath | ConvertFrom-Json
    }
    else {
        $applications = @{}
    }

    $applications.GOG = $gogGames

    $applications | ConvertTo-Json -Depth 10 | Set-Content $applicationsPath

    Write-Host "Backed up $($gogGames.Count) GOG games" -ForegroundColor Green
}
catch {
    Write-Host "Error backing up GOG games: $_" -ForegroundColor Red
    exit 1
} 