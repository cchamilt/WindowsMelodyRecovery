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

function Backup-WSLSSHSettings {
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
            Write-Verbose "Starting backup of WSL SSH Settings..."
            Write-Host "Backing up WSL SSH Settings..." -ForegroundColor Blue
            
            # Validate inputs before proceeding
            if (!(Test-Path $BackupRootPath)) {
                throw [System.IO.DirectoryNotFoundException]"Backup root path not found: $BackupRootPath"
            }
            
            $backupPath = Initialize-BackupDirectory -Path "WSLSSH" -BackupType "WSL SSH Settings" -BackupRootPath $BackupRootPath
            
            if ($backupPath) {
                $backedUpItems = @()
                $errors = @()
                
                # Create SSH backup directory
                $sshConfigPath = Join-Path $backupPath "Config"
                $sshKeysPath = Join-Path $backupPath "Keys"
                $sshKnownHostsPath = Join-Path $backupPath "KnownHosts"
                
                if ($WhatIf) {
                    Write-Host "WhatIf: Would create SSH backup directories"
                } else {
                    New-Item -ItemType Directory -Force -Path $sshConfigPath | Out-Null
                    New-Item -ItemType Directory -Force -Path $sshKeysPath | Out-Null
                    New-Item -ItemType Directory -Force -Path $sshKnownHostsPath | Out-Null
                }

                # Export SSH config with proper error handling
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export SSH config"
                } else {
                    try {
                        $sshConfig = wsl bash -c 'if [ -f ~/.ssh/config ]; then cat ~/.ssh/config; fi' 2>$null
                        if ($sshConfig) {
                            $sshConfig | Out-File "$sshConfigPath\config" -Encoding utf8
                            $backedUpItems += "SSH config"
                        }
                    } catch {
                        $errors += "Failed to export SSH config : $_"
                    }
                }

                # Export public keys with proper error handling
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export public keys"
                } else {
                    try {
                        $pubKeys = wsl bash -c 'for key in ~/.ssh/*.pub; do if [ -f "$key" ]; then cat "$key"; echo ""; fi; done' 2>$null
                        if ($pubKeys) {
                            $pubKeys | Out-File "$sshKeysPath\public_keys.txt" -Encoding utf8
                            $backedUpItems += "Public keys"
                        }
                    } catch {
                        $errors += "Failed to export public keys : $_"
                    }
                }

                # Export known_hosts with proper error handling
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export known hosts"
                } else {
                    try {
                        $knownHosts = wsl bash -c 'if [ -f ~/.ssh/known_hosts ]; then cat ~/.ssh/known_hosts; fi' 2>$null
                        if ($knownHosts) {
                            $knownHosts | Out-File "$sshKnownHostsPath\known_hosts" -Encoding utf8
                            $backedUpItems += "Known hosts"
                        }
                    } catch {
                        $errors += "Failed to export known hosts : $_"
                    }
                }

                # Export system-wide SSH config with proper error handling
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export system SSH config"
                } else {
                    try {
                        $systemConfig = wsl bash -c 'if [ -f /etc/ssh/ssh_config ]; then sudo cat /etc/ssh/ssh_config; fi' 2>$null
                        if ($systemConfig) {
                            $systemConfig | Out-File "$sshConfigPath\system_config" -Encoding utf8
                            $backedUpItems += "System SSH config"
                        }
                    } catch {
                        $errors += "Failed to export system SSH config : $_"
                    }
                }

                # Export private keys (safely)
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export private keys"
                } else {
                    try {
                        $privateKeys = @()
                        $privateKeysList = wsl bash -c 'for key in ~/.ssh/id_*; do if [ -f "$key" ] && [[ ! "$key" =~ \.pub$ ]]; then echo "$key"; fi; done' 2>$null
                        if ($privateKeysList) {
                            $privateKeysList -split "`n" | ForEach-Object {
                                $keyPath = $_.Trim()
                                if (![string]::IsNullOrEmpty($keyPath)) {
                                    $keyName = Split-Path $keyPath -Leaf
                                    try {
                                        # Create a temporary copy with safe permissions
                                        wsl bash -c "cp '$keyPath' '/tmp/$keyName' && chmod 644 '/tmp/$keyName' && cat '/tmp/$keyName' && rm '/tmp/$keyName'" > "$sshKeysPath\$keyName" 2>$null
                                        $privateKeys += $keyName
                                        $backedUpItems += "Private key: $keyName"
                                    } catch {
                                        $errors += "Failed to export private key $keyName : $_"
                                    }
                                }
                            }
                        }
                    } catch {
                        $errors += "Failed to export private keys : $_"
                    }
                }
                
                # Return object for better testing and validation
                $result = [PSCustomObject]@{
                    Success = $true
                    BackupPath = $backupPath
                    Feature = "WSL SSH Settings"
                    Timestamp = Get-Date
                    Items = $backedUpItems
                    Errors = $errors
                }
                
                Write-Host "WSL SSH Settings backed up successfully to: $backupPath" -ForegroundColor Green
                Write-Verbose "Backup completed successfully"
                return $result
            }
            return $false
        } catch {
            $errorRecord = $_
            $errorMessage = @(
                "Failed to backup WSL SSH Settings"
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
    Export-ModuleMember -Function Backup-WSLSSHSettings
}

<#
.SYNOPSIS
Backs up WSL SSH settings and configuration.

.DESCRIPTION
Creates a backup of WSL SSH settings, including SSH config, public and private keys, known hosts, and system-wide SSH configuration.

.EXAMPLE
Backup-WSLSSHSettings -BackupRootPath "C:\Backups"

.NOTES
Test cases to consider:
1. Valid backup path with proper permissions
2. Invalid/nonexistent backup path
3. Empty backup path
4. No permissions to write
5. WSL not installed/enabled
6. SSH config exists/doesn't exist
7. Keys exist/don't exist
8. Known hosts exists/doesn't exist
9. System config exists/doesn't exist

.TESTCASES
# Mock test examples:
Describe "Backup-WSLSSHSettings" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Initialize-BackupDirectory { return "TestPath" }
        Mock wsl { return "test config" }
        Mock Out-File { }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Backup-WSLSSHSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.BackupPath | Should -Be "TestPath"
        $result.Feature | Should -Be "WSL SSH Settings"
    }

    It "Should handle WSL command failure gracefully" {
        Mock wsl { throw "WSL command failed" }
        $result = Backup-WSLSSHSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Backup-WSLSSHSettings -BackupRootPath $BackupRootPath
} 