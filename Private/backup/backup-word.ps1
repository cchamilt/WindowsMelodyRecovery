<#
.SYNOPSIS
    Backs up Microsoft Word settings and configurations.

.DESCRIPTION
    This script backs up Microsoft Word settings including:
    - Registry settings for Word preferences, options, security, and AutoCorrect
    - Configuration files for settings, templates, and custom content
    - Custom dictionaries and AutoCorrect entries
    - Building Blocks and QuickParts
    - Custom styles and ribbons
    - Startup items and add-ins
    - Recent files and Quick Access settings

.PARAMETER MachineBackupPath
    The root path where machine-specific backups are stored.

.PARAMETER SharedBackupPath
    The root path where shared backups are stored.

.EXAMPLE
    .\backup-word.ps1
    Backs up Word settings using default environment configuration.

.EXAMPLE
    .\backup-word.ps1 -MachineBackupPath "C:\Backups\Machine" -SharedBackupPath "C:\Backups\Shared"
    Backs up Word settings to specified backup paths.

.NOTES
    Author: Desktop Setup Script
    Requires: Windows PowerShell 5.1 or later
    
    Test Cases:
    1. Word 2016/2019/365 installed - Should backup all registry and config files
    2. Word not installed - Should complete gracefully with no items backed up
    3. Partial Word installation - Should backup available components only
    4. Custom templates and dictionaries - Should backup custom content
    5. Multiple Word versions - Should backup settings for all versions
    6. Corrupted Word settings - Should handle errors gracefully
    
    Mock Test Example:
    Mock-Command Test-Path { return $true }
    Mock-Command Copy-Item { return $null }
    Mock-Command reg { return "SUCCESS: The operation completed successfully." }
#>

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

function Backup-WordSettings {
    <#
    .SYNOPSIS
        Backs up Microsoft Word settings and configurations.

    .DESCRIPTION
        This script backs up Microsoft Word settings including:
        - Registry settings for Word preferences, options, security, and AutoCorrect
        - Configuration files for settings, templates, and custom content
        - Custom dictionaries and AutoCorrect entries
        - Building Blocks and QuickParts
        - Custom styles and ribbons
        - Startup items and add-ins
        - Recent files and Quick Access settings

    .PARAMETER BackupRootPath
        The root path where backups are stored.

    .PARAMETER Force
        Forces the backup operation even if Word is running.

    .EXAMPLE
        Backup-WordSettings -BackupRootPath "C:\Backups\Machine"
        Backs up Word settings to the specified backup path.

    .NOTES
        Author: Desktop Setup Script
        Requires: Windows PowerShell 5.1 or later
        
        Test Cases:
        1. Word 2016/2019/365 installed - Should backup all registry and config files
        2. Word not installed - Should complete gracefully with no items backed up
        3. Partial Word installation - Should backup available components only
        4. Custom templates and dictionaries - Should backup custom content
        5. Multiple Word versions - Should backup settings for all versions
        6. Corrupted Word settings - Should handle errors gracefully
        
        Mock Test Example:
        Mock-Command Test-Path { return $true }
        Mock-Command Copy-Item { return $null }
        Mock-Command reg { return "SUCCESS: The operation completed successfully." }
    #>
    
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
            Write-Verbose "Starting backup of Word Settings..."
            Write-Host "Backing up Word Settings..." -ForegroundColor Blue
            
            # Validate inputs before proceeding
            if (!(Test-Path $BackupRootPath)) {
                throw [System.IO.DirectoryNotFoundException]"Backup root path not found: $BackupRootPath"
            }
            
            $backupPath = Initialize-BackupDirectory -Path "Word" -BackupType "Word Settings" -BackupRootPath $BackupRootPath
            
            if ($backupPath) {
                $backedUpItems = @()
                $errors = @()
                
                # Stop Word processes if Force is specified
                if ($Force -and !$WhatIf -and !$script:TestMode) {
                    try {
                        $wordProcesses = Get-Process -Name "WINWORD" -ErrorAction SilentlyContinue
                        if ($wordProcesses) {
                            Write-Host "Stopping Word processes..." -ForegroundColor Yellow
                            $wordProcesses | Stop-Process -Force
                            Start-Sleep -Seconds 2
                        }
                    } catch {
                        Write-Warning "Could not stop Word processes: $_"
                    }
                }
                
                # Word config locations
                $configPaths = @{
                    # Main settings
                    "Settings" = "$env:APPDATA\Microsoft\Word"
                    # Custom templates
                    "Templates" = "$env:APPDATA\Microsoft\Templates"
                    # Quick Access and recent items
                    "RecentFiles" = "$env:APPDATA\Microsoft\Office\Recent"
                    # Custom dictionaries
                    "CustomDictionary" = "$env:APPDATA\Microsoft\UProof"
                    # AutoCorrect entries
                    "AutoCorrect" = "$env:APPDATA\Microsoft\Office"
                    # Building Blocks
                    "BuildingBlocks" = "$env:APPDATA\Microsoft\Document Building Blocks"
                    # Custom styles
                    "Styles" = "$env:APPDATA\Microsoft\QuickStyles"
                    # Custom toolbars and ribbons
                    "Ribbons" = "$env:APPDATA\Microsoft\Office\16.0\Word\Ribbons"
                    # Startup items
                    "Startup" = "$env:APPDATA\Microsoft\Word\STARTUP"
                    # QuickParts
                    "QuickParts" = "$env:APPDATA\Microsoft\Word\QuickParts"
                }

                # Create registry backup directory with subdirectories
                $registryPath = Join-Path $backupPath "Registry"
                $registrySubdirs = @("Word", "Common", "FileAssociations")
                
                if ($WhatIf) {
                    Write-Host "WhatIf: Would create registry backup directories"
                } else {
                    foreach ($subdir in $registrySubdirs) {
                        New-Item -ItemType Directory -Force -Path (Join-Path $registryPath $subdir) | Out-Null
                    }
                }

                # Export Word registry settings
                $regPaths = @(
                    # Word main settings for multiple versions
                    "HKCU\Software\Microsoft\Office\16.0\Word",
                    "HKCU\Software\Microsoft\Office\15.0\Word", 
                    "HKCU\Software\Microsoft\Office\14.0\Word",
                    "HKLM\SOFTWARE\Microsoft\Office\16.0\Word",
                    "HKLM\SOFTWARE\Microsoft\Office\15.0\Word",
                    "HKLM\SOFTWARE\Microsoft\Office\14.0\Word",
                    # Common settings
                    "HKCU\Software\Microsoft\Office\16.0\Common",
                    "HKCU\Software\Microsoft\Office\15.0\Common",
                    "HKCU\Software\Microsoft\Office\14.0\Common",
                    # File associations and shell integration
                    "HKCU\Software\Classes\.doc",
                    "HKCU\Software\Classes\.docx",
                    "HKCU\Software\Classes\.docm",
                    "HKCU\Software\Classes\.dotx",
                    "HKCU\Software\Classes\.dotm",
                    "HKLM\SOFTWARE\Classes\.doc",
                    "HKLM\SOFTWARE\Classes\.docx",
                    "HKLM\SOFTWARE\Classes\.docm",
                    "HKLM\SOFTWARE\Classes\.dotx",
                    "HKLM\SOFTWARE\Classes\.dotm"
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
                        # Determine subdirectory based on registry path
                        $subdir = "Word"
                        if ($regPath -like "*Common*") { $subdir = "Common" }
                        elseif ($regPath -like "*Classes*") { $subdir = "FileAssociations" }
                        
                        $regFile = Join-Path (Join-Path $registryPath $subdir) "$($regPath.Split('\')[-1]).reg"
                        
                        if ($WhatIf) {
                            Write-Host "WhatIf: Would export registry key $regPath to $regFile"
                        } else {
                            try {
                                if (!$script:TestMode) {
                                    $regResult = reg export $regPath $regFile /y 2>&1
                                    if ($LASTEXITCODE -eq 0) {
                                        $backedUpItems += "Registry\$subdir\$($regPath.Split('\')[-1]).reg"
                                    } else {
                                        $errors += "Could not export registry key: $regPath - $regResult"
                                    }
                                } else {
                                    # Test mode - create mock registry file
                                    "Windows Registry Editor Version 5.00" | Out-File $regFile -Force
                                    $backedUpItems += "Registry\$subdir\$($regPath.Split('\')[-1]).reg"
                                }
                            } catch {
                                $errors += "Failed to export registry key: $regPath - $($_.Exception.Message)"
                            }
                        }
                    } else {
                        Write-Verbose "Registry key not found: $regPath"
                    }
                }

                # Backup config files
                foreach ($config in $configPaths.GetEnumerator()) {
                    if ($WhatIf) {
                        Write-Host "WhatIf: Would backup $($config.Key) from $($config.Value)"
                    } else {
                        try {
                            if (Test-Path $config.Value) {
                                $targetPath = Join-Path $backupPath $config.Key
                                if ((Get-Item $config.Value) -is [System.IO.DirectoryInfo]) {
                                    # Skip temporary files
                                    $excludeFilter = @("*.tmp", "~*.*", "*.asd")
                                    if (!$script:TestMode) {
                                        Copy-Item $config.Value $targetPath -Recurse -Force -Exclude $excludeFilter -ErrorAction Stop
                                    } else {
                                        # Test mode - create mock directory
                                        New-Item -ItemType Directory -Force -Path $targetPath | Out-Null
                                        "Mock config file" | Out-File (Join-Path $targetPath "mock.txt") -Force
                                    }
                                } else {
                                    if (!$script:TestMode) {
                                        Copy-Item $config.Value $targetPath -Force -ErrorAction Stop
                                    } else {
                                        # Test mode - create mock file
                                        "Mock config file" | Out-File $targetPath -Force
                                    }
                                }
                                $backedUpItems += "Config: $($config.Key)"
                            }
                        } catch {
                            $errors += "Failed to backup $($config.Key): $($_.Exception.Message)"
                        }
                    }
                }

                # Create result object
                $result = [PSCustomObject]@{
                    Success = $true
                    BackupPath = $backupPath
                    Feature = "Word"
                    Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                    Items = $backedUpItems
                    Errors = $errors
                }

                # Summary
                Write-Host "`nWord Settings Backup Summary:" -ForegroundColor Green
                Write-Host "Items backed up: $($backedUpItems.Count)" -ForegroundColor Yellow
                if ($errors.Count -gt 0) {
                    Write-Host "Errors encountered: $($errors.Count)" -ForegroundColor Yellow
                    foreach ($error in $errors) {
                        Write-Host "  - $error" -ForegroundColor Red
                    }
                }
                
                Write-Host "Word Settings backed up successfully to: $backupPath" -ForegroundColor Green
                return $result
            } else {
                throw "Failed to initialize backup directory"
            }
        } catch {
            $errorMessage = "Failed to backup Word Settings: $($_.Exception.Message)"
            Write-Host $errorMessage -ForegroundColor Red
            
            return [PSCustomObject]@{
                Success = $false
                BackupPath = ""
                Feature = "Word"
                Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                Items = @()
                Errors = @($errorMessage)
            }
        }
    }
}

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    $result = Backup-WordSettings -BackupRootPath $BackupRootPath
    if (-not $result.Success) {
        exit 1
    }
}