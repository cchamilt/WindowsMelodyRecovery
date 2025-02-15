[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$BackupRootPath = $null
)

# Load environment if not provided
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path (Split-Path $scriptPath -Parent) "scripts\load-environment.ps1")

if (!$BackupRootPath) {
    if (!(Load-Environment)) {
        Write-Host "Failed to load environment configuration" -ForegroundColor Red
        exit 1
    }
    $BackupRootPath = "$env:BACKUP_ROOT\$env:MACHINE_NAME"
}

function Restore-Applications {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath
    )
    
    try {
        Write-Host "Restoring Applications..." -ForegroundColor Blue
        $applicationsPath = Test-BackupPath -Path "Applications" -BackupType "Applications"
        
        if ($applicationsPath) {
            $applicationsFile = "$applicationsPath\applications.json"
            if (Test-Path $applicationsFile) {
                $applications = Get-Content $applicationsFile | ConvertFrom-Json

                # Install packages in order of best package management
                if (Get-Command choco -ErrorAction SilentlyContinue) {
                    Write-Host "`nInstalling Chocolatey packages..." -ForegroundColor Yellow
                    foreach ($app in $applications.Chocolatey) {
                        Write-Host "Installing $($app.Name)..." -ForegroundColor Yellow
                        choco install $app.Name -y
                    }
                }

                if (Get-Command scoop -ErrorAction SilentlyContinue) {
                    Write-Host "`nInstalling Scoop packages..." -ForegroundColor Yellow
                    foreach ($app in $applications.Scoop) {
                        Write-Host "Installing $($app.Name)..." -ForegroundColor Yellow
                        scoop install $app.Name
                    }
                }

                Write-Host "`nInstalling Store applications..." -ForegroundColor Yellow
                foreach ($app in $applications.Store) {
                    Write-Host "Installing $($app.Name)..." -ForegroundColor Yellow
                    try {
                        Add-AppxPackage -Name $app.ID
                    } catch {
                        Write-Host "Failed to install $($app.Name): $_" -ForegroundColor Red
                    }
                }

                Write-Host "`nInstalling Winget applications..." -ForegroundColor Yellow
                foreach ($app in $applications.Winget) {
                    Write-Host "Installing $($app.Name)..." -ForegroundColor Yellow
                    winget install --id $app.ID --source winget --accept-package-agreements --accept-source-agreements
                }

                # List games and unmanaged applications that need manual attention
                Write-Host "`nThe following applications need manual installation:" -ForegroundColor Yellow
                Write-Host "=============================================" -ForegroundColor Yellow

                if ($applications.Steam.Count -gt 0) {
                    Write-Host "`nSteam Games:" -ForegroundColor Cyan
                    foreach ($game in $applications.Steam) {
                        Write-Host "  $($game.Name)" -ForegroundColor White
                    }
                }

                if ($applications.Epic.Count -gt 0) {
                    Write-Host "`nEpic Games:" -ForegroundColor Cyan
                    foreach ($game in $applications.Epic) {
                        Write-Host "  $($game.Name)" -ForegroundColor White
                    }
                }

                if ($applications.Unmanaged.Count -gt 0) {
                    Write-Host "`nUnmanaged Applications (some may already be installed by package managers):" -ForegroundColor Cyan
                    foreach ($app in $applications.Unmanaged) {
                        Write-Host "  $($app.Name)" -ForegroundColor White
                        Write-Host "    Publisher: $($app.Publisher)" -ForegroundColor Gray
                        Write-Host "    Version: $($app.Version)" -ForegroundColor Gray
                    }
                }

                Write-Host "`nAutomatic application installation completed" -ForegroundColor Green
                Write-Host "Please review the list above for applications that need manual installation" -ForegroundColor Yellow
            }
        }
        return $true
    } catch {
        Write-Host "Failed to restore Applications: $_" -ForegroundColor Red
        return $false
    }
}

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Restore-Applications -BackupRootPath $BackupRootPath
} 