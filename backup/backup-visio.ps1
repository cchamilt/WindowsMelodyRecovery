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

function Backup-VisioSettings {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath
    )
    
    try {
        Write-Host "Backing up Visio Settings..." -ForegroundColor Blue
        $backupPath = Initialize-BackupDirectory -Path "Visio" -BackupType "Visio Settings" -BackupRootPath $BackupRootPath
        
        if ($backupPath) {
            # Visio config locations
            $visioConfigs = @{
                # Main settings
                "Settings" = "$env:APPDATA\Microsoft\Visio"
                # Custom templates and stencils
                "Templates" = "$env:APPDATA\Microsoft\Templates"
                # Quick Access and recent items
                "RecentFiles" = "$env:APPDATA\Microsoft\Office\Recent"
                # Custom stencils
                "Stencils" = "$env:MYDOCUMENTS\My Shapes"
                # Custom add-ins
                "AddIns" = "$env:APPDATA\Microsoft\Visio\AddOns"
                # Custom toolbars and ribbons
                "Ribbons" = "$env:APPDATA\Microsoft\Office\16.0\Visio\Ribbons"
                # Custom themes
                "Themes" = "$env:APPDATA\Microsoft\Visio\Themes"
                # Custom workspace settings
                "Workspace" = "$env:APPDATA\Microsoft\Visio\Workspace"
                # Custom macros
                "Macros" = "$env:APPDATA\Microsoft\Visio\Macros"
            }

            # Registry paths to backup
            $regPaths = @(
                # Visio main settings
                "HKCU\Software\Microsoft\Office\16.0\Visio",
                # Common settings
                "HKCU\Software\Microsoft\Office\16.0\Common",
                # File MRU and settings
                "HKCU\Software\Microsoft\Office\16.0\Visio\File MRU",
                # Place MRU
                "HKCU\Software\Microsoft\Office\16.0\Visio\Place MRU",
                # User preferences
                "HKCU\Software\Microsoft\Office\16.0\Visio\Options",
                # Security settings
                "HKCU\Software\Microsoft\Office\16.0\Visio\Security",
                # Add-ins settings
                "HKCU\Software\Microsoft\Office\16.0\Visio\Add-in Manager",
                # Drawing settings
                "HKCU\Software\Microsoft\Office\16.0\Visio\Drawing"
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
            foreach ($config in $visioConfigs.GetEnumerator()) {
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

            Write-Host "`nVisio Settings Backup Summary:" -ForegroundColor Green
            Write-Host "Registry Settings: $(Test-Path $registryPath)" -ForegroundColor Yellow
            foreach ($configName in $visioConfigs.Keys) {
                $configPath = Join-Path $backupPath $configName
                Write-Host ("$configName" + ": $(Test-Path $configPath)") -ForegroundColor Yellow
            }
            
            Write-Host "Visio Settings backed up successfully to: $backupPath" -ForegroundColor Green
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
    Backup-VisioSettings -BackupRootPath $BackupRootPath
} 