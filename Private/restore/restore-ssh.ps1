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

function Restore-SSHSettings {
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
            Write-Verbose "Starting restore of SSH Settings..."
            Write-Host "Restoring SSH Settings..." -ForegroundColor Blue
            
            # Validate inputs before proceeding
            if (!(Test-Path $BackupRootPath)) {
                throw [System.IO.DirectoryNotFoundException]"Backup root path not found: $BackupRootPath"
            }
            
            $backupPath = Join-Path $BackupRootPath "SSH"
            if (!(Test-Path $backupPath)) {
                throw [System.IO.DirectoryNotFoundException]"SSH backup not found at: $backupPath"
            }
            
            # Define all possible restore items
            $restoreItems = @{
                "Registry" = @{
                    Path = Join-Path $backupPath "Registry"
                    Description = "SSH registry settings"
                    Action = "Import-RegistryFiles"
                }
                "UserSSH" = @{
                    Path = Join-Path $backupPath "User"
                    Description = "User SSH configuration"
                    Action = "Restore-UserSSH"
                }
                "SystemSSH" = @{
                    Path = Join-Path $backupPath "System"
                    Description = "System SSH configuration"
                    Action = "Restore-SystemSSH"
                }
                "KnownHosts" = @{
                    Path = $backupPath
                    Description = "SSH known hosts files"
                    Action = "Restore-KnownHosts"
                }
                "PuTTY" = @{
                    Path = Join-Path $backupPath "PuTTY"
                    Description = "PuTTY configuration"
                    Action = "Restore-PuTTY"
                }
                "WinSCP" = @{
                    Path = Join-Path $backupPath "WinSCP"
                    Description = "WinSCP configuration"
                    Action = "Restore-WinSCP"
                }
                "Services" = @{
                    Path = Join-Path $backupPath "ssh_services.json"
                    Description = "SSH service configuration"
                    Action = "Restore-SSHServices"
                }
                "Capabilities" = @{
                    Path = Join-Path $backupPath "ssh_capabilities.json"
                    Description = "SSH capabilities information"
                    Action = "Restore-SSHCapabilities"
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
            
            # Ensure SSH capabilities are installed if needed
            if (!$script:TestMode -and !$WhatIf) {
                try {
                    $sshFeatures = @(
                        "OpenSSH.Client~~~~0.0.1.0",
                        "OpenSSH.Server~~~~0.0.1.0"
                    )
                    
                    foreach ($feature in $sshFeatures) {
                        $capability = Get-WindowsCapability -Online -Name $feature -ErrorAction SilentlyContinue
                        if ($capability -and $capability.State -ne "Installed") {
                            if ($PSCmdlet.ShouldProcess($feature, "Install SSH Capability")) {
                                Add-WindowsCapability -Online -Name $feature | Out-Null
                                Write-Verbose "Installed SSH capability: $feature"
                            }
                        }
                    }
                } catch {
                    Write-Verbose "Could not check/install SSH capabilities: $_"
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
                                            $errors += "Failed to import registry file $($regFile.Name)`: $_"
                                            Write-Warning "Failed to import registry file $($regFile.Name)"
                                        }
                                    }
                                }
                                
                                "Restore-UserSSH" {
                                    $userSSHPath = "$env:USERPROFILE\.ssh"
                                    
                                    # Create user SSH directory if it doesn't exist
                                    if (!(Test-Path $userSSHPath)) {
                                        if (!$script:TestMode) {
                                            New-Item -ItemType Directory -Path $userSSHPath -Force | Out-Null
                                            # Set proper permissions
                                            icacls $userSSHPath /inheritance:r 2>$null
                                            icacls $userSSHPath /grant:r "${env:USERNAME}:(OI)(CI)F" 2>$null
                                        }
                                    }
                                    
                                    $backupFiles = Get-ChildItem -Path $itemPath -File -ErrorAction SilentlyContinue
                                    foreach ($file in $backupFiles) {
                                        try {
                                            if ($file.Name.EndsWith(".enc")) {
                                                # Handle encoded private keys
                                                $originalName = $file.Name.Replace(".enc", "")
                                                $destFile = Join-Path $userSSHPath $originalName
                                                
                                                if (!$script:TestMode) {
                                                    # Decode the private key
                                                    $encodedContent = Get-Content $file.FullName -Raw
                                                    $decodedContent = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encodedContent))
                                                    Set-Content -Path $destFile -Value $decodedContent -NoNewline
                                                    
                                                    # Set restrictive permissions for private keys
                                                    icacls $destFile /inheritance:r 2>$null
                                                    icacls $destFile /grant:r "${env:USERNAME}:F" 2>$null
                                                    
                                                    # Restore original permissions if available
                                                    $aclFile = Join-Path $itemPath "$originalName.acl"
                                                    if (Test-Path $aclFile) {
                                                        icacls $destFile /restore $aclFile 2>$null
                                                    }
                                                }
                                                $itemsRestored += "User SSH\$originalName"
                                            } elseif (!$file.Name.EndsWith(".acl")) {
                                                # Handle regular configuration files
                                                $destFile = Join-Path $userSSHPath $file.Name
                                                if (!$script:TestMode) {
                                                    Copy-Item -Path $file.FullName -Destination $destFile -Force
                                                    
                                                    # Restore original permissions if available
                                                    $aclFile = Join-Path $itemPath "$($file.Name).acl"
                                                    if (Test-Path $aclFile) {
                                                        icacls $destFile /restore $aclFile 2>$null
                                                    }
                                                }
                                                $itemsRestored += "User SSH\$($file.Name)"
                                            }
                                        } catch {
                                            $errors += "Failed to restore user SSH file $($file.Name)`: $_"
                                            Write-Warning "Failed to restore user SSH file $($file.Name)"
                                        }
                                    }
                                }
                                
                                "Restore-SystemSSH" {
                                    $systemSSHPath = "$env:ProgramData\ssh"
                                    
                                    # Create system SSH directory if it doesn't exist
                                    if (!(Test-Path $systemSSHPath)) {
                                        if (!$script:TestMode) {
                                            New-Item -ItemType Directory -Path $systemSSHPath -Force | Out-Null
                                        }
                                    }
                                    
                                    $backupFiles = Get-ChildItem -Path $itemPath -File -ErrorAction SilentlyContinue
                                    foreach ($file in $backupFiles) {
                                        try {
                                            if (!$file.Name.EndsWith(".acl")) {
                                                $destFile = Join-Path $systemSSHPath $file.Name
                                                if (!$script:TestMode) {
                                                    Copy-Item -Path $file.FullName -Destination $destFile -Force
                                                    
                                                    # Restore original permissions if available
                                                    $aclFile = Join-Path $itemPath "$($file.Name).acl"
                                                    if (Test-Path $aclFile) {
                                                        icacls $destFile /restore $aclFile 2>$null
                                                    }
                                                }
                                                $itemsRestored += "System SSH\$($file.Name)"
                                            }
                                        } catch {
                                            $errors += "Failed to restore system SSH file $($file.Name)`: $_"
                                            Write-Warning "Failed to restore system SSH file $($file.Name)"
                                        }
                                    }
                                }
                                
                                "Restore-KnownHosts" {
                                    $knownHostsFiles = @(
                                        @{ BackupName = "known_hosts_user"; RestorePath = "$env:USERPROFILE\.ssh\known_hosts" },
                                        @{ BackupName = "known_hosts_system"; RestorePath = "$env:ProgramData\ssh\known_hosts" }
                                    )
                                    
                                    foreach ($knownHosts in $knownHostsFiles) {
                                        $backupFile = Join-Path $itemPath $knownHosts.BackupName
                                        if (Test-Path $backupFile) {
                                            try {
                                                # Create parent directory if needed
                                                $parentDir = Split-Path $knownHosts.RestorePath -Parent
                                                if (!(Test-Path $parentDir)) {
                                                    if (!$script:TestMode) {
                                                        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
                                                    }
                                                }
                                                
                                                if (!$script:TestMode) {
                                                    Copy-Item -Path $backupFile -Destination $knownHosts.RestorePath -Force
                                                }
                                                $itemsRestored += $knownHosts.BackupName
                                            } catch {
                                                $errors += "Failed to restore known hosts file $($knownHosts.BackupName)`: $_"
                                                Write-Warning "Failed to restore known hosts file $($knownHosts.BackupName)"
                                            }
                                        }
                                    }
                                }
                                
                                "Restore-PuTTY" {
                                    $puttyPath = "$env:APPDATA\PuTTY"
                                    
                                    if (!(Test-Path $puttyPath)) {
                                        if (!$script:TestMode) {
                                            New-Item -ItemType Directory -Path $puttyPath -Force | Out-Null
                                        }
                                    }
                                    
                                    try {
                                        if (!$script:TestMode) {
                                            Copy-Item -Path "$itemPath\*" -Destination $puttyPath -Force -Recurse
                                        }
                                        $itemsRestored += "PuTTY configuration"
                                    } catch {
                                        $errors += "Failed to restore PuTTY configuration`: $_"
                                        Write-Warning "Failed to restore PuTTY configuration"
                                    }
                                }
                                
                                "Restore-WinSCP" {
                                    $winscpPath = "$env:APPDATA\WinSCP"
                                    
                                    if (!(Test-Path $winscpPath)) {
                                        if (!$script:TestMode) {
                                            New-Item -ItemType Directory -Path $winscpPath -Force | Out-Null
                                        }
                                    }
                                    
                                    try {
                                        if (!$script:TestMode) {
                                            Copy-Item -Path "$itemPath\*" -Destination $winscpPath -Force
                                        }
                                        $itemsRestored += "WinSCP configuration"
                                    } catch {
                                        $errors += "Failed to restore WinSCP configuration`: $_"
                                        Write-Warning "Failed to restore WinSCP configuration"
                                    }
                                }
                                
                                "Restore-SSHServices" {
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
                                                        
                                                        # Try to start the service if it was running
                                                        if ($serviceInfo.Status -eq "Running" -and $service.Status -ne "Running") {
                                                            Start-Service -Name $serviceName -ErrorAction SilentlyContinue
                                                        }
                                                    }
                                                }
                                                $itemsRestored += "Service configuration for $serviceName"
                                            } catch {
                                                $errors += "Failed to restore service configuration for $serviceName `: $_"
                                                Write-Warning "Failed to restore service configuration for $serviceName"
                                            }
                                        }
                                    } catch {
                                        $errors += "Failed to restore SSH service configuration`: $_"
                                        Write-Warning "Failed to restore SSH service configuration"
                                    }
                                }
                                
                                "Restore-SSHCapabilities" {
                                    try {
                                        $capabilities = Get-Content $itemPath | ConvertFrom-Json
                                        
                                        # This is primarily informational
                                        if ($capabilities.OpenSSHClient.Installed) {
                                            Write-Verbose "OpenSSH client was installed: $($capabilities.OpenSSHClient.Version)"
                                        }
                                        if ($capabilities.WindowsCapabilities.ClientInstalled) {
                                            Write-Verbose "Windows OpenSSH client capability was installed"
                                        }
                                        if ($capabilities.WindowsCapabilities.ServerInstalled) {
                                            Write-Verbose "Windows OpenSSH server capability was installed"
                                        }
                                        
                                        $itemsRestored += "SSH capabilities information (informational)"
                                    } catch {
                                        $errors += "Failed to restore SSH capabilities information`: $_"
                                        Write-Warning "Failed to restore SSH capabilities information"
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
                    $errors += "Failed to restore $itemDescription `: $_"
                    Write-Warning "Failed to restore $itemDescription `: $_"
                }
            }
            
            # Restart SSH services if they were running
            if (!$script:TestMode -and !$WhatIf) {
                $sshServices = @("sshd", "ssh-agent")
                foreach ($serviceName in $sshServices) {
                    try {
                        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
                        if ($service) {
                            if ($PSCmdlet.ShouldProcess($serviceName, "Restart SSH Service")) {
                                Restart-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
                                Write-Verbose "Restarted service: $serviceName"
                            }
                        }
                    } catch {
                        Write-Verbose "Could not restart service $serviceName `: $_"
                    }
                }
            }
            
            # Return result object
            $result = [PSCustomObject]@{
                Success = $true
                BackupPath = $backupPath
                Feature = "SSH Settings"
                Timestamp = Get-Date
                ItemsRestored = $itemsRestored
                ItemsSkipped = $itemsSkipped
                Errors = $errors
            }
            
            Write-Host "SSH Settings restored successfully from: $backupPath" -ForegroundColor Green
            Write-Verbose "Restore completed successfully"
            return $result
            
        } catch {
            $errorRecord = $_
            $errorMessage = @(
                "Failed to restore SSH Settings"
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
    Export-ModuleMember -Function Restore-SSHSettings
}

<#
.SYNOPSIS
Restores SSH settings, configurations, and related tools (OpenSSH, PuTTY, WinSCP) from backup.

.DESCRIPTION
Restores a comprehensive backup of SSH-related settings including OpenSSH client/server configurations, 
SSH keys (with decoding), known hosts, PuTTY sessions and settings, WinSCP configurations, and service 
settings. Handles both user-specific and system-wide SSH configurations with proper permission restoration.

.PARAMETER BackupRootPath
The root path where the backup is located. The script will look for an "SSH" subdirectory within this path.

.PARAMETER Force
Forces the restore operation even if it might overwrite existing settings.

.PARAMETER Include
Specifies which components to restore. Valid values: Registry, UserSSH, SystemSSH, KnownHosts, PuTTY, WinSCP, Services, Capabilities.

.PARAMETER Exclude
Specifies which components to exclude from restoration. Valid values: Registry, UserSSH, SystemSSH, KnownHosts, PuTTY, WinSCP, Services, Capabilities.

.PARAMETER SkipVerification
Skips verification steps during the restore process.

.PARAMETER WhatIf
Shows what would be restored without actually performing the restore operation.

.EXAMPLE
Restore-SSHSettings -BackupRootPath "C:\Backups"

.EXAMPLE
Restore-SSHSettings -BackupRootPath "C:\Backups" -Include @("Registry", "UserSSH")

.EXAMPLE
Restore-SSHSettings -BackupRootPath "C:\Backups" -Exclude @("SystemSSH") -WhatIf

.NOTES
Test cases to consider:
1. Valid backup path with all components
2. Invalid/nonexistent backup path
3. Partial backup (missing some components)
4. Registry import success/failure
5. User SSH configuration restore success/failure
6. System SSH configuration restore success/failure
7. Private key decoding success/failure
8. Known hosts restore success/failure
9. PuTTY configuration restore success/failure
10. WinSCP configuration restore success/failure
11. SSH service configuration restore success/failure
12. SSH capabilities restore success/failure
13. Include parameter filtering
14. Exclude parameter filtering
15. SSH capability installation
16. Service restart operations
17. Administrative privileges scenarios
18. Network path scenarios
19. File permission issues
20. Test mode scenarios

.TESTCASES
# Mock test examples:
Describe "Restore-SSHSettings" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Join-Path { return "TestPath" }
        Mock Get-ChildItem { 
            param($Path, $Filter)
            if ($Filter -eq "*.reg") {
                return @([PSCustomObject]@{ FullName = "test.reg"; Name = "test.reg" })
            } else {
                return @([PSCustomObject]@{ FullName = "config"; Name = "config" })
            }
        }
        Mock Get-Content { return '{"sshd":{"Status":"Running","StartType":"Automatic"}}' | ConvertFrom-Json }
        Mock New-Item { }
        Mock Copy-Item { }
        Mock Set-Content { }
        Mock Get-Service { return @{ Status = "Stopped"; StartType = "Automatic" } }
        Mock Start-Service { }
        Mock Restart-Service { }
        Mock Get-WindowsCapability { return @{ State = "NotPresent" } }
        Mock Add-WindowsCapability { }
        Mock icacls { }
        Mock reg { }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Restore-SSHSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.BackupPath | Should -Be "TestPath"
        $result.Feature | Should -Be "SSH Settings"
        $result.ItemsRestored | Should -BeOfType [System.Array]
        $result.ItemsSkipped | Should -BeOfType [System.Array]
        $result.Errors | Should -BeOfType [System.Array]
    }

    It "Should handle registry import failure gracefully" {
        Mock reg { throw "Registry import failed" }
        $result = Restore-SSHSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle SSH config restore failure gracefully" {
        Mock Copy-Item { throw "File copy failed" }
        $result = Restore-SSHSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should support Include parameter" {
        $result = Restore-SSHSettings -BackupRootPath "TestPath" -Include @("Registry")
        $result.Success | Should -Be $true
    }

    It "Should support Exclude parameter" {
        $result = Restore-SSHSettings -BackupRootPath "TestPath" -Exclude @("SystemSSH")
        $result.Success | Should -Be $true
    }

    It "Should handle service management failure gracefully" {
        Mock Start-Service { throw "Service start failed" }
        Mock Restart-Service { throw "Service restart failed" }
        $result = Restore-SSHSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
    }

    It "Should handle missing backup components gracefully" {
        Mock Test-Path { param($Path) return $Path -notlike "*PuTTY*" }
        $result = Restore-SSHSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.ItemsSkipped.Count | Should -BeGreaterThan 0
    }

    It "Should support WhatIf parameter" {
        $result = Restore-SSHSettings -BackupRootPath "TestPath" -WhatIf
        $result.Success | Should -Be $true
    }

    It "Should handle private key decoding failure gracefully" {
        Mock Set-Content { throw "Key decoding failed" }
        $result = Restore-SSHSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Restore-SSHSettings -BackupRootPath $BackupRootPath -Force:$Force -Include $Include -Exclude $Exclude -SkipVerification:$SkipVerification
} 