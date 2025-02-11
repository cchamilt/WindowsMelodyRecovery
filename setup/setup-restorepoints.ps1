# Requires admin privileges
#Requires -RunAsAdministrator

# At the start after admin check
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path (Split-Path $scriptPath -Parent) "scripts\load-environment.ps1")

if (!(Load-Environment)) {
    Write-Host "Failed to load environment configuration" -ForegroundColor Red
    exit 1
}

try {
    Write-Host "Configuring System Restore..." -ForegroundColor Blue

    # Enable System Protection (System Restore)
    $systemDrive = $env:SystemDrive
    Write-Host "Enabling System Protection for $systemDrive..." -ForegroundColor Yellow
    Enable-ComputerRestore -Drive $systemDrive
    
    # Enable through registry as well (equivalent to GUI toggle)
    $regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore"
    Set-ItemProperty -Path $regPath -Name "RPSessionInterval" -Value 1 -Type DWord
    
    # Set protection percentage through vssadmin
    $drive = Get-WmiObject -Class Win32_Volume -Filter "DriveLetter = '$systemDrive'"
    $driveSize = [math]::Round($drive.Capacity / 1GB)
    $maxSize = [math]::Max([math]::Round($driveSize * 0.1), 50) # 10% of drive or 50GB, whichever is larger

    Write-Host "Setting System Protection storage to $maxSize GB..." -ForegroundColor Yellow
    vssadmin resize shadowstorage /for=$systemDrive /on=$systemDrive /maxsize="$maxSize`GB" | Out-Null

    # Create an initial restore point
    $description = "Windows Configuration Initial Restore Point"
    Write-Host "Creating initial restore point: $description" -ForegroundColor Yellow
    Checkpoint-Computer -Description $description -RestorePointType "MODIFY_SETTINGS"

    # Configure restore point schedule (if not already configured)
    $taskName = "SystemRestorePoint"
    $taskExists = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

    if (!$taskExists) {
        Write-Host "Creating monthly System Restore point schedule..." -ForegroundColor Yellow
        $action = New-ScheduledTaskAction -Execute 'PowerShell.exe' `
            -Argument '-NoProfile -ExecutionPolicy Bypass -Command "Checkpoint-Computer -Description \"Monthly System Restore Point\" -RestorePointType MODIFY_SETTINGS"'
        
        $trigger = New-ScheduledTaskTrigger -Monthly -At 4AM -DaysOfMonth 1
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopIfGoingOnBatteries -AllowStartIfOnBatteries

        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Creates monthly system restore points"
    }

    # Enable automatic restore points before Windows Updates
    Write-Host "Enabling automatic restore points before Windows Updates..." -ForegroundColor Yellow
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" -Name "SystemRestorePointCreationFrequency" -Value 0 -Type DWord
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" -Name "CreateRestorePointBeforeInstall" -Value 1 -Type DWord

    # # Configure Windows Update to create restore points
    # $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
    # if (!(Test-Path $regPath)) {
    #     New-Item -Path $regPath -Force | Out-Null
    # }
    # Set-ItemProperty -Path $regPath -Name "CreateRestorePointAtStartup" -Value 1 -Type DWord

    Write-Host "System Restore configuration completed!" -ForegroundColor Green
} catch {
    Write-Host "Failed to configure System Restore: $_" -ForegroundColor Red
    exit 1
}



