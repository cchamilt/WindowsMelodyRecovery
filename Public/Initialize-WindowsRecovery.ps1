function Initialize-WindowsRecovery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$InstallPath = "$env:USERPROFILE\Scripts\WindowsMissingRecovery",
        [switch]$NoPrompt
    )

    # Verify admin privileges
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "This function requires elevation. Please run PowerShell as Administrator."
    }

    # Cloud storage providers and their common paths
    $cloudProviders = @{
        OneDrive = @(
            "$env:USERPROFILE\OneDrive",
            "$env:USERPROFILE\OneDrive - *",
            "$env:USERPROFILE\OneDriveCommercial",
            "$env:USERPROFILE\OneDrive - Enterprise"
        )
        GoogleDrive = @(
            "$env:USERPROFILE\Google Drive",
            "$env:USERPROFILE\My Drive",
            "$env:USERPROFILE\GDrive"
        )
        Dropbox = @(
            "$env:USERPROFILE\Dropbox",
            "$env:USERPROFILE\Dropbox (Personal)",
            "$env:USERPROFILE\Dropbox (Work)"
        )
        Box = @(
            "$env:USERPROFILE\Box",
            "$env:USERPROFILE\Box Sync"
        )
    }

    # Configuration prompts
    if (!$NoPrompt) {
        # Select cloud storage provider
        Write-Host "`nSelect cloud storage provider:" -ForegroundColor Blue
        $providerOptions = $cloudProviders.Keys | ForEach-Object { "[$($_.Substring(0,1))] $_" }
        $providerOptions += "[C] Custom location"
        Write-Host ($providerOptions -join "`n")
        
        do {
            $providerChoice = Read-Host "`nSelect provider (O/G/D/B/C)"
            $selectedProvider = switch ($providerChoice.ToUpper()) {
                'O' { 'OneDrive' }
                'G' { 'GoogleDrive' }
                'D' { 'Dropbox' }
                'B' { 'Box' }
                'C' { 'Custom' }
                default { $null }
            }
        } while (!$selectedProvider)

        # Select or enter backup root
        if ($selectedProvider -ne 'Custom') {
            # Find existing paths for selected provider
            $possiblePaths = $cloudProviders[$selectedProvider] | 
                ForEach-Object { Get-Item -Path $_ -ErrorAction SilentlyContinue } |
                Where-Object { $_ }

            if ($possiblePaths.Count -gt 0) {
                Write-Host "`nDetected $selectedProvider locations:" -ForegroundColor Blue
                for ($i=0; $i -lt $possiblePaths.Count; $i++) {
                    Write-Host "[$i] $($possiblePaths[$i].FullName)"
                }
                Write-Host "[C] Custom location"

                do {
                    $selection = Read-Host "`nSelect $selectedProvider location [0-$($possiblePaths.Count-1)] or [C]"
                    if ($selection -eq "C") {
                        $backupRoot = Read-Host "Enter custom backup location"
                    } elseif ($selection -match '^\d+$' -and [int]$selection -lt $possiblePaths.Count) {
                        $backupRoot = Join-Path $possiblePaths[$selection].FullName "WindowsMissingRecovery"
                    }
                } while (!$backupRoot)
            } else {
                $backupRoot = Read-Host "Enter $selectedProvider backup location"
            }
        } else {
            $backupRoot = Read-Host "Enter custom backup location"
        }

        # Machine name prompt
        $machineName = Read-Host "Enter machine name [default: $env:COMPUTERNAME]"
        if ([string]::IsNullOrWhiteSpace($machineName)) {
            $machineName = $env:COMPUTERNAME
        }

        # Create config.env in both local and backup locations
        $configContent = @"
BACKUP_ROOT=$backupRoot
MACHINE_NAME=$machineName
WINDOWS_MISSING_RECOVERY_PATH=$InstallPath
CLOUD_PROVIDER=$selectedProvider
MODULE_VERSION=1.0.0
LAST_CONFIGURED=$(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
"@

        # Save to local installation directory
        $localConfigPath = Join-Path $InstallPath "config.env"
        Set-Content -Path $localConfigPath -Value $configContent

        # Save to backup directory
        $backupConfigPath = Join-Path $backupRoot "config.env"
        if (!(Test-Path (Split-Path $backupConfigPath -Parent))) {
            New-Item -ItemType Directory -Path (Split-Path $backupConfigPath -Parent) -Force | Out-Null
        }
        Set-Content -Path $backupConfigPath -Value $configContent

        Write-Host "Configuration saved to both local and backup locations." -ForegroundColor Green
    }

    # Load environment
    if (!(Load-Environment)) {
        Write-Host "Failed to load environment configuration" -ForegroundColor Red
        return $false
    }

    return $true
}
