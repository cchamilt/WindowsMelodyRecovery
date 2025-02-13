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

function Backup-OneNoteSettings {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath
    )
    
    try {
        Write-Host "Backing up OneNote Settings..." -ForegroundColor Blue
        $backupPath = Initialize-BackupDirectory -Path "OneNote" -BackupType "OneNote Settings" -BackupRootPath $BackupRootPath
        
        if ($backupPath) {
            # OneNote config locations
            $oneNoteConfigs = @{
                # OneNote 2016 settings
                "Settings2016" = "$env:APPDATA\Microsoft\OneNote\16.0"
                # OneNote for Windows 10/11 settings
                "SettingsUWP" = "$env:LOCALAPPDATA\Packages\Microsoft.Office.OneNote_8wekyb3d8bbwe\LocalState"
                # Quick Access locations
                "QuickAccess" = "$env:APPDATA\Microsoft\Windows\Recent\OneNote.lnk"
                # Recent files list
                "RecentFiles" = "$env:APPDATA\Microsoft\Office\Recent"
                # Templates
                "Templates" = "$env:APPDATA\Microsoft\Templates"
            }

            # Export OneNote registry settings
            $regPaths = @(
                # OneNote 2016 registry settings
                "HKCU\Software\Microsoft\Office\16.0\OneNote",
                # OneNote UWP settings
                "HKCU\Software\Microsoft\Office\16.0\Common\OneNote",
                # File associations
                "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.one",
                # OneNote 2016 registry settings
                "HKLM\SOFTWARE\Microsoft\Office\16.0\OneNote",
                # OneNote UWP settings
                "HKCU\Software\Microsoft\Office\16.0\Common\OneNote",
                # File associations
                "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.one",
                "HKCU\Software\Microsoft\OneNote",
                "HKLM\SOFTWARE\Microsoft\OneNote"
            )

            # Create registry backup directory
            $registryPath = Join-Path $backupPath "Registry"
            New-Item -ItemType Directory -Force -Path $registryPath | Out-Null

            $registryBackupExists = $false
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
                        if ($LASTEXITCODE -eq 0) {
                            $registryBackupExists = $true
                            Write-Host "Registry key exported: $regPath" -ForegroundColor Green
                        } else {
                            Write-Host "Warning: Could not export registry key: $regPath" -ForegroundColor Yellow
                        }
                    } catch {
                        Write-Host "Warning: Failed to export registry key: $regPath" -ForegroundColor Yellow
                    }
                } else {
                    Write-Host "Registry key not found: $regPath" -ForegroundColor Yellow
                }
            }

            # Backup OneNote configuration files
            $configPaths = @{
                "AppData" = "$env:LOCALAPPDATA\Microsoft\OneNote"
                "Templates" = "$env:APPDATA\Microsoft\Templates"
                "Settings" = "$env:APPDATA\Microsoft\OneNote"
            }

            $configBackupExists = $false
            foreach ($config in $configPaths.GetEnumerator()) {
                if (Test-Path $config.Value) {
                    $destPath = Join-Path $backupPath $config.Key
                    New-Item -ItemType Directory -Path $destPath -Force | Out-Null
                    Copy-Item -Path "$($config.Value)\*" -Destination $destPath -Recurse -Force
                    $configBackupExists = $true
                    Write-Host "Configuration backed up: $($config.Key)" -ForegroundColor Green
                }
            }

            # Export notebook list and locations
            $notebooks = @()
            if (Test-Path "$env:APPDATA\Microsoft\OneNote\16.0\NotebookList.xml") {
                $notebooks += Get-Content "$env:APPDATA\Microsoft\OneNote\16.0\NotebookList.xml"
                Write-Host "Notebook list backed up successfully" -ForegroundColor Green
            }
            if ($notebooks.Count -gt 0) {
                $notebooks | Out-File (Join-Path $backupPath "notebook_locations.txt")
            }

            Write-Host "`nOneNote Settings Backup Summary:" -ForegroundColor Green
            if ($registryBackupExists) {
                Write-Host "Registry Settings: $(Test-Path $registryPath)" -ForegroundColor Yellow
            } else {
                Write-Host "Registry Settings: No registry keys found to backup" -ForegroundColor Yellow
            }
            if ($configBackupExists) {
                foreach ($configName in $configPaths.Keys) {
                    $configPath = Join-Path $backupPath $configName
                    Write-Host ("$configName" + ": $(Test-Path $configPath)") -ForegroundColor Yellow
                }
            } else {
                Write-Host "Configuration: No configuration files found to backup" -ForegroundColor Yellow
            }
            Write-Host "Notebook Locations: $(Test-Path (Join-Path $backupPath "notebook_locations.txt"))" -ForegroundColor Yellow
            
            Write-Host "OneNote Settings backed up successfully to: $backupPath" -ForegroundColor Green
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
    Backup-OneNoteSettings -BackupRootPath $BackupRootPath
} 