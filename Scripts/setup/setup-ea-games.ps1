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
    $backupGamesPath = Join-Path $backupPath "ea-applications.json"
    
    if (Test-Path $backupGamesPath) {
        $applications = Get-Content $backupGamesPath | ConvertFrom-Json
        if ($applications.EA) {
            $gamesList = $applications.EA
        } else {
            Write-Host "No EA games found in backup" -ForegroundColor Yellow
            $gamesList = @()
        }
    } else {
        $GamesListPath = "config\ea-games.json"
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

function Install-EAApp {
    $eaPath = "$env:LOCALAPPDATA\Electronic Arts\EA Desktop\EA Desktop\EADesktop.exe"
    if (Test-Path $eaPath) {
        return $true
    }

    Write-Host "EA app not found. Would you like to install it? (Y/N)" -ForegroundColor Yellow
    $response = Read-Host
    if ($response -eq 'Y') {
        try {
            # Download EA app installer
            $installerUrl = "https://origin-a.akamaihd.net/EA-Desktop-Client-Download/installer-releases/EAappInstaller.exe"
            $installerPath = Join-Path $env:TEMP "EAappInstaller.exe"
            
            Write-Host "Downloading EA app installer..." -ForegroundColor Yellow
            Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath
            
            # Install EA app
            Write-Host "Installing EA app..." -ForegroundColor Yellow
            Start-Process -FilePath $installerPath -ArgumentList "/silent" -Wait
            
            Remove-Item $installerPath
            return $true
        }
        catch {
            Write-Host "Failed to install EA app: $_" -ForegroundColor Red
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
                Write-Host "Error reading EA game info: $_" -ForegroundColor Red
            }
        }
    }

    return $installedGames
}

# Main script
try {
    # Install EA app if needed
    if (!(Install-EAApp)) {
        Write-Host "EA app is required to install games" -ForegroundColor Red
        exit 1
    }

    $installedGames = Get-InstalledGames

    # Show current status
    Write-Host "`nInstalled EA Games:" -ForegroundColor Blue
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

        # Launch EA app for installation
        Write-Host "`nLaunching EA app..." -ForegroundColor Yellow
        Write-Host "Please install the following games manually:" -ForegroundColor Yellow
        $gamesToInstall | ForEach-Object {
            Write-Host "- $($_.Name)" -ForegroundColor Cyan
        }
        
        Start-Process "$env:LOCALAPPDATA\Electronic Arts\EA Desktop\EA Desktop\EADesktop.exe"
    }
    else {
        Write-Host "`nRun with -Install to begin installation process" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "Error: $_" -ForegroundColor Red
    exit 1
} 