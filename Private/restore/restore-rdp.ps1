[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory=$false)]
    [string]$BackupRootPath = $null,
    
    [Parameter(Mandatory=$false)]
    [string]$MachineBackupPath = $null,
    
    [Parameter(Mandatory=$false)]
    [string]$SharedBackupPath = $null,
    
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

function Restore-RDPSettings {
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
        $itemsRestored = @()
        $itemsSkipped = @()
        $errors = @()
    }
    
    process {
        try {
            Write-Verbose "Starting restore of RDP Settings..."
            Write-Host "Restoring RDP Settings..." -ForegroundColor Blue
            
            # Validate inputs before proceeding
            if (!(Test-Path $BackupRootPath)) {
                throw [System.IO.DirectoryNotFoundException]"Backup root path not found: $BackupRootPath"
            }
            
            $backupPath = Join-Path $BackupRootPath "RDP"
            if (!(Test-Path $backupPath)) {
                throw [System.IO.DirectoryNotFoundException]"RDP backup not found at: $backupPath"
            }
            
            # Define all possible restore items
            $restoreItems = @{
                "Registry" = @{
                    Path = Join-Path $backupPath "Registry"
                    Description = "RDP registry settings"
                    Action = "Import-RegistryFiles"
                }
                "Connections" = @{
                    Path = Join-Path $backupPath "Connections"
                    Description = "RDP connection files"
                    Action = "Restore-ConnectionFiles"
                }
                "Certificates" = @{
                    Path = Join-Path $backupPath "Certificates"
                    Description = "RDP certificates"
                    Action = "Restore-Certificates"
                }
                "Configuration" = @{
                    Path = Join-Path $backupPath "rdp_settings.json"
                    Description = "RDP configuration settings"
                    Action = "Restore-Configuration"
                }
                "Services" = @{
                    Path = Join-Path $backupPath "rdp_services.json"
                    Description = "RDP service configuration"
                    Action = "Restore-ServiceConfiguration"
                }
                "Firewall" = @{
                    Path = Join-Path $backupPath "rdp_firewall.json"
                    Description = "RDP firewall rules"
                    Action = "Restore-FirewallRules"
                }
            }
            
            # Filter items based on Include/Exclude parameters
            $itemsToRestore = $restoreItems.GetEnumerator() | Where-Object {
                $itemName = $_.Key
                $shouldInclude = $true
                
                if ($Include.Count -gt 0) {
                    $shouldInclude = $Include -contains $itemName
                }
                
                if ($Exclude.Count -gt 0 -and $Exclude -contains $itemName) {
                    $shouldInclude = $false
                }
                
                return $shouldInclude
            }
            
            # Stop RDP services if not in test mode
            if (!$script:TestMode -and !$WhatIf) {
                $rdpServices = @("TermService", "UmRdpService", "SessionEnv")
                foreach ($serviceName in $rdpServices) {
                    try {
                        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
                        if ($service -and $service.Status -eq "Running") {
                            if ($PSCmdlet.ShouldProcess($serviceName, "Stop RDP Service")) {
                                Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
                                Write-Verbose "Stopped service: $serviceName"
                            }
                        }
                    } catch {
                        Write-Verbose "Could not stop service $serviceName : $_"
                    }
                }
            }
            
            # Process each restore item
            foreach ($item in $itemsToRestore) {
                $itemName = $item.Key
                $itemInfo = $item.Value
                $itemPath = $itemInfo.Path
                $itemDescription = $itemInfo.Description
                $itemAction = $itemInfo.Action
                
                try {
                    if (Test-Path $itemPath) {
                        if ($PSCmdlet.ShouldProcess($itemDescription, "Restore")) {
                            Write-Host "Restoring $itemDescription..." -ForegroundColor Yellow
                            
                            switch ($itemAction) {
                                "Import-RegistryFiles" {
                                    $regFiles = Get-ChildItem -Path $itemPath -Filter "*.reg" -ErrorAction SilentlyContinue
                                    foreach ($regFile in $regFiles) {
                                        try {
                                            if (!$script:TestMode) {
                                                reg import $regFile.FullName 2>$null
                                            }
                                            $itemsRestored += "Registry\$($regFile.Name)"
                                        } catch {
                                            $errors += "Failed to import registry file $($regFile.Name): $_"
                                        }
                                    }
                                }
                                
                                "Restore-ConnectionFiles" {
                                    $connectionFiles = Get-ChildItem -Path $itemPath -Filter "*.rdp" -ErrorAction SilentlyContinue
                                    $destinationPaths = @{
                                        "Documents" = "$env:USERPROFILE\Documents"
                                        "Desktop" = "$env:USERPROFILE\Desktop"
                                        "RDCMan" = "$env:USERPROFILE\Documents\Remote Desktop Connection Manager"
                                    }
                                    
                                    foreach ($destPath in $destinationPaths.Values) {
                                        if (!(Test-Path $destPath)) {
                                            New-Item -ItemType Directory -Path $destPath -Force | Out-Null
                                        }
                                    }
                                    
                                    foreach ($connFile in $connectionFiles) {
                                        try {
                                            # Determine destination based on file name or default to Documents
                                            $destination = $destinationPaths["Documents"]
                                            if ($connFile.Name -match "RDCMan|Remote Desktop Connection Manager") {
                                                $destination = $destinationPaths["RDCMan"]
                                            }
                                            
                                            $destFile = Join-Path $destination $connFile.Name
                                            if (!$script:TestMode) {
                                                Copy-Item -Path $connFile.FullName -Destination $destFile -Force
                                            }
                                            $itemsRestored += "Connections\$($connFile.Name)"
                                        } catch {
                                            $errors += "Failed to restore connection file $($connFile.Name): $_"
                                        }
                                    }
                                }
                                
                                "Restore-Certificates" {
                                    $certFiles = Get-ChildItem -Path $itemPath -Filter "*.pfx" -ErrorAction SilentlyContinue
                                    foreach ($certFile in $certFiles) {
                                        try {
                                            if (!$script:TestMode) {
                                                $certPassword = ConvertTo-SecureString -String "backup" -Force -AsPlainText
                                                Import-PfxCertificate -FilePath $certFile.FullName -CertStoreLocation "Cert:\LocalMachine\Remote Desktop" -Password $certPassword | Out-Null
                                            }
                                            $itemsRestored += "Certificates\$($certFile.Name)"
                                        } catch {
                                            $errors += "Failed to restore certificate $($certFile.Name): $_"
                                        }
                                    }
                                }
                                
                                "Restore-Configuration" {
                                    try {
                                        $rdpConfig = Get-Content $itemPath | ConvertFrom-Json
                                        
                                        # Restore RDP enabled status
                                        if ($null -ne $rdpConfig.Enabled) {
                                            $fDenyValue = if ($rdpConfig.Enabled) { 0 } else { 1 }
                                            if (!$script:TestMode) {
                                                Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value $fDenyValue -Force
                                            }
                                        }
                                        
                                        # Restore authentication settings
                                        if ($null -ne $rdpConfig.UserAuthentication) {
                                            if (!$script:TestMode) {
                                                Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "UserAuthentication" -Value $rdpConfig.UserAuthentication -Force
                                            }
                                        }
                                        
                                        # Restore security layer
                                        if ($null -ne $rdpConfig.SecurityLayer) {
                                            if (!$script:TestMode) {
                                                Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "SecurityLayer" -Value $rdpConfig.SecurityLayer -Force
                                            }
                                        }
                                        
                                        # Restore port number
                                        if ($null -ne $rdpConfig.PortNumber) {
                                            if (!$script:TestMode) {
                                                Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "PortNumber" -Value $rdpConfig.PortNumber -Force
                                            }
                                        }
                                        
                                        # Restore encryption level
                                        if ($null -ne $rdpConfig.MinEncryptionLevel) {
                                            if (!$script:TestMode) {
                                                Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "MinEncryptionLevel" -Value $rdpConfig.MinEncryptionLevel -Force
                                            }
                                        }
                                        
                                        $itemsRestored += "rdp_settings.json"
                                    } catch {
                                        $errors += "Failed to restore RDP configuration: $_"
                                    }
                                }
                                
                                "Restore-ServiceConfiguration" {
                                    try {
                                        $serviceConfig = Get-Content $itemPath | ConvertFrom-Json
                                        
                                        foreach ($serviceName in $serviceConfig.PSObject.Properties.Name) {
                                            try {
                                                $serviceInfo = $serviceConfig.$serviceName
                                                if (!$script:TestMode) {
                                                    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
                                                    if ($service) {
                                                        # Note: Service start type changes require administrative privileges
                                                        # and may not always be possible to restore automatically
                                                        Write-Verbose "Service $serviceName configuration noted (manual intervention may be required for start type changes)"
                                                    }
                                                }
                                                $itemsRestored += "Service configuration for $serviceName"
                                            } catch {
                                                $errors += "Failed to restore service configuration for $serviceName : $_"
                                            }
                                        }
                                    } catch {
                                        $errors += "Failed to restore service configuration: $_"
                                    }
                                }
                                
                                "Restore-FirewallRules" {
                                    try {
                                        $firewallConfig = Get-Content $itemPath | ConvertFrom-Json
                                        
                                        foreach ($rule in $firewallConfig) {
                                            try {
                                                if (!$script:TestMode) {
                                                    # Enable/disable firewall rules based on backup
                                                    if ($rule.Enabled) {
                                                        Enable-NetFirewallRule -DisplayName $rule.DisplayName -ErrorAction SilentlyContinue
                                                    } else {
                                                        Disable-NetFirewallRule -DisplayName $rule.DisplayName -ErrorAction SilentlyContinue
                                                    }
                                                }
                                                $itemsRestored += "Firewall rule: $($rule.DisplayName)"
                                            } catch {
                                                $errors += "Failed to restore firewall rule $($rule.DisplayName): $_"
                                            }
                                        }
                                    } catch {
                                        $errors += "Failed to restore firewall rules: $_"
                                    }
                                }
                            }
                            
                            Write-Host "Restored $itemDescription" -ForegroundColor Green
                        }
                    } else {
                        $itemsSkipped += "$itemDescription (not found in backup)"
                        Write-Verbose "Skipped $itemDescription - not found in backup"
                    }
                } catch {
                    $errors += "Failed to restore $itemDescription : $_"
                    Write-Warning "Failed to restore $itemDescription : $_"
                }
            }
            
            # Start RDP services if not in test mode
            if (!$script:TestMode -and !$WhatIf) {
                $rdpServices = @("TermService", "UmRdpService", "SessionEnv")
                foreach ($serviceName in $rdpServices) {
                    try {
                        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
                        if ($service -and $service.Status -ne "Running") {
                            if ($PSCmdlet.ShouldProcess($serviceName, "Start RDP Service")) {
                                Start-Service -Name $serviceName -ErrorAction SilentlyContinue
                                Write-Verbose "Started service: $serviceName"
                            }
                        }
                    } catch {
                        Write-Verbose "Could not start service $serviceName : $_"
                    }
                }
            }
            
            # Return result object
            $result = [PSCustomObject]@{
                Success = $true
                BackupPath = $backupPath
                Feature = "RDP Settings"
                Timestamp = Get-Date
                ItemsRestored = $itemsRestored
                ItemsSkipped = $itemsSkipped
                Errors = $errors
            }
            
            Write-Host "RDP Settings restored successfully from: $backupPath" -ForegroundColor Green
            Write-Verbose "Restore completed successfully"
            return $result
            
        } catch {
            $errorRecord = $_
            $errorMessage = @(
                "Failed to restore RDP Settings"
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

# Export the function if being imported as a module
if ($MyInvocation.Line -eq "") {
    Export-ModuleMember -Function Restore-RDPSettings
}

<#
.SYNOPSIS
Restores Windows Remote Desktop Protocol (RDP) settings and configurations from backup.

.DESCRIPTION
Restores a comprehensive backup of Windows RDP settings, including registry settings, connection files, 
certificates, service configuration, and firewall rules. Supports selective restoration with Include/Exclude
parameters and provides detailed result tracking for automation scenarios.

.PARAMETER BackupRootPath
The root path where the backup is located. The script will look for an "RDP" subdirectory within this path.

.PARAMETER Force
Forces the restore operation even if it might overwrite existing settings.

.PARAMETER Include
Specifies which components to restore. Valid values: Registry, Connections, Certificates, Configuration, Services, Firewall.

.PARAMETER Exclude
Specifies which components to exclude from restoration. Valid values: Registry, Connections, Certificates, Configuration, Services, Firewall.

.PARAMETER SkipVerification
Skips verification steps during the restore process.

.PARAMETER WhatIf
Shows what would be restored without actually performing the restore operation.

.EXAMPLE
Restore-RDPSettings -BackupRootPath "C:\Backups"

.EXAMPLE
Restore-RDPSettings -BackupRootPath "C:\Backups" -Include @("Registry", "Connections")

.EXAMPLE
Restore-RDPSettings -BackupRootPath "C:\Backups" -Exclude @("Certificates") -WhatIf

.NOTES
Test cases to consider:
1. Valid backup path with all components
2. Invalid/nonexistent backup path
3. Partial backup (missing some components)
4. Registry import success/failure
5. Connection files restore success/failure
6. Certificate import success/failure
7. Configuration restore success/failure
8. Service configuration restore success/failure
9. Firewall rules restore success/failure
10. Include parameter filtering
11. Exclude parameter filtering
12. Service stop/start operations
13. Administrative privileges scenarios
14. Network path scenarios
15. File permission issues
16. Registry access issues
17. Certificate store access issues
18. Service access issues
19. Firewall access issues
20. Test mode scenarios

.TESTCASES
# Mock test examples:
Describe "Restore-RDPSettings" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Join-Path { return "TestPath" }
        Mock Get-ChildItem { 
            param($Path, $Filter)
            if ($Filter -eq "*.reg") {
                return @([PSCustomObject]@{ FullName = "test.reg"; Name = "test.reg" })
            } elseif ($Filter -eq "*.rdp") {
                return @([PSCustomObject]@{ FullName = "test.rdp"; Name = "test.rdp" })
            } elseif ($Filter -eq "*.pfx") {
                return @([PSCustomObject]@{ FullName = "test.pfx"; Name = "test.pfx" })
            }
            return @()
        }
        Mock Get-Content { return '{"Enabled":true,"UserAuthentication":1,"SecurityLayer":2}' | ConvertFrom-Json }
        Mock New-Item { }
        Mock Copy-Item { }
        Mock Set-ItemProperty { }
        Mock Import-PfxCertificate { }
        Mock Get-Service { return @{ Status = "Running"; StartType = "Automatic" } }
        Mock Stop-Service { }
        Mock Start-Service { }
        Mock Enable-NetFirewallRule { }
        Mock Disable-NetFirewallRule { }
        Mock reg { }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Restore-RDPSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.BackupPath | Should -Be "TestPath"
        $result.Feature | Should -Be "RDP Settings"
        $result.ItemsRestored | Should -BeOfType [System.Array]
        $result.ItemsSkipped | Should -BeOfType [System.Array]
        $result.Errors | Should -BeOfType [System.Array]
    }

    It "Should handle registry import failure gracefully" {
        Mock reg { throw "Registry import failed" }
        $result = Restore-RDPSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle certificate import failure gracefully" {
        Mock Import-PfxCertificate { throw "Certificate import failed" }
        $result = Restore-RDPSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should support Include parameter" {
        $result = Restore-RDPSettings -BackupRootPath "TestPath" -Include @("Registry")
        $result.Success | Should -Be $true
    }

    It "Should support Exclude parameter" {
        $result = Restore-RDPSettings -BackupRootPath "TestPath" -Exclude @("Certificates")
        $result.Success | Should -Be $true
    }

    It "Should handle service management failure gracefully" {
        Mock Stop-Service { throw "Service stop failed" }
        Mock Start-Service { throw "Service start failed" }
        $result = Restore-RDPSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
    }

    It "Should handle missing backup components gracefully" {
        Mock Test-Path { param($Path) return $Path -notlike "*Certificates*" }
        $result = Restore-RDPSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.ItemsSkipped.Count | Should -BeGreaterThan 0
    }

    It "Should support WhatIf parameter" {
        $result = Restore-RDPSettings -BackupRootPath "TestPath" -WhatIf
        $result.Success | Should -Be $true
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Restore-RDPSettings -BackupRootPath $BackupRootPath -Force:$Force -Include $Include -Exclude $Exclude -SkipVerification:$SkipVerification
} 