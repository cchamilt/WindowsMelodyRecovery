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

function Backup-ExcelSettings {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath
    )
    
    try {
        Write-Host "Backing up Excel Settings..." -ForegroundColor Blue
        $backupPath = Initialize-BackupDirectory -Path "Excel" -BackupType "Excel Settings" -BackupRootPath $BackupRootPath
        
        if ($backupPath) {
            # Excel config locations
            $excelConfigs = @{
                # Main settings
                "Settings" = "$env:APPDATA\Microsoft\Excel"
                # Custom templates
                "Templates" = "$env:APPDATA\Microsoft\Templates"
                # Quick Access and recent items
                "RecentFiles" = "$env:APPDATA\Microsoft\Office\Recent"
                # Custom dictionaries
                "Dictionaries" = "$env:APPDATA\Microsoft\UProof"
                # AutoCorrect entries
                "AutoCorrect" = "$env:APPDATA\Microsoft\Office"
                # Custom add-ins
                "AddIns" = "$env:APPDATA\Microsoft\AddIns"
                # Custom toolbars and ribbons
                "Ribbons" = "$env:APPDATA\Microsoft\Office\16.0\Excel\Ribbons"
                # Custom views and workspaces
                "Views" = "$env:APPDATA\Microsoft\Excel\Views"
                # Personal macro workbook
                "Personal" = "$env:APPDATA\Microsoft\Excel\XLSTART"
            }

            # Registry paths to backup
            $regPaths = @(
                # Excel main settings
                "HKCU\Software\Microsoft\Office\16.0\Excel",
                # Common settings
                "HKCU\Software\Microsoft\Office\16.0\Common",
                # File MRU and settings
                "HKCU\Software\Microsoft\Office\16.0\Excel\File MRU",
                # Place MRU
                "HKCU\Software\Microsoft\Office\16.0\Excel\Place MRU",
                # User preferences
                "HKCU\Software\Microsoft\Office\16.0\Excel\Options",
                # Security settings
                "HKCU\Software\Microsoft\Office\16.0\Excel\Security",
                # Add-ins settings
                "HKCU\Software\Microsoft\Office\16.0\Excel\Add-in Manager"
            )

            # Create registry backup directory
            $registryPath = Join-Path $backupPath "Registry"
            New-Item -ItemType Directory -Force -Path $registryPath | Out-Null

            # Backup registry settings
            foreach ($regPath in $regPaths) {
                $regFile = Join-Path $registryPath "$($regPath.Split('\')[-1]).reg"
                reg export $regPath $regFile /y 2>$null
            }
            
            # Backup config files
            foreach ($config in $excelConfigs.GetEnumerator()) {
                if (Test-Path $config.Value) {
                    $targetPath = Join-Path $backupPath $config.Key
                    if ((Get-Item $config.Value) -is [System.IO.DirectoryInfo]) {
                        # Skip temporary files
                        $excludeFilter = @("*.tmp", "~$*.*", "*.lnk")
                        Copy-Item $config.Value $targetPath -Recurse -Force -Exclude $excludeFilter
                    } else {
                        Copy-Item $config.Value $targetPath -Force
                    }
                }
            }

            Write-Host "`nExcel Settings Backup Summary:" -ForegroundColor Green
            Write-Host "Registry Settings: $(Test-Path $registryPath)" -ForegroundColor Yellow
            foreach ($configName in $excelConfigs.Keys) {
                $configPath = Join-Path $backupPath $configName
                Write-Host ("$configName" + ": $(Test-Path $configPath)") -ForegroundColor Yellow
            }
            
            Write-Host "Excel Settings backed up successfully to: $backupPath" -ForegroundColor Green
            return $true
        }
        return $false
    } catch {
        Write-Host "Failed to backup Excel Settings: $_" -ForegroundColor Red
        return $false
    }
}

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Backup-ExcelSettings -BackupRootPath $BackupRootPath
} 