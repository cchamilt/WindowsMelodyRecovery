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

# Main backup function that can be called by master script
function Backup-Applications {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath
    )
    
    try {
        Write-Host "Backing up Application List..." -ForegroundColor Blue
        $backupPath = Initialize-BackupDirectory -Path "Applications" -BackupType "Applications" -BackupRootPath $BackupRootPath
        
        if ($backupPath) {
            $applications = @{
                Winget = @()
                Chocolatey = @()
                Other = @()
            }

            # Export installed applications from multiple sources
            try {
                # Get Winget applications
                Write-Host "Scanning Winget applications..." -ForegroundColor Blue
                $wingetApps = @()
                $wingetSearch = winget list

                # Parse winget output more safely
                try {
                    $wingetLines = $wingetSearch -split "`n" | Select-Object -Skip 3
                    foreach ($line in $wingetLines) {
                        if ($line -match "^(.+?)\s{2,}([^\s]+)\s{2,}(.+)$") {
                            $wingetApps += @{
                                Name = $Matches[1].Trim()
                                ID = $Matches[2]
                                Version = $Matches[3].Trim()
                                Source = "winget"
                            }
                        }
                    }
                } catch {
                    Write-Host "Warning: Error parsing winget output - $($_.Exception.Message)" -ForegroundColor Yellow
                }

                # Get Chocolatey applications if available
                Write-Host "Scanning Chocolatey applications..." -ForegroundColor Blue
                if (Get-Command choco -ErrorAction SilentlyContinue) {
                    $chocoApps = choco list -lo -r | ForEach-Object {
                        $parts = $_ -split '\|'
                        @{
                            Name = $parts[0]
                            Version = $parts[1]
                            Source = "chocolatey"
                        }
                    }
                }

                # Get Windows Store apps
                Write-Host "Scanning Windows Store applications..." -ForegroundColor Blue
                $storeApps = Get-AppxPackage | Select-Object Name, PackageFullName, Version | ForEach-Object {
                    @{
                        Name = $_.Name
                        ID = $_.PackageFullName
                        Version = $_.Version
                        Source = "store"
                    }
                }

                # Get traditional Windows applications
                Write-Host "Scanning traditional Windows applications..." -ForegroundColor Blue
                $uninstallKeys = @(
                    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
                    "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
                    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
                )

                $traditionalApps = Get-ItemProperty $uninstallKeys | 
                    Where-Object { $_.DisplayName } |
                    Select-Object @{N='Name';E={$_.DisplayName}}, 
                                @{N='Version';E={$_.DisplayVersion}},
                                @{N='Publisher';E={$_.Publisher}},
                                @{N='InstallDate';E={$_.InstallDate}} |
                    ForEach-Object {
                        @{
                            Name = $_.Name
                            Version = $_.Version
                            Publisher = $_.Publisher
                            InstallDate = $_.InstallDate
                            Source = "windows"
                        }
                    }

                # Combine all applications
                $allApps = @{
                    Winget = $wingetApps
                    Chocolatey = $chocoApps
                    Store = $storeApps
                    Traditional = $traditionalApps
                }

                # Export to JSON
                $allApps | ConvertTo-Json -Depth 10 | Out-File "$backupPath\installed_applications.json" -Force

                # Output summary
                Write-Host "`nApplication Summary:" -ForegroundColor Green
                Write-Host "Winget Applications: $($applications.Winget.Count)" -ForegroundColor Yellow
                Write-Host "Chocolatey Packages: $($applications.Chocolatey.Count)" -ForegroundColor Yellow
                Write-Host "Other Applications: $($applications.Other.Count)" -ForegroundColor Yellow
                
                Write-Host "Applications list backed up successfully to: $backupPath" -ForegroundColor Green
                return $true
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
    Backup-Applications -BackupRootPath $BackupRootPath
} 