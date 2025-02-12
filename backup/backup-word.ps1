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

function Backup-WordSettings {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath
    )
    
    try {
        Write-Host "Backing up Word Settings..." -ForegroundColor Blue
        $backupPath = Initialize-BackupDirectory -Path "Word" -BackupType "Word Settings" -BackupRootPath $BackupRootPath
        
        if ($backupPath) {
            # Word config locations
            $wordConfigs = @{
                # Main settings
                "Settings" = "$env:APPDATA\Microsoft\Word"
                # Custom templates
                "Templates" = "$env:APPDATA\Microsoft\Templates"
                # Quick Access and recent items
                "RecentFiles" = "$env:APPDATA\Microsoft\Office\Recent"
                # Custom dictionaries
                "Dictionaries" = "$env:APPDATA\Microsoft\UProof"
                # AutoCorrect entries
                "AutoCorrect" = "$env:APPDATA\Microsoft\Office"
                # Building Blocks
                "BuildingBlocks" = "$env:APPDATA\Microsoft\Document Building Blocks"
                # Custom styles
                "Styles" = "$env:APPDATA\Microsoft\QuickStyles"
                # Custom toolbars and ribbons
                "Ribbons" = "$env:APPDATA\Microsoft\Office\16.0\Word\Ribbons"
            }

            # Registry paths to backup
            $regPaths = @(
                # Word main settings
                "HKCU\Software\Microsoft\Office\16.0\Word",
                # Common settings
                "HKCU\Software\Microsoft\Office\16.0\Common",
                # File MRU and settings
                "HKCU\Software\Microsoft\Office\16.0\Word\File MRU",
                # Place MRU
                "HKCU\Software\Microsoft\Office\16.0\Word\Place MRU",
                # User preferences
                "HKCU\Software\Microsoft\Office\16.0\Word\Options",
                # Security settings
                "HKCU\Software\Microsoft\Office\16.0\Word\Security"
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
            foreach ($config in $wordConfigs.GetEnumerator()) {
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

            Write-Host "`nWord Settings Backup Summary:" -ForegroundColor Green
            Write-Host "Registry Settings: $(Test-Path $registryPath)" -ForegroundColor Yellow
            foreach ($configName in $wordConfigs.Keys) {
                $configPath = Join-Path $backupPath $configName
                Write-Host ("$configName" + ": $(Test-Path $configPath)") -ForegroundColor Yellow
            }
            
            Write-Host "Word Settings backed up successfully to: $backupPath" -ForegroundColor Green
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
    Backup-WordSettings -BackupRootPath $BackupRootPath
} 