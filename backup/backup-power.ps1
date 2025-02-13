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

function Backup-PowerSettings {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath
    )
    
    try {
        Write-Host "Backing up Power Settings..." -ForegroundColor Blue
        $backupPath = Initialize-BackupDirectory -Path "Power" -BackupType "Power Settings" -BackupRootPath $BackupRootPath
        
        if ($backupPath) {
            # Export power schemes
            $powerSchemes = powercfg.exe /list | Select-String "Power Scheme GUID: (.*?) \((.*?)\)" | ForEach-Object {
                @{
                    GUID = $_.Matches[0].Groups[1].Value
                    Name = $_.Matches[0].Groups[2].Value
                    IsActive = $false
                }
            }

            # Get active scheme
            $activeScheme = powercfg /getactivescheme | Select-String "Power Scheme GUID: (.*?) \((.*?)\)" | ForEach-Object {
                $_.Matches[0].Groups[1].Value
            }

            # Export each power scheme
            foreach ($scheme in $powerSchemes) {
                $scheme.IsActive = $scheme.GUID -eq $activeScheme
                $schemeFile = "$backupPath\$($scheme.GUID).pow"
                powercfg /export $schemeFile $scheme.GUID
            }

            # Save scheme metadata
            $powerSchemes | ConvertTo-Json | Out-File "$backupPath\power_schemes.json" -Force

            # Export power registry settings
            $regPaths = @(
                "HKLM\SYSTEM\CurrentControlSet\Control\Power",
                "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\PowerSettings",
                "HKCU\Control Panel\PowerCfg",
                "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power"
            )

            foreach ($regPath in $regPaths) {
                # Check if registry key exists before trying to export
                $keyExists = $false
                if ($regPath -match '^HKCU\\') {
                    $keyExists = Test-Path "Registry::HKEY_CURRENT_USER\$($regPath.Substring(5))"
                } elseif ($regPath -match '^HKLM\\') {
                    $keyExists = Test-Path "Registry::HKEY_LOCAL_MACHINE\$($regPath.Substring(5))"
                }
                
                if ($keyExists) {
                    $regFile = "$backupPath\$($regPath.Split('\')[-1]).reg"
                    reg export $regPath $regFile /y 2>$null
                } else {
                    Write-Host "Registry key not found: $regPath" -ForegroundColor Yellow
                }
            }

            # Export power button actions
            $buttonSettings = @{
                PowerButton = gwmi -Class Win32_PowerSettings | Where-Object { $_.Caption -like "*power button*" }
                SleepButton = gwmi -Class Win32_PowerSettings | Where-Object { $_.Caption -like "*sleep button*" }
                LidClose = gwmi -Class Win32_PowerSettings | Where-Object { $_.Caption -like "*lid*" }
            }
            $buttonSettings | ConvertTo-Json | Out-File "$backupPath\button_settings.json" -Force
            
            Write-Host "Power Settings backed up successfully to: $backupPath" -ForegroundColor Green
            return $true
        }
        return $false
    } catch {
        $errorRecord = $_
        $errorMessage = @(
            "Failed to backup Power Settings"
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
    Backup-PowerSettings -BackupRootPath $BackupRootPath
} 