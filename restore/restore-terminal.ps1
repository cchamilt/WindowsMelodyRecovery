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

function Restore-TerminalSettings {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath
    )
    
    try {
        Write-Host "Restoring Terminal Settings..." -ForegroundColor Blue
        $backupPath = Test-BackupPath -Path "Terminal" -BackupType "Terminal Settings"
        
        if ($backupPath) {
            # Windows Terminal settings
            $terminalSettingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState"
            $terminalBackupPath = "$backupPath\terminal-settings.json"
            if (Test-Path $terminalBackupPath) {
                if (!(Test-Path $terminalSettingsPath)) {
                    New-Item -ItemType Directory -Path $terminalSettingsPath -Force | Out-Null
                }
                Copy-Item -Path $terminalBackupPath -Destination "$terminalSettingsPath\settings.json" -Force
            }

            # Windows Terminal Preview settings
            $previewSettingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState"
            $previewBackupPath = "$backupPath\terminal-preview-settings.json"
            if (Test-Path $previewBackupPath) {
                if (!(Test-Path $previewSettingsPath)) {
                    New-Item -ItemType Directory -Path $previewSettingsPath -Force | Out-Null
                }
                Copy-Item -Path $previewBackupPath -Destination "$previewSettingsPath\settings.json" -Force
            }
            
            Write-Host "Terminal Settings restored successfully from: $backupPath" -ForegroundColor Green
            return $true
        }
        return $false
    } catch {
        Write-Host "Failed to restore Terminal Settings: $_" -ForegroundColor Red
        return $false
    }
}

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Restore-TerminalSettings -BackupRootPath $BackupRootPath
} 