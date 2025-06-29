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

function Backup-RDPSettings {
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
            Write-Verbose "Starting backup of RDP Settings..."
            Write-Host "Backing up RDP Settings..." -ForegroundColor Blue
            
            # Validate inputs before proceeding
            if (!(Test-Path $BackupRootPath)) {
                throw [System.IO.DirectoryNotFoundException]"Backup root path not found: $BackupRootPath"
            }
            
            $backupPath = Initialize-BackupDirectory -Path "RDP" -BackupType "RDP Settings" -BackupRootPath $BackupRootPath
            
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

                # Registry paths for RDP settings
                $registryPaths = @(
                    "HKCU\Software\Microsoft\Terminal Server Client",
                    "HKCU\Software\Microsoft\Terminal Server Client\Servers",
                    "HKCU\Software\Microsoft\Terminal Server Client\Default",
                    "HKLM\SOFTWARE\Microsoft\Terminal Server Client",
                    "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server",
                    "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp",
                    "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\DefaultUserConfiguration",
                    "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services",
                    "HKLM\SYSTEM\CurrentControlSet\Control\Remote Assistance",
                    "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\SessionData",
                    "HKLM\SYSTEM\CurrentControlSet\Services\TermService\Parameters",
                    "HKLM\SYSTEM\CurrentControlSet\Services\UmRdpService\Parameters"
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
                                reg export $path $regFile /y 2>$null
                                $backedUpItems += "Registry\$($path.Split('\')[-1]).reg"
                            } catch {
                                $errors += "Failed to export registry path $path : $_"
                            }
                        }
                    } else {
                        Write-Verbose "Registry key not found: $path"
                    }
                }

                # Export RDP connection files
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export RDP connection files"
                } else {
                    $rdpPaths = @(
                        "$env:USERPROFILE\Documents\*.rdp",
                        "$env:APPDATA\Microsoft\Windows\Recent\AutomaticDestinations\*.rdp",
                        "$env:USERPROFILE\Documents\Remote Desktop Connection Manager\*.rdp",
                        "$env:USERPROFILE\Desktop\*.rdp"
                    )

                    $connectionsPath = Join-Path $backupPath "Connections"
                    $foundConnections = $false

                    foreach ($rdpPath in $rdpPaths) {
                        try {
                            $rdpFiles = Get-ChildItem -Path $rdpPath -ErrorAction SilentlyContinue
                            if ($rdpFiles) {
                                if (!$foundConnections) {
                                    New-Item -ItemType Directory -Path $connectionsPath -Force | Out-Null
                                    $foundConnections = $true
                                }
                                
                                foreach ($file in $rdpFiles) {
                                    $destFile = Join-Path $connectionsPath $file.Name
                                    Copy-Item -Path $file.FullName -Destination $destFile -Force
                                }
                                $backedUpItems += "Connections from: $(Split-Path $rdpPath -Parent)"
                            }
                        } catch {
                            $errors += "Failed to backup RDP connections from $rdpPath : $_"
                        }
                    }
                    
                    if (!$foundConnections) {
                        Write-Verbose "No RDP connection files found"
                    }
                }

                # Export RDP certificates
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export RDP certificates"
                } else {
                    try {
                        $rdpCerts = Get-ChildItem -Path "Cert:\LocalMachine\Remote Desktop" -ErrorAction SilentlyContinue
                        if ($rdpCerts) {
                            $certsPath = Join-Path $backupPath "Certificates"
                            New-Item -ItemType Directory -Path $certsPath -Force | Out-Null
                            
                            foreach ($cert in $rdpCerts) {
                                try {
                                    $certFile = Join-Path $certsPath "$($cert.Thumbprint).pfx"
                                    Export-PfxCertificate -Cert $cert -FilePath $certFile -Password (ConvertTo-SecureString -String "backup" -Force -AsPlainText) | Out-Null
                                    $backedUpItems += "Certificates\$($cert.Thumbprint).pfx"
                                } catch {
                                    $errors += "Failed to export certificate $($cert.Thumbprint): $_"
                                }
                            }
                        } else {
                            Write-Verbose "No RDP certificates found"
                        }
                    } catch {
                        $errors += "Failed to access RDP certificates: $_"
                    }
                }

                # Export RDP configuration
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export RDP configuration"
                } else {
                    try {
                        $rdpSettings = @{}
                        
                        # Get RDP enabled status
                        try {
                            $rdpSettings.Enabled = (Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -ErrorAction SilentlyContinue).fDenyTSConnections -eq 0
                        } catch {
                            $rdpSettings.Enabled = $null
                        }
                        
                        # Get authentication settings
                        try {
                            $rdpSettings.UserAuthentication = (Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "UserAuthentication" -ErrorAction SilentlyContinue).UserAuthentication
                        } catch {
                            $rdpSettings.UserAuthentication = $null
                        }
                        
                        # Get security layer
                        try {
                            $rdpSettings.SecurityLayer = (Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "SecurityLayer" -ErrorAction SilentlyContinue).SecurityLayer
                        } catch {
                            $rdpSettings.SecurityLayer = $null
                        }
                        
                        # Get port number
                        try {
                            $rdpSettings.PortNumber = (Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "PortNumber" -ErrorAction SilentlyContinue).PortNumber
                        } catch {
                            $rdpSettings.PortNumber = $null
                        }
                        
                        # Get encryption level
                        try {
                            $rdpSettings.MinEncryptionLevel = (Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "MinEncryptionLevel" -ErrorAction SilentlyContinue).MinEncryptionLevel
                        } catch {
                            $rdpSettings.MinEncryptionLevel = $null
                        }
                        
                        $rdpSettings | ConvertTo-Json -Depth 10 | Out-File "$backupPath\rdp_settings.json" -Force
                        $backedUpItems += "rdp_settings.json"
                    } catch {
                        $errors += "Failed to export RDP configuration: $_"
                    }
                }

                # Export RDP service configuration
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export RDP service configuration"
                } else {
                    try {
                        $rdpServices = @("TermService", "UmRdpService", "SessionEnv")
                        $serviceConfig = @{}
                        
                        foreach ($serviceName in $rdpServices) {
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
                            $serviceConfig | ConvertTo-Json -Depth 10 | Out-File "$backupPath\rdp_services.json" -Force
                            $backedUpItems += "rdp_services.json"
                        }
                    } catch {
                        $errors += "Failed to export RDP service configuration: $_"
                    }
                }

                # Export firewall rules for RDP
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export RDP firewall rules"
                } else {
                    try {
                        $rdpFirewallRules = Get-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
                        if ($rdpFirewallRules) {
                            $firewallConfig = $rdpFirewallRules | Select-Object DisplayName, Enabled, Direction, Action, Profile
                            $firewallConfig | ConvertTo-Json -Depth 10 | Out-File "$backupPath\rdp_firewall.json" -Force
                            $backedUpItems += "rdp_firewall.json"
                        }
                    } catch {
                        $errors += "Failed to export RDP firewall rules: $_"
                    }
                }
                
                # Return object for better testing and validation
                $result = [PSCustomObject]@{
                    Success = $true
                    BackupPath = $backupPath
                    Feature = "RDP Settings"
                    Timestamp = Get-Date
                    Items = $backedUpItems
                    Errors = $errors
                }
                
                Write-Host "RDP Settings backed up successfully to: $backupPath" -ForegroundColor Green
                Write-Verbose "Backup completed successfully"
                return $result
            }
            return $false
        } catch {
            $errorRecord = $_
            $errorMessage = @(
                "Failed to backup RDP Settings"
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
Backs up Windows Remote Desktop Protocol (RDP) settings and configurations.

.DESCRIPTION
Creates a comprehensive backup of Windows RDP settings, including registry settings, connection files, 
certificates, service configuration, and firewall rules. Supports both client and server RDP configurations
with detailed security and authentication settings preservation.

.PARAMETER BackupRootPath
The root path where the backup will be created. A subdirectory named "RDP" will be created within this path.

.PARAMETER Force
Forces the backup operation even if the destination already exists.

.PARAMETER WhatIf
Shows what would be backed up without actually performing the backup operation.

.EXAMPLE
Backup-RDPSettings -BackupRootPath "C:\Backups"

.EXAMPLE
Backup-RDPSettings -BackupRootPath "C:\Backups" -WhatIf

.NOTES
Test cases to consider:
1. Valid backup path with proper permissions
2. Invalid/nonexistent backup path
3. Empty backup path
4. No permissions to write
5. Registry export success/failure for each key
6. RDP connection files backup success/failure
7. RDP certificates export success/failure
8. RDP configuration export success/failure
9. RDP service configuration export success/failure
10. RDP firewall rules export success/failure
11. JSON serialization success/failure
12. No RDP connections scenario
13. No RDP certificates scenario
14. RDP disabled scenario
15. RDP enabled with custom settings
16. Certificate export failures
17. Service access failures
18. Firewall rule access failures
19. Network path scenarios
20. Administrative privileges scenarios

.TESTCASES
# Mock test examples:
Describe "Backup-RDPSettings" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Initialize-BackupDirectory { return "TestPath" }
        Mock New-Item { }
        Mock Get-ChildItem { 
            param($Path)
            if ($Path -like "*Cert:*") {
                return @([PSCustomObject]@{ Thumbprint = "1234567890ABCDEF" })
            } else {
                return @([PSCustomObject]@{ FullName = "Test.rdp"; Name = "Test.rdp" })
            }
        }
        Mock Get-ItemProperty { return @{
            fDenyTSConnections = 0
            UserAuthentication = 1
            SecurityLayer = 2
            PortNumber = 3389
            MinEncryptionLevel = 3
        }}
        Mock Get-Service { return @{
            Status = "Running"
            StartType = "Automatic"
            DisplayName = "Remote Desktop Services"
        }}
        Mock Get-NetFirewallRule { return @(
            [PSCustomObject]@{
                DisplayName = "Remote Desktop - User Mode (TCP-In)"
                Enabled = $true
                Direction = "Inbound"
                Action = "Allow"
                Profile = "Any"
            }
        )}
        Mock ConvertTo-Json { return '{"test":"value"}' }
        Mock Out-File { }
        Mock Copy-Item { }
        Mock Export-PfxCertificate { }
        Mock reg { }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Backup-RDPSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.BackupPath | Should -Be "TestPath"
        $result.Feature | Should -Be "RDP Settings"
        $result.Items | Should -BeOfType [System.Array]
        $result.Errors | Should -BeOfType [System.Array]
    }

    It "Should handle registry export failure gracefully" {
        Mock reg { throw "Failed to export registry" }
        $result = Backup-RDPSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle certificate export failure gracefully" {
        Mock Export-PfxCertificate { throw "Certificate export failed" }
        $result = Backup-RDPSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should support WhatIf parameter" {
        $result = Backup-RDPSettings -BackupRootPath "TestPath" -WhatIf
        $result.Success | Should -Be $true
    }

    It "Should handle connection files backup failure gracefully" {
        Mock Copy-Item { throw "File copy failed" }
        $result = Backup-RDPSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle service configuration failure gracefully" {
        Mock Get-Service { throw "Service access denied" }
        $result = Backup-RDPSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle no connections scenario" {
        Mock Get-ChildItem { return @() }
        $result = Backup-RDPSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Backup-RDPSettings -BackupRootPath $BackupRootPath
} 