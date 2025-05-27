function Initialize-WindowsMissingRecovery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$CustomInstallPath,
        [switch]$NoPrompt
    )

    # Get the current module configuration
    $currentConfig = Get-WindowsMissingRecovery
    
    # Use the module's Config directory as the default
    if (!$CustomInstallPath) {
        $InstallPath = $currentConfig.WindowsMissingRecoveryPath
    } else {
        $InstallPath = $CustomInstallPath
    }

    # Ensure the installation path exists
    if (!(Test-Path $InstallPath)) {
        try {
            New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
            Write-Host "Created directory: $InstallPath" -ForegroundColor Green
        } catch {
            Write-Warning "Failed to create directory: $InstallPath - $_"
        }
    }

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

        # Update module configuration
        Set-WindowsMissingRecovery -BackupRoot $backupRoot -MachineName $machineName -CloudProvider $selectedProvider
        
        # Create machine-specific directory
        $machineBackupDir = Join-Path $backupRoot $machineName
        if (!(Test-Path -Path $machineBackupDir)) {
            try {
                New-Item -ItemType Directory -Path $machineBackupDir -Force | Out-Null
                Write-Host "Created machine-specific backup directory at: $machineBackupDir" -ForegroundColor Green
            } catch {
                Write-Warning "Failed to create machine-specific backup directory: $_"
            }
        }
        
        Write-Host "Configuration saved to both local and backup locations." -ForegroundColor Green
    }

    return $true
}
