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
$config = Get-WindowsMissingRecovery
if (!$config.IsInitialized) {
    throw "Module not initialized. Please run Initialize-WindowsMissingRecovery first."
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

function Backup-ExcelSettings {
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
            Write-Verbose "Starting backup of Excel Settings..."
            Write-Host "Backing up Excel Settings..." -ForegroundColor Blue
            
            # Validate inputs before proceeding
            if (!(Test-Path $BackupRootPath)) {
                throw [System.IO.DirectoryNotFoundException]"Backup root path not found: $BackupRootPath"
            }
            
            $backupPath = Initialize-BackupDirectory -Path "Excel" -BackupType "Excel Settings" -BackupRootPath $BackupRootPath
            
            if ($backupPath) {
                $backedUpItems = @()
                $errors = @()
                
                # Export Excel registry settings
                $regPaths = @(
                    # Excel 2016/365 settings
                    "HKCU\Software\Microsoft\Office\16.0\Excel",
                    "HKCU\Software\Microsoft\Office\16.0\Common\Excel",
                    "HKCU\Software\Microsoft\Office\16.0\Excel\Options",
                    "HKCU\Software\Microsoft\Office\16.0\Excel\Security",
                    "HKCU\Software\Microsoft\Office\16.0\Excel\Recent Files",
                   
                    # Excel 2013 settings
                    "HKCU\Software\Microsoft\Office\15.0\Excel",
                    "HKCU\Software\Microsoft\Office\15.0\Common\Excel",
                    "HKCU\Software\Microsoft\Office\15.0\Excel\Options",
                    "HKCU\Software\Microsoft\Office\15.0\Excel\Security",
                    "HKCU\Software\Microsoft\Office\15.0\Excel\Recent Files",
                   
                    # Excel 2010 settings
                    "HKCU\Software\Microsoft\Office\14.0\Excel",
                    "HKCU\Software\Microsoft\Office\14.0\Common\Excel",
                    "HKCU\Software\Microsoft\Office\14.0\Excel\Options",
                    "HKCU\Software\Microsoft\Office\14.0\Excel\Security",
                    "HKCU\Software\Microsoft\Office\14.0\Excel\Recent Files",
                   
                    # System-wide Excel settings
                    "HKLM\SOFTWARE\Microsoft\Office\16.0\Excel",
                    "HKLM\SOFTWARE\Microsoft\Office\15.0\Excel",
                    "HKLM\SOFTWARE\Microsoft\Office\14.0\Excel"
                )

                # Create registry backup directory
                $registryPath = Join-Path $backupPath "Registry"
                if ($WhatIf) {
                    Write-Host "WhatIf: Would create registry backup directory at $registryPath"
                } else {
                    New-Item -ItemType Directory -Force -Path $registryPath | Out-Null
                }

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
                                $backedUpItems += "$($regPath.Split('\')[-1]).reg"
                            } catch {
                                $errors += "Failed to export $regPath : $_"
                            }
                        }
                    } else {
                        Write-Verbose "Registry key not found: $regPath"
                    }
                }

                # Backup Excel configuration files
                $configPaths = @{
                    "AppData" = "$env:APPDATA\Microsoft\Excel"
                    "Templates" = "$env:APPDATA\Microsoft\Templates"
                    "XLSTART" = "$env:APPDATA\Microsoft\Excel\XLSTART"
                    "AddIns" = "$env:APPDATA\Microsoft\AddIns"
                    "QuickAccess" = "$env:APPDATA\Microsoft\Windows\Recent\Excel.lnk"
                }

                foreach ($config in $configPaths.GetEnumerator()) {
                    if (Test-Path $config.Value) {
                        $destPath = Join-Path $backupPath $config.Key
                        if ($WhatIf) {
                            Write-Host "WhatIf: Would copy configuration from $($config.Value) to $destPath"
                        } else {
                            try {
                                New-Item -ItemType Directory -Path $destPath -Force | Out-Null
                                Copy-Item -Path "$($config.Value)\*" -Destination $destPath -Recurse -Force
                                $backedUpItems += $config.Key
                            } catch {
                                $errors += "Failed to backup $($config.Key) : $_"
                            }
                        }
                    }
                }

                # Export recent files list
                if (Test-Path "$env:APPDATA\Microsoft\Office\Recent") {
                    $recentFiles = @()
                    try {
                        $recentFiles += Get-ChildItem "$env:APPDATA\Microsoft\Office\Recent\*.xls*" -ErrorAction SilentlyContinue
                        if ($recentFiles.Count -gt 0) {
                            $recentFile = Join-Path $backupPath "recent_files.txt"
                            if ($WhatIf) {
                                Write-Host "WhatIf: Would export recent files list to $recentFile"
                            } else {
                                $recentFiles | Select-Object Name, LastWriteTime | ConvertTo-Json | Out-File $recentFile
                                $backedUpItems += "recent_files.txt"
                            }
                        }
                    } catch {
                        $errors += "Failed to backup recent files list : $_"
                    }
                }
                
                # Return object for better testing and validation
                $result = [PSCustomObject]@{
                    Success = $true
                    BackupPath = $backupPath
                    Feature = "Excel Settings"
                    Timestamp = Get-Date
                    Items = $backedUpItems
                    Errors = $errors
                }
                
                Write-Host "Excel Settings backed up successfully to: $backupPath" -ForegroundColor Green
                Write-Verbose "Backup completed successfully"
                return $result
            }
            return $false
        } catch {
            $errorRecord = $_
            $errorMessage = @(
                "Failed to backup Excel Settings"
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
    Export-ModuleMember -Function Backup-ExcelSettings
}

<#
.SYNOPSIS
Backs up Excel settings and configuration.

.DESCRIPTION
Creates a backup of Excel settings, including registry settings, configuration files, templates, and recent files list.
Supports multiple Excel versions (2010, 2013, 2016/365) and backs up both user-specific and system-wide settings.

.PARAMETER BackupRootPath
The root path where the backup will be created. A subdirectory named "Excel" will be created within this path.

.PARAMETER Force
Forces the backup operation even if the destination already exists.

.PARAMETER WhatIf
Shows what would be backed up without actually performing the backup operation.

.EXAMPLE
Backup-ExcelSettings -BackupRootPath "C:\Backups"

.NOTES
Test cases to consider:
1. Valid backup path with proper permissions
2. Invalid/nonexistent backup path
3. Empty backup path
4. No permissions to write
5. Registry export success/failure for each key
6. Configuration file backup success/failure
7. Recent files list export success/failure
8. Multiple Excel versions installed
9. No Excel installation present
10. Partial Excel installation (some components missing)

.TESTCASES
# Mock test examples:
Describe "Backup-ExcelSettings" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Initialize-BackupDirectory { return "TestPath" }
        Mock reg { }
        Mock Get-ChildItem { return @(
            [PSCustomObject]@{
                Name = "test.xlsx"
                LastWriteTime = Get-Date
            }
        )}
        Mock Copy-Item { }
        Mock New-Item { }
        Mock Out-File { }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Backup-ExcelSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.BackupPath | Should -Be "TestPath"
        $result.Feature | Should -Be "Excel Settings"
        $result.Items | Should -BeOfType [System.Array]
        $result.Errors | Should -BeOfType [System.Array]
    }

    It "Should handle registry export failure gracefully" {
        Mock reg { throw "Registry export failed" }
        $result = Backup-ExcelSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle missing configuration paths gracefully" {
        Mock Test-Path { return $false } -ParameterFilter { $Path -like "*Microsoft\Excel*" }
        $result = Backup-ExcelSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
    }

    It "Should support WhatIf parameter" {
        $result = Backup-ExcelSettings -BackupRootPath "TestPath" -WhatIf
        $result.Success | Should -Be $true
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Backup-ExcelSettings -BackupRootPath $BackupRootPath
} 