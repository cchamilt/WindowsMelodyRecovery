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
                
                # Export Outlook registry settings
                $regPaths = @(
                    # Outlook 2016/365 settings
                    "HKCU\Software\Microsoft\Office\16.0\Outlook",
                    "HKCU\Software\Microsoft\Office\16.0\Outlook\Preferences",
                    "HKCU\Software\Microsoft\Office\16.0\Outlook\Profiles",
                    "HKCU\Software\Microsoft\Office\16.0\Outlook\Security",
                    "HKCU\Software\Microsoft\Office\16.0\Outlook\AutoNameCheck",
                    "HKCU\Software\Microsoft\Office\16.0\Outlook\AutoNameCheck\AutoComplete",
                    "HKCU\Software\Microsoft\Office\16.0\Outlook\AutoNameCheck\Nickname",
                    "HKCU\Software\Microsoft\Office\16.0\Outlook\AutoNameCheck\OneOff",
                    
                    # Outlook 2013 settings
                    "HKCU\Software\Microsoft\Office\15.0\Outlook",
                    "HKCU\Software\Microsoft\Office\15.0\Outlook\Preferences",
                    "HKCU\Software\Microsoft\Office\15.0\Outlook\Profiles",
                    "HKCU\Software\Microsoft\Office\15.0\Outlook\Security",
                    "HKCU\Software\Microsoft\Office\15.0\Outlook\AutoNameCheck",
                    "HKCU\Software\Microsoft\Office\15.0\Outlook\AutoNameCheck\AutoComplete",
                    "HKCU\Software\Microsoft\Office\15.0\Outlook\AutoNameCheck\Nickname",
                    "HKCU\Software\Microsoft\Office\15.0\Outlook\AutoNameCheck\OneOff",
                    
                    # Outlook 2010 settings
                    "HKCU\Software\Microsoft\Office\14.0\Outlook",
                    "HKCU\Software\Microsoft\Office\14.0\Outlook\Preferences",
                    "HKCU\Software\Microsoft\Office\14.0\Outlook\Profiles",
                    "HKCU\Software\Microsoft\Office\14.0\Outlook\Security",
                    "HKCU\Software\Microsoft\Office\14.0\Outlook\AutoNameCheck",
                    "HKCU\Software\Microsoft\Office\14.0\Outlook\AutoNameCheck\AutoComplete",
                    "HKCU\Software\Microsoft\Office\14.0\Outlook\AutoNameCheck\Nickname",
                    "HKCU\Software\Microsoft\Office\14.0\Outlook\AutoNameCheck\OneOff",
                    
                    # System-wide Outlook settings
                    "HKLM\SOFTWARE\Microsoft\Office\16.0\Outlook",
                    "HKLM\SOFTWARE\Microsoft\Office\15.0\Outlook",
                    "HKLM\SOFTWARE\Microsoft\Office\14.0\Outlook"
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

                # Backup Outlook configuration files
                $configPaths = @{
                    "Signatures" = "$env:APPDATA\Microsoft\Signatures"
                    "Templates" = "$env:APPDATA\Microsoft\Templates"
                    "Rules" = "$env:APPDATA\Microsoft\Outlook"
                    "Forms" = "$env:APPDATA\Microsoft\Forms"
                    "Stationery" = "$env:APPDATA\Microsoft\Stationery"
                    "QuickAccess" = "$env:APPDATA\Microsoft\Windows\Recent\Outlook.lnk"
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

                # Export profile information
                $profilePath = Join-Path $backupPath "Profiles"
                if ($WhatIf) {
                    Write-Host "WhatIf: Would create profiles directory at $profilePath"
                } else {
                    New-Item -ItemType Directory -Force -Path $profilePath | Out-Null
                }

                # Get Outlook profiles
                $profiles = @()
                try {
                    $profiles += Get-ChildItem "HKCU:\Software\Microsoft\Office\16.0\Outlook\Profiles" -ErrorAction SilentlyContinue
                    $profiles += Get-ChildItem "HKCU:\Software\Microsoft\Office\15.0\Outlook\Profiles" -ErrorAction SilentlyContinue
                    $profiles += Get-ChildItem "HKCU:\Software\Microsoft\Office\14.0\Outlook\Profiles" -ErrorAction SilentlyContinue
                    
                    if ($profiles.Count -gt 0) {
                        $profileFile = Join-Path $profilePath "profiles.json"
                        if ($WhatIf) {
                            Write-Host "WhatIf: Would export profile information to $profileFile"
                        } else {
                            $profiles | Select-Object Name, LastWriteTime | ConvertTo-Json | Out-File $profileFile
                            $backedUpItems += "Profiles\profiles.json"
                        }
                    }
                } catch {
                    $errors += "Failed to backup profile information : $_"
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

# Export the function if being imported as a module
if ($MyInvocation.Line -eq "") {
    Export-ModuleMember -Function Backup-OutlookSettings
}

<#
.SYNOPSIS
Backs up Outlook settings and configuration.

.DESCRIPTION
Creates a backup of Outlook settings, including registry settings, signatures, templates, rules, forms, and profile information.

.EXAMPLE
Backup-OutlookSettings -BackupRootPath "C:\Backups"

.NOTES
Test cases to consider:
1. Valid backup path with proper permissions
2. Invalid/nonexistent backup path
3. Empty backup path
4. No permissions to write
5. Registry export success/failure for each key
6. Configuration file backup success/failure
7. Profile information export success/failure

.TESTCASES
# Mock test examples:
Describe "Backup-OutlookSettings" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Initialize-BackupDirectory { return "TestPath" }
        Mock reg { }
        Mock Get-ChildItem { return @(
            [PSCustomObject]@{
                Name = "Default"
                LastWriteTime = Get-Date
            }
        )}
        Mock Copy-Item { }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Backup-OutlookSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.BackupPath | Should -Be "TestPath"
        $result.Feature | Should -Be "Outlook Settings"
    }

    It "Should handle registry export failure gracefully" {
        Mock reg { throw "Registry export failed" }
        $result = Backup-OutlookSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Backup-OutlookSettings -BackupRootPath $BackupRootPath
} 