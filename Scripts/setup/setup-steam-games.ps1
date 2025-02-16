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
        $GamesListPath = "config\steam-games.json"
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

function Install-SteamCmd {
    $steamCmdPath = "C:\steamcmd"
    
    if (!(Test-Path $steamCmdPath)) {
        Write-Host "Installing SteamCMD..." -ForegroundColor Yellow
        
        # Create directory
        New-Item -ItemType Directory -Path $steamCmdPath -Force | Out-Null
        
        # Download steamcmd
        $steamCmdZip = Join-Path $steamCmdPath "steamcmd.zip"
        Invoke-WebRequest -Uri "https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip" -OutFile $steamCmdZip
        
        # Extract
        Expand-Archive -Path $steamCmdZip -DestinationPath $steamCmdPath -Force
        Remove-Item $steamCmdZip
        
        # Initial run to update
        Start-Process -FilePath "$steamCmdPath\steamcmd.exe" -ArgumentList "+quit" -NoNewWindow -Wait
    }
    
    return "$steamCmdPath\steamcmd.exe"
}

function Get-InstalledGames {
    $steamPath = "C:\Program Files (x86)\Steam"
    if (!(Test-Path $steamPath)) {
        Write-Host "Steam installation not found" -ForegroundColor Red
        return @()
    }

    $libraryFolders = Get-Content "$steamPath\steamapps\libraryfolders.vdf" -Raw
    $installedGames = @()

    # Parse library folders (this is a simple parse, might need improvement for complex setups)
    $libraryPaths = $libraryFolders | Select-String '"path"\s+"([^"]+)"' -AllMatches | 
        ForEach-Object { $_.Matches.Groups[1].Value }

    foreach ($path in $libraryPaths) {
        $manifestFiles = Get-ChildItem "$path\steamapps\*.acf"
        foreach ($manifest in $manifestFiles) {
            $content = Get-Content $manifest -Raw
            $name = [regex]::Match($content, '"name"\s+"([^"]+)"').Groups[1].Value
            $appId = [regex]::Match($content, '"appid"\s+"(\d+)"').Groups[1].Value
            
            $installedGames += @{
                Name = $name
                AppId = $appId
                Path = $path
            }
        }
    }

    return $installedGames
}

function Install-SteamGames {
    param(
        [string]$SteamCmd,
        [array]$Games,
        [string]$Username
    )

    foreach ($game in $Games) {
        Write-Host "Installing $($game.Name) (AppID: $($game.AppId))..." -ForegroundColor Yellow
        
        $args = @(
            "+login $Username"
            "+app_update $($game.AppId) validate"
            "+quit"
        )

        Start-Process -FilePath $SteamCmd -ArgumentList ($args -join " ") -NoNewWindow -Wait
    }
}

# Main script
try {
    $installedGames = Get-InstalledGames

    # Show current status
    Write-Host "`nInstalled Steam Games:" -ForegroundColor Blue
    $installedGames | ForEach-Object {
        Write-Host "- $($_.Name) (AppID: $($_.AppId))" -ForegroundColor Green
    }

    Write-Host "`nGames to Install:" -ForegroundColor Blue
    $gamesToInstall = $gamesList | Where-Object { $_.AppId -notin $installedGames.AppId }
    $gamesToInstall | ForEach-Object {
        Write-Host "- $($_.Name) (AppID: $($_.AppId))" -ForegroundColor Yellow
    }

    if ($Install) {
        if ($gamesToInstall.Count -eq 0) {
            Write-Host "`nAll games are already installed!" -ForegroundColor Green
            exit 0
        }

        # Install SteamCMD if needed
        $steamCmd = Install-SteamCmd

        # Get Steam username
        $username = Read-Host "`nEnter your Steam username"
        
        # Install games
        Install-SteamGames -SteamCmd $steamCmd -Games $gamesToInstall -Username $username
    }
    else {
        Write-Host "`nRun with -Install to install missing games" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "Error: $_" -ForegroundColor Red
    exit 1
} 