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

function Backup-TouchpadSettings {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath
    )
    
    try {
        Write-Host "Backing up Touchpad Settings..." -ForegroundColor Blue
        $backupPath = Initialize-BackupDirectory -Path "Touchpad" -BackupType "Touchpad Settings" -BackupRootPath $BackupRootPath
        
        if ($backupPath) {
            # Export touchpad registry settings
            $regPaths = @(
                # Windows Precision Touchpad settings
                "HKCU\Software\Microsoft\Windows\CurrentVersion\PrecisionTouchPad",
                "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\PrecisionTouchPad",
                
                # Mouse properties (affects touchpad)
                "HKCU\Control Panel\Mouse",
                "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\ControlPanel\Mouse",
                
                # Synaptics settings
                "HKLM\SOFTWARE\Synaptics",
                "HKCU\Software\Synaptics",
                
                # Elan settings
                "HKLM\SOFTWARE\Elantech",
                "HKCU\Software\Elantech",
                
                # General input settings
                "HKLM\SYSTEM\CurrentControlSet\Services\MouseLikeTouchPad",
                "HKLM\SYSTEM\CurrentControlSet\Services\SynTP",
                "HKLM\SYSTEM\CurrentControlSet\Services\ETD"
            )

            foreach ($regPath in $regPaths) {
                $regFile = "$backupPath\$($regPath.Split('\')[-1]).reg"
                reg export $regPath $regFile /y 2>$null
            }

            # Get all touchpad devices, including disabled ones
            $touchpadDevices = Get-PnpDevice | Where-Object { 
                ($_.Class -eq "Mouse" -or $_.Class -eq "HIDClass") -and 
                ($_.FriendlyName -match "touchpad|synaptics|elan|precision" -or
                 $_.Manufacturer -match "synaptics|elan|alps")
            } | Select-Object -Property @(
                'InstanceId',
                'FriendlyName',
                'Manufacturer',
                'Status',
                @{Name='IsEnabled'; Expression={$_.Status -eq 'OK'}}
            )
            
            if ($touchpadDevices) {
                $touchpadDevices | ConvertTo-Json | Out-File "$backupPath\touchpad_devices.json" -Force
            }
            
            Write-Host "Touchpad Settings backed up successfully to: $backupPath" -ForegroundColor Green
            return $true
        }
        return $false
    } catch {
        $errorRecord = $_
        $errorMessage = @(
            "Failed to backup [Feature]"
            "Error Message: $($errorRecord.Exception.Message)"
            "Error Type: $($errorRecord.Exception.GetType().FullName)"
            "Script Line Number: $($errorRecord.InvocationInfo.ScriptLineNumber)"
            "Script Name: $($errorRecord.InvocationInfo.ScriptName)"
            "Statement: $($errorRecord.InvocationInfo.Line.Trim())"
            if ($errorRecord.Exception.StackTrace) { "Stack Trace: $($errorRecord.Exception.StackTrace)" }
            if ($errorRecord.Exception.InnerException) { "Inner Exception: $($errorRecord.Exception.InnerException.Message)" }
        ) -join "`n"
        
        Write-Host $errorMessage -ForegroundColor Red
        return $false
    }
}

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Backup-TouchpadSettings -BackupRootPath $BackupRootPath
} 