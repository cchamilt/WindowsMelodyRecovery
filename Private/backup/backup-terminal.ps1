[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$BackupRootPath = $null,
    
    [Parameter(Mandatory=$false)]
    [string]$MachineBackupPath = $null,
    
    [Parameter(Mandatory=$false)]
    [string]$SharedBackupPath = $null
)

# Load environment if not provided
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$parentPath = Split-Path $scriptPath -Parent
$loadEnvPath = Join-Path $parentPath "load-environment.ps1"
$backupUtilsPath = Join-Path $parentPath "scripts\backup-utilities.ps1"

# Source the load-environment script
if (Test-Path $loadEnvPath) {
    . $loadEnvPath
} else {
    Write-Host "Cannot find load-environment.ps1 at: $loadEnvPath" -ForegroundColor Red
    exit 1
}

# Source the backup utilities script that contains Initialize-BackupDirectory
if (Test-Path $backupUtilsPath) {
    . $backupUtilsPath
} else {
    Write-Host "Cannot find backup-utilities.ps1 at: $backupUtilsPath" -ForegroundColor Red
    
    # Define Initialize-BackupDirectory function if the script is not found
    function Initialize-BackupDirectory {
        param (
            [Parameter(Mandatory=$true)]
            [string]$Path,
            
            [Parameter(Mandatory=$true)]
            [string]$BackupType,
            
            [Parameter(Mandatory=$true)]
            [string]$BackupRootPath
        )
        
        # Create machine-specific backup directory if it doesn't exist
        $backupPath = Join-Path $BackupRootPath $Path
        if (!(Test-Path -Path $backupPath)) {
            try {
                New-Item -ItemType Directory -Path $backupPath -Force | Out-Null
                Write-Host "Created backup directory for $BackupType at: $backupPath" -ForegroundColor Green
            } catch {
                Write-Host "Failed to create backup directory for $BackupType : $_" -ForegroundColor Red
                return $null
            }
        }
        
        return $backupPath
    }
}

# Set a default BackupRootPath if not provided
if (!$BackupRootPath) {
    # Try to read from the environment or use a default
    $BackupRootPath = "$env:USERPROFILE\OneDrive - Fyber Labs\WindowsMissingRecovery\$env:COMPUTERNAME"
    Write-Host "Using default backup path: $BackupRootPath" -ForegroundColor Yellow
}

function Backup-TerminalSettings {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath
    )
    
    try {
        Write-Host "Backing up Terminal Settings..." -ForegroundColor Blue
        $backupPath = Initialize-BackupDirectory -Path "Terminal" -BackupType "Terminal Settings" -BackupRootPath $BackupRootPath
        
        if ($backupPath) {
            # Windows Terminal settings
            $terminalSettingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
            if (Test-Path $terminalSettingsPath) {
                Copy-Item -Path $terminalSettingsPath -Destination "$backupPath\terminal-settings.json" -Force
            }

            # Windows Terminal Preview settings
            $previewSettingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json"
            if (Test-Path $previewSettingsPath) {
                Copy-Item -Path $previewSettingsPath -Destination "$backupPath\terminal-preview-settings.json" -Force
            }
            
            Write-Host "Terminal Settings backed up successfully to: $backupPath" -ForegroundColor Green
            return $true
        }
        return $false
    } catch {
        $errorRecord = $_
        $errorMessage = @(
            "Failed to backup Terminal Settings"
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
    Backup-TerminalSettings -BackupRootPath $BackupRootPath
} 