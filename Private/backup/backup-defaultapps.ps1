[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$MachineBackupPath = $null,
    [Parameter(Mandatory=$false)]
    [string]$SharedBackupPath = $null
)

# Load environment if not provided
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path (Split-Path $scriptPath -Parent) "scripts\load-environment.ps1")

if (!$MachineBackupPath -or !$SharedBackupPath) {
    if (!(Load-Environment)) {
        Write-Host "Failed to load environment configuration" -ForegroundColor Red
        exit 1
    }
    $MachineBackupPath = "$env:BACKUP_ROOT\$env:MACHINE_NAME"
    $SharedBackupPath = "$env:BACKUP_ROOT\shared"
}

function Backup-DefaultAppsSettings {
    param(
        [Parameter(Mandatory=$true)]
        [string]$MachineBackupPath,
        [Parameter(Mandatory=$true)]
        [string]$SharedBackupPath
    )
    
    try {
        Write-Host "Backing up Default Apps Settings..." -ForegroundColor Blue
        $backupPath = Initialize-BackupDirectory -Path "DefaultApps" -BackupType "Default Apps Settings" -BackupRootPath $MachineBackupPath
        
        if ($backupPath) {
            # Export default apps registry settings
            $regPaths = @(
                # File type associations
                "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts",
                "HKLM\SOFTWARE\Classes",
                "HKCU\Software\Classes",
                
                # Default programs
                "HKCU\Software\Microsoft\Windows\Shell\Associations",
                "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FileAssociation",
                
                # App defaults
                "HKCU\Software\Microsoft\Windows\CurrentVersion\ApplicationAssociationToasts",
                "HKLM\SOFTWARE\RegisteredApplications",
                
                # URL protocol handlers
                "HKCU\Software\Microsoft\Windows\Shell\Associations\UrlAssociations",
                "HKLM\SOFTWARE\Microsoft\Windows\Shell\Associations\UrlAssociations"
            )

            foreach ($regPath in $regPaths) {
                $regFile = "$backupPath\$($regPath.Split('\')[-1]).reg"
                reg export $regPath $regFile /y 2>$null
            }

            # Export default apps using DISM
            $defaultAppsXml = "$backupPath\defaultapps.xml"
            Dism.exe /Online /Export-DefaultAppAssociations:$defaultAppsXml | Out-Null

            # Export user choice settings - only for common file types
            $commonExtensions = @(
                '.txt', '.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx',
                '.jpg', '.jpeg', '.png', '.gif', '.bmp',
                '.mp3', '.mp4', '.avi', '.mkv', '.wav',
                '.zip', '.rar', '.7z',
                '.html', '.htm', '.xml',
                '.exe', '.msi'
            )
            
            $userChoices = foreach ($ext in $commonExtensions) {
                $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$ext\UserChoice"
                if (Test-Path $path) {
                    Get-ItemProperty $path -ErrorAction SilentlyContinue | 
                    Add-Member -NotePropertyName Extension -NotePropertyValue $ext -PassThru
                }
            }

            if ($userChoices) {
                $userChoices | Select-Object Extension, ProgId, Hash | 
                    ConvertTo-Json -Depth 10 | 
                    Out-File "$backupPath\user_choices.json" -Force
            }

            # Export app capabilities
            $appCapabilities = Get-AppxPackage | Where-Object { $_.SignatureKind -ne "System" } | ForEach-Object {
                @{
                    Name = $_.Name
                    PackageFamilyName = $_.PackageFamilyName
                    Capabilities = (Get-AppxPackageManifest $_.PackageFullName).Package.Capabilities.Capability.Name
                }
            }
            $appCapabilities | ConvertTo-Json -Depth 10 | Out-File "$backupPath\app_capabilities.json" -Force

            # Export browser settings
            $browserSettings = @{
                DefaultBrowser = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\http\UserChoice").ProgId
                PDFViewer = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.pdf\UserChoice").ProgId
                ImageViewer = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.jpg\UserChoice").ProgId
                VideoPlayer = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.mp4\UserChoice").ProgId
                MusicPlayer = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.mp3\UserChoice").ProgId
            }
            $browserSettings | ConvertTo-Json | Out-File "$backupPath\browser_settings.json" -Force
            
            Write-Host "Default Apps Settings backed up successfully to: $backupPath" -ForegroundColor Green
            return $true
        }
        return $false
    } catch {
        $errorRecord = $_
        $errorMessage = @(
            "Failed to backup Default Apps Settings"
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
    Backup-DefaultAppsSettings -MachineBackupPath $MachineBackupPath -SharedBackupPath $SharedBackupPath
} 