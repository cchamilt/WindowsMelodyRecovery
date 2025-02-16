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
            # Terminal config locations
            $terminalConfigs = @{
                # Windows Terminal settings
                "Settings" = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState"
                # Windows Terminal Preview settings
                "SettingsPreview" = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState"
                # Terminal profiles
                "Profiles" = "$env:LOCALAPPDATA\Microsoft\Windows Terminal"
                # Terminal fragments
                "Fragments" = "$env:LOCALAPPDATA\Microsoft\Windows Terminal\Fragments"
                # Terminal themes
                "Themes" = "$env:LOCALAPPDATA\Microsoft\Windows Terminal\Themes"
                # Terminal icons
                "Icons" = "$env:LOCALAPPDATA\Microsoft\Windows Terminal\Icons"
            }

            # Restore Terminal settings
            Write-Host "Checking Windows Terminal installation..." -ForegroundColor Yellow
            $terminalApp = Get-AppxPackage -Name "Microsoft.WindowsTerminal" -ErrorAction SilentlyContinue
            if (!$terminalApp) {
                Write-Host "Installing Windows Terminal..." -ForegroundColor Yellow
                winget install --id Microsoft.WindowsTerminal -e
            }

            # Restore config files
            foreach ($config in $terminalConfigs.GetEnumerator()) {
                $backupItem = Join-Path $backupPath $config.Key
                if (Test-Path $backupItem) {
                    Write-Host "Restoring $($config.Key) settings..." -ForegroundColor Yellow
                    # Create parent directory if it doesn't exist
                    $parentDir = Split-Path $config.Value -Parent
                    if (!(Test-Path $parentDir)) {
                        New-Item -ItemType Directory -Force -Path $parentDir | Out-Null
                    }

                    if ((Get-Item $backupItem) -is [System.IO.DirectoryInfo]) {
                        # Skip temporary files during restore
                        $excludeFilter = @("*.tmp", "~*.*", "*.bak", "*.old", "state.json")
                        Copy-Item $backupItem $config.Value -Recurse -Force -Exclude $excludeFilter
                    } else {
                        Copy-Item $backupItem $config.Value -Force
                    }
                    Write-Host "Restored configuration: $($config.Key)" -ForegroundColor Green
                }
            }

            # Restore default terminal app setting
            $defaultTerminalFile = Join-Path $backupPath "default_terminal.json"
            if (Test-Path $defaultTerminalFile) {
                $defaultTerminal = Get-Content $defaultTerminalFile | ConvertFrom-Json
                if ($defaultTerminal.DefaultTerminal) {
                    Set-ItemProperty -Path "HKCU:\Console\%%Startup" -Name "DelegationTerminal" `
                        -Value $defaultTerminal.DefaultTerminal
                }
            }

            # Kill any running terminal processes to apply changes
            Get-Process -Name "WindowsTerminal*" -ErrorAction SilentlyContinue | Stop-Process -Force
            
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