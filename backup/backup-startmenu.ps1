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

function Backup-StartMenuSettings {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath
    )
    
    try {
        Write-Host "Backing up Start Menu Settings..." -ForegroundColor Blue
        $backupPath = Initialize-BackupDirectory -Path "StartMenu" -BackupType "Start Menu Settings" -BackupRootPath $BackupRootPath
        
        if ($backupPath) {
            # Export Start Menu registry settings
            $regPaths = @(
                # Start Menu layout and customization
                "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced",
                "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced",
                "HKCU\Software\Microsoft\Windows\CurrentVersion\Start",
                "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartPage",
                
                # Taskbar settings
                "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband",
                "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\TaskbarItemsCache",
                
                # Jump Lists
                "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\JumpLists",
                
                # Search settings
                "HKCU\Software\Microsoft\Windows\CurrentVersion\Search",
                "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Search"
            )

            foreach ($regPath in $regPaths) {
                $regFile = "$backupPath\$($regPath.Split('\')[-1]).reg"
                reg export $regPath $regFile /y 2>$null
            }

            # Export Start Menu layout
            Export-StartLayout -Path "$backupPath\startlayout.xml"

            # Backup Start Menu folders
            $startMenuPaths = @{
                "User" = "$env:APPDATA\Microsoft\Windows\Start Menu"
                "AllUsers" = "$env:ProgramData\Microsoft\Windows\Start Menu"
            }

            foreach ($startMenu in $startMenuPaths.GetEnumerator()) {
                if (Test-Path $startMenu.Value) {
                    $destPath = Join-Path $backupPath $startMenu.Key
                    New-Item -ItemType Directory -Path $destPath -Force | Out-Null
                    Copy-Item -Path "$($startMenu.Value)\*" -Destination $destPath -Recurse -Force
                }
            }

            # Export pinned items
            $pinnedApps = (New-Object -Com Shell.Application).NameSpace("shell:::{4234d49b-0245-4df3-b780-3893943456e1}").Items()
            $pinnedItems = $pinnedApps | Select-Object Name, Path
            $pinnedItems | ConvertTo-Json | Out-File "$backupPath\pinned_items.json" -Force

            # Export taskbar settings
            $taskbarSettings = @{
                Position = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3" -ErrorAction SilentlyContinue
                AutoHide = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3" -Name Settings -ErrorAction SilentlyContinue
                Toolbars = Get-ChildItem "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Streams\Desktop" -ErrorAction SilentlyContinue
            }
            $taskbarSettings | ConvertTo-Json -Depth 10 | Out-File "$backupPath\taskbar_settings.json" -Force

            # Export jump list customizations
            $jumpListPath = "$env:APPDATA\Microsoft\Windows\Recent\AutomaticDestinations"
            if (Test-Path $jumpListPath) {
                $jumpListBackupPath = Join-Path $backupPath "JumpLists"
                New-Item -ItemType Directory -Path $jumpListBackupPath -Force | Out-Null
                Copy-Item -Path "$jumpListPath\*" -Destination $jumpListBackupPath -Force
            }
            
            Write-Host "Start Menu Settings backed up successfully to: $backupPath" -ForegroundColor Green
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
    Backup-StartMenuSettings -BackupRootPath $BackupRootPath
} 