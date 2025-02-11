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

function Restore-DefaultAppsSettings {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath
    )
    
    try {
        Write-Host "Restoring Default Apps Settings..." -ForegroundColor Blue
        $backupPath = Test-BackupPath -Path "DefaultApps" -BackupType "Default Apps Settings"
        
        if ($backupPath) {
            # Import registry settings first
            $regFiles = Get-ChildItem -Path $backupPath -Filter "*.reg"
            foreach ($regFile in $regFiles) {
                reg import $regFile.FullName | Out-Null
            }

            # Import default apps using DISM
            $defaultAppsXml = "$backupPath\defaultapps.xml"
            if (Test-Path $defaultAppsXml) {
                Write-Host "Importing default app associations..." -ForegroundColor Yellow
                Dism.exe /Online /Import-DefaultAppAssociations:$defaultAppsXml | Out-Null
            }

            # Restore user choice settings
            $userChoicesFile = "$backupPath\user_choices.json"
            if (Test-Path $userChoicesFile) {
                $userChoices = Get-Content $userChoicesFile | ConvertFrom-Json
                foreach ($choice in $userChoices.PSObject.Properties) {
                    $extPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$($choice.Name)\UserChoice"
                    if (!(Test-Path $extPath)) {
                        New-Item -Path $extPath -Force | Out-Null
                    }
                    Set-ItemProperty -Path $extPath -Name "ProgId" -Value $choice.Value.ProgId
                    Set-ItemProperty -Path $extPath -Name "Hash" -Value $choice.Value.Hash
                }
            }

            # Restore app capabilities
            $appCapabilitiesFile = "$backupPath\app_capabilities.json"
            if (Test-Path $appCapabilitiesFile) {
                $appCapabilities = Get-Content $appCapabilitiesFile | ConvertFrom-Json
                foreach ($app in $appCapabilities) {
                    $currentApp = Get-AppxPackage -Name $app.Name -ErrorAction SilentlyContinue
                    if ($currentApp) {
                        # Update app capabilities if needed
                        $manifest = Get-AppxPackageManifest $currentApp.PackageFullName
                        $currentCapabilities = $manifest.Package.Capabilities.Capability.Name
                        
                        $missingCapabilities = $app.Capabilities | Where-Object { $_ -notin $currentCapabilities }
                        if ($missingCapabilities) {
                            Write-Host "Updating capabilities for $($app.Name)..." -ForegroundColor Yellow
                            foreach ($capability in $missingCapabilities) {
                                Add-AppxPackageCapability -Package $currentApp -Capability $capability
                            }
                        }
                    }
                }
            }

            # Restore browser settings
            $browserSettingsFile = "$backupPath\browser_settings.json"
            if (Test-Path $browserSettingsFile) {
                $browserSettings = Get-Content $browserSettingsFile | ConvertFrom-Json
                
                # Set default browser
                if ($browserSettings.DefaultBrowser) {
                    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\http\UserChoice" `
                        -Name "ProgId" -Value $browserSettings.DefaultBrowser
                }

                # Set default apps for common file types
                $fileTypes = @{
                    ".pdf" = $browserSettings.PDFViewer
                    ".jpg" = $browserSettings.ImageViewer
                    ".mp4" = $browserSettings.VideoPlayer
                    ".mp3" = $browserSettings.MusicPlayer
                }

                foreach ($type in $fileTypes.GetEnumerator()) {
                    if ($type.Value) {
                        $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$($type.Key)\UserChoice"
                        if (!(Test-Path $path)) {
                            New-Item -Path $path -Force | Out-Null
                        }
                        Set-ItemProperty -Path $path -Name "ProgId" -Value $type.Value
                    }
                }
            }

            # Restart Explorer to apply changes
            Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
            Start-Process explorer
            
            Write-Host "Default Apps Settings restored successfully from: $backupPath" -ForegroundColor Green
            return $true
        }
        return $false
    } catch {
        Write-Host "Failed to restore Default Apps Settings: $_" -ForegroundColor Red
        return $false
    }
}

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Restore-DefaultAppsSettings -BackupRootPath $BackupRootPath
} 