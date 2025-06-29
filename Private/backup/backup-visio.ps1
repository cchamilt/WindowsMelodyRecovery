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

function Backup-VisioSettings {
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
            Write-Verbose "Starting backup of Visio Settings..."
            Write-Host "Backing up Visio Settings..." -ForegroundColor Blue
            
            # Validate inputs before proceeding
            if (!(Test-Path $BackupRootPath)) {
                throw [System.IO.DirectoryNotFoundException]"Backup root path not found: $BackupRootPath"
            }
            
            $backupPath = Initialize-BackupDirectory -Path "Visio" -BackupType "Visio Settings" -BackupRootPath $BackupRootPath
            
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

                # Visio-related registry settings to backup (multiple versions)
                $registryPaths = @(
                    # Visio 2019/365 (Office 16.0)
                    "HKCU\Software\Microsoft\Office\16.0\Visio",
                    "HKLM\SOFTWARE\Microsoft\Office\16.0\Visio",
                    "HKCU\Software\Microsoft\Office\16.0\Visio\Options",
                    "HKCU\Software\Microsoft\Office\16.0\Visio\Security",
                    "HKCU\Software\Microsoft\Office\16.0\Visio\AddIns",
                    "HKCU\Software\Microsoft\Office\16.0\Visio\Drawing",
                    "HKCU\Software\Microsoft\Office\16.0\Visio\File MRU",
                    "HKCU\Software\Microsoft\Office\16.0\Visio\Place MRU",
                    
                    # Visio 2016 (Office 15.0)
                    "HKCU\Software\Microsoft\Office\15.0\Visio",
                    "HKLM\SOFTWARE\Microsoft\Office\15.0\Visio",
                    "HKCU\Software\Microsoft\Office\15.0\Visio\Options",
                    "HKCU\Software\Microsoft\Office\15.0\Visio\Security",
                    "HKCU\Software\Microsoft\Office\15.0\Visio\AddIns",
                    
                    # Visio 2013 (Office 15.0)
                    "HKCU\Software\Microsoft\Office\14.0\Visio",
                    "HKLM\SOFTWARE\Microsoft\Office\14.0\Visio",
                    
                    # Visio 2010 (Office 14.0)
                    "HKCU\Software\Microsoft\Office\12.0\Visio",
                    "HKLM\SOFTWARE\Microsoft\Office\12.0\Visio",
                    
                    # Common Office settings that affect Visio
                    "HKCU\Software\Microsoft\Office\16.0\Common",
                    "HKCU\Software\Microsoft\Office\15.0\Common",
                    "HKCU\Software\Microsoft\Office\14.0\Common",
                    "HKCU\Software\Microsoft\Office\12.0\Common",
                    
                    # File associations
                    "HKCU\Software\Classes\.vsd",
                    "HKCU\Software\Classes\.vsdx",
                    "HKCU\Software\Classes\.vss",
                    "HKCU\Software\Classes\.vssx",
                    "HKCU\Software\Classes\.vst",
                    "HKCU\Software\Classes\.vstx",
                    "HKCU\Software\Classes\.vdx",
                    "HKCU\Software\Classes\.vtx",
                    "HKCU\Software\Classes\.vsx",
                    
                    # Visio Viewer settings
                    "HKCU\Software\Microsoft\Visio Viewer",
                    "HKLM\SOFTWARE\Microsoft\Visio Viewer"
                )

                # Export registry settings
                foreach ($path in $registryPaths) {
                    # Check if registry key exists before trying to export
                    $keyExists = $false
                    if ($path -match '^HKCU\\') {
                        $keyExists = Test-Path "Registry::HKEY_CURRENT_USER\$($path.Substring(5))"
                    } elseif ($path -match '^HKLM\\') {
                        $keyExists = Test-Path "Registry::HKEY_LOCAL_MACHINE\$($path.Substring(5))"
                    }
                    
                    if ($keyExists) {
                        $regFile = Join-Path $registryPath "$($path.Split('\')[-1]).reg"
                        if ($WhatIf) {
                            Write-Host "WhatIf: Would export registry key $path to $regFile"
                        } else {
                            try {
                                $result = reg export $path $regFile /y 2>&1
                                if ($LASTEXITCODE -eq 0) {
                                    $backedUpItems += "Registry\$($path.Split('\')[-1]).reg"
                                } else {
                                    $errors += "Could not export registry key: $path"
                                }
                            } catch {
                                $errors += "Failed to export registry key $path : $_"
                            }
                        }
                    } else {
                        Write-Verbose "Registry key not found: $path"
                    }
                }

                # Define configuration paths to backup
                $configPaths = @{
                    "Settings" = "$env:APPDATA\Microsoft\Visio"
                    "Templates" = "$env:APPDATA\Microsoft\Templates"
                    "RecentFiles" = "$env:APPDATA\Microsoft\Office\Recent"
                    "CustomDictionary" = "$env:APPDATA\Microsoft\UProof"
                    "AutoCorrect" = "$env:APPDATA\Microsoft\Office"
                    "Ribbons" = "$env:APPDATA\Microsoft\Office\16.0\Visio\Ribbons"
                    "AddIns" = "$env:APPDATA\Microsoft\Visio\AddOns"
                    "Stencils" = "$env:APPDATA\Microsoft\Visio\Stencils"
                    "MyShapes" = "$env:APPDATA\Microsoft\Visio\My Shapes"
                    "Themes" = "$env:APPDATA\Microsoft\Visio\Themes"
                    "Workspace" = "$env:APPDATA\Microsoft\Visio\Workspace"
                    "Macros" = "$env:APPDATA\Microsoft\Visio\Macros"
                    "QuickAccess" = "$env:APPDATA\Microsoft\Office\16.0\Visio\QuickAccess"
                    "CustomUI" = "$env:APPDATA\Microsoft\Office\16.0\Visio\CustomUI"
                    "VBAProjects" = "$env:APPDATA\Microsoft\Office\16.0\Visio\VBA"
                    "Preferences" = "$env:APPDATA\Microsoft\Office\16.0\Visio\Preferences"
                }

                # Backup configuration files and directories
                foreach ($config in $configPaths.GetEnumerator()) {
                    $sourcePath = $config.Value
                    $configName = $config.Key
                    
                    if ($WhatIf) {
                        Write-Host "WhatIf: Would backup $configName from $sourcePath"
                        continue
                    }
                    
                    if (Test-Path $sourcePath) {
                        try {
                            $targetPath = Join-Path $backupPath $configName
                            
                            if ((Get-Item $sourcePath) -is [System.IO.DirectoryInfo]) {
                                # Skip temporary files and certain file types
                                $excludeFilter = @("*.tmp", "~*.*", "*.bak", "*.old", "*.log")
                                Copy-Item $sourcePath $targetPath -Recurse -Force -Exclude $excludeFilter -ErrorAction SilentlyContinue
                            } else {
                                Copy-Item $sourcePath $targetPath -Force -ErrorAction SilentlyContinue
                            }
                            
                            $backedUpItems += $configName
                        } catch {
                            $errors += "Failed to backup $configName : $_"
                        }
                    } else {
                        Write-Verbose "Configuration path not found: $sourcePath"
                    }
                }

                # Get Visio installation information
                if ($WhatIf) {
                    Write-Host "WhatIf: Would backup Visio installation information"
                } else {
                    try {
                        if (!$script:TestMode) {
                            $visioInfo = @{}
                            
                            # Get installed Visio versions
                            $visioVersions = @()
                            $officeVersions = @("16.0", "15.0", "14.0", "12.0")
                            
                            foreach ($version in $officeVersions) {
                                $versionKey = "HKLM:\SOFTWARE\Microsoft\Office\$version\Visio\InstallRoot"
                                if (Test-Path $versionKey) {
                                    try {
                                        $installPath = Get-ItemProperty -Path $versionKey -Name "Path" -ErrorAction SilentlyContinue
                                        if ($installPath) {
                                            $visioVersions += @{
                                                Version = $version
                                                InstallPath = $installPath.Path
                                            }
                                        }
                                    } catch {
                                        Write-Verbose "Could not read Visio $version install path"
                                    }
                                }
                            }
                            
                            if ($visioVersions.Count -gt 0) {
                                $visioInfo.InstalledVersions = $visioVersions
                            }
                            
                            # Get Visio add-ins information
                            $addInsInfo = @()
                            foreach ($version in $officeVersions) {
                                $addInsKey = "HKCU:\Software\Microsoft\Office\$version\Visio\AddIns"
                                if (Test-Path $addInsKey) {
                                    try {
                                        $addIns = Get-ChildItem -Path $addInsKey -ErrorAction SilentlyContinue
                                        foreach ($addIn in $addIns) {
                                            $addInProps = Get-ItemProperty -Path $addIn.PSPath -ErrorAction SilentlyContinue
                                            if ($addInProps) {
                                                $addInsInfo += @{
                                                    Version = $version
                                                    Name = $addIn.PSChildName
                                                    Properties = $addInProps
                                                }
                                            }
                                        }
                                    } catch {
                                        Write-Verbose "Could not read Visio $version add-ins"
                                    }
                                }
                            }
                            
                            if ($addInsInfo.Count -gt 0) {
                                $visioInfo.AddIns = $addInsInfo
                            }
                            
                            if ($visioInfo.Count -gt 0) {
                                $visioInfo | ConvertTo-Json -Depth 10 | Out-File (Join-Path $backupPath "visio_info.json") -Force
                                $backedUpItems += "visio_info.json"
                            }
                        }
                    } catch {
                        $errors += "Failed to backup Visio installation information: $_"
                    }
                }

                # Get Visio file associations
                if ($WhatIf) {
                    Write-Host "WhatIf: Would backup Visio file associations"
                } else {
                    try {
                        $fileAssociations = @{}
                        $visioExtensions = @(".vsd", ".vsdx", ".vss", ".vssx", ".vst", ".vstx", ".vdx", ".vtx", ".vsx")
                        
                        foreach ($ext in $visioExtensions) {
                            $extKey = "HKCU:\Software\Classes\$ext"
                            if (Test-Path $extKey) {
                                try {
                                    $assoc = Get-ItemProperty -Path $extKey -ErrorAction SilentlyContinue
                                    if ($assoc) {
                                        $fileAssociations[$ext] = $assoc
                                    }
                                } catch {
                                    Write-Verbose "Could not read file association for $ext"
                                }
                            }
                        }
                        
                        if ($fileAssociations.Count -gt 0) {
                            $fileAssociations | ConvertTo-Json -Depth 10 | Out-File (Join-Path $backupPath "file_associations.json") -Force
                            $backedUpItems += "file_associations.json"
                        }
                    } catch {
                        $errors += "Failed to backup Visio file associations: $_"
                    }
                }

                # Get Visio COM add-ins information
                if ($WhatIf) {
                    Write-Host "WhatIf: Would backup Visio COM add-ins information"
                } else {
                    try {
                        if (!$script:TestMode) {
                            $comAddIns = @()
                            
                            # Check for COM add-ins in different Office versions
                            foreach ($version in @("16.0", "15.0", "14.0", "12.0")) {
                                $comKey = "HKCU:\Software\Microsoft\Office\$version\Visio\AddIns"
                                if (Test-Path $comKey) {
                                    try {
                                        $addIns = Get-ChildItem -Path $comKey -ErrorAction SilentlyContinue
                                        foreach ($addIn in $addIns) {
                                            $addInInfo = Get-ItemProperty -Path $addIn.PSPath -ErrorAction SilentlyContinue
                                            if ($addInInfo) {
                                                $comAddIns += @{
                                                    Version = $version
                                                    Name = $addIn.PSChildName
                                                    LoadBehavior = $addInInfo.LoadBehavior
                                                    FriendlyName = $addInInfo.FriendlyName
                                                    Description = $addInInfo.Description
                                                }
                                            }
                                        }
                                    } catch {
                                        Write-Verbose "Could not read COM add-ins for Visio $version"
                                    }
                                }
                            }
                            
                            if ($comAddIns.Count -gt 0) {
                                $comAddIns | ConvertTo-Json -Depth 10 | Out-File (Join-Path $backupPath "com_addins.json") -Force
                                $backedUpItems += "com_addins.json"
                            }
                        }
                    } catch {
                        $errors += "Failed to backup Visio COM add-ins information: $_"
                    }
                }
                
                # Return object for better testing and validation
                $result = [PSCustomObject]@{
                    Success = $true
                    BackupPath = $backupPath
                    Feature = "Visio Settings"
                    Timestamp = Get-Date
                    Items = $backedUpItems
                    Errors = $errors
                }
                
                Write-Host "Visio Settings backed up successfully to: $backupPath" -ForegroundColor Green
                Write-Verbose "Backup completed successfully"
                return $result
            }
            return $false
        } catch {
            $errorRecord = $_
            $errorMessage = @(
                "Failed to backup Visio Settings"
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
Backs up comprehensive Microsoft Visio settings, configurations, and customizations.

.DESCRIPTION
Creates a comprehensive backup of Microsoft Visio settings including user preferences, 
templates, stencils, custom shapes, themes, macros, add-ins, ribbons, file associations, 
COM add-ins, and installation information. Supports multiple Visio versions (2010, 2013, 
2016, 2019, 365) and handles both user-specific and system-wide configurations.

.PARAMETER BackupRootPath
The root path where the backup will be created. A subdirectory named "Visio" will be created within this path.

.PARAMETER Force
Forces the backup operation even if the destination already exists.

.PARAMETER WhatIf
Shows what would be backed up without actually performing the backup operation.

.EXAMPLE
Backup-VisioSettings -BackupRootPath "C:\Backups"

.EXAMPLE
Backup-VisioSettings -BackupRootPath "C:\Backups" -WhatIf

.NOTES
Test cases to consider:
1. Valid backup path with proper permissions
2. Invalid/nonexistent backup path
3. Empty backup path
4. No permissions to write
5. Visio 2010 present vs absent
6. Visio 2013 present vs absent
7. Visio 2016 present vs absent
8. Visio 2019 present vs absent
9. Visio 365 present vs absent
10. Registry export success/failure for each key
11. Configuration file backup success/failure
12. Custom templates and stencils backup
13. Add-ins backup success/failure
14. COM add-ins information retrieval
15. File associations backup
16. Installation information retrieval
17. Multiple Visio versions scenarios
18. Missing configuration directories
19. Administrative privileges scenarios
20. Network path scenarios
21. Custom shapes backup
22. Themes backup
23. Macros backup
24. Workspace settings backup
25. VBA projects backup

.TESTCASES
# Mock test examples:
Describe "Backup-VisioSettings" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Initialize-BackupDirectory { return "TestPath" }
        Mock New-Item { }
        Mock Copy-Item { }
        Mock Get-ItemProperty { return @{ Path = "C:\Program Files\Microsoft Office\root\Office16\" } }
        Mock Get-ChildItem { return @() }
        Mock ConvertTo-Json { return '{"test":"value"}' }
        Mock Out-File { }
        Mock reg { $global:LASTEXITCODE = 0 }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Backup-VisioSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.BackupPath | Should -Be "TestPath"
        $result.Feature | Should -Be "Visio Settings"
        $result.Items | Should -BeOfType [System.Array]
        $result.Errors | Should -BeOfType [System.Array]
    }

    It "Should handle registry export failure gracefully" {
        Mock reg { $global:LASTEXITCODE = 1; return "Error" }
        $result = Backup-VisioSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle file copy failure gracefully" {
        Mock Copy-Item { throw "File copy failed" }
        $result = Backup-VisioSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should support WhatIf parameter" {
        $result = Backup-VisioSettings -BackupRootPath "TestPath" -WhatIf
        $result.Success | Should -Be $true
    }

    It "Should handle registry access failure gracefully" {
        Mock Get-ItemProperty { throw "Registry access failed" }
        $result = Backup-VisioSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle missing configuration directories gracefully" {
        Mock Test-Path { param($Path) return $Path -notlike "*AppData*" }
        $result = Backup-VisioSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
    }

    It "Should handle installation information backup failure gracefully" {
        Mock Get-ItemProperty { throw "Installation info access failed" }
        $result = Backup-VisioSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle file associations backup failure gracefully" {
        Mock Get-ItemProperty { throw "File associations access failed" }
        $result = Backup-VisioSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle COM add-ins backup failure gracefully" {
        Mock Get-ChildItem { throw "COM add-ins enumeration failed" }
        $result = Backup-VisioSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Backup-VisioSettings -BackupRootPath $BackupRootPath
} 