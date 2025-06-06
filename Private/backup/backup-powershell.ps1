[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$BackupRootPath = $null,
    
    [Parameter(Mandatory=$false)]
    [string]$MachineBackupPath = $null,
    
    [Parameter(Mandatory=$false)]
    [string]$SharedBackupPath = $null,
    
    [Parameter(Mandatory=$false)]
    [switch]$Force,

    # For testing purposes
    [Parameter(DontShow)]
    [switch]$WhatIf
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

# Set default paths if not provided
if (!$BackupRootPath) {
    $BackupRootPath = Join-Path $config.BackupRoot $config.MachineName
}
if (!$MachineBackupPath) {
    $MachineBackupPath = $BackupRootPath
}
if (!$SharedBackupPath) {
    $SharedBackupPath = Join-Path $config.BackupRoot "shared"
}

# Define Initialize-BackupDirectory function directly in the script
function Initialize-BackupDirectory {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Path,
        
        [Parameter(Mandatory=$true)]
        [string]$BackupType,
        
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath,
        
        [Parameter(Mandatory=$false)]
        [switch]$IsShared
    )
    
    # Create backup directory if it doesn't exist
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

function Backup-PowerShellSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath,
        
        [Parameter(Mandatory=$true)]
        [string]$MachineBackupPath,
        
        [Parameter(Mandatory=$true)]
        [string]$SharedBackupPath,
        
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
            Write-Verbose "Starting backup of PowerShell Settings..."
            Write-Host "Backing up PowerShell Settings..." -ForegroundColor Blue
            
            # Validate inputs before proceeding
            if (!(Test-Path $BackupRootPath)) {
                throw [System.IO.DirectoryNotFoundException]"Backup root path not found: $BackupRootPath"
            }
            if (!(Test-Path $MachineBackupPath)) {
                throw [System.IO.DirectoryNotFoundException]"Machine backup path not found: $MachineBackupPath"
            }
            if (!(Test-Path $SharedBackupPath)) {
                throw [System.IO.DirectoryNotFoundException]"Shared backup path not found: $SharedBackupPath"
            }
            
            $backupPath = Initialize-BackupDirectory -Path "PowerShell" -BackupType "PowerShell Settings" -BackupRootPath $MachineBackupPath
            $sharedBackupPath = Initialize-BackupDirectory -Path "PowerShell" -BackupType "Shared PowerShell Settings" -BackupRootPath $SharedBackupPath -IsShared
            $backedUpItems = @()
            $errors = @()
            
            if ($backupPath -and $sharedBackupPath) {
                # Export PowerShell registry settings
                $regPaths = @(
                    # PowerShell execution policy
                    "HKLM\SOFTWARE\Microsoft\PowerShell\1\ShellIds\Microsoft.PowerShell",
                    "HKLM\SOFTWARE\Microsoft\PowerShell\3\ShellIds\Microsoft.PowerShell",
                    "HKLM\SOFTWARE\Wow6432Node\Microsoft\PowerShell\1\ShellIds\Microsoft.PowerShell",
                    
                    # PowerShell module logging
                    "HKLM\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging",
                    "HKLM\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging",
                    
                    # PowerShell transcription
                    "HKLM\SOFTWARE\Policies\Microsoft\Windows\PowerShell\Transcription",
                    
                    # PSReadLine settings
                    "HKCU\Console",
                    "HKCU\Software\Microsoft\PowerShell",
                    
                    # Additional PowerShell settings
                    "HKLM\SOFTWARE\Microsoft\PowerShell",
                    "HKLM\SOFTWARE\Microsoft\PowerShellCore",
                    "HKCU\Software\Microsoft\PowerShellCore"
                )

                foreach ($regPath in $regPaths) {
                    # Check if registry key exists before trying to export
                    $keyExists = $false
                    if ($regPath -match '^HKCU\\') {
                        $keyExists = Test-Path "Registry::HKEY_CURRENT_USER\$($regPath.Substring(5))"
                    } elseif ($regPath -match '^HKLM\\') {
                        $keyExists = Test-Path "Registry::HKEY_LOCAL_MACHINE\$($regPath.Substring(5))"
                    }
                    
                    if ($keyExists) {
                        try {
                            $regFile = "$backupPath\$($regPath.Split('\')[-1]).reg"
                            $sharedRegFile = "$sharedBackupPath\$($regPath.Split('\')[-1]).reg"
                            if ($WhatIf) {
                                Write-Host "WhatIf: Would export registry key: $regPath to $regFile and $sharedRegFile"
                            } else {
                                $result = reg export $regPath $regFile /y 2>&1
                                if ($LASTEXITCODE -eq 0) {
                                    Copy-Item $regFile $sharedRegFile -Force
                                    $backedUpItems += $regFile
                                } else {
                                    $errors += "Could not export registry key: $regPath"
                                }
                            }
                        } catch {
                            $errors += "Failed to export registry key: $regPath - $($_.Exception.Message)"
                        }
                    }
                }

                # Export PowerShell profiles and modules
                $psConfigPaths = @{
                    "WindowsPowerShell" = "$env:USERPROFILE\Documents\WindowsPowerShell"
                    "PowerShell" = "$env:USERPROFILE\Documents\PowerShell"
                    "SystemPowerShell" = "$env:ProgramFiles\PowerShell"
                }

                foreach ($config in $psConfigPaths.GetEnumerator()) {
                    if (Test-Path $config.Value) {
                        $destPath = Join-Path $backupPath $config.Key
                        $sharedDestPath = Join-Path $sharedBackupPath $config.Key
                        if ($WhatIf) {
                            Write-Host "WhatIf: Would copy $($config.Value) to $destPath and $sharedDestPath"
                        } else {
                            New-Item -ItemType Directory -Path $destPath -Force | Out-Null
                            New-Item -ItemType Directory -Path $sharedDestPath -Force | Out-Null
                            Copy-Item -Path "$($config.Value)\*" -Destination $destPath -Recurse -Force
                            Copy-Item -Path "$($config.Value)\*" -Destination $sharedDestPath -Recurse -Force
                            $backedUpItems += $config.Key
                        }
                    }
                }

                # Backup PowerShell profiles with unique names
                $profilePaths = @{
                    $PROFILE.AllUsersAllHosts = "AllUsers_AllHosts_profile.ps1"
                    $PROFILE.AllUsersCurrentHost = "AllUsers_CurrentHost_profile.ps1"
                    $PROFILE.CurrentUserAllHosts = "CurrentUser_AllHosts_profile.ps1"
                    $PROFILE.CurrentUserCurrentHost = "CurrentUser_CurrentHost_profile.ps1"
                }

                foreach ($profile in $profilePaths.GetEnumerator()) {
                    if (Test-Path $profile.Key) {
                        if ($WhatIf) {
                            Write-Host "WhatIf: Would copy $($profile.Key) to $backupPath\$($profile.Value) and $sharedBackupPath\$($profile.Value)"
                        } else {
                            Copy-Item -Path $profile.Key -Destination "$backupPath\$($profile.Value)" -Force
                            Copy-Item -Path $profile.Key -Destination "$sharedBackupPath\$($profile.Value)" -Force
                            $backedUpItems += $profile.Value
                        }
                    }
                }

                # Backup installed modules list
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export installed modules list to $backupPath\installed_modules.json and $sharedBackupPath\installed_modules.json"
                } else {
                    $installedModules = Get-InstalledModule | Select-Object Name, Version, Repository
                    $installedModules | ConvertTo-Json | Out-File "$backupPath\installed_modules.json" -Force
                    $installedModules | ConvertTo-Json | Out-File "$sharedBackupPath\installed_modules.json" -Force
                    $backedUpItems += "installed_modules.json"
                }

                # Backup NuGet package sources
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export NuGet sources to $backupPath\nuget_sources.json and $sharedBackupPath\nuget_sources.json"
                } else {
                    $nugetSources = Get-PackageSource | Select-Object Name, Location, ProviderName, IsTrusted
                    $nugetSources | ConvertTo-Json | Out-File "$backupPath\nuget_sources.json" -Force
                    $nugetSources | ConvertTo-Json | Out-File "$sharedBackupPath\nuget_sources.json" -Force
                    $backedUpItems += "nuget_sources.json"
                }

                # Backup PSRepository settings
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export PS repositories to $backupPath\ps_repositories.json and $sharedBackupPath\ps_repositories.json"
                } else {
                    $psRepositories = Get-PSRepository | Select-Object Name, SourceLocation, PublishLocation, InstallationPolicy
                    $psRepositories | ConvertTo-Json | Out-File "$backupPath\ps_repositories.json" -Force
                    $psRepositories | ConvertTo-Json | Out-File "$sharedBackupPath\ps_repositories.json" -Force
                    $backedUpItems += "ps_repositories.json"
                }

                # Backup PSReadLine history
                $historyPath = "$env:APPDATA\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt"
                if (Test-Path $historyPath) {
                    if ($WhatIf) {
                        Write-Host "WhatIf: Would copy $historyPath to $backupPath\ConsoleHost_history.txt and $sharedBackupPath\ConsoleHost_history.txt"
                    } else {
                        Copy-Item -Path $historyPath -Destination "$backupPath\ConsoleHost_history.txt" -Force
                        Copy-Item -Path $historyPath -Destination "$sharedBackupPath\ConsoleHost_history.txt" -Force
                        $backedUpItems += "ConsoleHost_history.txt"
                    }
                }

                # Backup custom formats and types
                $customPaths = @(
                    "$env:USERPROFILE\Documents\WindowsPowerShell\Types",
                    "$env:USERPROFILE\Documents\WindowsPowerShell\Formats"
                )

                foreach ($path in $customPaths) {
                    if (Test-Path $path) {
                        $folderName = Split-Path $path -Leaf
                        $destPath = Join-Path $backupPath $folderName
                        $sharedDestPath = Join-Path $sharedBackupPath $folderName
                        if ($WhatIf) {
                            Write-Host "WhatIf: Would copy $path to $destPath and $sharedDestPath"
                        } else {
                            Copy-Item -Path $path -Destination $destPath -Recurse -Force
                            Copy-Item -Path $path -Destination $sharedDestPath -Recurse -Force
                            $backedUpItems += $folderName
                        }
                    }
                }

                # Backup module configurations
                $moduleConfigPath = "$env:USERPROFILE\Documents\WindowsPowerShell\Modules"
                if (Test-Path $moduleConfigPath) {
                    $moduleConfigBackupPath = Join-Path $backupPath "ModuleConfigs"
                    $moduleConfigSharedBackupPath = Join-Path $sharedBackupPath "ModuleConfigs"
                    if ($WhatIf) {
                        Write-Host "WhatIf: Would copy $moduleConfigPath to $moduleConfigBackupPath and $moduleConfigSharedBackupPath"
                    } else {
                        New-Item -ItemType Directory -Path $moduleConfigBackupPath -Force | Out-Null
                        New-Item -ItemType Directory -Path $moduleConfigSharedBackupPath -Force | Out-Null
                        Copy-Item -Path "$moduleConfigPath\*" -Destination $moduleConfigBackupPath -Recurse -Force
                        Copy-Item -Path "$moduleConfigPath\*" -Destination $moduleConfigSharedBackupPath -Recurse -Force
                        $backedUpItems += "ModuleConfigs"
                    }
                }

                # Return object for better testing and validation
                $result = [PSCustomObject]@{
                    Success = $true
                    BackupPath = $backupPath
                    SharedBackupPath = $sharedBackupPath
                    Feature = "PowerShell Settings"
                    Timestamp = Get-Date
                    Items = $backedUpItems
                    Errors = $errors
                }
                
                Write-Host "PowerShell Settings backed up successfully to: $backupPath" -ForegroundColor Green
                Write-Host "Shared PowerShell Settings backed up successfully to: $sharedBackupPath" -ForegroundColor Green
                Write-Verbose "Backup completed successfully"
                return $result
            }
            return $false
        } catch {
            $errorRecord = $_
            $errorMessage = @(
                "Failed to backup PowerShell Settings"
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
    Export-ModuleMember -Function Backup-PowerShellSettings
}

<#
.SYNOPSIS
Backs up PowerShell settings and configuration.

.DESCRIPTION
Creates a backup of PowerShell settings including:
- Registry settings for PowerShell execution policy, module logging, and transcription
- PSReadLine settings and history
- PowerShell profiles (AllUsers and CurrentUser)
- Installed modules and their versions
- NuGet package sources
- PowerShell repositories
- Custom formats and types
- Module configurations
- Both machine-specific and shared settings

.EXAMPLE
Backup-PowerShellSettings -BackupRootPath "C:\Backups" -MachineBackupPath "C:\Backups\Machine" -SharedBackupPath "C:\Backups\Shared"

.NOTES
Test cases to consider:
1. Valid backup paths with proper permissions
2. Invalid/nonexistent backup paths
3. Empty backup paths
4. No permissions to write
5. Registry keys exist/don't exist
6. Profile files exist/don't exist
7. Module configurations exist/don't exist

.TESTCASES
# Mock test examples:
Describe "Backup-PowerShellSettings" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Initialize-BackupDirectory { return "TestPath" }
        Mock Copy-Item { }
        Mock Get-InstalledModule { return @() }
        Mock Get-PackageSource { return @() }
        Mock Get-PSRepository { return @() }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Backup-PowerShellSettings -BackupRootPath "TestPath" -MachineBackupPath "TestPath\Machine" -SharedBackupPath "TestPath\Shared"
        $result.Success | Should -Be $true
        $result.BackupPath | Should -Be "TestPath"
        $result.SharedBackupPath | Should -Be "TestPath\Shared"
        $result.Feature | Should -Be "PowerShell Settings"
    }

    It "Should handle missing registry keys gracefully" {
        Mock Test-Path { return $false }
        $result = Backup-PowerShellSettings -BackupRootPath "TestPath" -MachineBackupPath "TestPath\Machine" -SharedBackupPath "TestPath\Shared"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Backup-PowerShellSettings -BackupRootPath $BackupRootPath -MachineBackupPath $MachineBackupPath -SharedBackupPath $SharedBackupPath
} 