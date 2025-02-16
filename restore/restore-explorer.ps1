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
            # Explorer config locations
            $explorerConfigs = @{
                # File Explorer settings
                "Settings" = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer"
                # Folder options
                "FolderOptions" = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
                # Navigation pane settings
                "Navigation" = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
                # Quick access settings
                "QuickAccess" = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons"
                # File associations
                "FileAssoc" = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts"
                # Desktop icons
                "DesktopIcons" = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel"
                # Shell folders
                "ShellFolders" = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders"
                # User shell folders
                "UserShellFolders" = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders"
            }

            # Restore Explorer settings
            Write-Host "Checking Explorer components..." -ForegroundColor Yellow
            
            # Stop Explorer process to allow settings changes
            Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2

            # Restore registry settings
            foreach ($config in $explorerConfigs.GetEnumerator()) {
                $backupItem = Join-Path $backupPath $config.Key
                if (Test-Path $backupItem) {
                    Write-Host "Restoring $($config.Key) settings..." -ForegroundColor Yellow
                    if ((Get-Item $backupItem) -is [System.IO.DirectoryInfo]) {
                        # Skip temporary files during restore
                        $excludeFilter = @("*.tmp", "~*.*", "*.bak", "*.old")
                        Copy-Item $backupItem $config.Value -Recurse -Force -Exclude $excludeFilter
                    } else {
                        Copy-Item $backupItem $config.Value -Force
                    }
                    Write-Host "Restored configuration: $($config.Key)" -ForegroundColor Green
                }
            }

            # Restore Quick Access pins
            $quickAccessFile = Join-Path $backupPath "quick_access.json"
            if (Test-Path $quickAccessFile) {
                $quickAccessItems = Get-Content $quickAccessFile | ConvertFrom-Json
                foreach ($item in $quickAccessItems) {
                    if (Test-Path $item.Path) {
                        $shell = New-Object -ComObject Shell.Application
                        $folder = $shell.Namespace($item.Path)
                        $folder.Self.InvokeVerb("pintohome")
                    }
                }
            }

            # Restore custom folder views
            $folderViewsFile = Join-Path $backupPath "folder_views.json"
            if (Test-Path $folderViewsFile) {
                $folderViews = Get-Content $folderViewsFile | ConvertFrom-Json
                foreach ($view in $folderViews) {
                    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Streams\Defaults" `
                        -Name $view.ID -Value $view.Settings -Type Binary
                }
            }

            # Start Explorer process
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