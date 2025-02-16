[CmdletBinding()]
param()

# Load environment
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path (Split-Path $scriptPath -Parent) "scripts\load-environment.ps1")

if (!(Load-Environment)) {
    Write-Host "Failed to load environment configuration" -ForegroundColor Red
    exit 1
}

function Get-EAGames {
    $eaGames = @()
    
    # Check for EA app installation
    $eaPath = "$env:LOCALAPPDATA\Electronic Arts\EA Desktop\EA Desktop"
    if (Test-Path $eaPath) {
        Write-Host "Found EA app installation" -ForegroundColor Green
        
        # EA stores game info in multiple locations
        $contentPath = "$env:PROGRAMDATA\Electronic Arts\EA Desktop\Downloaded"
        $manifestPath = "$env:LOCALAPPDATA\Electronic Arts\EA Desktop\Downloaded"

        if (Test-Path $contentPath) {
            Get-ChildItem $contentPath -Filter "*.json" | ForEach-Object {
                try {
                    $content = Get-Content $_.FullName | ConvertFrom-Json
                    if ($content.gameTitle) {
                        $eaGames += @{
                            Name = $content.gameTitle
                            Id = $content.gameId
                            Platform = "EA"
                            InstallPath = $content.installPath
                        }
                    }
                }
                catch {
                    Write-Host "Error reading EA game info: $_" -ForegroundColor Red
                }
            }
        }

        # Also check manifests for additional games
        if (Test-Path $manifestPath) {
            Get-ChildItem $manifestPath -Filter "*.json" | ForEach-Object {
                try {
                    $manifest = Get-Content $_.FullName | ConvertFrom-Json
                    if ($manifest.gameTitle -and ($manifest.gameTitle -notin $eaGames.Name)) {
                        $eaGames += @{
                            Name = $manifest.gameTitle
                            Id = $manifest.gameId
                            Platform = "EA"
                            InstallPath = $manifest.installPath
                        }
                    }
                }
                catch {
                    Write-Host "Error reading EA manifest: $_" -ForegroundColor Red
                }
            }
        }
    }

    return $eaGames
}

# Main backup logic
try {
    $backupPath = Join-Path $env:BACKUP_ROOT $env:MACHINE_NAME "Applications"
    if (!(Test-Path $backupPath)) {
        New-Item -Path $backupPath -ItemType Directory -Force | Out-Null
    }

    # Get EA games
    Write-Host "Scanning for EA games..." -ForegroundColor Blue
    $eaGames = Get-EAGames

    # Update applications.json
    $applicationsPath = Join-Path $backupPath "ea-applications.json"
    if (Test-Path $applicationsPath) {
        $applications = Get-Content $applicationsPath | ConvertFrom-Json
    }
    else {
        $applications = @{}
    }

    $applications.EA = $eaGames

    $applications | ConvertTo-Json -Depth 10 | Set-Content $applicationsPath

    Write-Host "Backed up $($eaGames.Count) EA games" -ForegroundColor Green
}
catch {
    Write-Host "Error backing up EA games: $_" -ForegroundColor Red
    exit 1
} 