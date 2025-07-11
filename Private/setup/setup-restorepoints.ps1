# Setup-RestorePoints.ps1 - Configure automatic system restore points

function Setup-RestorePoints {
    [CmdletBinding()]
    param()

    # Check for admin privileges
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Warning "This function requires administrator privileges. Please run PowerShell as Administrator."
        return $false
    }

    # Load environment configuration (optional - module will use fallback configuration)
    try {
        Import-Environment | Out-Null
    } catch {
        Write-Verbose "Using module configuration fallback"
    }

    try {
        Write-Information -MessageData "Configuring System Restore..." -InformationAction Continue

        # Enable System Protection (System Restore)
        $systemDrive = $env:SystemDrive
        Write-Warning -Message "Enabling System Protection for $systemDrive..."
        Enable-ComputerRestore -Drive $systemDrive

        # Enable through registry as well (equivalent to GUI toggle)
        $regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore"
        Set-ItemProperty -Path $regPath -Name "RPSessionInterval" -Value 1 -Type DWord

        # Set protection percentage through vssadmin
        $drive = Get-WmiObject -Class Win32_Volume -Filter "DriveLetter = '$systemDrive'"
        $driveSize = [math]::Round($drive.Capacity / 1GB)
        $maxSize = [math]::Max([math]::Round($driveSize * 0.1), 50) # 10% of drive or 50GB, whichever is larger

        Write-Warning -Message "Setting System Protection storage to $maxSize GB..."
        vssadmin resize shadowstorage /for=$systemDrive /on=$systemDrive /maxsize="$maxSize`GB" | Out-Null

        # Check if we can create a restore point
        $canCreate = $true
        try {
            $lastRestore = Get-ComputerRestorePoint | Sort-Object -Property CreationTime -Descending | Select-Object -First 1
            if ($lastRestore) {
                $timeSinceLastRestore = (Get-Date) - $lastRestore.CreationTime
                $minInterval = 1440 # 24 hours in minutes
                if ($timeSinceLastRestore.TotalMinutes -lt $minInterval) {
                    Write-Warning -Message "Skipping initial restore point - one was created in the last 24 hours"
                    $canCreate = $false
                }
            }
        } catch {
            Write-Warning -Message "Warning: Could not check last restore point time: $($_.Exception.Message)"
        }

        # Create an initial restore point
        if ($canCreate) {
            $description = "Windows Configuration Initial Restore Point"
            Write-Warning -Message "Creating initial restore point: $description"
            Checkpoint-Computer -Description $description -RestorePointType "MODIFY_SETTINGS"
        }

        # Configure restore point schedule (if not already configured)
        $taskName = "SystemRestorePoint"
        $taskExists = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

        if (!$taskExists) {
            Write-Warning -Message "Creating monthly System Restore point schedule..."
            $action = New-ScheduledTaskAction -Execute 'PowerShell.exe' `
                -Argument '-NoProfile -ExecutionPolicy Bypass -Command "Checkpoint-Computer -Description \"Monthly System Restore Point\" -RestorePointType MODIFY_SETTINGS"'

            # Create weekly trigger and modify for monthly
            $trigger = New-ScheduledTaskTrigger `
                -Weekly `
                -WeeksInterval 4 `
                -DaysOfWeek Monday `
                -At 4am

            # Modify trigger to run on day 1 of each month
            $trigger.Repetition.Duration = $null
            $trigger.Repetition.Interval = "P1M"

            $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
            $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopIfGoingOnBatteries -AllowStartIfOnBatteries

            Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Creates monthly system restore points"
        }

        # Enable automatic restore points before Windows Updates
        Write-Warning -Message "Enabling automatic restore points before Windows Updates..."
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" -Name "SystemRestorePointCreationFrequency" -Value 0 -Type DWord
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" -Name "CreateRestorePointBeforeInstall" -Value 1 -Type DWord

        Write-Information -MessageData "System Restore configuration completed!" -InformationAction Continue
        return $true

    } catch {
        Write-Error -Message "Failed to configure System Restore: $($_.Exception.Message)"
        return $false
    }
}






