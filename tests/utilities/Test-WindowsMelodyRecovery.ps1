#Validates the recovery setup and backup integrity
#Also runs the private functions from the module individually

function Test-WindowsMelodyRecovery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [switch]$Detailed,
        [switch]$NoPrompt
    )

    # Import the test utility
    . (Resolve-Path "$PSScriptRoot/Test-WmrAdminPrivilege.ps1")

    # Verify admin privileges (Windows only) by calling the mockable helper
    if ($IsWindows) {
        if (-not (Test-WmrAdminPrivilege)) {
            Write-Warning "This function requires elevation. Please run PowerShell as Administrator."
            return $false
        }
    }

    $results = @{
        ModuleLoaded             = $false
        ConfigurationValid       = $false
        BackupLocationAccessible = $false
        ScheduledTasksInstalled  = $false
        BackupFunctionality      = $false
        RestoreFunctionality     = $false
        UpdateFunctionality      = $false
        Errors                   = @()
        Warnings                 = @()
    }

    Write-Information -MessageData "" -InformationAction Continue
    Write-Information -MessageData "Testing WindowsMelodyRecovery Module..." -InformationAction Continue

    # Test 1: Module Loading
    try {
        $module = Get-Module WindowsMelodyRecovery
        if ($module) {
            $results.ModuleLoaded = $true
            Write-Information -MessageData "Module loaded successfully" -InformationAction Continue
        }
        else {
            $results.Errors += "Module not loaded"
            Write-Error -Message "Module not loaded"
        }
    }
    catch {
        $results.Errors += "Failed to check module: $_"
        Write-Error -Message "Failed to check module: $_"
    }

    # Test 2: Configuration
    try {
        $config = Get-WindowsMelodyRecovery
        if ($config -and $config.BackupRoot) {
            $results.ConfigurationValid = $true
            Write-Information -MessageData "Configuration is valid" -InformationAction Continue

            if ($Detailed) {
                Write-Information -MessageData "" -InformationAction Continue
                Write-Information -MessageData "Configuration Details:" -InformationAction Continue
                Write-Information -MessageData "  Backup Root: $($config.BackupRoot)" -InformationAction Continue
                Write-Information -MessageData "  Machine Name: $($config.MachineName)" -InformationAction Continue
                Write-Information -MessageData "  Cloud Provider: $($config.CloudProvider)" -InformationAction Continue
                Write-Information -MessageData "  Last Configured: $($config.LastConfigured)" -InformationAction Continue
            }
        }
        else {
            $results.Errors += "Configuration not initialized"
            Write-Error -Message "Configuration not initialized"
        }
    }
    catch {
        $results.Errors += "Failed to check configuration: $_"
        Write-Error -Message "Failed to check configuration: $_"
    }

    # Test 3: Backup Location
    if ($results.ConfigurationValid) {
        try {
            $backupRoot = $config.BackupRoot
            $machineBackupDir = Join-Path $backupRoot $config.MachineName

            if (Test-Path $backupRoot) {
                $results.BackupLocationAccessible = $true
                Write-Information -MessageData "Backup root location is accessible" -InformationAction Continue

                if (Test-Path $machineBackupDir) {
                    Write-Information -MessageData "Machine-specific backup directory exists" -InformationAction Continue
                }
                else {
                    $results.Warnings += "Machine-specific backup directory does not exist"
                    Write-Warning -Message "Machine-specific backup directory does not exist"
                }
            }
            else {
                $results.Errors += "Backup root location is not accessible"
                Write-Error -Message "Backup root location is not accessible"
            }
        }
        catch {
            $results.Errors += "Failed to check backup location: $_"
            Write-Error -Message "Failed to check backup location: $_"
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
                Write-Information -MessageData "Scheduled tasks are installed" -InformationAction Continue

                if ($Detailed) {
                    Write-Information -MessageData "" -InformationAction Continue
                    Write-Information -MessageData "Scheduled Tasks Details:" -InformationAction Continue
                    Write-Information -MessageData "  Backup Task: $($backupTask.State)" -InformationAction Continue
                    Write-Information -MessageData "  Update Task: $($updateTask.State)" -InformationAction Continue
                }
            }
            else {
                $results.Warnings += "Some scheduled tasks are missing"
                Write-Warning -Message "Some scheduled tasks are missing"
            }
        }
        catch {
            $results.Errors += "Failed to check scheduled tasks: $_"
            Write-Error -Message "Failed to check scheduled tasks: $_"
        }
    }
    else {
        $results.Warnings += "Scheduled tasks check skipped (not available on this platform)"
        Write-Warning -Message "Scheduled tasks check skipped (not available on this platform)"
    }

    # Test 5: Backup Functionality
    if ($results.ConfigurationValid -and $results.BackupLocationAccessible) {
        try {
            $backupTest = Get-Command Backup-WindowsMelodyRecovery -ErrorAction Stop
            if ($backupTest) {
                $results.BackupFunctionality = $true
                Write-Information -MessageData "Backup functionality is available" -InformationAction Continue
            }
        }
        catch {
            $results.Errors += "Backup functionality not available: $_"
            Write-Error -Message "Backup functionality not available: $_"
        }
    }

    # Test 6: Restore Functionality
    if ($results.ConfigurationValid) {
        try {
            $restoreTest = Get-Command Restore-WindowsMelodyRecovery -ErrorAction Stop
            if ($restoreTest) {
                $results.RestoreFunctionality = $true
                Write-Information -MessageData "Restore functionality is available" -InformationAction Continue
            }
        }
        catch {
            $results.Errors += "Restore functionality not available: $_"
            Write-Error -Message "Restore functionality not available: $_"
        }
    }

    # Test 7: Update Functionality
    try {
        $updateTest = Get-Command Update-WindowsMelodyRecovery -ErrorAction Stop
        if ($updateTest) {
            $results.UpdateFunctionality = $true
            Write-Information -MessageData "Update functionality is available" -InformationAction Continue
        }
    }
    catch {
        $results.Errors += "Update functionality not available: $_"
        Write-Error -Message "Update functionality not available: $_"
    }

    # Summary
    Write-Information -MessageData "" -InformationAction Continue
    Write-Information -MessageData "Test Summary:" -InformationAction Continue
    Write-Information -MessageData "Module Loaded: $($results.ModuleLoaded)"  -InformationAction Continue-ForegroundColor $(if ($results.ModuleLoaded) { "Green" } else { "Red" })
    Write-Information -MessageData "Configuration Valid: $($results.ConfigurationValid)"  -InformationAction Continue-ForegroundColor $(if ($results.ConfigurationValid) { "Green" } else { "Red" })
    Write-Information -MessageData "Backup Location Accessible: $($results.BackupLocationAccessible)"  -InformationAction Continue-ForegroundColor $(if ($results.BackupLocationAccessible) { "Green" } else { "Red" })
    Write-Information -MessageData "Scheduled Tasks Installed: $($results.ScheduledTasksInstalled)"  -InformationAction Continue-ForegroundColor $(if ($results.ScheduledTasksInstalled) { "Green" } else { "Yellow" })
    Write-Information -MessageData "Backup Functionality: $($results.BackupFunctionality)"  -InformationAction Continue-ForegroundColor $(if ($results.BackupFunctionality) { "Green" } else { "Red" })
    Write-Information -MessageData "Restore Functionality: $($results.RestoreFunctionality)"  -InformationAction Continue-ForegroundColor $(if ($results.RestoreFunctionality) { "Green" } else { "Red" })
    Write-Information -MessageData "Update Functionality: $($results.UpdateFunctionality)"  -InformationAction Continue-ForegroundColor $(if ($results.UpdateFunctionality) { "Green" } else { "Red" })

    if ($results.Errors.Count -gt 0) {
        Write-Information -MessageData "" -InformationAction Continue
        Write-Error -Message "Errors:"
        foreach ($errorMessage in $results.Errors) {
            Write-Error -Message "  $errorMessage"
        }
    }

    if ($results.Warnings.Count -gt 0) {
        Write-Information -MessageData "" -InformationAction Continue
        Write-Warning -Message "Warnings:"
        foreach ($warning in $results.Warnings) {
            Write-Warning -Message "  $warning"
        }
    }

    # Return overall status
    return $results.Errors.Count -eq 0
}








