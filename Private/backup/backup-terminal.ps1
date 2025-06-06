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

function Backup-TerminalSettings {
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
            Write-Verbose "Starting backup of Terminal Settings..."
            Write-Host "Backing up Terminal Settings..." -ForegroundColor Blue
            
            # Validate inputs before proceeding
            if (!(Test-Path $BackupRootPath)) {
                throw [System.IO.DirectoryNotFoundException]"Backup root path not found: $BackupRootPath"
            }
            
            $backupPath = Initialize-BackupDirectory -Path "Terminal" -BackupType "Terminal Settings" -BackupRootPath $BackupRootPath
            
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

                # Terminal-related registry settings to backup
                $registryPaths = @(
                    # Console settings
                    "HKCU\Console",
                    "HKLM\SOFTWARE\Microsoft\Command Processor",
                    
                    # Windows Terminal settings
                    "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\wt.exe",
                    "HKCU\SOFTWARE\Classes\Directory\Background\shell\wt",
                    "HKCU\SOFTWARE\Classes\Directory\shell\wt",
                    
                    # Default terminal application
                    "HKCU\Console\%%Startup",
                    
                    # PowerShell settings
                    "HKCU\SOFTWARE\Microsoft\PowerShell",
                    "HKLM\SOFTWARE\Microsoft\PowerShell",
                    
                    # Command prompt settings
                    "HKCU\SOFTWARE\Microsoft\Command Processor",
                    "HKLM\SOFTWARE\Microsoft\Command Processor"
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

                # Windows Terminal settings
                $terminalSettingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
                if (Test-Path $terminalSettingsPath) {
                    $destinationPath = Join-Path $backupPath "terminal-settings.json"
                    if ($WhatIf) {
                        Write-Host "WhatIf: Would copy $terminalSettingsPath to $destinationPath"
                    } else {
                        try {
                            Copy-Item -Path $terminalSettingsPath -Destination $destinationPath -Force
                            $backedUpItems += "terminal-settings.json"
                        } catch {
                            $errors += "Failed to backup Windows Terminal settings: $_"
                        }
                    }
                }

                # Windows Terminal Preview settings
                $previewSettingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json"
                if (Test-Path $previewSettingsPath) {
                    $destinationPath = Join-Path $backupPath "terminal-preview-settings.json"
                    if ($WhatIf) {
                        Write-Host "WhatIf: Would copy $previewSettingsPath to $destinationPath"
                    } else {
                        try {
                            Copy-Item -Path $previewSettingsPath -Destination $destinationPath -Force
                            $backedUpItems += "terminal-preview-settings.json"
                        } catch {
                            $errors += "Failed to backup Windows Terminal Preview settings: $_"
                        }
                    }
                }

                # Windows Terminal state files
                $terminalStatePath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\state.json"
                if (Test-Path $terminalStatePath) {
                    $destinationPath = Join-Path $backupPath "terminal-state.json"
                    if ($WhatIf) {
                        Write-Host "WhatIf: Would copy $terminalStatePath to $destinationPath"
                    } else {
                        try {
                            Copy-Item -Path $terminalStatePath -Destination $destinationPath -Force
                            $backedUpItems += "terminal-state.json"
                        } catch {
                            $errors += "Failed to backup Windows Terminal state: $_"
                        }
                    }
                }

                # Windows Terminal Preview state files
                $previewStatePath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\state.json"
                if (Test-Path $previewStatePath) {
                    $destinationPath = Join-Path $backupPath "terminal-preview-state.json"
                    if ($WhatIf) {
                        Write-Host "WhatIf: Would copy $previewStatePath to $destinationPath"
                    } else {
                        try {
                            Copy-Item -Path $previewStatePath -Destination $destinationPath -Force
                            $backedUpItems += "terminal-preview-state.json"
                        } catch {
                            $errors += "Failed to backup Windows Terminal Preview state: $_"
                        }
                    }
                }

                # Terminal profiles directory
                $profilesPath = "$env:LOCALAPPDATA\Microsoft\Windows Terminal"
                if (Test-Path $profilesPath) {
                    $destinationPath = Join-Path $backupPath "Profiles"
                    if ($WhatIf) {
                        Write-Host "WhatIf: Would copy $profilesPath to $destinationPath"
                    } else {
                        try {
                            # Create destination directory
                            New-Item -ItemType Directory -Path $destinationPath -Force | Out-Null
                            
                            # Copy profiles, fragments, themes, and icons
                            $subDirectories = @("Fragments", "Themes", "Icons")
                            foreach ($subDir in $subDirectories) {
                                $sourcePath = Join-Path $profilesPath $subDir
                                if (Test-Path $sourcePath) {
                                    $destPath = Join-Path $destinationPath $subDir
                                    Copy-Item -Path $sourcePath -Destination $destPath -Recurse -Force
                                    $backedUpItems += "Profiles\$subDir"
                                }
                            }
                        } catch {
                            $errors += "Failed to backup Windows Terminal profiles: $_"
                        }
                    }
                }

                # PowerShell profiles
                $powerShellProfilePaths = @(
                    @{
                        Name = "PowerShell-AllUsersAllHosts"
                        Path = "$env:ProgramFiles\PowerShell\7\profile.ps1"
                    },
                    @{
                        Name = "PowerShell-AllUsersCurrentHost"
                        Path = "$env:ProgramFiles\PowerShell\7\Microsoft.PowerShell_profile.ps1"
                    },
                    @{
                        Name = "PowerShell-CurrentUserAllHosts"
                        Path = "$env:USERPROFILE\Documents\PowerShell\profile.ps1"
                    },
                    @{
                        Name = "PowerShell-CurrentUserCurrentHost"
                        Path = "$env:USERPROFILE\Documents\PowerShell\Microsoft.PowerShell_profile.ps1"
                    },
                    @{
                        Name = "WindowsPowerShell-AllUsersAllHosts"
                        Path = "$env:WINDIR\System32\WindowsPowerShell\v1.0\profile.ps1"
                    },
                    @{
                        Name = "WindowsPowerShell-AllUsersCurrentHost"
                        Path = "$env:WINDIR\System32\WindowsPowerShell\v1.0\Microsoft.PowerShell_profile.ps1"
                    },
                    @{
                        Name = "WindowsPowerShell-CurrentUserAllHosts"
                        Path = "$env:USERPROFILE\Documents\WindowsPowerShell\profile.ps1"
                    },
                    @{
                        Name = "WindowsPowerShell-CurrentUserCurrentHost"
                        Path = "$env:USERPROFILE\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"
                    }
                )

                $profilesBackupPath = Join-Path $backupPath "PowerShellProfiles"
                if ($WhatIf) {
                    Write-Host "WhatIf: Would create PowerShell profiles backup directory at $profilesBackupPath"
                } else {
                    New-Item -ItemType Directory -Path $profilesBackupPath -Force | Out-Null
                }

                foreach ($profileInfo in $powerShellProfilePaths) {
                    if (Test-Path $profileInfo.Path) {
                        $destinationPath = Join-Path $profilesBackupPath "$($profileInfo.Name).ps1"
                        if ($WhatIf) {
                            Write-Host "WhatIf: Would copy $($profileInfo.Path) to $destinationPath"
                        } else {
                            try {
                                Copy-Item -Path $profileInfo.Path -Destination $destinationPath -Force
                                $backedUpItems += "PowerShellProfiles\$($profileInfo.Name).ps1"
                            } catch {
                                $errors += "Failed to backup PowerShell profile $($profileInfo.Name): $_"
                            }
                        }
                    }
                }

                # PowerShell modules (user-installed)
                $userModulesPath = "$env:USERPROFILE\Documents\PowerShell\Modules"
                if (Test-Path $userModulesPath) {
                    $destinationPath = Join-Path $backupPath "PowerShellModules"
                    if ($WhatIf) {
                        Write-Host "WhatIf: Would backup PowerShell modules from $userModulesPath"
                    } else {
                        try {
                            # Get list of user-installed modules
                            $userModules = Get-ChildItem -Path $userModulesPath -Directory -ErrorAction SilentlyContinue
                            if ($userModules) {
                                $moduleList = $userModules | Select-Object Name, @{Name="Path";Expression={$_.FullName}}
                                $moduleList | Export-Clixml (Join-Path $destinationPath "user-modules.xml")
                                $backedUpItems += "PowerShellModules\user-modules.xml"
                            }
                        } catch {
                            $errors += "Failed to backup PowerShell modules list: $_"
                        }
                    }
                }

                # Default terminal application setting
                if ($WhatIf) {
                    Write-Host "WhatIf: Would backup default terminal application setting"
                } else {
                    try {
                        $defaultTerminalSetting = @{
                            DefaultTerminal = $null
                            DelegationConsole = $null
                            DelegationTerminal = $null
                        }
                        
                        # Check for default terminal setting
                        $startupKey = "HKCU:\Console\%%Startup"
                        if (Test-Path $startupKey) {
                            $delegationTerminal = Get-ItemProperty -Path $startupKey -Name "DelegationTerminal" -ErrorAction SilentlyContinue
                            if ($delegationTerminal) {
                                $defaultTerminalSetting.DelegationTerminal = $delegationTerminal.DelegationTerminal
                            }
                            
                            $delegationConsole = Get-ItemProperty -Path $startupKey -Name "DelegationConsole" -ErrorAction SilentlyContinue
                            if ($delegationConsole) {
                                $defaultTerminalSetting.DelegationConsole = $delegationConsole.DelegationConsole
                            }
                        }
                        
                        $defaultTerminalSetting | ConvertTo-Json | Out-File (Join-Path $backupPath "default-terminal.json") -Force
                        $backedUpItems += "default-terminal.json"
                    } catch {
                        $errors += "Failed to backup default terminal setting: $_"
                    }
                }

                # Console font settings
                if ($WhatIf) {
                    Write-Host "WhatIf: Would backup console font settings"
                } else {
                    try {
                        $consoleFonts = @()
                        $consoleKey = "HKCU:\Console"
                        if (Test-Path $consoleKey) {
                            $fontProperties = @("FaceName", "FontFamily", "FontSize", "FontWeight")
                            $fontSettings = @{}
                            
                            foreach ($prop in $fontProperties) {
                                $value = Get-ItemProperty -Path $consoleKey -Name $prop -ErrorAction SilentlyContinue
                                if ($value) {
                                    $fontSettings[$prop] = $value.$prop
                                }
                            }
                            
                            if ($fontSettings.Count -gt 0) {
                                $consoleFonts += $fontSettings
                            }
                        }
                        
                        $consoleFonts | ConvertTo-Json | Out-File (Join-Path $backupPath "console-fonts.json") -Force
                        $backedUpItems += "console-fonts.json"
                    } catch {
                        $errors += "Failed to backup console font settings: $_"
                    }
                }

                # Terminal application information
                if ($WhatIf) {
                    Write-Host "WhatIf: Would backup terminal application information"
                } else {
                    try {
                        $terminalApps = @()
                        
                        # Windows Terminal
                        $windowsTerminal = Get-AppxPackage -Name "Microsoft.WindowsTerminal" -ErrorAction SilentlyContinue
                        if ($windowsTerminal) {
                            $terminalApps += @{
                                Name = "Windows Terminal"
                                PackageName = $windowsTerminal.Name
                                Version = $windowsTerminal.Version
                                InstallLocation = $windowsTerminal.InstallLocation
                            }
                        }
                        
                        # Windows Terminal Preview
                        $windowsTerminalPreview = Get-AppxPackage -Name "Microsoft.WindowsTerminalPreview" -ErrorAction SilentlyContinue
                        if ($windowsTerminalPreview) {
                            $terminalApps += @{
                                Name = "Windows Terminal Preview"
                                PackageName = $windowsTerminalPreview.Name
                                Version = $windowsTerminalPreview.Version
                                InstallLocation = $windowsTerminalPreview.InstallLocation
                            }
                        }
                        
                        $terminalApps | ConvertTo-Json | Out-File (Join-Path $backupPath "terminal-apps.json") -Force
                        $backedUpItems += "terminal-apps.json"
                    } catch {
                        $errors += "Failed to backup terminal application information: $_"
                    }
                }
                
                # Return object for better testing and validation
                $result = [PSCustomObject]@{
                    Success = $true
                    BackupPath = $backupPath
                    Feature = "Terminal Settings"
                    Timestamp = Get-Date
                    Items = $backedUpItems
                    Errors = $errors
                }
                
                Write-Host "Terminal Settings backed up successfully to: $backupPath" -ForegroundColor Green
                Write-Verbose "Backup completed successfully"
                return $result
            }
            return $false
        } catch {
            $errorRecord = $_
            $errorMessage = @(
                "Failed to backup Terminal Settings"
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
    Export-ModuleMember -Function Backup-TerminalSettings
}

<#
.SYNOPSIS
Backs up comprehensive Windows Terminal settings, PowerShell profiles, and console configurations.

.DESCRIPTION
Creates a comprehensive backup of Windows Terminal and Windows Terminal Preview settings, 
PowerShell profiles, console configurations, terminal application information, and related 
registry settings. Handles both user-specific and system-wide terminal configurations.

.PARAMETER BackupRootPath
The root path where the backup will be created. A subdirectory named "Terminal" will be created within this path.

.PARAMETER Force
Forces the backup operation even if the destination already exists.

.PARAMETER WhatIf
Shows what would be backed up without actually performing the backup operation.

.EXAMPLE
Backup-TerminalSettings -BackupRootPath "C:\Backups"

.EXAMPLE
Backup-TerminalSettings -BackupRootPath "C:\Backups" -WhatIf

.NOTES
Test cases to consider:
1. Valid backup path with proper permissions
2. Invalid/nonexistent backup path
3. Empty backup path
4. No permissions to write
5. Windows Terminal installed vs not installed
6. Windows Terminal Preview installed vs not installed
7. PowerShell profiles exist vs don't exist
8. Registry export success/failure for each key
9. Terminal settings file exists/doesn't exist
10. Terminal state files exist/don't exist
11. PowerShell modules directory exists/doesn't exist
12. Console font settings exist/don't exist
13. Default terminal application setting exists/doesn't exist
14. Terminal application information retrieval success/failure
15. File copy operations success/failure
16. Directory creation success/failure
17. Network path scenarios
18. Administrative privileges scenarios
19. Multiple PowerShell versions scenarios
20. Terminal profiles, fragments, themes, and icons scenarios

.TESTCASES
# Mock test examples:
Describe "Backup-TerminalSettings" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Initialize-BackupDirectory { return "TestPath" }
        Mock New-Item { }
        Mock Copy-Item { }
        Mock Get-ChildItem { return @() }
        Mock Export-Clixml { }
        Mock Get-AppxPackage { return @{ Name = "Microsoft.WindowsTerminal"; Version = "1.0.0"; InstallLocation = "C:\Test" } }
        Mock Get-ItemProperty { return @{ DelegationTerminal = "Windows Terminal" } }
        Mock ConvertTo-Json { return '{"test":"value"}' }
        Mock Out-File { }
        Mock reg { $global:LASTEXITCODE = 0 }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Backup-TerminalSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.BackupPath | Should -Be "TestPath"
        $result.Feature | Should -Be "Terminal Settings"
        $result.Items | Should -BeOfType [System.Array]
        $result.Errors | Should -BeOfType [System.Array]
    }

    It "Should handle registry export failure gracefully" {
        Mock reg { $global:LASTEXITCODE = 1; return "Error" }
        $result = Backup-TerminalSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle file copy failure gracefully" {
        Mock Copy-Item { throw "File copy failed" }
        $result = Backup-TerminalSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should support WhatIf parameter" {
        $result = Backup-TerminalSettings -BackupRootPath "TestPath" -WhatIf
        $result.Success | Should -Be $true
    }

    It "Should handle missing terminal applications gracefully" {
        Mock Get-AppxPackage { return $null }
        $result = Backup-TerminalSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
    }

    It "Should handle PowerShell profiles backup failure gracefully" {
        Mock Get-ChildItem { throw "Directory access failed" }
        $result = Backup-TerminalSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle registry access failure gracefully" {
        Mock Get-ItemProperty { throw "Registry access failed" }
        $result = Backup-TerminalSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It "Should handle missing terminal settings files gracefully" {
        Mock Test-Path { param($Path) return $Path -notlike "*terminal*" }
        $result = Backup-TerminalSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
    }

    It "Should handle terminal application information failure gracefully" {
        Mock Get-AppxPackage { throw "AppX query failed" }
        $result = Backup-TerminalSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Backup-TerminalSettings -BackupRootPath $BackupRootPath
} 