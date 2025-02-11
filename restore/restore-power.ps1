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

function Restore-PowerSettings {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath
    )
    
    try {
        Write-Host "Restoring Power Settings..." -ForegroundColor Blue
        $backupPath = Test-BackupPath -Path "Power" -BackupType "Power Settings"
        
        if ($backupPath) {
            # Import registry settings first
            $regFiles = Get-ChildItem -Path $backupPath -Filter "*.reg"
            foreach ($regFile in $regFiles) {
                reg import $regFile.FullName | Out-Null
            }

            # Import power schemes
            $schemesFile = "$backupPath\power_schemes.json"
            if (Test-Path $schemesFile) {
                $powerSchemes = Get-Content $schemesFile | ConvertFrom-Json

                # Import each power scheme
                foreach ($scheme in $powerSchemes) {
                    $schemeFile = "$backupPath\$($scheme.GUID).pow"
                    if (Test-Path $schemeFile) {
                        # Delete existing scheme if it exists
                        powercfg /delete $scheme.GUID 2>$null

                        # Import the scheme
                        powercfg /import $schemeFile
                        
                        # Rename if needed (import might use a different GUID)
                        $importedGuid = powercfg /list | Select-String $scheme.Name | ForEach-Object {
                            if ($_ -match "Power Scheme GUID: (.*?) \(") {
                                $matches[1]
                            }
                        }
                        if ($importedGuid) {
                            powercfg /changename $importedGuid $scheme.Name $scheme.Name
                        }

                        # Set as active if it was active in backup
                        if ($scheme.IsActive) {
                            Write-Host "Setting active power scheme: $($scheme.Name)" -ForegroundColor Yellow
                            powercfg /setactive $importedGuid
                        }
                    }
                }
            }

            # Restore button actions
            $buttonFile = "$backupPath\button_settings.json"
            if (Test-Path $buttonFile) {
                $buttonSettings = Get-Content $buttonFile | ConvertFrom-Json
                
                # Apply button settings using powercfg
                foreach ($setting in $buttonSettings.PSObject.Properties) {
                    $action = $setting.Value
                    if ($action) {
                        switch ($setting.Name) {
                            "PowerButton" { powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS PBUTTONACTION $action.Value }
                            "SleepButton" { powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS SBUTTONACTION $action.Value }
                            "LidClose" { powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION $action.Value }
                        }
                    }
                }
            }
            
            Write-Host "Power Settings restored successfully from: $backupPath" -ForegroundColor Green
            return $true
        }
        return $false
    } catch {
        Write-Host "Failed to restore Power Settings: $_" -ForegroundColor Red
        return $false
    }
}

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Restore-PowerSettings -BackupRootPath $BackupRootPath
} 