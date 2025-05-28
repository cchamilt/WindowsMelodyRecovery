function Initialize-WindowsMissingRecovery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$CustomInstallPath,
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

        # Create machine-specific directory structure
        $machineBackupDir = Join-Path $backupRoot $machineName
        $configDir = Join-Path $machineBackupDir "Config"
        $configFile = Join-Path $configDir "config.json"
        
        # Check if configuration already exists
        $existingConfig = $null
        if (Test-Path $configFile) {
            try {
                $existingConfig = Get-Content -Path $configFile -Raw | ConvertFrom-Json
                Write-Host "`nExisting configuration found for machine '$machineName' at:" -ForegroundColor Yellow
                Write-Host "Backup location: $($existingConfig.MachineBackupDir)" -ForegroundColor Cyan
                Write-Host "Last configured: $($existingConfig.LastConfigured)" -ForegroundColor Cyan
                
                do {
                    $choice = Read-Host "`nDo you want to: [K]eep existing configuration, [R]eplace it, or [C]ancel? (K/R/C)"
                    switch ($choice.ToUpper()) {
                        'K' { 
                            Write-Host "Keeping existing configuration." -ForegroundColor Green
                            return $true 
                        }
                        'R' { 
                            Write-Host "Replacing existing configuration..." -ForegroundColor Yellow
                            break
                        }
                        'C' { 
                            Write-Host "Operation cancelled." -ForegroundColor Yellow
                            return $false
                        }
                        default { 
                            Write-Host "Invalid choice. Please select K, R, or C." -ForegroundColor Red
                            continue
                        }
                    }
                } while ($choice -notmatch '^[KRC]$')
            } catch {
                Write-Warning "Error reading existing configuration: $_"
                Write-Host "Will create new configuration." -ForegroundColor Yellow
            }
        }
        
        # Create directories if they don't exist
        foreach ($dir in @($machineBackupDir, $configDir)) {
            if (!(Test-Path -Path $dir)) {
                try {
                    New-Item -ItemType Directory -Path $dir -Force | Out-Null
                    Write-Host "Created directory: $dir" -ForegroundColor Green
                } catch {
                    Write-Warning "Failed to create directory: $dir - $_"
                    throw
                }
            }
        }

        # Create local module config directory
        $moduleConfigDir = Join-Path $PSScriptRoot "..\Config"
        if (!(Test-Path -Path $moduleConfigDir)) {
            try {
                New-Item -ItemType Directory -Path $moduleConfigDir -Force | Out-Null
                Write-Host "Created module config directory: $moduleConfigDir" -ForegroundColor Green
            } catch {
                Write-Warning "Failed to create module config directory: $_"
                throw
            }
        }

        # Update module configuration
        $config = @{
            BackupRoot = $backupRoot
            MachineName = $machineName
            CloudProvider = $selectedProvider
            MachineBackupDir = $machineBackupDir
            ConfigDir = $configDir
            LastConfigured = Get-Date
            IsInitialized = $true
        }

        # Save configuration to both locations
        $configJson = $config | ConvertTo-Json
        $configFiles = @(
            (Join-Path $moduleConfigDir "config.json"),
            $configFile
        )

        foreach ($configFile in $configFiles) {
            try {
                Set-Content -Path $configFile -Value $configJson -Force
                Write-Host "Saved configuration to: $configFile" -ForegroundColor Green
            } catch {
                Write-Warning "Failed to save configuration to $configFile - $_"
                throw
            }
        }
        
        Write-Host "`nConfiguration completed successfully!" -ForegroundColor Green
        Write-Host "Backup location: $machineBackupDir" -ForegroundColor Cyan
        Write-Host "Machine name: $machineName" -ForegroundColor Cyan
        Write-Host "`nYou can now use Backup-WindowsMissingRecovery to create your first backup." -ForegroundColor Yellow
    }

    return $true
}
