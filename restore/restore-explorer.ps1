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

function Restore-ExplorerSettings {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath
    )
    
    try {
        Write-Host "Restoring Explorer Settings..." -ForegroundColor Blue
        $backupPath = Test-BackupPath -Path "Explorer" -BackupType "Explorer Settings"
        
        if ($backupPath) {
            # Import registry settings
            $regFile = "$backupPath\explorer-settings.reg"
            if (Test-Path $regFile) {
                reg import $regFile | Out-Null
            }

            # Restore Quick Access locations
            $quickAccessFile = "$backupPath\quick-access.json"
            if (Test-Path $quickAccessFile) {
                $quickAccess = Get-Content $quickAccessFile | ConvertFrom-Json

                # Get Quick Access shell application
                $shell = New-Object -ComObject Shell.Application
                $quickAccessShell = $shell.Namespace("shell:::{679f85cb-0220-4080-b29b-5540cc05aab6}")

                # Clear existing pinned items
                foreach ($folder in $quickAccessShell.Items()) {
                    if ($folder.IsPinnedToNameSpaceTree) {
                        $folder.InvokeVerb("unpinfromhome")
                    }
                }

                # Pin folders from backup
                foreach ($path in $quickAccess.Pinned) {
                    if (Test-Path $path) {
                        $folder = $shell.Namespace($path)
                        $folder.Self.InvokeVerb("pintohome")
                    }
                }
            }

            # Restart Explorer to apply changes
            Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
            Start-Process explorer
            
            Write-Host "Explorer Settings restored successfully from: $backupPath" -ForegroundColor Green
            return $true
        }
        return $false
    } catch {
        Write-Host "Failed to restore Explorer Settings: $_" -ForegroundColor Red
        return $false
    }
}

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Restore-ExplorerSettings -BackupRootPath $BackupRootPath
} 