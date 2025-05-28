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

function Backup-PowerSettings {
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
            Write-Verbose "Starting backup of Power Settings..."
            Write-Host "Backing up Power Settings..." -ForegroundColor Blue
            
            # Validate inputs before proceeding
            if (!(Test-Path $BackupRootPath)) {
                throw [System.IO.DirectoryNotFoundException]"Backup root path not found: $BackupRootPath"
            }
            
            $backupPath = Initialize-BackupDirectory -Path "Power" -BackupType "Power Settings" -BackupRootPath $BackupRootPath
            
            if ($backupPath) {
                $backedUpItems = @()
                $errors = @()
                
                # Export power settings
                $powerSchemes = @()
                try {
                    $powerSchemes = powercfg /list
                    $schemeFile = Join-Path $backupPath "power_schemes.txt"
                    if ($WhatIf) {
                        Write-Host "WhatIf: Would export power schemes to $schemeFile"
                    } else {
                        $powerSchemes | Out-File $schemeFile
                        $backedUpItems += "power_schemes.txt"
                    }
                } catch {
                    $errors += "Failed to export power schemes : $_"
                }

                # Export active power scheme
                try {
                    $activeScheme = powercfg /getactivescheme
                    $activeFile = Join-Path $backupPath "active_scheme.txt"
                    if ($WhatIf) {
                        Write-Host "WhatIf: Would export active power scheme to $activeFile"
                    } else {
                        $activeScheme | Out-File $activeFile
                        $backedUpItems += "active_scheme.txt"
                    }
                } catch {
                    $errors += "Failed to export active power scheme : $_"
                }

                # Export power settings for each scheme
                foreach ($scheme in $powerSchemes) {
                    if ($scheme -match "Power Scheme GUID: ([^(]+)") {
                        $guid = $matches[1].Trim()
                        $schemeName = $scheme -replace ".*\((.*)\).*", '$1'
                        $schemeFile = Join-Path $backupPath "$schemeName.txt"
                        if ($WhatIf) {
                            Write-Host "WhatIf: Would export power settings for scheme $schemeName to $schemeFile"
                        } else {
                            try {
                                powercfg /query $guid | Out-File $schemeFile
                                $backedUpItems += "$schemeName.txt"
                            } catch {
                                $errors += "Failed to export power settings for scheme $schemeName : $_"
                            }
                        }
                    }
                }

                # Export power settings registry
                $regPaths = @(
                    "HKLM\SYSTEM\CurrentControlSet\Control\Power",
                    "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerSettings",
                    "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling",
                    "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling\PowerThrottlingOff",
                    "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling\PowerThrottlingOn"
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
                
                # Return object for better testing and validation
                $result = [PSCustomObject]@{
                    Success = $true
                    BackupPath = $backupPath
                    Feature = "Power Settings"
                    Timestamp = Get-Date
                    Items = $backedUpItems
                    Errors = $errors
                }
                
                Write-Host "Power Settings backed up successfully to: $backupPath" -ForegroundColor Green
                Write-Verbose "Backup completed successfully"
                return $result
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
            
            Write-Error $errorMessage
            Write-Verbose "Backup failed"
            throw  # Re-throw for proper error handling
        }
    }
}

# Export the function if being imported as a module
if ($MyInvocation.Line -eq "") {
    Export-ModuleMember -Function Backup-PowerSettings
}

<#
.SYNOPSIS
Backs up Windows power settings and configuration.

.DESCRIPTION
Creates a backup of Windows power settings, including power schemes, active scheme, and registry settings.

.EXAMPLE
Backup-PowerSettings -BackupRootPath "C:\Backups"

.NOTES
Test cases to consider:
1. Valid backup path with proper permissions
2. Invalid/nonexistent backup path
3. Empty backup path
4. No permissions to write
5. Power scheme export success/failure
6. Active scheme export success/failure
7. Registry export success/failure

.TESTCASES
# Mock test examples:
Describe "Backup-PowerSettings" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Initialize-BackupDirectory { return "TestPath" }
        Mock powercfg { return "Power Scheme GUID: 12345678-1234-1234-1234-123456789012 (Balanced)" }
        Mock reg { }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Backup-PowerSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.BackupPath | Should -Be "TestPath"
        $result.Feature | Should -Be "Power Settings"
    }

    It "Should handle power scheme export failure gracefully" {
        Mock powercfg { throw "Power scheme export failed" }
        $result = Backup-PowerSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Backup-PowerSettings -BackupRootPath $BackupRootPath
}