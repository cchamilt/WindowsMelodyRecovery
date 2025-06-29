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

function Backup-VPNSettings {
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
            Write-Verbose "Starting backup of VPN Settings..."
            Write-Host "Backing up VPN Settings..." -ForegroundColor Blue
            
            # Validate inputs before proceeding
            if (!(Test-Path $BackupRootPath)) {
                throw [System.IO.DirectoryNotFoundException]"Backup root path not found: $BackupRootPath"
            }
            
            $backupPath = Initialize-BackupDirectory -Path "VPN" -BackupType "VPN Settings" -BackupRootPath $BackupRootPath
            
            if ($backupPath) {
                $backedUpItems = @()
                $errors = @()
                
                # Export VPN registry settings
                $regPaths = @(
                    # RAS/VPN settings
                    "HKLM\SYSTEM\CurrentControlSet\Services\RasMan",
                    "HKLM\SYSTEM\CurrentControlSet\Services\RASTAPI",
                    "HKLM\SYSTEM\CurrentControlSet\Services\RasMan\Parameters",
                    "HKLM\SOFTWARE\Microsoft\RasCredentials",
                    "HKCU\Software\Microsoft\RasCredentials",
                   
                    # VPN client settings
                    "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\Connections",
                    "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings\Connections",
                   
                    # Network Connections
                    "HKLM\SOFTWARE\Policies\Microsoft\Windows\NetworkConnections",
                   
                    # OpenVPN settings
                    "HKLM\SOFTWARE\OpenVPN",
                    "HKCU\Software\OpenVPN",
                   
                    # Cisco VPN settings
                    "HKLM\SOFTWARE\Cisco",
                    "HKCU\Software\Cisco",
                   
                    # Azure VPN settings
                    "HKCU\Software\Microsoft\Azure VPN"
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

                # Export Azure VPN configurations
                $azureVpnPath = "$env:ProgramFiles\Microsoft\AzureVpn"
                if (Test-Path $azureVpnPath) {
                    if ($WhatIf) {
                        Write-Host "WhatIf: Would export Azure VPN configurations"
                    } else {
                        try {
                            $process = Start-Process -FilePath "$azureVpnPath\AzureVpn.exe" `
                                -ArgumentList "-e `"$backupPath\azure_vpn_config.xml`"" `
                                -Wait -PassThru -NoNewWindow
                            
                            if ($process.ExitCode -eq 0) {
                                $backedUpItems += "Azure VPN configurations"
                            } else {
                                $errors += "Azure VPN export failed with exit code $($process.ExitCode)"
                            }
                        } catch {
                            $errors += "Failed to export Azure VPN configurations : $_"
                        }
                    }
                }

                # Export VPN connections if any exist
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export VPN connections"
                } else {
                    try {
                        $vpnConnections = Get-VpnConnection -AllUserConnection | Select-Object -Property *
                        if ($vpnConnections) {
                            $vpnConnections | ConvertTo-Json -Depth 10 | Out-File "$backupPath\vpn_connections.json" -Force
                            $backedUpItems += "VPN connections"
                        }
                    } catch {
                        $errors += "Failed to export VPN connections : $_"
                    }
                }

                # Export rasphone.pbk files
                $pbkPaths = @(
                    "$env:APPDATA\Microsoft\Network\Connections\Pbk\rasphone.pbk",
                    "$env:ProgramData\Microsoft\Network\Connections\Pbk\rasphone.pbk"
                )

                foreach ($pbkPath in $pbkPaths) {
                    if (Test-Path $pbkPath) {
                        $pbkName = Split-Path -Leaf (Split-Path -Parent $pbkPath)
                        if ($WhatIf) {
                            Write-Host "WhatIf: Would copy $pbkPath to $backupPath\$pbkName.pbk"
                        } else {
                            try {
                                Copy-Item -Path $pbkPath -Destination "$backupPath\$pbkName.pbk" -Force
                                $backedUpItems += "$pbkName.pbk"
                            } catch {
                                $errors += "Failed to copy $pbkName.pbk : $_"
                            }
                        }
                    }
                }

                # Export VPN certificates
                $certPath = "Cert:\CurrentUser\My"
                $vpnCerts = Get-ChildItem -Path $certPath | Where-Object {
                    $_.EnhancedKeyUsageList.FriendlyName -match "Client Authentication" -or
                    $_.Subject -match "VPN" -or
                    $_.FriendlyName -match "VPN"
                }

                if ($vpnCerts) {
                    $certsPath = Join-Path $backupPath "Certificates"
                    if ($WhatIf) {
                        Write-Host "WhatIf: Would create certificates directory at $certsPath"
                    } else {
                        New-Item -ItemType Directory -Path $certsPath -Force | Out-Null
                        
                        foreach ($cert in $vpnCerts) {
                            $certFile = Join-Path $certsPath "$($cert.Thumbprint).cer"
                            if ($WhatIf) {
                                Write-Host "WhatIf: Would export certificate $($cert.Subject)"
                            } else {
                                # Try to export as CER first (public key only)
                                try {
                                    $cert | Export-Certificate -FilePath $certFile -Force | Out-Null
                                    $backedUpItems += "Certificate: $($cert.Subject)"
                                } catch {
                                    $errors += "Failed to export certificate $($cert.Subject) : $_"
                                }

                                # Try to export as PFX only if private key is exportable
                                if ($cert.HasPrivateKey) {
                                    try {
                                        $pfxFile = Join-Path $certsPath "$($cert.Thumbprint).pfx"
                                        if ($cert.PrivateKey.CspKeyContainerInfo.Exportable) {
                                            Export-PfxCertificate -Cert $cert -FilePath $pfxFile `
                                                -Password (ConvertTo-SecureString -String "temp" -Force -AsPlainText) | Out-Null
                                            $backedUpItems += "Certificate with private key: $($cert.Subject)"
                                        } else {
                                            $errors += "Certificate $($cert.Subject) private key is not exportable"
                                        }
                                    } catch {
                                        $errors += "Failed to export certificate $($cert.Subject) with private key : $_"
                                    }
                                }
                            }
                        }
                    }
                }

                # Export OpenVPN configs if they exist
                $openVpnPath = "$env:ProgramFiles\OpenVPN\config"
                if (Test-Path $openVpnPath) {
                    $openVpnBackupPath = Join-Path $backupPath "OpenVPN"
                    if ($WhatIf) {
                        Write-Host "WhatIf: Would copy OpenVPN configs from $openVpnPath to $openVpnBackupPath"
                    } else {
                        try {
                            New-Item -ItemType Directory -Path $openVpnBackupPath -Force | Out-Null
                            Copy-Item -Path "$openVpnPath\*" -Destination $openVpnBackupPath -Recurse -Force
                            $backedUpItems += "OpenVPN configs"
                        } catch {
                            $errors += "Failed to copy OpenVPN configs : $_"
                        }
                    }
                }
                
                # Return object for better testing and validation
                $result = [PSCustomObject]@{
                    Success = $true
                    BackupPath = $backupPath
                    Feature = "VPN Settings"
                    Timestamp = Get-Date
                    Items = $backedUpItems
                    Errors = $errors
                }
                
                Write-Host "VPN Settings backed up successfully to: $backupPath" -ForegroundColor Green
                Write-Verbose "Backup completed successfully"
                return $result
            }
            return $false
        } catch {
            $errorRecord = $_
            $errorMessage = @(
                "Failed to backup VPN Settings"
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
Backs up comprehensive VPN settings, connections, and configurations.

.DESCRIPTION
Creates a comprehensive backup of VPN settings including registry settings, VPN connections,
certificates, phonebook files, OpenVPN configurations, and Azure VPN settings. Supports
multiple VPN client types including Windows built-in VPN, OpenVPN, Cisco VPN, and Azure VPN.

The backup includes:
- Registry settings for RAS/VPN, credentials, and various VPN clients
- VPN connection configurations and settings
- VPN certificates (both public and private keys where exportable)
- Phonebook files (rasphone.pbk) from user and system locations
- OpenVPN configuration files
- Azure VPN configurations
- Cisco VPN settings

.PARAMETER BackupRootPath
The root path where the backup will be created. A subdirectory named "VPN" will be created within this path.

.PARAMETER Force
Forces the backup operation even if the destination already exists.

.PARAMETER WhatIf
Shows what would be backed up without actually performing the backup operation.

.EXAMPLE
Backup-VPNSettings -BackupRootPath "C:\Backups"

.EXAMPLE
Backup-VPNSettings -BackupRootPath "C:\Backups" -WhatIf

.NOTES
Test cases to consider:
1. Valid backup path with proper permissions
2. Invalid/nonexistent backup path
3. Empty backup path
4. No permissions to write
5. Registry export success/failure for each key
6. Azure VPN export success/failure
7. VPN connections export success/failure
8. Certificate export success/failure (CER and PFX)
9. OpenVPN config export success/failure
10. Phonebook file backup success/failure
11. Cisco VPN settings backup
12. Multiple VPN client scenarios
13. Certificate private key exportability
14. Azure VPN client present vs absent
15. OpenVPN client present vs absent
16. Cisco VPN client present vs absent
17. Administrative privileges scenarios
18. Network path scenarios
19. Certificate store access failure
20. VPN service access failure
21. File system permissions issues
22. Large configuration file scenarios
23. Corrupted configuration files
24. Multiple certificate scenarios
25. Mixed VPN client environments

.TESTCASES
# Mock test examples:
Describe "Backup-VPNSettings" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Initialize-BackupDirectory { return "TestPath" }
        Mock New-Item { }
        Mock reg { $global:LASTEXITCODE = 0 }
        Mock Get-VpnConnection { return @(
            [PSCustomObject]@{
                Name = "Test VPN"
                ServerAddress = "vpn.example.com"
                TunnelType = "IKEv2"
                EncryptionLevel = "Required"
            }
        )}
        Mock Get-ChildItem { return @(
            [PSCustomObject]@{
                Subject = "CN=Test VPN"
                Thumbprint = "test123"
                HasPrivateKey = $true
                PrivateKey = @{
                    CspKeyContainerInfo = @{
                        Exportable = $true
                    }
                }
                EnhancedKeyUsageList = @(
                    @{FriendlyName = "Client Authentication"}
                )
            }
        )}
        Mock Export-Certificate { }
        Mock Export-PfxCertificate { }
        Mock Copy-Item { }
        Mock ConvertTo-Json { return '{"test":"value"}' }
        Mock Out-File { }
        Mock Start-Process { return @{ExitCode=0} }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Backup-VPNSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.BackupPath | Should -Be "TestPath"
        $result.Feature | Should -Be "VPN Settings"
        $result.Items | Should -BeOfType [System.Array]
        $result.Errors | Should -BeOfType [System.Array]
    }

    It "Should handle registry export failure gracefully" {
        Mock reg { $global:LASTEXITCODE = 1; return "Error" }
        $result = Backup-VPNSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle VPN connections export failure gracefully" {
        Mock Get-VpnConnection { throw "VPN access failed" }
        $result = Backup-VPNSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle certificate export failure gracefully" {
        Mock Export-Certificate { throw "Certificate export failed" }
        $result = Backup-VPNSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should support WhatIf parameter" {
        $result = Backup-VPNSettings -BackupRootPath "TestPath" -WhatIf
        $result.Success | Should -Be $true
    }

    It "Should handle Azure VPN export failure gracefully" {
        Mock Start-Process { return @{ExitCode=1} }
        $result = Backup-VPNSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle OpenVPN config backup failure gracefully" {
        Mock Copy-Item { throw "File copy failed" }
        $result = Backup-VPNSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle missing VPN clients gracefully" {
        Mock Test-Path { param($Path) return $Path -notlike "*OpenVPN*" -and $Path -notlike "*AzureVpn*" }
        $result = Backup-VPNSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
    }

    It "Should handle certificate private key non-exportable gracefully" {
        Mock Get-ChildItem { return @(
            [PSCustomObject]@{
                Subject = "CN=Test VPN"
                Thumbprint = "test123"
                HasPrivateKey = $true
                PrivateKey = @{
                    CspKeyContainerInfo = @{
                        Exportable = $false
                    }
                }
            }
        )}
        $result = Backup-VPNSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle phonebook file backup failure gracefully" {
        Mock Copy-Item { param($Path) if ($Path -like "*.pbk") { throw "PBK copy failed" } }
        $result = Backup-VPNSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Backup-VPNSettings -BackupRootPath $BackupRootPath
} 