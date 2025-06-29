[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$BackupRootPath = $null,
    
    [Parameter(Mandatory=$false)]
    [string]$MachineBackupPath = $null,
    
    [Parameter(Mandatory=$false)]
    [string]$SharedBackupPath = $null
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
$config = Get-WindowsMelodyRecovery
if (!$config.IsInitialized) {
    throw "Module not initialized. Please run Initialize-WindowsMelodyRecovery first."
}

if (!$BackupRootPath) {
    $BackupRootPath = Join-Path $config.BackupRoot $config.MachineName
}

# Define Initialize-BackupDirectory function directly in the script
function Initialize-BackupDirectory {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Path,
        
        [Parameter(Mandatory=$true)]
        [string]$BackupType,
        
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath
    )
    
    # Create machine-specific backup directory if it doesn't exist
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

function Backup-OutlookSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath,
        
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
            Write-Verbose "Starting backup of Outlook Settings..."
            Write-Host "Backing up Outlook Settings..." -ForegroundColor Blue
            
            # Validate inputs before proceeding
            if (!(Test-Path $BackupRootPath)) {
                throw [System.IO.DirectoryNotFoundException]"Backup root path not found: $BackupRootPath"
            }
            
            $backupPath = Initialize-BackupDirectory -Path "Outlook" -BackupType "Outlook Settings" -BackupRootPath $BackupRootPath
            
            if ($backupPath) {
                $backedUpItems = @()
                $errors = @()
                
                # Create registry backup directory
                $registryPath = Join-Path $backupPath "Registry"
                if ($WhatIf) {
                    Write-Host "WhatIf: Would create registry backup directory at $registryPath"
                } else {
                    New-Item -ItemType Directory -Force -Path $registryPath | Out-Null
                }

                # Export Outlook registry settings
                $regPaths = @(
                    # Outlook 2016/365 settings
                    "HKCU\Software\Microsoft\Office\16.0\Outlook",
                    "HKCU\Software\Microsoft\Office\16.0\Outlook\Preferences",
                    "HKCU\Software\Microsoft\Office\16.0\Outlook\Profiles",
                    "HKCU\Software\Microsoft\Office\16.0\Outlook\Security",
                    "HKCU\Software\Microsoft\Office\16.0\Outlook\AutoNameCheck",
                    "HKCU\Software\Microsoft\Office\16.0\Outlook\Options",
                    "HKCU\Software\Microsoft\Office\16.0\Outlook\Today",
                    "HKCU\Software\Microsoft\Office\16.0\Outlook\Journal",
                    "HKCU\Software\Microsoft\Office\16.0\Outlook\Calendar",
                    "HKCU\Software\Microsoft\Office\16.0\Outlook\Contact",
                    "HKCU\Software\Microsoft\Office\16.0\Outlook\Mail",
                    "HKCU\Software\Microsoft\Office\16.0\Outlook\Note",
                    "HKCU\Software\Microsoft\Office\16.0\Outlook\Task",
                    
                    # Outlook 2019 settings
                    "HKCU\Software\Microsoft\Office\19.0\Outlook",
                    "HKCU\Software\Microsoft\Office\19.0\Outlook\Preferences",
                    "HKCU\Software\Microsoft\Office\19.0\Outlook\Profiles",
                    "HKCU\Software\Microsoft\Office\19.0\Outlook\Security",
                    "HKCU\Software\Microsoft\Office\19.0\Outlook\AutoNameCheck",
                    "HKCU\Software\Microsoft\Office\19.0\Outlook\Options",
                    
                    # Outlook 2013 settings
                    "HKCU\Software\Microsoft\Office\15.0\Outlook",
                    "HKCU\Software\Microsoft\Office\15.0\Outlook\Preferences",
                    "HKCU\Software\Microsoft\Office\15.0\Outlook\Profiles",
                    "HKCU\Software\Microsoft\Office\15.0\Outlook\Security",
                    "HKCU\Software\Microsoft\Office\15.0\Outlook\AutoNameCheck",
                    
                    # Outlook 2010 settings
                    "HKCU\Software\Microsoft\Office\14.0\Outlook",
                    "HKCU\Software\Microsoft\Office\14.0\Outlook\Preferences",
                    "HKCU\Software\Microsoft\Office\14.0\Outlook\Profiles",
                    "HKCU\Software\Microsoft\Office\14.0\Outlook\Security",
                    "HKCU\Software\Microsoft\Office\14.0\Outlook\AutoNameCheck",
                    
                    # System-wide Outlook settings
                    "HKLM\SOFTWARE\Microsoft\Office\16.0\Outlook",
                    "HKLM\SOFTWARE\Microsoft\Office\19.0\Outlook",
                    "HKLM\SOFTWARE\Microsoft\Office\15.0\Outlook",
                    "HKLM\SOFTWARE\Microsoft\Office\14.0\Outlook",
                    
                    # Common Office settings that affect Outlook
                    "HKCU\Software\Microsoft\Office\Common\MailSettings",
                    "HKCU\Software\Microsoft\Office\Common\UserInfo"
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
                        $regFile = Join-Path $registryPath "$($regPath.Split('\')[-1]).reg"
                        if ($WhatIf) {
                            Write-Host "WhatIf: Would export registry key $regPath to $regFile"
                        } else {
                            try {
                                reg export $regPath $regFile /y 2>$null
                                $backedUpItems += "Registry\$($regPath.Split('\')[-1]).reg"
                            } catch {
                                $errors += "Failed to export $regPath : $_"
                            }
                        }
                    } else {
                        Write-Verbose "Registry key not found: $regPath"
                    }
                }

                # Backup Outlook configuration files
                $configPaths = @{
                    "Signatures" = "$env:APPDATA\Microsoft\Signatures"
                    "Templates" = "$env:APPDATA\Microsoft\Templates"
                    "Rules" = "$env:APPDATA\Microsoft\Outlook"
                    "Forms" = "$env:APPDATA\Microsoft\Forms"
                    "Stationery" = "$env:APPDATA\Microsoft\Stationery"
                    "QuickParts" = "$env:APPDATA\Microsoft\Document Building Blocks"
                    "CustomUI" = "$env:APPDATA\Microsoft\Office\16.0\User Content\Ribbon"
                    "AddIns" = "$env:APPDATA\Microsoft\AddIns"
                    "VBA" = "$env:APPDATA\Microsoft\Office\16.0\VBA"
                    "Themes" = "$env:APPDATA\Microsoft\Templates\Document Themes"
                    "RecentFiles" = "$env:APPDATA\Microsoft\Office\Recent"
                    "UProof" = "$env:APPDATA\Microsoft\UProof"
                }

                foreach ($config in $configPaths.GetEnumerator()) {
                    if (Test-Path $config.Value) {
                        $destPath = Join-Path $backupPath $config.Key
                        if ($WhatIf) {
                            Write-Host "WhatIf: Would copy configuration from $($config.Value) to $destPath"
                        } else {
                            try {
                                New-Item -ItemType Directory -Path $destPath -Force | Out-Null
                                # Exclude temporary files and large data files
                                $excludeFilter = @("*.tmp", "~*.*", "*.ost", "*.pst", "*.log", "*.lock")
                                Copy-Item -Path "$($config.Value)\*" -Destination $destPath -Recurse -Force -Exclude $excludeFilter -ErrorAction SilentlyContinue
                                $backedUpItems += $config.Key
                            } catch {
                                $errors += "Failed to backup $($config.Key) : $_"
                            }
                        }
                    } else {
                        Write-Verbose "Configuration path not found: $($config.Value)"
                    }
                }

                # Export profile information
                $profilePath = Join-Path $backupPath "Profiles"
                if ($WhatIf) {
                    Write-Host "WhatIf: Would create profiles directory at $profilePath"
                } else {
                    New-Item -ItemType Directory -Force -Path $profilePath | Out-Null
                }

                # Get Outlook profiles from all versions
                $profiles = @()
                $profileVersions = @("16.0", "19.0", "15.0", "14.0")
                
                foreach ($version in $profileVersions) {
                    try {
                        $profileKey = "HKCU:\Software\Microsoft\Office\$version\Outlook\Profiles"
                        if (Test-Path $profileKey) {
                            $versionProfiles = Get-ChildItem $profileKey -ErrorAction SilentlyContinue
                            if ($versionProfiles) {
                                $profiles += $versionProfiles | Select-Object @{Name="Version";Expression={$version}}, Name, LastWriteTime
                            }
                        }
                    } catch {
                        Write-Verbose "Could not access profiles for Office version $version"
                    }
                }
                
                if ($profiles.Count -gt 0) {
                    $profileFile = Join-Path $profilePath "profiles.json"
                    if ($WhatIf) {
                        Write-Host "WhatIf: Would export profile information to $profileFile"
                    } else {
                        try {
                            $profiles | ConvertTo-Json -Depth 10 | Out-File $profileFile -Force
                            $backedUpItems += "Profiles\profiles.json"
                        } catch {
                            $errors += "Failed to export profile information : $_"
                        }
                    }
                } else {
                    Write-Verbose "No Outlook profiles found"
                }

                # Backup Outlook Quick Access Toolbar customizations
                $quickAccessFile = "$env:APPDATA\Microsoft\Windows\Recent\Outlook.lnk"
                if (Test-Path $quickAccessFile) {
                    $quickAccessDest = Join-Path $backupPath "QuickAccess"
                    if ($WhatIf) {
                        Write-Host "WhatIf: Would backup Quick Access Toolbar to $quickAccessDest"
                    } else {
                        try {
                            New-Item -ItemType Directory -Path $quickAccessDest -Force | Out-Null
                            Copy-Item $quickAccessFile $quickAccessDest -Force
                            $backedUpItems += "QuickAccess\Outlook.lnk"
                        } catch {
                            $errors += "Failed to backup Quick Access Toolbar : $_"
                        }
                    }
                }
                
                # Return object for better testing and validation
                $result = [PSCustomObject]@{
                    Success = $true
                    BackupPath = $backupPath
                    Feature = "Outlook Settings"
                    Timestamp = Get-Date
                    Items = $backedUpItems
                    Errors = $errors
                }
                
                Write-Host "Outlook Settings backed up successfully to: $backupPath" -ForegroundColor Green
                Write-Verbose "Backup completed successfully"
                return $result
            }
            return $false
        } catch {
            $errorRecord = $_
            $errorMessage = @(
                "Failed to backup Outlook Settings"
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

<#
.SYNOPSIS
Backs up Microsoft Outlook settings and configuration.

.DESCRIPTION
Creates a comprehensive backup of Microsoft Outlook settings, including registry settings, signatures, templates, 
rules, forms, stationery, Quick Parts, custom UI, add-ins, VBA projects, themes, and profile information.
Supports multiple Outlook versions (2010, 2013, 2016, 2019, 365).

.PARAMETER BackupRootPath
The root path where the backup will be created. A subdirectory named "Outlook" will be created within this path.

.PARAMETER Force
Forces the backup operation even if the destination already exists.

.PARAMETER WhatIf
Shows what would be backed up without actually performing the backup operation.

.EXAMPLE
Backup-OutlookSettings -BackupRootPath "C:\Backups"

.EXAMPLE
Backup-OutlookSettings -BackupRootPath "C:\Backups" -WhatIf

.NOTES
Test cases to consider:
1. Valid backup path with proper permissions
2. Invalid/nonexistent backup path
3. Empty backup path
4. No permissions to write
5. Registry export success/failure for each key
6. Configuration file backup success/failure
7. Profile information export success/failure
8. Multiple Outlook versions installed
9. Outlook not installed scenario
10. Large PST/OST files (excluded from backup)
11. Custom signatures and templates
12. VBA projects and add-ins
13. Custom forms and stationery
14. Quick Parts and building blocks
15. Network path scenarios
16. Corrupted profile scenarios
17. Missing configuration directories
18. File permission issues
19. Disk space limitations
20. Concurrent Outlook usage

.TESTCASES
# Mock test examples:
Describe "Backup-OutlookSettings" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Initialize-BackupDirectory { return "TestPath" }
        Mock New-Item { }
        Mock reg { }
        Mock Get-ChildItem { return @(
            [PSCustomObject]@{
                Name = "Default"
                LastWriteTime = Get-Date
            }
        )}
        Mock Copy-Item { }
        Mock ConvertTo-Json { return '{"test":"value"}' }
        Mock Out-File { }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Backup-OutlookSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.BackupPath | Should -Be "TestPath"
        $result.Feature | Should -Be "Outlook Settings"
        $result.Items | Should -BeOfType [System.Array]
        $result.Errors | Should -BeOfType [System.Array]
    }

    It "Should handle registry export failure gracefully" {
        Mock reg { throw "Registry export failed" }
        $result = Backup-OutlookSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle configuration backup failure gracefully" {
        Mock Copy-Item { throw "Access denied" }
        $result = Backup-OutlookSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should support WhatIf parameter" {
        $result = Backup-OutlookSettings -BackupRootPath "TestPath" -WhatIf
        $result.Success | Should -Be $true
    }

    It "Should handle profile export failure gracefully" {
        Mock Get-ChildItem { throw "Profile access denied" }
        $result = Backup-OutlookSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle missing configuration directories" {
        Mock Test-Path { param($Path) return $Path -like "*TestPath*" }
        $result = Backup-OutlookSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Backup-OutlookSettings -BackupRootPath $BackupRootPath
} 