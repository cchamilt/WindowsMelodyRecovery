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

function Backup-ExplorerSettings {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath
    )
    
    try {
        Write-Host "Backing up Explorer Settings..." -ForegroundColor Blue
        $backupPath = Initialize-BackupDirectory -Path "Explorer" -BackupType "Explorer Settings" -BackupRootPath $BackupRootPath
        
        if ($backupPath) {
            # Export Explorer view settings
            $explorerKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer"
            $advancedKey = "$explorerKey\Advanced"
            
            # Create registry backup
            $regFile = "$backupPath\explorer-settings.reg"
            reg export "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer" $regFile /y | Out-Null

            # Export Quick Access locations
            $quickAccess = @{
                Pinned = @()
                Recent = @()
            }

            # Get Quick Access shell application
            $shell = New-Object -ComObject Shell.Application
            $quickAccessShell = $shell.Namespace("shell:::{679f85cb-0220-4080-b29b-5540cc05aab6}")

            # Export pinned folders
            foreach ($folder in $quickAccessShell.Items()) {
                if ($folder.IsPinnedToNameSpaceTree) {
                    $quickAccess.Pinned += $folder.Path
                }
            }

            # Export Quick Access settings to JSON
            $quickAccess | ConvertTo-Json | Out-File "$backupPath\quick-access.json" -Force
            
            Write-Host "Explorer Settings backed up successfully to: $backupPath" -ForegroundColor Green
            return $true
        }
        return $false
    } catch {
        Write-Host "Failed to backup Explorer Settings: $_" -ForegroundColor Red
        return $false
    }
}

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Backup-ExplorerSettings -BackupRootPath $BackupRootPath
} 