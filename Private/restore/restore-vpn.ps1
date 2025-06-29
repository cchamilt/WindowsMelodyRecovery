[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory=$false)]
    [string]$BackupRootPath = $null,
    
    [Parameter(Mandatory=$false)]
    [switch]$Force,
    
    [Parameter(Mandatory=$false)]
    [string[]]$Include = @(),
    
    [Parameter(Mandatory=$false)]
    [string[]]$Exclude = @(),
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipVerification
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

function Test-BackupPath {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path,
        
        [Parameter(Mandatory=$true)]
        [string]$BackupType
    )
    
    $backupPath = Join-Path $BackupRootPath $Path
    if (Test-Path $backupPath) {
        Write-Host "Found backup for $BackupType at: $backupPath" -ForegroundColor Green
        return $backupPath
    } else {
        Write-Host "No backup found for $BackupType at: $backupPath" -ForegroundColor Yellow
        return $null
    }
}

function Start-VPNServices {
    param(
        [Parameter(Mandatory=$false)]
        [switch]$WhatIf
    )
    
    $vpnServices = @(
        @{Name="RasMan"; DisplayName="Remote Access Connection Manager"},
        @{Name="RasAuto"; DisplayName="Remote Access Auto Connection Manager"},
        @{Name="Tapisrv"; DisplayName="Telephony"},
        @{Name="IKEv2"; DisplayName="IKE and AuthIP IPsec Keying Modules"},
        @{Name="PolicyAgent"; DisplayName="IPsec Policy Agent"}
    )
    
    $startedServices = @()
    
    foreach ($serviceInfo in $vpnServices) {
        if ($script:TestMode) {
            Write-Verbose "Test mode: Would check service $($serviceInfo.Name)"
            continue
        }
        
        $service = Get-Service -Name $serviceInfo.Name -ErrorAction SilentlyContinue
        if ($service) {
            if ($service.Status -ne "Running") {
                if ($WhatIf) {
                    Write-Host "WhatIf: Would start service $($serviceInfo.DisplayName)"
                } else {
                    try {
                        Write-Host "Starting service: $($serviceInfo.DisplayName)" -ForegroundColor Yellow
                        Start-Service -Name $serviceInfo.Name -ErrorAction Stop
                        $startedServices += $serviceInfo.Name
                        Write-Host "Successfully started: $($serviceInfo.DisplayName)" -ForegroundColor Green
                    } catch {
                        Write-Warning "Failed to start service $($serviceInfo.DisplayName)`: $_"
                    }
                }
            } else {
                Write-Verbose "Service $($serviceInfo.DisplayName) is already running"
            }
        } else {
            Write-Verbose "Service $($serviceInfo.Name) not found on this system"
        }
    }
    
    return $startedServices
}

function Restore-VPNSettings {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force,
        
        [Parameter(Mandatory=$false)]
        [string[]]$Include = @(),
        
        [Parameter(Mandatory=$false)]
        [string[]]$Exclude = @(),
        
        [Parameter(Mandatory=$false)]
        [switch]$SkipVerification,

        # For testing purposes
        [Parameter(DontShow)]
        [switch]$WhatIf
    )
    
    begin {
        # Test hook for mocking
        if ($script:TestMode) {
            Write-Verbose "Running in test mode"
        }
        
        # Initialize result tracking
        $script:ItemsRestored = @()
        $script:ItemsSkipped = @()
        $script:Errors = @()
    }
    
    process {
        try {
            Write-Verbose "Starting restore of VPN Settings..."
            Write-Host "Restoring VPN Settings..." -ForegroundColor Blue
            
            # Validate backup path
            if (!(Test-Path $BackupRootPath)) {
                throw [System.IO.DirectoryNotFoundException]"Backup root path not found: $BackupRootPath"
            }
            
            $backupPath = Test-BackupPath -Path "VPN" -BackupType "VPN Settings"
            
            if (!$backupPath) {
                throw [System.IO.FileNotFoundException]"No VPN Settings backup found at: $(Join-Path $BackupRootPath 'VPN')"
            }
            
            # Start VPN services before restoration
            if ($PSCmdlet.ShouldProcess("VPN services", "Start")) {
                $startedServices = Start-VPNServices -WhatIf:$WhatIf
                if ($startedServices.Count -gt 0) {
                    Write-Host "Started $($startedServices.Count) VPN service(s)" -ForegroundColor Green
                }
            }
            
            # Define all items that can be restored
            $restoreItems = @{
                "Registry" = @{
                    Path = Join-Path $backupPath "Registry"
                    Description = "VPN registry settings"
                    Action = {
                        param($ItemPath, $WhatIf)
                        
                        if (Test-Path $ItemPath) {
                            $regFiles = Get-ChildItem -Path $ItemPath -Filter "*.reg" -ErrorAction SilentlyContinue
                            $importedFiles = @()
                            
                            foreach ($regFile in $regFiles) {
                                if ($WhatIf) {
                                    Write-Host "WhatIf: Would import registry file: $($regFile.Name)"
                                    $importedFiles += $regFile.Name
                                } else {
                                    try {
                                        Write-Host "Importing registry file: $($regFile.Name)" -ForegroundColor Yellow
                                        if (!$script:TestMode) {
                                            $result = reg import $regFile.FullName 2>&1
                                            if ($LASTEXITCODE -eq 0) {
                                                $importedFiles += $regFile.Name
                                                Write-Host "Successfully imported: $($regFile.Name)" -ForegroundColor Green
                                            } else {
                                                $script:Errors += "Failed to import registry file $($regFile.Name): $result"
                                            }
                                        } else {
                                            $importedFiles += $regFile.Name
                                        }
                                    } catch {
                                        $script:Errors += "Error importing registry file $($regFile.Name)`: $_"
                                        Write-Warning "Failed to import registry file $($regFile.Name)"
                                    }
                                }
                            }
                            
                            return $importedFiles
                        }
                        return @()
                    }
                }
                
                "VPNConnections" = @{
                    Path = Join-Path $backupPath "vpn_connections.json"
                    Description = "VPN connections configuration"
                    Action = {
                        param($ItemPath, $WhatIf)
                        
                        if (Test-Path $ItemPath) {
                            if ($WhatIf) {
                                Write-Host "WhatIf: Would restore VPN connections from $ItemPath"
                                return @("VPN connections")
                            } else {
                                try {
                                    if (!$script:TestMode) {
                                        $connections = Get-Content $ItemPath | ConvertFrom-Json
                                        $restoredConnections = @()
                                        
                                        foreach ($connection in $connections) {
                                            try {
                                                # Remove existing connection if it exists
                                                $existingConnection = Get-VpnConnection -Name $connection.Name -ErrorAction SilentlyContinue
                                                if ($existingConnection) {
                                                    Remove-VpnConnection -Name $connection.Name -Force -ErrorAction SilentlyContinue
                                                }
                                                
                                                # Add VPN connection with basic parameters
                                                $addParams = @{
                                                    Name = $connection.Name
                                                    ServerAddress = $connection.ServerAddress
                                                    Force = $true
                                                }
                                                
                                                # Add optional parameters if they exist
                                                if ($connection.TunnelType) { $addParams.TunnelType = $connection.TunnelType }
                                                if ($connection.EncryptionLevel) { $addParams.EncryptionLevel = $connection.EncryptionLevel }
                                                if ($connection.AuthenticationMethod) { $addParams.AuthenticationMethod = $connection.AuthenticationMethod }
                                                if ($connection.RememberCredential -ne $null) { $addParams.RememberCredential = $connection.RememberCredential }
                                                if ($connection.SplitTunneling -ne $null) { $addParams.SplitTunneling = $connection.SplitTunneling }
                                                
                                                Add-VpnConnection @addParams
                                                $restoredConnections += $connection.Name
                                                Write-Host "Restored VPN connection: $($connection.Name)" -ForegroundColor Green
                                            } catch {
                                                $script:Errors += "Failed to restore VPN connection $($connection.Name)`: $_"
                                                Write-Warning "Failed to restore VPN connection $($connection.Name)"
                                            }
                                        }
                                        
                                        return $restoredConnections
                                    } else {
                                        return @("Test VPN connections")
                                    }
                                } catch {
                                    $script:Errors += "Failed to restore VPN connections`: $_"
                                    Write-Warning "Failed to restore VPN connections"
                                }
                            }
                        }
                        return @()
                    }
                }
                
                "Certificates" = @{
                    Path = Join-Path $backupPath "Certificates"
                    Description = "VPN certificates"
                    Action = {
                        param($ItemPath, $WhatIf)
                        
                        if (Test-Path $ItemPath) {
                            $certFiles = Get-ChildItem -Path $ItemPath -Filter "*.cer" -ErrorAction SilentlyContinue
                            $pfxFiles = Get-ChildItem -Path $ItemPath -Filter "*.pfx" -ErrorAction SilentlyContinue
                            $importedCerts = @()
                            
                            # Import CER files (public certificates)
                            foreach ($certFile in $certFiles) {
                                if ($WhatIf) {
                                    Write-Host "WhatIf: Would import certificate: $($certFile.Name)"
                                    $importedCerts += $certFile.Name
                                } else {
                                    try {
                                        if (!$script:TestMode) {
                                            Import-Certificate -FilePath $certFile.FullName -CertStoreLocation "Cert:\CurrentUser\My" -ErrorAction Stop
                                            $importedCerts += $certFile.Name
                                            Write-Host "Imported certificate: $($certFile.Name)" -ForegroundColor Green
                                        } else {
                                            $importedCerts += $certFile.Name
                                        }
                                    } catch {
                                        $script:Errors += "Failed to import certificate $($certFile.Name)`: $_"
                                        Write-Warning "Failed to import certificate $($certFile.Name)"
                                    }
                                }
                            }
                            
                            # Import PFX files (certificates with private keys)
                            foreach ($pfxFile in $pfxFiles) {
                                if ($WhatIf) {
                                    Write-Host "WhatIf: Would import PFX certificate: $($pfxFile.Name)"
                                    $importedCerts += $pfxFile.Name
                                } else {
                                    try {
                                        if (!$script:TestMode) {
                                            $password = ConvertTo-SecureString -String "temp" -Force -AsPlainText
                                            Import-PfxCertificate -FilePath $pfxFile.FullName -CertStoreLocation "Cert:\CurrentUser\My" -Password $password -ErrorAction Stop
                                            $importedCerts += $pfxFile.Name
                                            Write-Host "Imported PFX certificate: $($pfxFile.Name)" -ForegroundColor Green
                                        } else {
                                            $importedCerts += $pfxFile.Name
                                        }
                                    } catch {
                                        $script:Errors += "Failed to import PFX certificate $($pfxFile.Name)`: $_"
                                        Write-Warning "Failed to import PFX certificate $($pfxFile.Name)"
                                    }
                                }
                            }
                            
                            return $importedCerts
                        }
                        return @()
                    }
                }
                
                "RasphonePBK" = @{
                    Path = $backupPath
                    Description = "Rasphone phonebook files"
                    Action = {
                        param($ItemPath, $WhatIf)
                        
                        $pbkFiles = Get-ChildItem -Path $ItemPath -Filter "*.pbk" -ErrorAction SilentlyContinue
                        $restoredPBKs = @()
                        
                        foreach ($pbkFile in $pbkFiles) {
                            $destPath = if ($pbkFile.Name -like "*ProgramData*") {
                                "$env:ProgramData\Microsoft\Network\Connections\Pbk\rasphone.pbk"
                            } else {
                                "$env:APPDATA\Microsoft\Network\Connections\Pbk\rasphone.pbk"
                            }
                            
                            if ($WhatIf) {
                                Write-Host "WhatIf: Would restore $($pbkFile.Name) to $destPath"
                                $restoredPBKs += $pbkFile.Name
                            } else {
                                try {
                                    $parentDir = Split-Path $destPath -Parent
                                    if (!(Test-Path $parentDir)) {
                                        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
                                    }
                                    
                                    Copy-Item -Path $pbkFile.FullName -Destination $destPath -Force -ErrorAction Stop
                                    $restoredPBKs += $pbkFile.Name
                                    Write-Host "Restored phonebook: $($pbkFile.Name)" -ForegroundColor Green
                                } catch {
                                    $script:Errors += "Failed to restore phonebook $($pbkFile.Name)`: $_"
                                    Write-Warning "Failed to restore phonebook $($pbkFile.Name)"
                                }
                            }
                        }
                        
                        return $restoredPBKs
                    }
                }
                
                "OpenVPN" = @{
                    Path = Join-Path $backupPath "OpenVPN"
                    Description = "OpenVPN configuration files"
                    Action = {
                        param($ItemPath, $WhatIf)
                        
                        if (Test-Path $ItemPath) {
                            $openVpnPath = "$env:ProgramFiles\OpenVPN\config"
                            
                            if ($WhatIf) {
                                Write-Host "WhatIf: Would restore OpenVPN configs from $ItemPath to $openVpnPath"
                                return @("OpenVPN configs")
                            } else {
                                try {
                                    if (!(Test-Path $openVpnPath)) {
                                        New-Item -ItemType Directory -Path $openVpnPath -Force | Out-Null
                                    }
                                    
                                    Copy-Item -Path "$ItemPath\*" -Destination $openVpnPath -Recurse -Force -ErrorAction Stop
                                    Write-Host "Restored OpenVPN configurations" -ForegroundColor Green
                                    return @("OpenVPN configs")
                                } catch {
                                    $script:Errors += "Failed to restore OpenVPN configs`: $_"
                                    Write-Warning "Failed to restore OpenVPN configs"
                                }
                            }
                        }
                        return @()
                    }
                }
                
                "AzureVPN" = @{
                    Path = Join-Path $backupPath "azure_vpn_config.xml"
                    Description = "Azure VPN configuration"
                    Action = {
                        param($ItemPath, $WhatIf)
                        
                        if (Test-Path $ItemPath) {
                            $azureVpnPath = "$env:ProgramFiles\Microsoft\AzureVpn\AzureVpn.exe"
                            
                            if ($WhatIf) {
                                Write-Host "WhatIf: Would import Azure VPN config from $ItemPath"
                                return @("Azure VPN config")
                            } else {
                                if (Test-Path $azureVpnPath) {
                                    try {
                                        if (!$script:TestMode) {
                                            $process = Start-Process -FilePath $azureVpnPath -ArgumentList "-i `"$ItemPath`"" -Wait -PassThru -NoNewWindow
                                            if ($process.ExitCode -eq 0) {
                                                Write-Host "Imported Azure VPN configuration" -ForegroundColor Green
                                                return @("Azure VPN config")
                                            } else {
                                                $script:Errors += "Azure VPN import failed with exit code $($process.ExitCode)"
                                                return @()
                                            }
                                        } else {
                                            return @("Azure VPN config")
                                        }
                                    } catch {
                                        $script:Errors += "Failed to import Azure VPN config`: $_"
                                        Write-Warning "Failed to import Azure VPN config"
                                    }
                                } else {
                                    $script:Errors += "Azure VPN client not found at $azureVpnPath"
                                    return @()
                                }
                            }
                        }
                        return @()
                    }
                }
            }
            
            # Process each restore item
            foreach ($itemName in $restoreItems.Keys) {
                $item = $restoreItems[$itemName]
                
                # Check include/exclude filters
                if ($Include.Count -gt 0 -and $itemName -notin $Include) {
                    $script:ItemsSkipped += "$itemName (not in include list)"
                    Write-Verbose "Skipping $itemName (not in include list)"
                    continue
                }
                
                if ($Exclude.Count -gt 0 -and $itemName -in $Exclude) {
                    $script:ItemsSkipped += "$itemName (in exclude list)"
                    Write-Verbose "Skipping $itemName (in exclude list)"
                    continue
                }
                
                # Check if backup exists
                if (!(Test-Path $item.Path)) {
                    $script:ItemsSkipped += "$itemName (no backup found)"
                    Write-Verbose "Skipping $itemName (no backup found at $($item.Path))"
                    continue
                }
                
                if ($PSCmdlet.ShouldProcess($item.Description, "Restore")) {
                    try {
                        # All items have custom actions
                        $result = & $item.Action $item.Path $WhatIf
                        if ($result -and $result.Count -gt 0) {
                            $script:ItemsRestored += "$itemName ($($result.Count) items)"
                            Write-Host "Restored $itemName ($($result.Count) items)" -ForegroundColor Green
                        } else {
                            $script:ItemsSkipped += "$itemName (no items to restore)"
                        }
                    } catch {
                        $script:Errors += "Failed to restore $itemName `: $_"
                        Write-Warning "Failed to restore $($item.Description)`: $_"
                    }
                }
            }
            
            # Restart VPN services after restoration
            if ($PSCmdlet.ShouldProcess("VPN services", "Restart")) {
                if ($WhatIf) {
                    Write-Host "WhatIf: Would restart VPN services"
                } else {
                    $servicesToRestart = @("RasMan", "RasAuto", "Tapisrv", "OpenVPNService")
                    $restartedServices = @()
                    
                    foreach ($serviceName in $servicesToRestart) {
                        if ($script:TestMode) {
                            Write-Verbose "Test mode: Would restart service $serviceName"
                            continue
                        }
                        
                        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
                        if ($service) {
                            try {
                                Restart-Service -Name $serviceName -Force -ErrorAction Stop
                                $restartedServices += $serviceName
                                Write-Host "Restarted service: $serviceName" -ForegroundColor Green
                            } catch {
                                Write-Warning "Failed to restart service $serviceName `: $_"
                            }
                        }
                    }
                    
                    if ($restartedServices.Count -gt 0) {
                        Write-Host "Restarted $($restartedServices.Count) VPN service(s)" -ForegroundColor Green
                    }
                }
            }
            
            # Create result object
            $result = [PSCustomObject]@{
                Success = $true
                BackupPath = $backupPath
                Feature = "VPN Settings"
                Timestamp = Get-Date
                ItemsRestored = $script:ItemsRestored
                ItemsSkipped = $script:ItemsSkipped
                Errors = $script:Errors
                RequiresRestart = $false
            }
            
            # Display summary
            Write-Host "`nVPN Settings Restore Summary:" -ForegroundColor Green
            Write-Host "Items Restored: $($script:ItemsRestored.Count)" -ForegroundColor Yellow
            Write-Host "Items Skipped: $($script:ItemsSkipped.Count)" -ForegroundColor Yellow
            Write-Host "Errors: $($script:Errors.Count)" -ForegroundColor $(if ($script:Errors.Count -gt 0) { "Red" } else { "Yellow" })
            
            if ($script:ItemsRestored.Count -gt 0) {
                Write-Host "`nRestored Items:" -ForegroundColor Green
                $script:ItemsRestored | ForEach-Object { Write-Host "  - $_" -ForegroundColor White }
            }
            
            if ($script:ItemsSkipped.Count -gt 0) {
                Write-Host "`nSkipped Items:" -ForegroundColor Yellow
                $script:ItemsSkipped | ForEach-Object { Write-Host "  - $_" -ForegroundColor Gray }
            }
            
            if ($script:Errors.Count -gt 0) {
                Write-Host "`nErrors:" -ForegroundColor Red
                $script:Errors | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
            }
            
            if ($script:ItemsRestored.Count -gt 0) {
                Write-Host "`nNote: VPN connections and settings have been restored. You may need to re-enter credentials for some connections." -ForegroundColor Cyan
            }
            
            Write-Host "VPN Settings restored successfully from: $backupPath" -ForegroundColor Green
            Write-Verbose "Restore completed successfully"
            return $result
            
        } catch {
            $errorRecord = $_
            $errorMessage = @(
                "Failed to restore VPN Settings"
                "Error Message: $($errorRecord.Exception.Message)"
                "Error Type: $($errorRecord.Exception.GetType().FullName)"
                "Script Line Number: $($errorRecord.InvocationInfo.ScriptLineNumber)"
                "Script Name: $($errorRecord.InvocationInfo.ScriptName)"
                "Statement: $($errorRecord.InvocationInfo.Line.Trim())"
                if ($errorRecord.Exception.StackTrace) { "Stack Trace: $($errorRecord.Exception.StackTrace)" }
                if ($errorRecord.Exception.InnerException) { "Inner Exception: $($errorRecord.Exception.InnerException.Message)" }
            ) -join "`n"
            
            Write-Error $errorMessage
            Write-Verbose "Restore failed"
            throw  # Re-throw for proper error handling
        }
    }
}

<#
.SYNOPSIS
Restores comprehensive VPN settings, connections, and configurations from backup.

.DESCRIPTION
Restores VPN settings from a backup created by Backup-VPNSettings. This includes
registry settings, VPN connections, certificates, phonebook files, OpenVPN configurations,
and Azure VPN settings. The restore process handles multiple VPN client types and
ensures proper service management.

The restore process will:
1. Start required VPN services
2. Import registry settings for VPN components
3. Restore VPN connections with their configurations
4. Import VPN certificates (both public and private keys)
5. Restore phonebook files (rasphone.pbk)
6. Restore OpenVPN configuration files
7. Import Azure VPN configurations
8. Restart VPN services after restoration

.PARAMETER BackupRootPath
The root path where the backup is located. The script will look for a "VPN" subdirectory within this path.

.PARAMETER Force
Forces the restore operation even if VPN services are running or if destination files already exist.

.PARAMETER Include
Specifies which items to include in the restore. If not specified, all available items are restored.
Valid values: Registry, VPNConnections, Certificates, RasphonePBK, OpenVPN, AzureVPN

.PARAMETER Exclude
Specifies which items to exclude from the restore.
Valid values: Registry, VPNConnections, Certificates, RasphonePBK, OpenVPN, AzureVPN

.PARAMETER SkipVerification
Skips verification steps and proceeds with the restore operation.

.EXAMPLE
Restore-VPNSettings -BackupRootPath "C:\Backups"

.EXAMPLE
Restore-VPNSettings -BackupRootPath "C:\Backups" -Include @("Registry", "VPNConnections")

.EXAMPLE
Restore-VPNSettings -BackupRootPath "C:\Backups" -Exclude @("Certificates") -WhatIf

.NOTES
Test cases to consider:
1. Valid backup path with complete backup
2. Invalid/nonexistent backup path
3. Partial backup (some items missing)
4. VPN services not running
5. No permissions to write to target locations
6. Registry import success/failure
7. VPN connection creation success/failure
8. Certificate import success/failure (CER and PFX)
9. Phonebook file restoration success/failure
10. OpenVPN config restoration success/failure
11. Azure VPN config import success/failure
12. Include filter functionality
13. Exclude filter functionality
14. WhatIf parameter functionality
15. Force parameter functionality
16. Service management success/failure
17. Missing VPN client software
18. Corrupted backup files
19. Network path scenarios
20. Administrative privileges scenarios
21. Certificate password handling
22. Existing VPN connection conflicts
23. Service restart success/failure
24. Multiple VPN client scenarios
25. Credential restoration limitations

.TESTCASES
# Mock test examples:
Describe "Restore-VPNSettings" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Test-BackupPath { return "TestBackupPath" }
        Mock Start-VPNServices { return @("RasMan") }
        Mock Get-ChildItem { return @(@{Name="test.reg"; FullName="C:\test.reg"}) }
        Mock Get-Content { return '[]' }
        Mock ConvertFrom-Json { return @() }
        Mock Add-VpnConnection { }
        Mock Remove-VpnConnection { }
        Mock Get-VpnConnection { return $null }
        Mock Import-Certificate { }
        Mock Import-PfxCertificate { }
        Mock Copy-Item { }
        Mock New-Item { }
        Mock reg { $global:LASTEXITCODE = 0 }
        Mock Get-Service { return @{Status="Running"} }
        Mock Start-Service { }
        Mock Restart-Service { }
        Mock Start-Process { return @{ExitCode=0} }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Restore-VPNSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.BackupPath | Should -Be "TestBackupPath"
        $result.Feature | Should -Be "VPN Settings"
        $result.ItemsRestored | Should -BeOfType [System.Array]
        $result.ItemsSkipped | Should -BeOfType [System.Array]
        $result.Errors | Should -BeOfType [System.Array]
        $result.RequiresRestart | Should -Be $false
    }

    It "Should handle missing backup gracefully" {
        Mock Test-BackupPath { return $null }
        { Restore-VPNSettings -BackupRootPath "TestPath" } | Should -Throw
    }

    It "Should handle registry import failure gracefully" {
        Mock reg { $global:LASTEXITCODE = 1; return "Error" }
        $result = Restore-VPNSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle VPN connection creation failure gracefully" {
        Mock Add-VpnConnection { throw "VPN connection failed" }
        Mock Get-Content { return '[{"Name":"Test","ServerAddress":"test.com"}]' }
        Mock ConvertFrom-Json { return @(@{Name="Test"; ServerAddress="test.com"}) }
        $result = Restore-VPNSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should support Include parameter" {
        $result = Restore-VPNSettings -BackupRootPath "TestPath" -Include @("Registry")
        $result.Success | Should -Be $true
        $result.ItemsSkipped | Should -Contain "VPNConnections (not in include list)"
    }

    It "Should support Exclude parameter" {
        $result = Restore-VPNSettings -BackupRootPath "TestPath" -Exclude @("Registry")
        $result.Success | Should -Be $true
        $result.ItemsSkipped | Should -Contain "Registry (in exclude list)"
    }

    It "Should support WhatIf parameter" {
        $result = Restore-VPNSettings -BackupRootPath "TestPath" -WhatIf
        $result.Success | Should -Be $true
    }

    It "Should handle service management" {
        Mock Get-Service { return @{Status="Stopped"} }
        Mock Start-Service { }
        $result = Restore-VPNSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
    }

    It "Should handle certificate import failure gracefully" {
        Mock Import-Certificate { throw "Certificate import failed" }
        $result = Restore-VPNSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle missing backup items gracefully" {
        Mock Test-Path { param($Path) return $Path -notlike "*VPNConnections*" }
        $result = Restore-VPNSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.ItemsSkipped | Should -Contain "VPNConnections (no backup found)"
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Restore-VPNSettings -BackupRootPath $BackupRootPath -Force:$Force -Include $Include -Exclude $Exclude -SkipVerification:$SkipVerification
} 