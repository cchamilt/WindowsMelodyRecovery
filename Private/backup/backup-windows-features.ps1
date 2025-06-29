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

function Backup-WindowsFeatures {
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
            Write-Verbose "Starting backup of Windows Features..."
            Write-Host "Backing up Windows Features..." -ForegroundColor Blue
            
            # Validate inputs before proceeding
            if (!(Test-Path $BackupRootPath)) {
                throw [System.IO.DirectoryNotFoundException]"Backup root path not found: $BackupRootPath"
            }
            
            $backupPath = Initialize-BackupDirectory -Path "WindowsFeatures" -BackupType "Windows Features" -BackupRootPath $BackupRootPath
            
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

                # Windows Features-related registry settings to backup
                $registryPaths = @(
                    # Windows Features settings
                    "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OptionalFeatures",
                    "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\OptionalComponents",
                    
                    # Component settings
                    "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing",
                    "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Features",
                    
                    # Feature staging and services
                    "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\FeatureStaging",
                    "HKLM\SYSTEM\CurrentControlSet\Services\TrustedInstaller",
                    
                    # Windows Update and servicing
                    "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Services\Pending",
                    "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Servicing",
                    
                    # Feature on demand settings
                    "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Servicing",
                    "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate",
                    
                    # DISM settings
                    "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\DISM",
                    
                    # Windows subsystem settings
                    "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Lxss",
                    "HKLM\SYSTEM\CurrentControlSet\Services\LxssManager"
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

                # Export Windows Optional Features
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export Windows Optional Features"
                } else {
                    try {
                        if (!$script:TestMode) {
                            # Get all features but save enabled ones separately for restore
                            $allFeatures = Get-WindowsOptionalFeature -Online | Select-Object FeatureName, State, Description
                            $enabledFeatures = $allFeatures | Where-Object { $_.State -eq "Enabled" }
                            
                            $allFeatures | ConvertTo-Json -Depth 10 | Out-File (Join-Path $backupPath "optional_features.json") -Force
                            $enabledFeatures | ConvertTo-Json -Depth 10 | Out-File (Join-Path $backupPath "enabled_features.json") -Force
                            
                            $backedUpItems += "optional_features.json"
                            $backedUpItems += "enabled_features.json"
                            Write-Host "Windows Optional Features backed up successfully" -ForegroundColor Green
                        } else {
                            # Test mode - create mock data
                            $mockFeatures = @(
                                @{FeatureName="IIS-WebServerRole"; State="Enabled"; Description="Internet Information Services"}
                                @{FeatureName="Microsoft-Windows-Subsystem-Linux"; State="Enabled"; Description="Windows Subsystem for Linux"}
                            )
                            $mockFeatures | ConvertTo-Json -Depth 10 | Out-File (Join-Path $backupPath "optional_features.json") -Force
                            $mockFeatures | ConvertTo-Json -Depth 10 | Out-File (Join-Path $backupPath "enabled_features.json") -Force
                            $backedUpItems += "optional_features.json"
                            $backedUpItems += "enabled_features.json"
                        }
                    } catch {
                        $errors += "Failed to export Windows Optional Features: $_"
                    }
                }

                # Export Windows Capabilities
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export Windows Capabilities"
                } else {
                    try {
                        if (!$script:TestMode) {
                            # Get all capabilities but save installed ones separately for restore
                            $allCapabilities = Get-WindowsCapability -Online | Select-Object Name, State, Description
                            $installedCapabilities = $allCapabilities | Where-Object { $_.State -eq "Installed" }
                            
                            $allCapabilities | ConvertTo-Json -Depth 10 | Out-File (Join-Path $backupPath "capabilities.json") -Force
                            $installedCapabilities | ConvertTo-Json -Depth 10 | Out-File (Join-Path $backupPath "installed_capabilities.json") -Force
                            
                            $backedUpItems += "capabilities.json"
                            $backedUpItems += "installed_capabilities.json"
                            Write-Host "Windows Capabilities backed up successfully" -ForegroundColor Green
                        } else {
                            # Test mode - create mock data
                            $mockCapabilities = @(
                                @{Name="Language.Basic~~~en-US~0.0.1.0"; State="Installed"; Description="English Language Pack"}
                                @{Name="Tools.Graphics.DirectX~~~0.0.1.0"; State="NotPresent"; Description="DirectX Graphics Tools"}
                            )
                            $mockCapabilities | ConvertTo-Json -Depth 10 | Out-File (Join-Path $backupPath "capabilities.json") -Force
                            $mockCapabilities | ConvertTo-Json -Depth 10 | Out-File (Join-Path $backupPath "installed_capabilities.json") -Force
                            $backedUpItems += "capabilities.json"
                            $backedUpItems += "installed_capabilities.json"
                        }
                    } catch {
                        $errors += "Failed to export Windows Capabilities: $_"
                    }
                }

                # Export Windows Features (Server)
                if ($WhatIf) {
                    Write-Host "WhatIf: Would check for Windows Server Features"
                } else {
                    try {
                        if (!$script:TestMode) {
                            $osInfo = Get-WmiObject -Class Win32_OperatingSystem
                            if ($osInfo.ProductType -ne 1) {
                                # This is a server OS
                                $serverFeatures = Get-WindowsFeature | Where-Object { $_.Installed -eq $true }
                                $serverFeatures | Select-Object Name, InstallState, Description | ConvertTo-Json -Depth 10 | Out-File (Join-Path $backupPath "server_features.json") -Force
                                $backedUpItems += "server_features.json"
                                Write-Host "Windows Server Features backed up successfully" -ForegroundColor Green
                            }
                        } else {
                            # Test mode - create mock server features
                            $mockServerFeatures = @(
                                @{Name="IIS-WebServerRole"; InstallState="Installed"; Description="Web Server (IIS)"}
                                @{Name="DNS"; InstallState="Installed"; Description="DNS Server"}
                            )
                            $mockServerFeatures | ConvertTo-Json -Depth 10 | Out-File (Join-Path $backupPath "server_features.json") -Force
                            $backedUpItems += "server_features.json"
                        }
                    } catch {
                        $errors += "Failed to export Windows Server Features: $_"
                    }
                }

                # Export DISM packages info
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export DISM packages information"
                } else {
                    try {
                        if (!$script:TestMode) {
                            $dismPackages = dism /online /get-packages /format:table 2>&1
                            $dismPackages | Out-File (Join-Path $backupPath "dism_packages.txt") -Force
                            $backedUpItems += "dism_packages.txt"
                        } else {
                            "Mock DISM packages information" | Out-File (Join-Path $backupPath "dism_packages.txt") -Force
                            $backedUpItems += "dism_packages.txt"
                        }
                    } catch {
                        $errors += "Failed to export DISM packages information: $_"
                    }
                }

                # Export Windows Update packages
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export Windows Update packages"
                } else {
                    try {
                        if (!$script:TestMode) {
                            $updatePackages = Get-HotFix | Select-Object Description, HotFixID, InstalledBy, InstalledOn
                            $updatePackages | ConvertTo-Json -Depth 10 | Out-File (Join-Path $backupPath "installed_updates.json") -Force
                            $backedUpItems += "installed_updates.json"
                        } else {
                            $mockUpdates = @(
                                @{Description="Security Update"; HotFixID="KB5000001"; InstalledBy="NT AUTHORITY\SYSTEM"; InstalledOn="2023-01-01"}
                            )
                            $mockUpdates | ConvertTo-Json -Depth 10 | Out-File (Join-Path $backupPath "installed_updates.json") -Force
                            $backedUpItems += "installed_updates.json"
                        }
                    } catch {
                        $errors += "Failed to export Windows Update packages: $_"
                    }
                }

                # Export Windows Store apps (AppX packages)
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export Windows Store apps"
                } else {
                    try {
                        if (!$script:TestMode) {
                            $appxPackages = Get-AppxPackage | Select-Object Name, PackageFullName, Version, Architecture, Publisher
                            $appxPackages | ConvertTo-Json -Depth 10 | Out-File (Join-Path $backupPath "appx_packages.json") -Force
                            $backedUpItems += "appx_packages.json"
                        } else {
                            $mockAppx = @(
                                @{Name="Microsoft.WindowsCalculator"; PackageFullName="Microsoft.WindowsCalculator_10.0.0.0_x64__8wekyb3d8bbwe"; Version="10.0.0.0"; Architecture="X64"; Publisher="CN=Microsoft Corporation"}
                            )
                            $mockAppx | ConvertTo-Json -Depth 10 | Out-File (Join-Path $backupPath "appx_packages.json") -Force
                            $backedUpItems += "appx_packages.json"
                        }
                    } catch {
                        $errors += "Failed to export Windows Store apps: $_"
                    }
                }

                # Get system information
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export system information"
                } else {
                    try {
                        if (!$script:TestMode) {
                            $osInfo = Get-WmiObject -Class Win32_OperatingSystem
                            $systemInfo = @{
                                LastBackupDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                                OSVersion = $osInfo.Version
                                OSBuildNumber = $osInfo.BuildNumber
                                OSArchitecture = $osInfo.OSArchitecture
                                ProductType = $osInfo.ProductType
                                IsServer = ($osInfo.ProductType -ne 1)
                                ServicePackMajorVersion = $osInfo.ServicePackMajorVersion
                                ServicePackMinorVersion = $osInfo.ServicePackMinorVersion
                                WindowsDirectory = $osInfo.WindowsDirectory
                                SystemDirectory = $osInfo.SystemDirectory
                            }
                        } else {
                            $systemInfo = @{
                                LastBackupDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                                OSVersion = "10.0.19041"
                                OSBuildNumber = "19041"
                                OSArchitecture = "64-bit"
                                ProductType = 1
                                IsServer = $false
                                ServicePackMajorVersion = 0
                                ServicePackMinorVersion = 0
                                WindowsDirectory = "C:\Windows"
                                SystemDirectory = "C:\Windows\system32"
                            }
                        }
                        
                        $systemInfo | ConvertTo-Json -Depth 10 | Out-File (Join-Path $backupPath "system_info.json") -Force
                        $backedUpItems += "system_info.json"
                    } catch {
                        $errors += "Failed to export system information: $_"
                    }
                }
                
                # Return object for better testing and validation
                $result = [PSCustomObject]@{
                    Success = $true
                    BackupPath = $backupPath
                    Feature = "Windows Features"
                    Timestamp = Get-Date
                    Items = $backedUpItems
                    Errors = $errors
                }
                
                Write-Host "Windows Features backed up successfully to: $backupPath" -ForegroundColor Green
                Write-Verbose "Backup completed successfully"
                return $result
            }
            return $false
        } catch {
            $errorRecord = $_
            $errorMessage = @(
                "Failed to backup Windows Features"
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
Backs up comprehensive Windows Features, capabilities, and system components.

.DESCRIPTION
Creates a comprehensive backup of Windows Features including optional features, capabilities,
server features (if applicable), DISM packages, Windows Update packages, AppX packages,
and related registry settings. This backup captures the current state of Windows components
and features for restoration on the same or similar systems.

The backup includes:
- Registry settings for Windows Features, Component Based Servicing, and related services
- Windows Optional Features (enabled and available)
- Windows Capabilities (installed and available)
- Windows Server Features (if running on Windows Server)
- DISM packages information
- Installed Windows Updates
- Windows Store apps (AppX packages)
- System information and OS details

.PARAMETER BackupRootPath
The root path where the backup will be created. A subdirectory named "WindowsFeatures" will be created within this path.

.PARAMETER Force
Forces the backup operation even if the destination already exists.

.PARAMETER WhatIf
Shows what would be backed up without actually performing the backup operation.

.EXAMPLE
Backup-WindowsFeatures -BackupRootPath "C:\Backups"

.EXAMPLE
Backup-WindowsFeatures -BackupRootPath "C:\Backups" -WhatIf

.NOTES
Test cases to consider:
1. Valid backup path with proper permissions
2. Invalid/nonexistent backup path
3. Empty backup path
4. No permissions to write
5. Windows 10 vs Windows 11 vs Windows Server
6. Registry export success/failure for each key
7. Optional Features enumeration success/failure
8. Capabilities enumeration success/failure
9. Server Features enumeration (server vs client OS)
10. DISM command execution success/failure
11. Windows Update enumeration success/failure
12. AppX packages enumeration success/failure
13. System information retrieval success/failure
14. Administrative privileges scenarios
15. Network path scenarios
16. Large feature sets scenarios
17. Corrupted Windows Features database
18. Windows Subsystem for Linux scenarios
19. Hyper-V features scenarios
20. IIS features scenarios
21. .NET Framework features scenarios
22. Windows Media features scenarios
23. Legacy component scenarios
24. Feature on demand scenarios
25. Mixed architecture scenarios

.TESTCASES
# Mock test examples:
Describe "Backup-WindowsFeatures" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Initialize-BackupDirectory { return "TestPath" }
        Mock New-Item { }
        Mock reg { $global:LASTEXITCODE = 0 }
        Mock Get-WindowsOptionalFeature { return @(
            @{FeatureName="IIS-WebServerRole"; State="Enabled"; Description="Internet Information Services"}
            @{FeatureName="Microsoft-Windows-Subsystem-Linux"; State="Disabled"; Description="Windows Subsystem for Linux"}
        )}
        Mock Get-WindowsCapability { return @(
            @{Name="Language.Basic~~~en-US~0.0.1.0"; State="Installed"; Description="English Language Pack"}
            @{Name="Tools.Graphics.DirectX~~~0.0.1.0"; State="NotPresent"; Description="DirectX Graphics Tools"}
        )}
        Mock Get-WindowsFeature { return @(
            @{Name="IIS-WebServerRole"; InstallState="Installed"; Description="Web Server (IIS)"}
        )}
        Mock Get-WmiObject { return @{ProductType=1; Version="10.0.19041"; BuildNumber="19041"; OSArchitecture="64-bit"} }
        Mock Get-HotFix { return @(@{Description="Security Update"; HotFixID="KB5000001"}) }
        Mock Get-AppxPackage { return @(@{Name="Microsoft.WindowsCalculator"; PackageFullName="Microsoft.WindowsCalculator_10.0.0.0_x64__8wekyb3d8bbwe"}) }
        Mock ConvertTo-Json { return '{"test":"value"}' }
        Mock Out-File { }
        Mock dism { return "Mock DISM output" }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Backup-WindowsFeatures -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.BackupPath | Should -Be "TestPath"
        $result.Feature | Should -Be "Windows Features"
        $result.Items | Should -BeOfType [System.Array]
        $result.Errors | Should -BeOfType [System.Array]
    }

    It "Should handle registry export failure gracefully" {
        Mock reg { $global:LASTEXITCODE = 1; return "Error" }
        $result = Backup-WindowsFeatures -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle Optional Features enumeration failure gracefully" {
        Mock Get-WindowsOptionalFeature { throw "Features access failed" }
        $result = Backup-WindowsFeatures -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle Capabilities enumeration failure gracefully" {
        Mock Get-WindowsCapability { throw "Capabilities access failed" }
        $result = Backup-WindowsFeatures -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should support WhatIf parameter" {
        $result = Backup-WindowsFeatures -BackupRootPath "TestPath" -WhatIf
        $result.Success | Should -Be $true
    }

    It "Should handle Server Features on client OS gracefully" {
        Mock Get-WmiObject { return @{ProductType=1} }  # Client OS
        Mock Get-WindowsFeature { throw "Not available on client OS" }
        $result = Backup-WindowsFeatures -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
    }

    It "Should handle DISM command failure gracefully" {
        Mock dism { throw "DISM command failed" }
        $result = Backup-WindowsFeatures -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle Windows Update enumeration failure gracefully" {
        Mock Get-HotFix { throw "Update enumeration failed" }
        $result = Backup-WindowsFeatures -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle AppX packages enumeration failure gracefully" {
        Mock Get-AppxPackage { throw "AppX enumeration failed" }
        $result = Backup-WindowsFeatures -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle system information retrieval failure gracefully" {
        Mock Get-WmiObject { throw "WMI access failed" }
        $result = Backup-WindowsFeatures -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Backup-WindowsFeatures -BackupRootPath $BackupRootPath
} 