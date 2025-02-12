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

function Backup-TouchscreenSettings {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath
    )
    
    try {
        Write-Host "Backing up Touchscreen Settings..." -ForegroundColor Blue
        $backupPath = Initialize-BackupDirectory -Path "Touchscreen" -BackupType "Touchscreen Settings" -BackupRootPath $BackupRootPath
        
        if ($backupPath) {
            # Export touchscreen registry settings
            $regPaths = @(
                # Windows Touch settings
                "HKCU\Software\Microsoft\Windows\CurrentVersion\TouchSettings",
                "HKLM\SOFTWARE\Microsoft\TouchPrediction",
                
                # Tablet PC settings
                "HKCU\Software\Microsoft\Windows\CurrentVersion\TabletPC",
                "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\TabletPC",
                
                # Pen and Touch settings
                "HKCU\Software\Microsoft\Windows\CurrentVersion\PenWorkspace",
                "HKLM\SYSTEM\CurrentControlSet\Services\TabletInputService",
                
                # Device-specific settings
                "HKLM\SYSTEM\CurrentControlSet\Services\HidIr",
                "HKLM\SYSTEM\CurrentControlSet\Services\WacomPen"
            )

            foreach ($regPath in $regPaths) {
                $regFile = "$backupPath\$($regPath.Split('\')[-1]).reg"
                reg export $regPath $regFile /y 2>$null
            }

            # Get all touchscreen devices
            $touchscreenDevices = Get-PnpDevice | Where-Object { 
                ($_.Class -eq "HIDClass" -or $_.Class -eq "TouchScreen") -and 
                ($_.FriendlyName -match "touch|screen|tablet|pen" -or
                 $_.Manufacturer -match "wacom|n-trig|elan")
            } | Select-Object -Property @(
                'InstanceId',
                'FriendlyName',
                'Manufacturer',
                'Status',
                @{Name='IsEnabled'; Expression={$_.Status -eq 'OK'}}
            )
            
            if ($touchscreenDevices) {
                $touchscreenDevices | ConvertTo-Json | Out-File "$backupPath\touchscreen_devices.json" -Force
            }
            
            Write-Host "Touchscreen Settings backed up successfully to: $backupPath" -ForegroundColor Green
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
    Backup-TouchscreenSettings -BackupRootPath $BackupRootPath
} 