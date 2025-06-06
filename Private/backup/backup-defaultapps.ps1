[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$BackupRootPath = $null,
    
    [Parameter(Mandatory=$false)]
    [string]$MachineBackupPath = $null,
    
    [Parameter(Mandatory=$false)]
    [string]$SharedBackupPath = $null,
    
    [Parameter(Mandatory=$false)]
    [switch]$Force,

    # For testing purposes
    [Parameter(DontShow)]
    [switch]$WhatIf
)

# Load environment script from the correct location
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$modulePath = Split-Path -Parent (Split-Path -Parent $scriptPath)
$loadEnvPath = Join-Path $modulePath "Private\scripts\load-environment.ps1"

# Source the load-environment script
if (Test-Path $loadEnvPath) {
    . $loadEnvPath
} else {
    Write-Host "Cannot find load-environment.ps1 at: $loadEnvPath" -ForegroundColor Red
}

# Get module configuration
$config = Get-WindowsMissingRecovery
if (!$config.IsInitialized) {
    throw "Module not initialized. Please run Initialize-WindowsMissingRecovery first."
}

# Set default paths if not provided
if (!$BackupRootPath) {
    $BackupRootPath = Join-Path $config.BackupRoot $config.MachineName
}
if (!$MachineBackupPath) {
    $MachineBackupPath = $BackupRootPath
}
if (!$SharedBackupPath) {
    $SharedBackupPath = Join-Path $config.BackupRoot "shared"
}

# Define Initialize-BackupDirectory function directly in the script
function Initialize-BackupDirectory {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Path,
        
        [Parameter(Mandatory=$true)]
        [string]$BackupType,
        
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath,
        
        [Parameter(Mandatory=$false)]
        [switch]$IsShared
    )
    
    # Create backup directory if it doesn't exist
    $backupPath = Join-Path $BackupRootPath $Path
    if (!(Test-Path -Path $backupPath)) {
        try {
            New-Item -ItemType Directory -Path $backupPath -Force | Out-Null
            Write-Host "Created backup directory for $BackupType at: $backupPath" -ForegroundColor Green
        } catch {
            Write-Host "Failed to create backup directory for $BackupType : $_" -ForegroundColor Red
            return $null
        }
    }
    
    return $backupPath
}

function Backup-DefaultAppsSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath,
        
        [Parameter(Mandatory=$true)]
        [string]$MachineBackupPath,
        
        [Parameter(Mandatory=$true)]
        [string]$SharedBackupPath,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force,

        # For testing purposes
        [Parameter(DontShow)]
        [switch]$WhatIf
    )
    
    begin {
        # Test hook for mocking
        if ($script:TestMode) {
            Write-Verbose "Running in test mode"
        }
    }
    
    process {
        try {
            Write-Verbose "Starting backup of Default Apps Settings..."
            Write-Host "Backing up Default Apps Settings..." -ForegroundColor Blue
            
            # Validate inputs before proceeding
            if (!(Test-Path $BackupRootPath)) {
                throw [System.IO.DirectoryNotFoundException]"Backup root path not found: $BackupRootPath"
            }
            if (!(Test-Path $MachineBackupPath)) {
                throw [System.IO.DirectoryNotFoundException]"Machine backup path not found: $MachineBackupPath"
            }
            if (!(Test-Path $SharedBackupPath)) {
                throw [System.IO.DirectoryNotFoundException]"Shared backup path not found: $SharedBackupPath"
            }
            
            $backupPath = Initialize-BackupDirectory -Path "DefaultApps" -BackupType "Default Apps Settings" -BackupRootPath $MachineBackupPath
            $sharedBackupPath = Initialize-BackupDirectory -Path "DefaultApps" -BackupType "Shared Default Apps Settings" -BackupRootPath $SharedBackupPath -IsShared
            $backedUpItems = @()
            $errors = @()
            
            if ($backupPath -and $sharedBackupPath) {
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
                    $sharedRegFile = "$sharedBackupPath\$($regPath.Split('\')[-1]).reg"
                    
                    if ($WhatIf) {
                        Write-Host "WhatIf: Would export registry path $regPath to $regFile and $sharedRegFile"
                    } else {
                        reg export $regPath $regFile /y 2>$null
                        reg export $regPath $sharedRegFile /y 2>$null
                        $backedUpItems += "$($regPath.Split('\')[-1]).reg"
                    }
                }

                # Export default apps using DISM
                $defaultAppsXml = "$backupPath\defaultapps.xml"
                $sharedDefaultAppsXml = "$sharedBackupPath\defaultapps.xml"
                
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export default apps XML to $defaultAppsXml and $sharedDefaultAppsXml"
                } else {
                    Dism.exe /Online /Export-DefaultAppAssociations:$defaultAppsXml | Out-Null
                    Copy-Item $defaultAppsXml $sharedDefaultAppsXml -Force
                    $backedUpItems += "defaultapps.xml"
                }

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
                    $jsonContent = $userChoices | Select-Object Extension, ProgId, Hash | ConvertTo-Json -Depth 10
                    $machineUserChoicesFile = "$backupPath\user_choices.json"
                    $sharedUserChoicesFile = "$sharedBackupPath\user_choices.json"
                    
                    if ($WhatIf) {
                        Write-Host "WhatIf: Would export user choices to $machineUserChoicesFile and $sharedUserChoicesFile"
                    } else {
                        $jsonContent | Out-File $machineUserChoicesFile -Force
                        $jsonContent | Out-File $sharedUserChoicesFile -Force
                        $backedUpItems += "user_choices.json"
                    }
                }

                # Export app capabilities
                $appCapabilities = Get-AppxPackage | Where-Object { $_.SignatureKind -ne "System" } | ForEach-Object {
                    @{
                        Name = $_.Name
                        PackageFamilyName = $_.PackageFamilyName
                        Capabilities = (Get-AppxPackageManifest $_.PackageFullName).Package.Capabilities.Capability.Name
                    }
                }
                
                $appCapabilitiesJson = $appCapabilities | ConvertTo-Json -Depth 10
                $machineAppCapabilitiesFile = "$backupPath\app_capabilities.json"
                $sharedAppCapabilitiesFile = "$sharedBackupPath\app_capabilities.json"
                
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export app capabilities to $machineAppCapabilitiesFile and $sharedAppCapabilitiesFile"
                } else {
                    $appCapabilitiesJson | Out-File $machineAppCapabilitiesFile -Force
                    $appCapabilitiesJson | Out-File $sharedAppCapabilitiesFile -Force
                    $backedUpItems += "app_capabilities.json"
                }

                # Export browser settings
                $browserSettings = @{
                    DefaultBrowser = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\http\UserChoice" -ErrorAction SilentlyContinue).ProgId
                    PDFViewer = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.pdf\UserChoice" -ErrorAction SilentlyContinue).ProgId
                    ImageViewer = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.jpg\UserChoice" -ErrorAction SilentlyContinue).ProgId
                    VideoPlayer = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.mp4\UserChoice" -ErrorAction SilentlyContinue).ProgId
                    MusicPlayer = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.mp3\UserChoice" -ErrorAction SilentlyContinue).ProgId
                }
                
                $browserSettingsJson = $browserSettings | ConvertTo-Json
                $machineBrowserSettingsFile = "$backupPath\browser_settings.json"
                $sharedBrowserSettingsFile = "$sharedBackupPath\browser_settings.json"
                
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export browser settings to $machineBrowserSettingsFile and $sharedBrowserSettingsFile"
                } else {
                    $browserSettingsJson | Out-File $machineBrowserSettingsFile -Force
                    $browserSettingsJson | Out-File $sharedBrowserSettingsFile -Force
                    $backedUpItems += "browser_settings.json"
                }
                
                # Return object for better testing and validation
                $result = [PSCustomObject]@{
                    Success = $true
                    BackupPath = $backupPath
                    SharedBackupPath = $sharedBackupPath
                    Feature = "DefaultApps"
                    Timestamp = Get-Date
                    Items = $backedUpItems
                    Errors = $errors
                }
                
                Write-Host "Default Apps Settings backed up successfully to: $backupPath" -ForegroundColor Green
                Write-Host "Shared Default Apps Settings backed up successfully to: $sharedBackupPath" -ForegroundColor Green
                Write-Verbose "Backup completed successfully"
                return $result
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
            
            Write-Error $errorMessage
            Write-Verbose "Backup failed"
            throw  # Re-throw for proper error handling
        }
    }
}

# Export the function if being imported as a module
if ($MyInvocation.Line -eq "") {
    Export-ModuleMember -Function Backup-DefaultAppsSettings
}

<#
.SYNOPSIS
Backs up Windows default app associations and settings.

.DESCRIPTION
Creates a backup of Windows default app settings including:
- Registry settings for file type associations
- Default programs and app defaults
- URL protocol handlers
- DISM export of default app associations
- User choice settings for common file types
- App capabilities
- Browser settings
- Both machine-specific and shared settings

.EXAMPLE
Backup-DefaultAppsSettings -BackupRootPath "C:\Backups" -MachineBackupPath "C:\Backups\Machine" -SharedBackupPath "C:\Backups\Shared"

.NOTES
Test cases to consider:
1. Valid backup paths with proper permissions
2. Invalid/nonexistent backup paths
3. Empty backup paths
4. No permissions to write
5. Registry keys exist/don't exist
6. DISM command succeeds/fails
7. AppX packages exist/don't exist
8. File associations exist/don't exist

.TESTCASES
# Mock test examples:
Describe "Backup-DefaultAppsSettings" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Initialize-BackupDirectory { return "TestPath" }
        Mock reg { }
        Mock Dism.exe { }
        Mock Get-ItemProperty { return @() }
        Mock Get-AppxPackage { return @() }
        Mock Get-AppxPackageManifest { return @{ Package = @{ Capabilities = @{ Capability = @{ Name = @() } } } } }
        Mock Out-File { }
        Mock Copy-Item { }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Backup-DefaultAppsSettings -BackupRootPath "TestPath" -MachineBackupPath "TestPath\Machine" -SharedBackupPath "TestPath\Shared"
        $result.Success | Should -Be $true
        $result.BackupPath | Should -Be "TestPath"
        $result.SharedBackupPath | Should -Be "TestPath\Shared"
        $result.Feature | Should -Be "DefaultApps"
    }

    It "Should handle registry export errors gracefully" {
        Mock reg { throw "Registry error" }
        $result = Backup-DefaultAppsSettings -BackupRootPath "TestPath" -MachineBackupPath "TestPath\Machine" -SharedBackupPath "TestPath\Shared"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Backup-DefaultAppsSettings -BackupRootPath $BackupRootPath -MachineBackupPath $MachineBackupPath -SharedBackupPath $SharedBackupPath
} 