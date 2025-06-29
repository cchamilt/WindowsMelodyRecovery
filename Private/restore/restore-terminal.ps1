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

function Restore-TerminalSettings {
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
            Write-Verbose "Starting restore of Terminal Settings..."
            Write-Host "Restoring Terminal Settings..." -ForegroundColor Blue
            
            # Validate inputs before proceeding
            if (!(Test-Path $BackupRootPath)) {
                throw [System.IO.DirectoryNotFoundException]"Backup root path not found: $BackupRootPath"
            }
            
            $backupPath = Join-Path $BackupRootPath "Terminal"
            if (!(Test-Path $backupPath)) {
                throw [System.IO.DirectoryNotFoundException]"Terminal Settings backup not found at: $backupPath"
            }
            
            # Define all possible restore items
            $restoreItems = @{
                "Registry" = @{
                    Path = Join-Path $backupPath "Registry"
                    Description = "Terminal registry settings"
                    Action = "Import-RegistryFiles"
                }
                "TerminalSettings" = @{
                    Path = Join-Path $backupPath "terminal-settings.json"
                    Description = "Windows Terminal settings"
                    Action = "Restore-TerminalSettings"
                }
                "TerminalPreviewSettings" = @{
                    Path = Join-Path $backupPath "terminal-preview-settings.json"
                    Description = "Windows Terminal Preview settings"
                    Action = "Restore-TerminalPreviewSettings"
                }
                "TerminalState" = @{
                    Path = Join-Path $backupPath "terminal-state.json"
                    Description = "Windows Terminal state"
                    Action = "Restore-TerminalState"
                }
                "TerminalPreviewState" = @{
                    Path = Join-Path $backupPath "terminal-preview-state.json"
                    Description = "Windows Terminal Preview state"
                    Action = "Restore-TerminalPreviewState"
                }
                "TerminalProfiles" = @{
                    Path = Join-Path $backupPath "Profiles"
                    Description = "Terminal profiles, themes, and fragments"
                    Action = "Restore-TerminalProfiles"
                }
                "PowerShellProfiles" = @{
                    Path = Join-Path $backupPath "PowerShellProfiles"
                    Description = "PowerShell profiles"
                    Action = "Restore-PowerShellProfiles"
                }
                "PowerShellModules" = @{
                    Path = Join-Path $backupPath "PowerShellModules"
                    Description = "PowerShell modules information"
                    Action = "Restore-PowerShellModules"
                }
                "DefaultTerminal" = @{
                    Path = Join-Path $backupPath "default-terminal.json"
                    Description = "Default terminal application setting"
                    Action = "Restore-DefaultTerminal"
                }
                "ConsoleFonts" = @{
                    Path = Join-Path $backupPath "console-fonts.json"
                    Description = "Console font settings"
                    Action = "Restore-ConsoleFonts"
                }
                "TerminalApps" = @{
                    Path = Join-Path $backupPath "terminal-apps.json"
                    Description = "Terminal application information"
                    Action = "Restore-TerminalApps"
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
            
            # Ensure Windows Terminal is installed if needed
            if (!$script:TestMode -and !$WhatIf) {
                $terminalApp = Get-AppxPackage -Name "Microsoft.WindowsTerminal" -ErrorAction SilentlyContinue
                if (!$terminalApp) {
                    if ($PSCmdlet.ShouldProcess("Windows Terminal", "Install")) {
                        Write-Host "Installing Windows Terminal..." -ForegroundColor Yellow
                        try {
                            winget install --id Microsoft.WindowsTerminal -e --silent
                            Write-Verbose "Windows Terminal installed successfully"
                        } catch {
                            Write-Warning "Could not install Windows Terminal automatically: $_"
                        }
                    }
                }
            }
            
            # Stop terminal processes before restoration
            if (!$script:TestMode -and !$WhatIf) {
                $terminalProcesses = Get-Process -Name "WindowsTerminal*" -ErrorAction SilentlyContinue
                if ($terminalProcesses) {
                    if ($PSCmdlet.ShouldProcess("Terminal processes", "Stop")) {
                        try {
                            $terminalProcesses | Stop-Process -Force -ErrorAction SilentlyContinue
                            Write-Verbose "Stopped terminal processes for restoration"
                        } catch {
                            Write-Verbose "Could not stop some terminal processes: $_"
                        }
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
                                            $errors += "Failed to import registry file $($regFile.Name)`: $_"
                                            Write-Warning "Failed to import registry file $($regFile.Name)"
                                        }
                                    }
                                }
                                
                                "Restore-TerminalSettings" {
                                    try {
                                        $destinationPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
                                        $destinationDir = Split-Path $destinationPath -Parent
                                        
                                        if (!$script:TestMode) {
                                            # Create destination directory if it doesn't exist
                                            if (!(Test-Path $destinationDir)) {
                                                New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
                                            }
                                            Copy-Item -Path $itemPath -Destination $destinationPath -Force
                                        }
                                        $itemsRestored += "Windows Terminal settings"
                                    } catch {
                                        $errors += "Failed to restore Windows Terminal settings`: $_"
                                        Write-Warning "Failed to restore Windows Terminal settings"
                                    }
                                }
                                
                                "Restore-TerminalPreviewSettings" {
                                    try {
                                        $destinationPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json"
                                        $destinationDir = Split-Path $destinationPath -Parent
                                        
                                        if (!$script:TestMode) {
                                            # Create destination directory if it doesn't exist
                                            if (!(Test-Path $destinationDir)) {
                                                New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
                                            }
                                            Copy-Item -Path $itemPath -Destination $destinationPath -Force
                                        }
                                        $itemsRestored += "Windows Terminal Preview settings"
                                    } catch {
                                        $errors += "Failed to restore Windows Terminal Preview settings`: $_"
                                        Write-Warning "Failed to restore Windows Terminal Preview settings"
                                    }
                                }
                                
                                "Restore-TerminalState" {
                                    try {
                                        $destinationPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\state.json"
                                        $destinationDir = Split-Path $destinationPath -Parent
                                        
                                        if (!$script:TestMode) {
                                            # Create destination directory if it doesn't exist
                                            if (!(Test-Path $destinationDir)) {
                                                New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
                                            }
                                            Copy-Item -Path $itemPath -Destination $destinationPath -Force
                                        }
                                        $itemsRestored += "Windows Terminal state"
                                    } catch {
                                        $errors += "Failed to restore Windows Terminal state`: $_"
                                        Write-Warning "Failed to restore Windows Terminal state"
                                    }
                                }
                                
                                "Restore-TerminalPreviewState" {
                                    try {
                                        $destinationPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\state.json"
                                        $destinationDir = Split-Path $destinationPath -Parent
                                        
                                        if (!$script:TestMode) {
                                            # Create destination directory if it doesn't exist
                                            if (!(Test-Path $destinationDir)) {
                                                New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
                                            }
                                            Copy-Item -Path $itemPath -Destination $destinationPath -Force
                                        }
                                        $itemsRestored += "Windows Terminal Preview state"
                                    } catch {
                                        $errors += "Failed to restore Windows Terminal Preview state`: $_"
                                        Write-Warning "Failed to restore Windows Terminal Preview state"
                                    }
                                }
                                
                                "Restore-TerminalProfiles" {
                                    try {
                                        $destinationPath = "$env:LOCALAPPDATA\Microsoft\Windows Terminal"
                                        
                                        if (!$script:TestMode) {
                                            # Create destination directory if it doesn't exist
                                            if (!(Test-Path $destinationPath)) {
                                                New-Item -ItemType Directory -Path $destinationPath -Force | Out-Null
                                            }
                                            
                                            # Copy subdirectories (Fragments, Themes, Icons)
                                            $subDirectories = Get-ChildItem -Path $itemPath -Directory -ErrorAction SilentlyContinue
                                            foreach ($subDir in $subDirectories) {
                                                $destSubDir = Join-Path $destinationPath $subDir.Name
                                                Copy-Item -Path $subDir.FullName -Destination $destSubDir -Recurse -Force
                                                Write-Verbose "Restored terminal $($subDir.Name)"
                                            }
                                        }
                                        $itemsRestored += "Terminal profiles, themes, and fragments"
                                    } catch {
                                        $errors += "Failed to restore terminal profiles`: $_"
                                        Write-Warning "Failed to restore terminal profiles"
                                    }
                                }
                                
                                "Restore-PowerShellProfiles" {
                                    try {
                                        $profileFiles = Get-ChildItem -Path $itemPath -Filter "*.ps1" -ErrorAction SilentlyContinue
                                        
                                        foreach ($profileFile in $profileFiles) {
                                            $profileName = [System.IO.Path]::GetFileNameWithoutExtension($profileFile.Name)
                                            
                                            # Map profile names back to their original paths
                                            $destinationPath = switch ($profileName) {
                                                "PowerShell-AllUsersAllHosts" { "$env:ProgramFiles\PowerShell\7\profile.ps1" }
                                                "PowerShell-AllUsersCurrentHost" { "$env:ProgramFiles\PowerShell\7\Microsoft.PowerShell_profile.ps1" }
                                                "PowerShell-CurrentUserAllHosts" { "$env:USERPROFILE\Documents\PowerShell\profile.ps1" }
                                                "PowerShell-CurrentUserCurrentHost" { "$env:USERPROFILE\Documents\PowerShell\Microsoft.PowerShell_profile.ps1" }
                                                "WindowsPowerShell-AllUsersAllHosts" { "$env:WINDIR\System32\WindowsPowerShell\v1.0\profile.ps1" }
                                                "WindowsPowerShell-AllUsersCurrentHost" { "$env:WINDIR\System32\WindowsPowerShell\v1.0\Microsoft.PowerShell_profile.ps1" }
                                                "WindowsPowerShell-CurrentUserAllHosts" { "$env:USERPROFILE\Documents\WindowsPowerShell\profile.ps1" }
                                                "WindowsPowerShell-CurrentUserCurrentHost" { "$env:USERPROFILE\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1" }
                                                default { $null }
                                            }
                                            
                                            if ($destinationPath -and !$script:TestMode) {
                                                try {
                                                    $destinationDir = Split-Path $destinationPath -Parent
                                                    if (!(Test-Path $destinationDir)) {
                                                        New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
                                                    }
                                                    Copy-Item -Path $profileFile.FullName -Destination $destinationPath -Force
                                                    Write-Verbose "Restored PowerShell profile: $profileName"
                                                } catch {
                                                    Write-Verbose "Could not restore PowerShell profile $profileName (may require administrative privileges)`: $_"
                                                }
                                            }
                                        }
                                        
                                        $itemsRestored += "PowerShell profiles"
                                    } catch {
                                        $errors += "Failed to restore PowerShell profiles`: $_"
                                        Write-Warning "Failed to restore PowerShell profiles"
                                    }
                                }
                                
                                "Restore-PowerShellModules" {
                                    try {
                                        $userModulesFile = Join-Path $itemPath "user-modules.xml"
                                        if (Test-Path $userModulesFile) {
                                            $userModules = Import-Clixml $userModulesFile
                                            
                                            # This is informational only - modules need to be reinstalled
                                            Write-Verbose "PowerShell modules information available (modules need to be reinstalled manually)"
                                            foreach ($module in $userModules) {
                                                Write-Verbose "Module found in backup: $($module.Name)"
                                            }
                                        }
                                        
                                        $itemsRestored += "PowerShell modules information"
                                    } catch {
                                        $errors += "Failed to restore PowerShell modules information`: $_"
                                        Write-Warning "Failed to restore PowerShell modules information"
                                    }
                                }
                                
                                "Restore-DefaultTerminal" {
                                    try {
                                        $defaultTerminalSettings = Get-Content $itemPath | ConvertFrom-Json
                                        
                                        if (!$script:TestMode) {
                                            $startupKey = "HKCU:\Console\%%Startup"
                                            
                                            # Create the registry key if it doesn't exist
                                            if (!(Test-Path $startupKey)) {
                                                New-Item -Path $startupKey -Force | Out-Null
                                            }
                                            
                                            # Restore delegation settings
                                            if ($defaultTerminalSettings.DelegationTerminal) {
                                                Set-ItemProperty -Path $startupKey -Name "DelegationTerminal" -Value $defaultTerminalSettings.DelegationTerminal -ErrorAction SilentlyContinue
                                            }
                                            
                                            if ($defaultTerminalSettings.DelegationConsole) {
                                                Set-ItemProperty -Path $startupKey -Name "DelegationConsole" -Value $defaultTerminalSettings.DelegationConsole -ErrorAction SilentlyContinue
                                            }
                                        }
                                        
                                        $itemsRestored += "Default terminal application setting"
                                    } catch {
                                        $errors += "Failed to restore default terminal setting`: $_"
                                        Write-Warning "Failed to restore default terminal setting"
                                    }
                                }
                                
                                "Restore-ConsoleFonts" {
                                    try {
                                        $consoleFonts = Get-Content $itemPath | ConvertFrom-Json
                                        
                                        if (!$script:TestMode -and $consoleFonts) {
                                            $consoleKey = "HKCU:\Console"
                                            
                                            foreach ($fontSetting in $consoleFonts) {
                                                foreach ($property in $fontSetting.PSObject.Properties) {
                                                    try {
                                                        Set-ItemProperty -Path $consoleKey -Name $property.Name -Value $property.Value -ErrorAction SilentlyContinue
                                                    } catch {
                                                        Write-Verbose "Could not restore console font property $($property.Name)`: $_"
                                                    }
                                                }
                                            }
                                        }
                                        
                                        $itemsRestored += "Console font settings"
                                    } catch {
                                        $errors += "Failed to restore console font settings`: $_"
                                        Write-Warning "Failed to restore console font settings"
                                    }
                                }
                                
                                "Restore-TerminalApps" {
                                    try {
                                        $terminalApps = Get-Content $itemPath | ConvertFrom-Json
                                        
                                        # This is informational only - apps need to be installed separately
                                        Write-Verbose "Terminal application information available (apps need to be installed manually if missing)"
                                        foreach ($app in $terminalApps) {
                                            Write-Verbose "Terminal app found in backup: $($app.Name) v$($app.Version)"
                                        }
                                        
                                        $itemsRestored += "Terminal application information"
                                    } catch {
                                        $errors += "Failed to restore terminal application information`: $_"
                                        Write-Warning "Failed to restore terminal application information"
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
            
            # Return result object
            $result = [PSCustomObject]@{
                Success = $true
                BackupPath = $backupPath
                Feature = "Terminal Settings"
                Timestamp = Get-Date
                ItemsRestored = $itemsRestored
                ItemsSkipped = $itemsSkipped
                Errors = $errors
            }
            
            Write-Host "Terminal Settings restored successfully from: $backupPath" -ForegroundColor Green
            Write-Host "`nNote: You may need to restart terminal applications to see all changes" -ForegroundColor Yellow
            Write-Verbose "Restore completed successfully"
            return $result
            
        } catch {
            $errorRecord = $_
            $errorMessage = @(
                "Failed to restore Terminal Settings"
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
    Export-ModuleMember -Function Restore-TerminalSettings
}

<#
.SYNOPSIS
Restores comprehensive Windows Terminal settings, PowerShell profiles, and console configurations from backup.

.DESCRIPTION
Restores a comprehensive backup of Windows Terminal and Windows Terminal Preview settings, 
PowerShell profiles, console configurations, terminal application information, and related 
registry settings. Handles both user-specific and system-wide terminal configurations with 
proper error handling and process management.

.PARAMETER BackupRootPath
The root path where the backup is located. The script will look for a "Terminal" subdirectory within this path.

.PARAMETER Force
Forces the restore operation even if it might overwrite existing settings.

.PARAMETER Include
Specifies which components to restore. Valid values: Registry, TerminalSettings, TerminalPreviewSettings, TerminalState, TerminalPreviewState, TerminalProfiles, PowerShellProfiles, PowerShellModules, DefaultTerminal, ConsoleFonts, TerminalApps.

.PARAMETER Exclude
Specifies which components to exclude from restoration. Valid values: Registry, TerminalSettings, TerminalPreviewSettings, TerminalState, TerminalPreviewState, TerminalProfiles, PowerShellProfiles, PowerShellModules, DefaultTerminal, ConsoleFonts, TerminalApps.

.PARAMETER SkipVerification
Skips verification steps during the restore process.

.PARAMETER WhatIf
Shows what would be restored without actually performing the restore operation.

.EXAMPLE
Restore-TerminalSettings -BackupRootPath "C:\Backups"

.EXAMPLE
Restore-TerminalSettings -BackupRootPath "C:\Backups" -Include @("TerminalSettings", "PowerShellProfiles")

.EXAMPLE
Restore-TerminalSettings -BackupRootPath "C:\Backups" -Exclude @("TerminalApps") -WhatIf

.NOTES
Test cases to consider:
1. Valid backup path with all components
2. Invalid/nonexistent backup path
3. Partial backup (missing some components)
4. Registry import success/failure
5. Terminal settings restore success/failure
6. Terminal state restore success/failure
7. PowerShell profiles restore success/failure
8. Default terminal setting restore success/failure
9. Console fonts restore success/failure
10. Terminal profiles restore success/failure
11. PowerShell modules information restore success/failure
12. Terminal application information restore success/failure
13. Include parameter filtering
14. Exclude parameter filtering
15. Windows Terminal installation scenarios
16. Terminal process management
17. Administrative privileges scenarios
18. File copy operations success/failure
19. Directory creation success/failure
20. Test mode scenarios

.TESTCASES
# Mock test examples:
Describe "Restore-TerminalSettings" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Join-Path { return "TestPath" }
        Mock Get-ChildItem { 
            param($Path, $Filter)
            if ($Filter -eq "*.reg") {
                return @([PSCustomObject]@{ FullName = "test.reg"; Name = "test.reg" })
            } elseif ($Filter -eq "*.ps1") {
                return @([PSCustomObject]@{ FullName = "test.ps1"; Name = "PowerShell-CurrentUserCurrentHost.ps1" })
            } else {
                return @([PSCustomObject]@{ Name = "Fragments"; FullName = "TestPath\Fragments" })
            }
        }
        Mock Get-Content { return '{"test":"value"}' | ConvertFrom-Json }
        Mock Import-Clixml { return @(@{ Name = "TestModule"; Path = "TestPath" }) }
        Mock Get-AppxPackage { return @{ Name = "Microsoft.WindowsTerminal" } }
        Mock Get-Process { return @() }
        Mock New-Item { }
        Mock Copy-Item { }
        Mock Set-ItemProperty { }
        Mock winget { }
        Mock reg { }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Restore-TerminalSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.BackupPath | Should -Be "TestPath"
        $result.Feature | Should -Be "Terminal Settings"
        $result.ItemsRestored | Should -BeOfType [System.Array]
        $result.ItemsSkipped | Should -BeOfType [System.Array]
        $result.Errors | Should -BeOfType [System.Array]
    }

    It "Should handle registry import failure gracefully" {
        Mock reg { throw "Registry import failed" }
        $result = Restore-TerminalSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle file copy failure gracefully" {
        Mock Copy-Item { throw "File copy failed" }
        $result = Restore-TerminalSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should support Include parameter" {
        $result = Restore-TerminalSettings -BackupRootPath "TestPath" -Include @("TerminalSettings")
        $result.Success | Should -Be $true
    }

    It "Should support Exclude parameter" {
        $result = Restore-TerminalSettings -BackupRootPath "TestPath" -Exclude @("TerminalApps")
        $result.Success | Should -Be $true
    }

    It "Should handle Windows Terminal installation failure gracefully" {
        Mock winget { throw "Installation failed" }
        $result = Restore-TerminalSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
    }

    It "Should handle missing backup components gracefully" {
        Mock Test-Path { param($Path) return $Path -notlike "*terminal-settings*" }
        $result = Restore-TerminalSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.ItemsSkipped.Count | Should -BeGreaterThan 0
    }

    It "Should support WhatIf parameter" {
        $result = Restore-TerminalSettings -BackupRootPath "TestPath" -WhatIf
        $result.Success | Should -Be $true
    }

    It "Should handle PowerShell profile restore failure gracefully" {
        Mock Copy-Item { param($Path, $Destination) if ($Destination -like "*PowerShell*") { throw "Profile restore failed" } }
        $result = Restore-TerminalSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Restore-TerminalSettings -BackupRootPath $BackupRootPath -Force:$Force -Include $Include -Exclude $Exclude -SkipVerification:$SkipVerification
} 