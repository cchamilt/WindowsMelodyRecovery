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
            # Import registry settings first
            $regFiles = Get-ChildItem -Path $backupPath -Filter "*.reg"
            foreach ($regFile in $regFiles) {
                reg import $regFile.FullName | Out-Null
            }

            # Import Start Menu layout
            $layoutFile = "$backupPath\startlayout.xml"
            if (Test-Path $layoutFile) {
                Import-StartLayout -LayoutPath $layoutFile -MountPath $env:SystemDrive\
            }

            # Restore Start Menu folders
            $startMenuPaths = @{
                "User" = "$env:APPDATA\Microsoft\Windows\Start Menu"
                "AllUsers" = "$env:ProgramData\Microsoft\Windows\Start Menu"
            }

            foreach ($startMenu in $startMenuPaths.GetEnumerator()) {
                $sourcePath = Join-Path $backupPath $startMenu.Key
                if (Test-Path $sourcePath) {
                    if (!(Test-Path $startMenu.Value)) {
                        New-Item -ItemType Directory -Path $startMenu.Value -Force | Out-Null
                    }
                    Copy-Item -Path "$sourcePath\*" -Destination $startMenu.Value -Recurse -Force
                }
            }

            # Restore pinned items
            $pinnedItemsFile = "$backupPath\pinned_items.json"
            if (Test-Path $pinnedItemsFile) {
                $pinnedItems = Get-Content $pinnedItemsFile | ConvertFrom-Json
                $shell = New-Object -Com Shell.Application
                $pinnedFolder = $shell.NameSpace("shell:::{4234d49b-0245-4df3-b780-3893943456e1}")
                
                foreach ($item in $pinnedItems) {
                    if (Test-Path $item.Path) {
                        $pinnedFolder.Items() | Where-Object { $_.Path -eq $item.Path } | ForEach-Object {
                            $_.InvokeVerb("pintostartscreen")
                        }
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