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
            $configPaths = @{
                # Main settings
                "Settings" = "$env:APPDATA\Microsoft\Visio"
                # Custom templates and stencils
                "Templates" = "$env:APPDATA\Microsoft\Templates"
                # Quick Access and recent items
                "RecentFiles" = "$env:APPDATA\Microsoft\Office\Recent"
                # Custom dictionaries
                "Custom Dictionary" = "$env:APPDATA\Microsoft\UProof"
                # AutoCorrect entries
                "AutoCorrect" = "$env:APPDATA\Microsoft\Office"
                # Custom toolbars and ribbons
                "Ribbons" = "$env:APPDATA\Microsoft\Office\16.0\Visio\Ribbons"
                # Add-ins
                "AddIns" = "$env:APPDATA\Microsoft\Visio\AddOns"
                # Custom stencils
                "Stencils" = "$env:APPDATA\Microsoft\Visio\Stencils"
                # Custom templates
                "MyShapes" = "$env:APPDATA\Microsoft\Visio\My Shapes"
                # Custom themes
                "Themes" = "$env:APPDATA\Microsoft\Visio\Themes"
                # Custom workspace settings
                "Workspace" = "$env:APPDATA\Microsoft\Visio\Workspace"
                # Custom macros
                "Macros" = "$env:APPDATA\Microsoft\Visio\Macros"
            }

            # Export Visio registry settings
            $regPaths = @(
                # Visio main settings
                "HKCU\Software\Microsoft\Office\16.0\Visio",
                "HKLM\SOFTWARE\Microsoft\Office\16.0\Visio",
                # Common settings
                "HKCU\Software\Microsoft\Office\16.0\Common",
                # File MRU and settings
                "HKCU\Software\Microsoft\Office\16.0\Visio\File MRU",
                "HKCU\Software\Microsoft\Office\16.0\Visio\Place MRU",
                # User preferences
                "HKCU\Software\Microsoft\Office\16.0\Visio\Options",
                # Security settings
                "HKCU\Software\Microsoft\Office\16.0\Visio\Security",
                # Add-ins settings
                "HKCU\Software\Microsoft\Office\16.0\Visio\AddIns",
                # Drawing settings
                "HKCU\Software\Microsoft\Office\16.0\Visio\Drawing"
            )

            # Create registry backup directory
            $registryPath = Join-Path $backupPath "Registry"
            New-Item -ItemType Directory -Force -Path $registryPath | Out-Null

            foreach ($regPath in $regPaths) {
                # Check if registry key exists before trying to export
                $keyExists = $false
                if ($regPath -match '^HKCU\\') {
                    $keyExists = Test-Path "Registry::HKEY_CURRENT_USER\$($regPath.Substring(5))"
                } elseif ($regPath -match '^HKLM\\') {
                    $keyExists = Test-Path "Registry::HKEY_LOCAL_MACHINE\$($regPath.Substring(5))"
                }
                
                if ($keyExists) {
                    try {
                        $regFile = Join-Path $registryPath "$($regPath.Split('\')[-1]).reg"
                        $result = reg export $regPath $regFile /y 2>&1
                        if ($LASTEXITCODE -ne 0) {
                            Write-Host "Warning: Could not export registry key: $regPath" -ForegroundColor Yellow
                        }
                    } catch {
                        Write-Host "Warning: Failed to export registry key: $regPath" -ForegroundColor Yellow
                    }
                } else {
                    Write-Host "Registry key not found: $regPath" -ForegroundColor Yellow
                }
            }

            # Backup config files
            foreach ($config in $configPaths.GetEnumerator()) {
                if (Test-Path $config.Value) {
                    $targetPath = Join-Path $backupPath $config.Key
                    if ((Get-Item $config.Value) -is [System.IO.DirectoryInfo]) {
                        # Skip temporary files
                        $excludeFilter = @("*.tmp", "~*.*")
                        Copy-Item $config.Value $targetPath -Recurse -Force -Exclude $excludeFilter
                    } else {
                        Copy-Item $config.Value $targetPath -Force
                    }
                }
            }

            Write-Host "`nVisio Settings Backup Summary:" -ForegroundColor Green
            Write-Host "Registry Settings: $(Test-Path $registryPath)" -ForegroundColor Yellow
            foreach ($configName in $configPaths.Keys) {
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