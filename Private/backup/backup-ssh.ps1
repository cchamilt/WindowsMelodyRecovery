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

function Backup-SSHSettings {
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
            Write-Verbose "Starting backup of SSH Settings..."
            Write-Host "Backing up SSH Settings..." -ForegroundColor Blue
            
            # Validate inputs before proceeding
            if (!(Test-Path $BackupRootPath)) {
                throw [System.IO.DirectoryNotFoundException]"Backup root path not found: $BackupRootPath"
            }
            
            $backupPath = Initialize-BackupDirectory -Path "SSH" -BackupType "SSH Settings" -BackupRootPath $BackupRootPath
            
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

                # Registry paths for SSH settings
                $registryPaths = @(
                    # OpenSSH settings
                    "HKLM\SOFTWARE\OpenSSH",
                    "HKCU\Software\OpenSSH",
                    
                    # PuTTY settings
                    "HKCU\Software\SimonTatham\PuTTY",
                    "HKCU\Software\SimonTatham\PuTTY\Sessions",
                    "HKCU\Software\SimonTatham\PuTTY\SshHostKeys",
                    
                    # WinSCP settings
                    "HKCU\Software\Martin Prikryl\WinSCP 2",
                    "HKCU\Software\Martin Prikryl\WinSCP 2\Sessions",
                    
                    # SSH services
                    "HKLM\SYSTEM\CurrentControlSet\Services\OpenSSHd",
                    "HKLM\SYSTEM\CurrentControlSet\Services\ssh-agent",
                    "HKLM\SYSTEM\CurrentControlSet\Services\sshd"
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

                # Backup SSH configuration directories
                $sshPaths = @{
                    "User" = "$env:USERPROFILE\.ssh"
                    "System" = "$env:ProgramData\ssh"
                }

                foreach ($sshPath in $sshPaths.GetEnumerator()) {
                    if (Test-Path $sshPath.Value) {
                        $destPath = Join-Path $backupPath $sshPath.Key
                        if ($WhatIf) {
                            Write-Host "WhatIf: Would backup SSH $($sshPath.Key) configuration from $($sshPath.Value)"
                        } else {
                            try {
                                New-Item -ItemType Directory -Path $destPath -Force | Out-Null
                                
                                # Set proper initial permissions on backup directory
                                if (!$script:TestMode) {
                                    icacls $destPath /inheritance:r 2>$null
                                    icacls $destPath /grant:r "${env:USERNAME}:(OI)(CI)F" 2>$null
                                }
                                
                                # Copy configuration files (non-sensitive)
                                $configFiles = Get-ChildItem -Path $sshPath.Value -File | Where-Object { 
                                    $_.Name -notmatch "^(id_|.*_rsa|.*_dsa|.*_ed25519|.*_ecdsa)$" -and 
                                    $_.Extension -ne ".key" 
                                }
                                
                                foreach ($file in $configFiles) {
                                    try {
                                        Copy-Item -Path $file.FullName -Destination $destPath -Force
                                        
                                        # Save original permissions
                                        if (!$script:TestMode) {
                                            icacls "$($file.FullName)" /save "$destPath\$($file.Name).acl" 2>$null
                                        }
                                        $backedUpItems += "$($sshPath.Key)\$($file.Name)"
                                    } catch {
                                        $errors += "Failed to backup SSH config file $($file.Name): $_"
                                    }
                                }
                                
                                # Handle private keys with encryption
                                $privateKeys = Get-ChildItem -Path $sshPath.Value -File | Where-Object { 
                                    $_.Name -match "^(id_|.*_rsa|.*_dsa|.*_ed25519|.*_ecdsa)$" -and 
                                    $_.Extension -ne ".pub" 
                                }
                                
                                foreach ($key in $privateKeys) {
                                    try {
                                        if (!$script:TestMode) {
                                            $encryptedKey = "$destPath\$($key.Name).enc"
                                            # Simple base64 encoding for backup (not production encryption)
                                            $keyContent = Get-Content $key.FullName -Raw
                                            $encodedContent = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($keyContent))
                                            Set-Content -Path $encryptedKey -Value $encodedContent
                                            
                                            # Save original permissions
                                            icacls "$($key.FullName)" /save "$destPath\$($key.Name).acl" 2>$null
                                            
                                            # Set restrictive permissions on encoded key
                                            icacls $encryptedKey /inheritance:r 2>$null
                                            icacls $encryptedKey /grant:r "${env:USERNAME}:F" 2>$null
                                        }
                                        $backedUpItems += "$($sshPath.Key)\$($key.Name).enc"
                                    } catch {
                                        $errors += "Failed to backup private key $($key.Name): $_"
                                    }
                                }
                            } catch {
                                $errors += "Failed to backup SSH $($sshPath.Key) configuration: $_"
                            }
                        }
                    } else {
                        Write-Verbose "SSH $($sshPath.Key) directory not found: $($sshPath.Value)"
                    }
                }

                # Backup known_hosts files
                $knownHostsPaths = @(
                    @{ Path = "$env:USERPROFILE\.ssh\known_hosts"; Name = "known_hosts_user" },
                    @{ Path = "$env:ProgramData\ssh\known_hosts"; Name = "known_hosts_system" }
                )

                foreach ($knownHosts in $knownHostsPaths) {
                    if (Test-Path $knownHosts.Path) {
                        $destFile = Join-Path $backupPath $knownHosts.Name
                        if ($WhatIf) {
                            Write-Host "WhatIf: Would backup known_hosts file from $($knownHosts.Path)"
                        } else {
                            try {
                                Copy-Item -Path $knownHosts.Path -Destination $destFile -Force
                                $backedUpItems += $knownHosts.Name
                            } catch {
                                $errors += "Failed to backup known_hosts file $($knownHosts.Path): $_"
                            }
                        }
                    }
                }

                # Backup PuTTY configuration
                $puttyPath = "$env:APPDATA\PuTTY"
                if (Test-Path $puttyPath) {
                    $puttyBackupPath = Join-Path $backupPath "PuTTY"
                    if ($WhatIf) {
                        Write-Host "WhatIf: Would backup PuTTY configuration from $puttyPath"
                    } else {
                        try {
                            New-Item -ItemType Directory -Path $puttyBackupPath -Force | Out-Null
                            Copy-Item -Path "$puttyPath\*" -Destination $puttyBackupPath -Force -Recurse
                            $backedUpItems += "PuTTY configuration"
                        } catch {
                            $errors += "Failed to backup PuTTY configuration: $_"
                        }
                    }
                }

                # Backup WinSCP configuration
                $winscpPath = "$env:APPDATA\WinSCP"
                if (Test-Path $winscpPath) {
                    $winscpBackupPath = Join-Path $backupPath "WinSCP"
                    if ($WhatIf) {
                        Write-Host "WhatIf: Would backup WinSCP configuration from $winscpPath"
                    } else {
                        try {
                            New-Item -ItemType Directory -Path $winscpBackupPath -Force | Out-Null
                            
                            # Backup configuration files
                            $winscpFiles = Get-ChildItem -Path $winscpPath -Filter "*.ini" -ErrorAction SilentlyContinue
                            foreach ($file in $winscpFiles) {
                                Copy-Item -Path $file.FullName -Destination $winscpBackupPath -Force
                            }
                            
                            # Backup random seed file
                            $rndFile = Join-Path $winscpPath "WinSCP.rnd"
                            if (Test-Path $rndFile) {
                                Copy-Item -Path $rndFile -Destination $winscpBackupPath -Force
                            }
                            
                            $backedUpItems += "WinSCP configuration"
                        } catch {
                            $errors += "Failed to backup WinSCP configuration: $_"
                        }
                    }
                }

                # Export SSH service configuration
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export SSH service configuration"
                } else {
                    try {
                        $sshServices = @("sshd", "ssh-agent", "OpenSSHd")
                        $serviceConfig = @{}
                        
                        foreach ($serviceName in $sshServices) {
                            try {
                                $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
                                if ($service) {
                                    $serviceConfig[$serviceName] = @{
                                        Status = $service.Status
                                        StartType = $service.StartType
                                        DisplayName = $service.DisplayName
                                    }
                                }
                            } catch {
                                Write-Verbose "Could not get service information for: $serviceName"
                            }
                        }
                        
                        if ($serviceConfig.Count -gt 0) {
                            $serviceConfig | ConvertTo-Json -Depth 10 | Out-File "$backupPath\ssh_services.json" -Force
                            $backedUpItems += "ssh_services.json"
                        }
                    } catch {
                        $errors += "Failed to export SSH service configuration: $_"
                    }
                }

                # Export SSH client capabilities and features
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export SSH client capabilities"
                } else {
                    try {
                        $sshCapabilities = @{}
                        
                        # Check for OpenSSH client
                        try {
                            $sshVersion = ssh -V 2>&1
                            $sshCapabilities.OpenSSHClient = @{
                                Installed = $true
                                Version = $sshVersion
                            }
                        } catch {
                            $sshCapabilities.OpenSSHClient = @{
                                Installed = $false
                                Version = $null
                            }
                        }
                        
                        # Check for Windows capabilities
                        try {
                            $sshClientCap = Get-WindowsCapability -Online -Name "OpenSSH.Client*" -ErrorAction SilentlyContinue
                            $sshServerCap = Get-WindowsCapability -Online -Name "OpenSSH.Server*" -ErrorAction SilentlyContinue
                            
                            $sshCapabilities.WindowsCapabilities = @{
                                ClientInstalled = ($sshClientCap.State -eq "Installed")
                                ServerInstalled = ($sshServerCap.State -eq "Installed")
                            }
                        } catch {
                            $sshCapabilities.WindowsCapabilities = @{
                                ClientInstalled = $false
                                ServerInstalled = $false
                            }
                        }
                        
                        $sshCapabilities | ConvertTo-Json -Depth 10 | Out-File "$backupPath\ssh_capabilities.json" -Force
                        $backedUpItems += "ssh_capabilities.json"
                    } catch {
                        $errors += "Failed to export SSH capabilities: $_"
                    }
                }
                
                # Return object for better testing and validation
                $result = [PSCustomObject]@{
                    Success = $true
                    BackupPath = $backupPath
                    Feature = "SSH Settings"
                    Timestamp = Get-Date
                    Items = $backedUpItems
                    Errors = $errors
                }
                
                Write-Host "SSH Settings backed up successfully to: $backupPath" -ForegroundColor Green
                Write-Verbose "Backup completed successfully"
                return $result
            }
            return $false
        } catch {
            $errorRecord = $_
            $errorMessage = @(
                "Failed to backup SSH Settings"
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
Backs up SSH settings, configurations, and related tools (OpenSSH, PuTTY, WinSCP).

.DESCRIPTION
Creates a comprehensive backup of SSH-related settings including OpenSSH client/server configurations, 
SSH keys (with encoding), known hosts, PuTTY sessions and settings, WinSCP configurations, and service 
settings. Handles both user-specific and system-wide SSH configurations with proper permission preservation.

.PARAMETER BackupRootPath
The root path where the backup will be created. A subdirectory named "SSH" will be created within this path.

.PARAMETER Force
Forces the backup operation even if the destination already exists.

.PARAMETER WhatIf
Shows what would be backed up without actually performing the backup operation.

.EXAMPLE
Backup-SSHSettings -BackupRootPath "C:\Backups"

.EXAMPLE
Backup-SSHSettings -BackupRootPath "C:\Backups" -WhatIf

.NOTES
Test cases to consider:
1. Valid backup path with proper permissions
2. Invalid/nonexistent backup path
3. Empty backup path
4. No permissions to write
5. Registry export success/failure for each key
6. SSH configuration backup success/failure
7. Private key backup with encoding success/failure
8. Known hosts backup success/failure
9. PuTTY configuration backup success/failure
10. WinSCP configuration backup success/failure
11. SSH service configuration export success/failure
12. SSH capabilities export success/failure
13. JSON serialization success/failure
14. No SSH configuration scenario
15. No PuTTY/WinSCP scenario
16. SSH services not installed scenario
17. Permission handling for private keys
18. File access issues
19. Network path scenarios
20. Administrative privileges scenarios

.TESTCASES
# Mock test examples:
Describe "Backup-SSHSettings" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Initialize-BackupDirectory { return "TestPath" }
        Mock New-Item { }
        Mock Get-ChildItem { 
            param($Path, $Filter)
            if ($Path -like "*\.ssh*") {
                return @(
                    [PSCustomObject]@{ FullName = "config"; Name = "config" },
                    [PSCustomObject]@{ FullName = "id_rsa"; Name = "id_rsa" },
                    [PSCustomObject]@{ FullName = "id_rsa.pub"; Name = "id_rsa.pub" }
                )
            }
            return @()
        }
        Mock Get-Service { return @{
            Status = "Running"
            StartType = "Automatic"
            DisplayName = "OpenSSH SSH Server"
        }}
        Mock Get-WindowsCapability { return @{
            State = "Installed"
        }}
        Mock Get-Content { return "ssh config content" }
        Mock Set-Content { }
        Mock ConvertTo-Json { return '{"test":"value"}' }
        Mock Out-File { }
        Mock Copy-Item { }
        Mock icacls { }
        Mock reg { $global:LASTEXITCODE = 0 }
        Mock ssh { return "OpenSSH_8.1p1" }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Backup-SSHSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.BackupPath | Should -Be "TestPath"
        $result.Feature | Should -Be "SSH Settings"
        $result.Items | Should -BeOfType [System.Array]
        $result.Errors | Should -BeOfType [System.Array]
    }

    It "Should handle registry export failure gracefully" {
        Mock reg { $global:LASTEXITCODE = 1; return "Error" }
        $result = Backup-SSHSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle SSH config backup failure gracefully" {
        Mock Copy-Item { throw "File copy failed" }
        $result = Backup-SSHSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should support WhatIf parameter" {
        $result = Backup-SSHSettings -BackupRootPath "TestPath" -WhatIf
        $result.Success | Should -Be $true
    }

    It "Should handle private key encoding failure gracefully" {
        Mock Set-Content { throw "Encoding failed" }
        $result = Backup-SSHSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle service configuration failure gracefully" {
        Mock Get-Service { throw "Service access denied" }
        $result = Backup-SSHSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle no SSH configuration scenario" {
        Mock Test-Path { return $false }
        $result = Backup-SSHSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
    }

    It "Should handle SSH capabilities query failure gracefully" {
        Mock Get-WindowsCapability { throw "Capability query failed" }
        $result = Backup-SSHSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Backup-SSHSettings -BackupRootPath $BackupRootPath
} 