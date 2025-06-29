[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory=$false)]
    [string]$BackupRootPath = $null,
    
    [Parameter(Mandatory=$false)]
    [switch]$Force,
    
    [Parameter(Mandatory=$false)]
    [string[]]$Include = @(),
    
    [Parameter(Mandatory=$false)]
    [string[]]$Exclude = @(),
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipVerification
)

# Load environment script from the correct location
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$modulePath = Split-Path -Parent (Split-Path -Parent $scriptPath)
$loadEnvPath = Join-Path $modulePath "Private\scripts\load-environment.ps1"

# Source the load-environment script
if (Test-Path $loadEnvPath) {
    . $loadEnvPath
} else {
    Write-Host "Cannot find load-environment.ps1 at: $loadEnvPath" -ForegroundColor Red
}

# Get module configuration
$config = Get-WindowsMelodyRecovery
if (!$config.IsInitialized) {
    throw "Module not initialized. Please run Initialize-WindowsMelodyRecovery first."
}

if (!$BackupRootPath) {
    $BackupRootPath = Join-Path $config.BackupRoot $config.MachineName
}

function Restore-WordSettings {
    <#
    .SYNOPSIS
        Restores Microsoft Word settings and configurations from backup.

    .DESCRIPTION
        This script restores Microsoft Word settings including:
        - Registry settings for Word preferences, options, security, and AutoCorrect
        - Configuration files for settings, templates, and custom content
        - Custom dictionaries and AutoCorrect entries
        - Building Blocks and QuickParts
        - Custom styles and ribbons
        - Startup items and add-ins
        - Recent files and Quick Access settings

    .PARAMETER BackupRootPath
        The root path where backups are stored.

    .PARAMETER Force
        Forces the restore operation even if Word is running.

    .PARAMETER Include
        Array of specific items to include in the restore. If not specified, all items are restored.

    .PARAMETER Exclude
        Array of specific items to exclude from the restore.

    .PARAMETER SkipVerification
        Skips verification of restored items.

    .EXAMPLE
        Restore-WordSettings -BackupRootPath "C:\Backups\Machine"
        Restores Word settings from the specified backup path.

    .EXAMPLE
        Restore-WordSettings -BackupRootPath "C:\Backups\Machine" -Include @("Settings", "Templates") -WhatIf
        Shows what would be restored for Settings and Templates only.

    .NOTES
        Author: Desktop Setup Script
        Requires: Windows PowerShell 5.1 or later
        
        Test Cases:
        1. Full restore - Should restore all backed up components
        2. Selective restore with Include - Should restore only specified items
        3. Selective restore with Exclude - Should restore all except excluded items
        4. Word running - Should handle gracefully or stop if Force specified
        5. Missing backup - Should handle gracefully with appropriate error
        6. Corrupted backup - Should handle errors gracefully
        7. WhatIf mode - Should show what would be restored without making changes
        
        Mock Test Example:
        Mock-Command Test-Path { return $true }
        Mock-Command Copy-Item { return $null }
        Mock-Command reg { return "The operation completed successfully." }
        Mock-Command Get-Process { return @() }
    #>
    
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force,
        
        [Parameter(Mandatory=$false)]
        [string[]]$Include = @(),
        
        [Parameter(Mandatory=$false)]
        [string[]]$Exclude = @(),
        
        [Parameter(Mandatory=$false)]
        [switch]$SkipVerification
    )
    
    begin {
        # Test hook for mocking
        if ($script:TestMode) {
            Write-Verbose "Running in test mode"
        }
    }
    
    process {
        try {
            Write-Verbose "Starting restore of Word Settings..."
            Write-Host "Restoring Word Settings..." -ForegroundColor Blue
            
            # Validate inputs before proceeding
            if (!(Test-Path $BackupRootPath)) {
                throw [System.IO.DirectoryNotFoundException]"Backup root path not found: $BackupRootPath"
            }
            
            $backupPath = Join-Path $BackupRootPath "Word"
            if (!(Test-Path $backupPath)) {
                throw [System.IO.DirectoryNotFoundException]"Word backup not found at: $backupPath"
            }
            
            $itemsRestored = @()
            $itemsSkipped = @()
            $errors = @()
            
            # Stop Word processes if Force is specified
            if ($Force -and !$script:TestMode) {
                try {
                    $wordProcesses = Get-Process -Name "WINWORD" -ErrorAction SilentlyContinue
                    if ($wordProcesses) {
                        if ($PSCmdlet.ShouldProcess("Word processes", "Stop")) {
                            Write-Host "Stopping Word processes..." -ForegroundColor Yellow
                            $wordProcesses | Stop-Process -Force
                            Start-Sleep -Seconds 2
                        }
                    }
                } catch {
                    Write-Warning "Could not stop Word processes: $_"
                }
            }
            
            # Word config locations
            $configPaths = @{
                # Main settings
                "Settings" = "$env:APPDATA\Microsoft\Word"
                # Custom templates
                "Templates" = "$env:APPDATA\Microsoft\Templates"
                # Quick Access and recent items
                "RecentFiles" = "$env:APPDATA\Microsoft\Office\Recent"
                # Custom dictionaries
                "CustomDictionary" = "$env:APPDATA\Microsoft\UProof"
                # AutoCorrect entries
                "AutoCorrect" = "$env:APPDATA\Microsoft\Office"
                # Building Blocks
                "BuildingBlocks" = "$env:APPDATA\Microsoft\Document Building Blocks"
                # Custom styles
                "Styles" = "$env:APPDATA\Microsoft\QuickStyles"
                # Custom toolbars and ribbons
                "Ribbons" = "$env:APPDATA\Microsoft\Office\16.0\Word\Ribbons"
                # Startup items
                "Startup" = "$env:APPDATA\Microsoft\Word\STARTUP"
                # QuickParts
                "QuickParts" = "$env:APPDATA\Microsoft\Word\QuickParts"
            }

            # Restore registry settings first
            $registryPath = Join-Path $backupPath "Registry"
            if (Test-Path $registryPath) {
                $registrySubdirs = @("Word", "Common", "FileAssociations")
                foreach ($subdir in $registrySubdirs) {
                    $subdirPath = Join-Path $registryPath $subdir
                    if (Test-Path $subdirPath) {
                        # Check include/exclude filters
                        $shouldProcess = $true
                        if ($Include.Count -gt 0 -and $subdir -notin $Include) {
                            $shouldProcess = $false
                        }
                        if ($Exclude.Count -gt 0 -and $subdir -in $Exclude) {
                            $shouldProcess = $false
                        }
                        
                        if ($shouldProcess) {
                            Get-ChildItem -Path $subdirPath -Filter "*.reg" | ForEach-Object {
                                if ($PSCmdlet.ShouldProcess($_.Name, "Import registry file")) {
                                    try {
                                        if (!$script:TestMode) {
                                            $regResult = reg import $_.FullName 2>&1
                                            if ($LASTEXITCODE -eq 0) {
                                                $itemsRestored += "Registry\$subdir\$($_.Name)"
                                                Write-Host "Imported registry file: $($_.Name)" -ForegroundColor Green
                                            } else {
                                                $errors += "Failed to import registry file $($_.Name): $regResult"
                                            }
                                        } else {
                                            # Test mode
                                            $itemsRestored += "Registry\$subdir\$($_.Name)"
                                            Write-Host "Test: Would import registry file: $($_.Name)" -ForegroundColor Green
                                        }
                                    } catch {
                                        $errors += "Failed to import registry file $($_.Name): $($_.Exception.Message)"
                                    }
                                }
                            }
                        } else {
                            $itemsSkipped += "Registry\$subdir (filtered)"
                        }
                    }
                }
            }

            # Restore config files
            foreach ($config in $configPaths.GetEnumerator()) {
                $backupItem = Join-Path $backupPath $config.Key
                if (Test-Path $backupItem) {
                    # Check include/exclude filters
                    $shouldProcess = $true
                    if ($Include.Count -gt 0 -and $config.Key -notin $Include) {
                        $shouldProcess = $false
                    }
                    if ($Exclude.Count -gt 0 -and $config.Key -in $Exclude) {
                        $shouldProcess = $false
                    }
                    
                    if ($shouldProcess) {
                        if ($PSCmdlet.ShouldProcess($config.Key, "Restore configuration")) {
                            try {
                                # Create parent directory if it doesn't exist
                                $parentDir = Split-Path $config.Value -Parent
                                if (!(Test-Path $parentDir)) {
                                    if (!$script:TestMode) {
                                        New-Item -ItemType Directory -Force -Path $parentDir | Out-Null
                                    }
                                }

                                if ((Get-Item $backupItem) -is [System.IO.DirectoryInfo]) {
                                    # Skip temporary files during restore
                                    $excludeFilter = @("*.tmp", "~*.*", "*.asd")
                                    if (!$script:TestMode) {
                                        Copy-Item $backupItem $config.Value -Recurse -Force -Exclude $excludeFilter -ErrorAction Stop
                                    }
                                } else {
                                    if (!$script:TestMode) {
                                        Copy-Item $backupItem $config.Value -Force -ErrorAction Stop
                                    }
                                }
                                $itemsRestored += "Config: $($config.Key)"
                                Write-Host "Restored configuration: $($config.Key)" -ForegroundColor Green
                            } catch {
                                $errors += "Failed to restore $($config.Key): $($_.Exception.Message)"
                            }
                        }
                    } else {
                        $itemsSkipped += "Config: $($config.Key) (filtered)"
                    }
                } else {
                    Write-Verbose "Backup item not found: $($config.Key)"
                }
            }

            # Verification (if not skipped)
            if (!$SkipVerification -and !$WhatIfPreference) {
                Write-Host "Verifying restored items..." -ForegroundColor Yellow
                $verificationErrors = @()
                
                foreach ($config in $configPaths.GetEnumerator()) {
                    if ($config.Key -in ($itemsRestored | Where-Object { $_ -like "Config: *" } | ForEach-Object { $_.Replace("Config: ", "") })) {
                        if (!(Test-Path $config.Value)) {
                            $verificationErrors += "Restored item not found: $($config.Key) at $($config.Value)"
                        }
                    }
                }
                
                if ($verificationErrors.Count -gt 0) {
                    $errors += $verificationErrors
                }
            }

            # Create result object
            $result = [PSCustomObject]@{
                Success = $errors.Count -eq 0
                BackupPath = $backupPath
                Feature = "Word"
                Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                ItemsRestored = $itemsRestored
                ItemsSkipped = $itemsSkipped
                Errors = $errors
            }

            # Summary
            Write-Host "`nWord Settings Restore Summary:" -ForegroundColor Green
            Write-Host "Items restored: $($itemsRestored.Count)" -ForegroundColor Yellow
            Write-Host "Items skipped: $($itemsSkipped.Count)" -ForegroundColor Yellow
            if ($errors.Count -gt 0) {
                Write-Host "Errors encountered: $($errors.Count)" -ForegroundColor Yellow
                foreach ($error in $errors) {
                    Write-Host "  - $error" -ForegroundColor Red
                }
            }
            
            if ($result.Success) {
                Write-Host "Word Settings restored successfully from: $backupPath" -ForegroundColor Green
                if (!$WhatIfPreference) {
                    Write-Host "`nNote: Word restart may be required for settings to take effect" -ForegroundColor Yellow
                }
            } else {
                Write-Host "Word Settings restore completed with errors" -ForegroundColor Yellow
            }
            
            return $result
        } catch {
            $errorMessage = "Failed to restore Word Settings: $($_.Exception.Message)"
            Write-Host $errorMessage -ForegroundColor Red
            
            return [PSCustomObject]@{
                Success = $false
                BackupPath = $backupPath
                Feature = "Word"
                Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                ItemsRestored = @()
                ItemsSkipped = @()
                Errors = @($errorMessage)
            }
        }
    }
}

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    $result = Restore-WordSettings -BackupRootPath $BackupRootPath -Force:$Force -Include $Include -Exclude $Exclude -SkipVerification:$SkipVerification
    if (-not $result.Success) {
        exit 1
    }
}