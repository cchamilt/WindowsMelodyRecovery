param(
    [Parameter(Mandatory=$true)]
    [string]$BackupRootPath
)

try {
    Write-Host "Backing up Power settings..." -ForegroundColor Blue
    $backupPath = Initialize-BackupDirectory -Path "Power" -BackupType "Power" -BackupRootPath $BackupRootPath
    
    if ($backupPath) {
        # Export current power scheme
        $activePlan = powercfg /getactivescheme
        if ($activePlan -match "Power Scheme GUID: (.+) \((.+)\)") {
            $planGuid = $matches[1]
            $planName = $matches[2]
            
            # Export the active power scheme
            $schemePath = "$backupPath\power_scheme.pow"
            powercfg /export $schemePath $planGuid
            
            # Save the plan name for reference
            $planName | Out-File "$backupPath\scheme_name.txt"
            
            Write-Host "Power settings backed up successfully to: $backupPath" -ForegroundColor Green
        } else {
            Write-Host "Failed to identify active power scheme" -ForegroundColor Red
        }
    }
} catch {
    Write-Host "Failed to backup Power settings: $_" -ForegroundColor Red
} 