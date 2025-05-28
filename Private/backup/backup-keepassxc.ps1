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

function Backup-KeePassXCSettings {
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
            Write-Verbose "Starting backup of KeePassXC Settings..."
            Write-Host "Backing up KeePassXC Settings..." -ForegroundColor Blue
            
            # Validate inputs before proceeding
            if (!(Test-Path $BackupRootPath)) {
                throw [System.IO.DirectoryNotFoundException]"Backup root path not found: $BackupRootPath"
            }
            
            $backupPath = Initialize-BackupDirectory -Path "KeePassXC" -BackupType "KeePassXC Settings" -BackupRootPath $BackupRootPath
            
            if ($backupPath) {
                $backedUpItems = @()
                $errors = @()
                
                # Export KeePassXC registry settings
                $regPaths = @(
                    # KeePassXC settings
                    "HKCU\Software\KeePassXC",
                    "HKCU\Software\KeePassXC\KeePassXC",
                    "HKCU\Software\KeePassXC\KeePassXC\Auto-Type",
                    "HKCU\Software\KeePassXC\KeePassXC\Browser Integration",
                    "HKCU\Software\KeePassXC\KeePassXC\General",
                    "HKCU\Software\KeePassXC\KeePassXC\GUI",
                    "HKCU\Software\KeePassXC\KeePassXC\Security",
                    "HKCU\Software\KeePassXC\KeePassXC\SSHAgent"
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

                # Backup KeePassXC configuration files
                $configPaths = @{
                    "Config" = "$env:APPDATA\KeePassXC"
                    "Plugins" = "$env:APPDATA\KeePassXC\plugins"
                    "KeyFiles" = "$env:APPDATA\KeePassXC\keyfiles"
                    "AutoType" = "$env:APPDATA\KeePassXC\autotype"
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

                # Export browser integration settings
                $browserPaths = @{
                    "Chrome" = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Local Extension Settings\oboonakemofpalcgghocfoadofidjkkk"
                    "Firefox" = "$env:APPDATA\Mozilla\Firefox\Profiles\*\browser-extension-data\keepassxc-browser@keepassxc.org"
                    "Edge" = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Local Extension Settings\pdffhmdngciaglkoonimfcmckehcpafo"
                }

                $browserPath = Join-Path $backupPath "BrowserIntegration"
                if ($WhatIf) {
                    Write-Host "WhatIf: Would create browser integration directory at $browserPath"
                } else {
                    New-Item -ItemType Directory -Force -Path $browserPath | Out-Null
                }

                foreach ($browser in $browserPaths.GetEnumerator()) {
                    if (Test-Path $browser.Value) {
                        $destPath = Join-Path $browserPath $browser.Key
                        if ($WhatIf) {
                            Write-Host "WhatIf: Would copy browser integration settings from $($browser.Value) to $destPath"
                        } else {
                            try {
                                New-Item -ItemType Directory -Path $destPath -Force | Out-Null
                                Copy-Item -Path "$($browser.Value)\*" -Destination $destPath -Recurse -Force
                                $backedUpItems += "BrowserIntegration\$($browser.Key)"
                            } catch {
                                $errors += "Failed to backup browser integration settings for $($browser.Key) : $_"
                            }
                        }
                    }
                }
                
                # Return object for better testing and validation
                $result = [PSCustomObject]@{
                    Success = $true
                    BackupPath = $backupPath
                    Feature = "KeePassXC Settings"
                    Timestamp = Get-Date
                    Items = $backedUpItems
                    Errors = $errors
                }
                
                Write-Host "KeePassXC Settings backed up successfully to: $backupPath" -ForegroundColor Green
                Write-Verbose "Backup completed successfully"
                return $result
            }
            return $false
        } catch {
            $errorRecord = $_
            $errorMessage = @(
                "Failed to backup KeePassXC Settings"
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
    Export-ModuleMember -Function Backup-KeePassXCSettings
}

<#
.SYNOPSIS
Backs up KeePassXC settings and configuration.

.DESCRIPTION
Creates a backup of KeePassXC settings, including registry settings, configuration files, plugins, key files, and browser integration settings.

.EXAMPLE
Backup-KeePassXCSettings -BackupRootPath "C:\Backups"

.NOTES
Test cases to consider:
1. Valid backup path with proper permissions
2. Invalid/nonexistent backup path
3. Empty backup path
4. No permissions to write
5. Registry export success/failure for each key
6. Configuration file backup success/failure
7. Browser integration settings backup success/failure

.TESTCASES
# Mock test examples:
Describe "Backup-KeePassXCSettings" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Initialize-BackupDirectory { return "TestPath" }
        Mock reg { }
        Mock Copy-Item { }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Backup-KeePassXCSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.BackupPath | Should -Be "TestPath"
        $result.Feature | Should -Be "KeePassXC Settings"
    }

    It "Should handle registry export failure gracefully" {
        Mock reg { throw "Registry export failed" }
        $result = Backup-KeePassXCSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Backup-KeePassXCSettings -BackupRootPath $BackupRootPath
} 