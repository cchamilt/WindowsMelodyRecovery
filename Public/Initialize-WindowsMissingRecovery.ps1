# Initialize-WindowsMissingRecovery.ps1
# This script ONLY handles configuration - nothing else

function Initialize-WindowsMissingRecovery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$InstallPath = "$env:USERPROFILE\Scripts\WindowsMissingRecovery",
        
        [Parameter(Mandatory=$false)]
        [switch]$NoPrompt,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force
    )

    # Check for admin privileges
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Warning "This function requires administrator privileges. Please run PowerShell as Administrator."
        return $false
    }

    # Check if already initialized
    $configFile = Join-Path $InstallPath "Config\windows.env"
    $configExists = Test-Path $configFile

    if ($configExists -and -not $Force) {
        Write-Host "WindowsMissingRecovery is already initialized with the following configuration:" -ForegroundColor Yellow
        Get-Content $configFile | ForEach-Object {
            if ($_ -match '^([^=]+)=(.*)$') {
                $key = $matches[1]
                $value = $matches[2]
                Write-Host "$key = $value" -ForegroundColor Gray
            }
        }
        
        if (-not $NoPrompt) {
            $response = Read-Host "Do you want to replace the existing configuration? (y/N)"
            if ($response -ne 'y') {
                return $true
            }
        }
    }

    # Get machine name
    Write-Host "`nEnter machine name:" -ForegroundColor Cyan
    $machineName = if ($NoPrompt) { 
        $env:COMPUTERNAME 
    } else {
        $input = Read-Host "Machine name [default: $env:COMPUTERNAME]"
        if ([string]::IsNullOrWhiteSpace($input)) { 
            $env:COMPUTERNAME 
        } else { 
            $input 
        }
    }

    # Get cloud provider
    Write-Host "`nSelect cloud storage provider:" -ForegroundColor Cyan
    Write-Host "[O] OneDrive"
    Write-Host "[G] Google Drive"
    Write-Host "[D] Dropbox"
    Write-Host "[B] Box"
    Write-Host "[C] Custom location"

    $selectedProvider = if ($NoPrompt) { "OneDrive" } else {
        do {
            $choice = Read-Host "Select provider (O/G/D/B/C)"
            switch ($choice.ToUpper()) {
                'O' { 'OneDrive'; break }
                'G' { 'GoogleDrive'; break }
                'D' { 'Dropbox'; break }
                'B' { 'Box'; break }
                'C' { 'Custom'; break }
                default { $null }
            }
        } while (-not $selectedProvider)
    }

    # Get backup location
    $backupRoot = if ($selectedProvider -eq 'Custom') {
        if ($NoPrompt) {
            Join-Path $env:USERPROFILE "Backups\WindowsMissingRecovery"
        } else {
            do {
                $input = Read-Host "Enter custom backup location (default: $env:USERPROFILE\Backups\WindowsMissingRecovery)"
                $path = if ([string]::IsNullOrWhiteSpace($input)) { 
                    Join-Path $env:USERPROFILE "Backups\WindowsMissingRecovery"
                } else { 
                    $input 
                }
                $valid = Test-Path (Split-Path $path -Parent)
                if (-not $valid) {
                    Write-Host "Parent directory does not exist. Please enter a valid path." -ForegroundColor Red
                }
            } while (-not $valid)
            $path
        }
    } else {
        # Find OneDrive paths
        $onedrivePaths = @(
            "$env:USERPROFILE\OneDrive",
            "$env:USERPROFILE\OneDrive - *",
            "$env:USERPROFILE\OneDriveCommercial",
            "$env:USERPROFILE\OneDrive - Enterprise"
        )

        $possiblePaths = $onedrivePaths | 
            ForEach-Object { Get-Item -Path $_ -ErrorAction SilentlyContinue } |
            Where-Object { $_ }

        if ($possiblePaths.Count -gt 0) {
            if (-not $NoPrompt) {
                Write-Host "`nDetected OneDrive locations:" -ForegroundColor Cyan
                for ($i=0; $i -lt $possiblePaths.Count; $i++) {
                    Write-Host "[$i] $($possiblePaths[$i].FullName)"
                }
                Write-Host "[C] Custom location"

                do {
                    $selection = Read-Host "`nSelect OneDrive location [0-$($possiblePaths.Count-1)] or [C]"
                    if ($selection -eq "C") {
                        $backupRoot = Read-Host "Enter custom backup location"
                    } elseif ($selection -match '^\d+$' -and [int]$selection -lt $possiblePaths.Count) {
                        $backupRoot = $possiblePaths[$selection].FullName
                    }
                } while (-not $backupRoot)
            } else {
                $backupRoot = $possiblePaths[0].FullName
            }
        } else {
            Write-Warning "No OneDrive paths found. Using default backup location."
            $backupRoot = Join-Path $env:USERPROFILE "Backups\WindowsMissingRecovery"
        }
    }

    # Create configuration
    $config = @{
        BACKUP_ROOT = $backupRoot
        CLOUD_PROVIDER = $selectedProvider
        MACHINE_NAME = $machineName
        WINDOWS_MISSING_RECOVERY_PATH = $InstallPath
    }

    # Create config directory if it doesn't exist
    $configDir = Join-Path $InstallPath "Config"
    if (!(Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }

    # Save configuration
    $configContent = $config.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }
    Set-Content -Path $configFile -Value $configContent -Force

    Write-Host "`nConfiguration saved to: $configFile" -ForegroundColor Green
    return $config
}
