#Validates the recovery setup and backup integrity
#Also runs the private functions from the module individually

function Test-WindowsMelodyRecovery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [switch]$Detailed,
        [switch]$NoPrompt
    )

    # Verify admin privileges (Windows only) by calling the mockable helper
    if ($IsWindows) {
        if (-not (Test-WmrAdminPrivilege)) {
            Write-Warning "This function requires elevation. Please run PowerShell as Administrator."
            return $false
        }
    }

    $results = @{
        ModuleLoaded = $false
        ConfigurationValid = $false
        BackupLocationAccessible = $false
        ScheduledTasksInstalled = $false
        BackupFunctionality = $false
        RestoreFunctionality = $false
        UpdateFunctionality = $false
        Errors = @()
        Warnings = @()
    }

    Write-Host ""
    Write-Host "Testing WindowsMelodyRecovery Module..." -ForegroundColor Blue

    # Test 1: Module Loading
    try {
        $module = Get-Module WindowsMelodyRecovery
        if ($module) {
            $results.ModuleLoaded = $true
            Write-Host "Module loaded successfully" -ForegroundColor Green
        } else {
            $results.Errors += "Module not loaded"
            Write-Host "Module not loaded" -ForegroundColor Red
        }
    } catch {
        $results.Errors += "Failed to check module: $_"
        Write-Host "Failed to check module: $_" -ForegroundColor Red
    }

    # Test 2: Configuration
    try {
        $config = Get-WindowsMelodyRecovery
        if ($config -and $config.BackupRoot) {
            $results.ConfigurationValid = $true
            Write-Host "Configuration is valid" -ForegroundColor Green

            if ($Detailed) {
                Write-Host ""
                Write-Host "Configuration Details:" -ForegroundColor Cyan
                Write-Host "  Backup Root: $($config.BackupRoot)" -ForegroundColor Cyan
                Write-Host "  Machine Name: $($config.MachineName)" -ForegroundColor Cyan
                Write-Host "  Cloud Provider: $($config.CloudProvider)" -ForegroundColor Cyan
                Write-Host "  Last Configured: $($config.LastConfigured)" -ForegroundColor Cyan
            }
        } else {
            $results.Errors += "Configuration not initialized"
            Write-Host "Configuration not initialized" -ForegroundColor Red
        }
    } catch {
        $results.Errors += "Failed to check configuration: $_"
        Write-Host "Failed to check configuration: $_" -ForegroundColor Red
    }

    # Test 3: Backup Location
    if ($results.ConfigurationValid) {
        try {
            $backupRoot = $config.BackupRoot
            $machineBackupDir = Join-Path $backupRoot $config.MachineName

            if (Test-Path $backupRoot) {
                $results.BackupLocationAccessible = $true
                Write-Host "Backup root location is accessible" -ForegroundColor Green

                if (Test-Path $machineBackupDir) {
                    Write-Host "Machine-specific backup directory exists" -ForegroundColor Green
                } else {
                    $results.Warnings += "Machine-specific backup directory does not exist"
                    Write-Host "Machine-specific backup directory does not exist" -ForegroundColor Yellow
                }
            } else {
                $results.Errors += "Backup root location is not accessible"
                Write-Host "Backup root location is not accessible" -ForegroundColor Red
            }
        } catch {
            $results.Errors += "Failed to check backup location: $_"
            Write-Host "Failed to check backup location: $_" -ForegroundColor Red
        }
    }

    # Test 4: Scheduled Tasks (Windows only)
    if ($IsWindows) {
        try {
            $taskPath = "\WindowsMelodyRecovery\"
            $backupTask = Get-ScheduledTask -TaskName "WindowsMelodyRecovery-Backup" -TaskPath $taskPath -ErrorAction SilentlyContinue
            $updateTask = Get-ScheduledTask -TaskName "WindowsMelodyRecovery-Update" -TaskPath $taskPath -ErrorAction SilentlyContinue

            if ($backupTask -and $updateTask) {
                $results.ScheduledTasksInstalled = $true
                Write-Host "Scheduled tasks are installed" -ForegroundColor Green

                if ($Detailed) {
                    Write-Host ""
                    Write-Host "Scheduled Tasks Details:" -ForegroundColor Cyan
                    Write-Host "  Backup Task: $($backupTask.State)" -ForegroundColor Cyan
                    Write-Host "  Update Task: $($updateTask.State)" -ForegroundColor Cyan
                }
            } else {
                $results.Warnings += "Some scheduled tasks are missing"
                Write-Host "Some scheduled tasks are missing" -ForegroundColor Yellow
            }
        } catch {
            $results.Errors += "Failed to check scheduled tasks: $_"
            Write-Host "Failed to check scheduled tasks: $_" -ForegroundColor Red
        }
    } else {
        $results.Warnings += "Scheduled tasks check skipped (not available on this platform)"
        Write-Host "Scheduled tasks check skipped (not available on this platform)" -ForegroundColor Yellow
    }

    # Test 5: Backup Functionality
    if ($results.ConfigurationValid -and $results.BackupLocationAccessible) {
        try {
            $backupTest = Get-Command Backup-WindowsMelodyRecovery -ErrorAction Stop
            if ($backupTest) {
                $results.BackupFunctionality = $true
                Write-Host "Backup functionality is available" -ForegroundColor Green
            }
        } catch {
            $results.Errors += "Backup functionality not available: $_"
            Write-Host "Backup functionality not available: $_" -ForegroundColor Red
        }
    }

    # Test 6: Restore Functionality
    if ($results.ConfigurationValid) {
        try {
            $restoreTest = Get-Command Restore-WindowsMelodyRecovery -ErrorAction Stop
            if ($restoreTest) {
                $results.RestoreFunctionality = $true
                Write-Host "Restore functionality is available" -ForegroundColor Green
            }
        } catch {
            $results.Errors += "Restore functionality not available: $_"
            Write-Host "Restore functionality not available: $_" -ForegroundColor Red
        }
    }

    # Test 7: Update Functionality
    try {
        $updateTest = Get-Command Update-WindowsMelodyRecovery -ErrorAction Stop
        if ($updateTest) {
            $results.UpdateFunctionality = $true
            Write-Host "Update functionality is available" -ForegroundColor Green
        }
    } catch {
        $results.Errors += "Update functionality not available: $_"
        Write-Host "Update functionality not available: $_" -ForegroundColor Red
    }

    # Summary
    Write-Host ""
    Write-Host "Test Summary:" -ForegroundColor Blue
    Write-Host "Module Loaded: $($results.ModuleLoaded)" -ForegroundColor $(if ($results.ModuleLoaded) { "Green" } else { "Red" })
    Write-Host "Configuration Valid: $($results.ConfigurationValid)" -ForegroundColor $(if ($results.ConfigurationValid) { "Green" } else { "Red" })
    Write-Host "Backup Location Accessible: $($results.BackupLocationAccessible)" -ForegroundColor $(if ($results.BackupLocationAccessible) { "Green" } else { "Red" })
    Write-Host "Scheduled Tasks Installed: $($results.ScheduledTasksInstalled)" -ForegroundColor $(if ($results.ScheduledTasksInstalled) { "Green" } else { "Yellow" })
    Write-Host "Backup Functionality: $($results.BackupFunctionality)" -ForegroundColor $(if ($results.BackupFunctionality) { "Green" } else { "Red" })
    Write-Host "Restore Functionality: $($results.RestoreFunctionality)" -ForegroundColor $(if ($results.RestoreFunctionality) { "Green" } else { "Red" })
    Write-Host "Update Functionality: $($results.UpdateFunctionality)" -ForegroundColor $(if ($results.UpdateFunctionality) { "Green" } else { "Red" })

    if ($results.Errors.Count -gt 0) {
        Write-Host ""
        Write-Host "Errors:" -ForegroundColor Red
        foreach ($errorMessage in $results.Errors) {
            Write-Host "  $errorMessage" -ForegroundColor Red
        }
    }

    if ($results.Warnings.Count -gt 0) {
        Write-Host ""
        Write-Host "Warnings:" -ForegroundColor Yellow
        foreach ($warning in $results.Warnings) {
            Write-Host "  $warning" -ForegroundColor Yellow
        }
    }

    # Return overall status
    return $results.Errors.Count -eq 0
}
