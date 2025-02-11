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

                # Install Winget applications
                Write-Host "`nInstalling Winget applications..." -ForegroundColor Yellow
                foreach ($app in $applications.Winget) {
                    if ($app.Id) {
                        Write-Host "Installing $($app.Name)..." -ForegroundColor Yellow
                        winget install --id $app.Id --source $app.Source --accept-package-agreements --accept-source-agreements
                    } else {
                        Write-Host "Skipping $($app.Name) - No package ID found" -ForegroundColor Red
                    }
                }

                # Install Chocolatey applications if choco is installed
                if (Get-Command choco -ErrorAction SilentlyContinue) {
                    Write-Host "`nInstalling Chocolatey packages..." -ForegroundColor Yellow
                    foreach ($app in $applications.Chocolatey) {
                        Write-Host "Installing $($app.Name)..." -ForegroundColor Yellow
                        choco install $app.Name -y
                    }
                }

                # List applications that need manual installation
                Write-Host "`nThe following applications need to be installed manually:" -ForegroundColor Yellow
                Write-Host "=============================================" -ForegroundColor Yellow
                foreach ($app in $applications.Other) {
                    Write-Host "$($app.DisplayName)" -ForegroundColor White
                    Write-Host "  Publisher: $($app.Publisher)" -ForegroundColor Gray
                    Write-Host "  Version: $($app.DisplayVersion)" -ForegroundColor Gray
                    Write-Host "  Install Date: $($app.InstallDate)" -ForegroundColor Gray
                    Write-Host "---------------------------------------------" -ForegroundColor Gray
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