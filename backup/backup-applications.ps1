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

# Main backup function that can be called by master script
function Backup-Applications {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath
    )
    
    try {
        Write-Host "Backing up Application List..." -ForegroundColor Blue
        $backupPath = Initialize-BackupDirectory -Path "Applications" -BackupType "Applications" -BackupRootPath $BackupRootPath
        
        if ($backupPath) {
            $applications = @{
                Winget = @()
                Chocolatey = @()
                Other = @()
            }

            # Get Winget installations
            Write-Host "Scanning Winget applications..." -ForegroundColor Yellow
            $wingetList = winget list --accept-source-agreements | Out-String
            $wingetApps = $wingetList -split "`n" | Select-Object -Skip 2 | Where-Object { $_ -match '\S' }
            
            foreach ($app in $wingetApps) {
                if ($app -match '^(.*?)\s+\d') {
                    $appName = $matches[1].Trim()
                    # Try to get the exact install command
                    $wingetSearch = winget search --exact $appName | Out-String
                    if ($wingetSearch -match "$appName.*") {
                        $applications.Winget += @{
                            Name = $appName
                            Id = if ($wingetSearch -match "$appName\s+(\S+)\s+") { $matches[1] } else { $null }
                            Source = if ($wingetSearch -match ".*\s(\w+)$") { $matches[1] } else { "winget" }
                        }
                    }
                }
            }

            # Get Chocolatey installations if choco is installed
            if (Get-Command choco -ErrorAction SilentlyContinue) {
                Write-Host "Scanning Chocolatey applications..." -ForegroundColor Yellow
                $chocoList = choco list -lo -r
                $applications.Chocolatey = $chocoList | ForEach-Object {
                    $parts = $_ -split '\|'
                    @{
                        Name = $parts[0]
                        Version = $parts[1]
                    }
                }
            }

            # Get all installed programs from registry
            Write-Host "Scanning other installed applications..." -ForegroundColor Yellow
            $regPaths = @(
                'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
                'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
            )

            $allPrograms = foreach ($path in $regPaths) {
                Get-ItemProperty $path | 
                    Where-Object DisplayName -ne $null | 
                    Select-Object DisplayName, Publisher, InstallDate, DisplayVersion, UninstallString
            }

            # Filter out Winget and Chocolatey apps
            $wingetNames = $applications.Winget.Name
            $chocoNames = $applications.Chocolatey.Name
            
            $applications.Other = $allPrograms | 
                Where-Object { $_.DisplayName -notin $wingetNames -and $_.DisplayName -notin $chocoNames } |
                Sort-Object DisplayName -Unique

            # Save to JSON files
            $applications | ConvertTo-Json -Depth 10 | Out-File "$backupPath\applications.json" -Force

            # Output summary
            Write-Host "`nApplication Summary:" -ForegroundColor Green
            Write-Host "Winget Applications: $($applications.Winget.Count)" -ForegroundColor Yellow
            Write-Host "Chocolatey Packages: $($applications.Chocolatey.Count)" -ForegroundColor Yellow
            Write-Host "Other Applications: $($applications.Other.Count)" -ForegroundColor Yellow
            
            Write-Host "Applications list backed up successfully to: $backupPath" -ForegroundColor Green
            return $true
        }
    } catch {
        Write-Host "Failed to backup Applications list: $_" -ForegroundColor Red
        return $false
    }
}

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Backup-Applications -BackupRootPath $BackupRootPath
} 