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

function Restore-StartMenuSettings {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath
    )
    
    try {
        Write-Host "Restoring Start Menu Settings..." -ForegroundColor Blue
        $backupPath = Test-BackupPath -Path "StartMenu" -BackupType "Start Menu Settings"
        
        if ($backupPath) {
            # StartMenu config locations
            $startMenuConfigs = @{
                # Start menu layout
                "Layout" = "HKCU:\Software\Microsoft\Windows\CurrentVersion\CloudStore\Store\Cache\DefaultAccount"
                # Start menu settings
                "Settings" = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
                # Taskbar settings
                "Taskbar" = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband"
                # Jump lists
                "JumpLists" = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\JumpLists"
                # Recent items
                "Recent" = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RecentDocs"
                # Pinned items
                "PinnedItems" = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband\Favorites"
                # Start menu folders
                "Folders" = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartPage"
                # Live tiles
                "LiveTiles" = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartLayout"
            }

            # Restore start menu settings
            Write-Host "Checking StartMenu components..." -ForegroundColor Yellow
            $startMenuServices = @(
                "ShellExperienceHost", # Windows Shell Experience Host
                "StartMenuExperienceHost", # Start Menu Experience Host
                "TileDataModel"       # Tile Data Model Server
            )
            
            foreach ($service in $startMenuServices) {
                if ((Get-Service -Name $service -ErrorAction SilentlyContinue).Status -ne "Running") {
                    Start-Service -Name $service
                }
            }

            # Restore registry settings
            foreach ($config in $startMenuConfigs.GetEnumerator()) {
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

            # Restore start menu layout
            $layoutFile = Join-Path $backupPath "start_layout.xml"
            if (Test-Path $layoutFile) {
                Import-StartLayout -LayoutPath $layoutFile -MountPath $env:SystemDrive\
            }

            # Restore pinned items
            $pinnedItemsFile = Join-Path $backupPath "pinned_items.json"
            if (Test-Path $pinnedItemsFile) {
                $pinnedItems = Get-Content $pinnedItemsFile | ConvertFrom-Json
                foreach ($item in $pinnedItems) {
                    if (Test-Path $item.Path) {
                        $shell = New-Object -ComObject Shell.Application
                        $folder = $shell.Namespace([System.IO.Path]::GetDirectoryName($item.Path))
                        $file = $folder.ParseName([System.IO.Path]::GetFileName($item.Path))
                        $verb = $file.Verbs() | Where-Object { $_.Name -eq "Pin to Start" }
                        if ($verb) { $verb.DoIt() }
                    }
                }
            }

            # Restore taskbar settings
            $taskbarFile = "$backupPath\taskbar_settings.json"
            if (Test-Path $taskbarFile) {
                $taskbarSettings = Get-Content $taskbarFile | ConvertFrom-Json
                
                # Restore taskbar position and auto-hide
                if ($taskbarSettings.Position) {
                    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3" `
                        -Name Settings -Value $taskbarSettings.Position.Settings
                }
                
                if ($taskbarSettings.AutoHide) {
                    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3" `
                        -Name Settings -Value $taskbarSettings.AutoHide.Settings
                }

                # Restore taskbar toolbars
                if ($taskbarSettings.Toolbars) {
                    foreach ($toolbar in $taskbarSettings.Toolbars) {
                        New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Streams\Desktop" `
                            -Name $toolbar.PSChildName -Value $toolbar.Property -Force | Out-Null
                    }
                }
            }

            # Restore jump lists
            $jumpListBackupPath = Join-Path $backupPath "JumpLists"
            if (Test-Path $jumpListBackupPath) {
                $jumpListDestPath = "$env:APPDATA\Microsoft\Windows\Recent\AutomaticDestinations"
                if (!(Test-Path $jumpListDestPath)) {
                    New-Item -ItemType Directory -Path $jumpListDestPath -Force | Out-Null
                }
                Copy-Item -Path "$jumpListBackupPath\*" -Destination $jumpListDestPath -Force
            }

            # Restart Explorer to apply changes
            Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
            Start-Process explorer
            
            Write-Host "Start Menu Settings restored successfully from: $backupPath" -ForegroundColor Green
            return $true
        }
        return $false
    } catch {
        Write-Host "Failed to restore Start Menu Settings: $_" -ForegroundColor Red
        return $false
    }
}

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Restore-StartMenuSettings -BackupRootPath $BackupRootPath
} 