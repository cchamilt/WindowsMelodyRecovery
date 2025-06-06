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
                
                # Create registry backup directory
                $registryPath = Join-Path $backupPath "Registry"
                if ($WhatIf) {
                    Write-Host "WhatIf: Would create registry backup directory at $registryPath"
                } else {
                    New-Item -ItemType Directory -Force -Path $registryPath | Out-Null
                }

                # Export power schemes list
                try {
                    if ($WhatIf) {
                        Write-Host "WhatIf: Would export power schemes list"
                    } else {
                        $powerSchemes = powercfg /list
                        $schemeFile = Join-Path $backupPath "power_schemes.txt"
                        $powerSchemes | Out-File $schemeFile -Force
                        $backedUpItems += "power_schemes.txt"
                    }
                } catch {
                    $errors += "Failed to export power schemes list: $_"
                }

                # Export active power scheme
                try {
                    if ($WhatIf) {
                        Write-Host "WhatIf: Would export active power scheme"
                    } else {
                        $activeScheme = powercfg /getactivescheme
                        $activeFile = Join-Path $backupPath "active_scheme.txt"
                        $activeScheme | Out-File $activeFile -Force
                        $backedUpItems += "active_scheme.txt"
                    }
                } catch {
                    $errors += "Failed to export active power scheme: $_"
                }

                # Export detailed power settings for each scheme
                if (!$WhatIf) {
                    try {
                        $powerSchemes = powercfg /list
                        foreach ($scheme in $powerSchemes) {
                            if ($scheme -match "Power Scheme GUID: ([a-fA-F0-9\-]+)\s+\((.+)\)") {
                                $guid = $matches[1].Trim()
                                $schemeName = $matches[2].Trim()
                                # Sanitize filename
                                $safeFileName = $schemeName -replace '[\\/:*?"<>|]', '_'
                                $schemeFile = Join-Path $backupPath "scheme_$safeFileName.txt"
                                
                                try {
                                    powercfg /query $guid | Out-File $schemeFile -Force
                                    $backedUpItems += "scheme_$safeFileName.txt"
                                } catch {
                                    $errors += "Failed to export power settings for scheme $schemeName : $_"
                                }
                            }
                        }
                    } catch {
                        $errors += "Failed to process power schemes for detailed export: $_"
                    }
                } else {
                    Write-Host "WhatIf: Would export detailed power settings for each scheme"
                }

                # Export power capabilities
                try {
                    if ($WhatIf) {
                        Write-Host "WhatIf: Would export power capabilities"
                    } else {
                        $capabilities = powercfg /availablesleepstates
                        $capFile = Join-Path $backupPath "power_capabilities.txt"
                        $capabilities | Out-File $capFile -Force
                        $backedUpItems += "power_capabilities.txt"
                    }
                } catch {
                    $errors += "Failed to export power capabilities: $_"
                }

                # Export battery report (if available)
                try {
                    if ($WhatIf) {
                        Write-Host "WhatIf: Would export battery report"
                    } else {
                        $batteryFile = Join-Path $backupPath "battery_report.html"
                        powercfg /batteryreport /output $batteryFile 2>$null
                        if (Test-Path $batteryFile) {
                            $backedUpItems += "battery_report.html"
                        }
                    }
                } catch {
                    Write-Verbose "Battery report not available (likely desktop system)"
                }

                # Export energy report
                try {
                    if ($WhatIf) {
                        Write-Host "WhatIf: Would export energy report"
                    } else {
                        $energyFile = Join-Path $backupPath "energy_report.html"
                        powercfg /energy /output $energyFile 2>$null
                        if (Test-Path $energyFile) {
                            $backedUpItems += "energy_report.html"
                        }
                    }
                } catch {
                    Write-Verbose "Energy report generation failed or not available"
                }

                # Export power settings registry
                $regPaths = @(
                    "HKLM\SYSTEM\CurrentControlSet\Control\Power",
                    "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerSettings",
                    "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling",
                    "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power",
                    "HKCU\Control Panel\PowerCfg",
                    "HKCU\System\CurrentControlSet\Control\Power",
                    "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\PowerOptions"
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
                                $errors += "Failed to export registry path $regPath : $_"
                            }
                        }
                    } else {
                        Write-Verbose "Registry key not found: $regPath"
                    }
                }

                # Export power button and lid settings
                try {
                    if ($WhatIf) {
                        Write-Host "WhatIf: Would export power button and lid settings"
                    } else {
                        $buttonSettings = @{}
                        
                        # Get power button settings
                        try {
                            $powerButtonAC = powercfg /query SCHEME_CURRENT SUB_BUTTONS PBUTTONACTION
                            $powerButtonDC = powercfg /query SCHEME_CURRENT SUB_BUTTONS PBUTTONACTION
                            $buttonSettings["PowerButton"] = @{
                                "AC" = $powerButtonAC
                                "DC" = $powerButtonDC
                            }
                        } catch {
                            Write-Verbose "Could not retrieve power button settings"
                        }
                        
                        # Get sleep button settings
                        try {
                            $sleepButtonAC = powercfg /query SCHEME_CURRENT SUB_BUTTONS SBUTTONACTION
                            $sleepButtonDC = powercfg /query SCHEME_CURRENT SUB_BUTTONS SBUTTONACTION
                            $buttonSettings["SleepButton"] = @{
                                "AC" = $sleepButtonAC
                                "DC" = $sleepButtonDC
                            }
                        } catch {
                            Write-Verbose "Could not retrieve sleep button settings"
                        }
                        
                        # Get lid close settings
                        try {
                            $lidCloseAC = powercfg /query SCHEME_CURRENT SUB_BUTTONS LIDACTION
                            $lidCloseDC = powercfg /query SCHEME_CURRENT SUB_BUTTONS LIDACTION
                            $buttonSettings["LidClose"] = @{
                                "AC" = $lidCloseAC
                                "DC" = $lidCloseDC
                            }
                        } catch {
                            Write-Verbose "Could not retrieve lid close settings"
                        }
                        
                        if ($buttonSettings.Count -gt 0) {
                            $buttonFile = Join-Path $backupPath "button_settings.json"
                            $buttonSettings | ConvertTo-Json -Depth 10 | Out-File $buttonFile -Force
                            $backedUpItems += "button_settings.json"
                        }
                    }
                } catch {
                    $errors += "Failed to export power button and lid settings: $_"
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
Backs up Windows Power settings and configuration.

.DESCRIPTION
Creates a comprehensive backup of Windows Power settings, including power schemes, active scheme configuration,
power capabilities, battery reports, energy reports, registry settings, and power button/lid configurations.
Supports both desktop and laptop power management settings.

.PARAMETER BackupRootPath
The root path where the backup will be created. A subdirectory named "Power" will be created within this path.

.PARAMETER Force
Forces the backup operation even if the destination already exists.

.PARAMETER WhatIf
Shows what would be backed up without actually performing the backup operation.

.EXAMPLE
Backup-PowerSettings -BackupRootPath "C:\Backups"

.EXAMPLE
Backup-PowerSettings -BackupRootPath "C:\Backups" -WhatIf

.NOTES
Test cases to consider:
1. Valid backup path with proper permissions
2. Invalid/nonexistent backup path
3. Empty backup path
4. No permissions to write
5. Power scheme export success/failure
6. Active scheme export success/failure
7. Registry export success/failure for each key
8. Battery report generation (laptop vs desktop)
9. Energy report generation success/failure
10. Power capabilities export success/failure
11. Button and lid settings export success/failure
12. Custom power schemes
13. Modified power settings
14. Laptop-specific settings (battery, lid)
15. Desktop-specific settings
16. UPS configurations
17. Network path scenarios
18. Administrative privileges scenarios
19. Power service availability
20. Corrupted power configuration

.TESTCASES
# Mock test examples:
Describe "Backup-PowerSettings" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Initialize-BackupDirectory { return "TestPath" }
        Mock New-Item { }
        Mock powercfg { 
            param($Command)
            switch ($Command) {
                "/list" { return "Power Scheme GUID: 12345678-1234-1234-1234-123456789012 (Balanced)" }
                "/getactivescheme" { return "Power Scheme GUID: 12345678-1234-1234-1234-123456789012 (Balanced)" }
                "/availablesleepstates" { return "Sleep states available: S1 S3 S4 S5" }
                default { return "Mock powercfg output" }
            }
        }
        Mock Out-File { }
        Mock ConvertTo-Json { return '{"test":"value"}' }
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
        $result.Items | Should -BeOfType [System.Array]
        $result.Errors | Should -BeOfType [System.Array]
    }

    It "Should handle power scheme export failure gracefully" {
        Mock powercfg { throw "Power scheme export failed" }
        $result = Backup-PowerSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle registry export failure gracefully" {
        Mock reg { throw "Registry export failed" }
        $result = Backup-PowerSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should support WhatIf parameter" {
        $result = Backup-PowerSettings -BackupRootPath "TestPath" -WhatIf
        $result.Success | Should -Be $true
    }

    It "Should handle button settings export failure gracefully" {
        Mock ConvertTo-Json { throw "JSON conversion failed" }
        $result = Backup-PowerSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle missing power capabilities gracefully" {
        Mock powercfg { 
            param($Command)
            if ($Command -eq "/availablesleepstates") { throw "Not available" }
            return "Mock output"
        }
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