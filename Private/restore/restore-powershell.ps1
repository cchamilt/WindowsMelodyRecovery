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

# Define Test-BackupPath function directly in the script
function Test-BackupPath {
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
    
    $backupPath = Join-Path $BackupRootPath $Path
    if (Test-Path -Path $backupPath) {
        Write-Host "Found backup directory for $BackupType at: $backupPath" -ForegroundColor Green
        return $backupPath
    } else {
        Write-Host "Backup directory for $BackupType not found at: $backupPath" -ForegroundColor Yellow
        return $null
    }
}

function Restore-PowerShellSettings {
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
            Write-Verbose "Starting restore of PowerShell Settings..."
            Write-Host "Restoring PowerShell Settings..." -ForegroundColor Blue
            
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
            
            $backupPath = Test-BackupPath -Path "PowerShell" -BackupType "PowerShell Settings" -BackupRootPath $MachineBackupPath
            $sharedBackupPath = Test-BackupPath -Path "PowerShell" -BackupType "Shared PowerShell Settings" -BackupRootPath $SharedBackupPath -IsShared
            $restoredItems = @()
            $errors = @()
            
            # Use machine backup path as primary, fall back to shared if needed
            $primaryBackupPath = if ($backupPath) { $backupPath } elseif ($sharedBackupPath) { $sharedBackupPath } else { $null }
            
            if ($primaryBackupPath) {
                # Restore registry settings from .reg files
                $regFiles = Get-ChildItem -Path "$primaryBackupPath\*.reg" -ErrorAction SilentlyContinue
                foreach ($regFile in $regFiles) {
                    if ($WhatIf) {
                        Write-Host "WhatIf: Would restore registry from $($regFile.FullName)"
                    } else {
                        try {
                            Write-Host "Restoring registry settings from $($regFile.Name)..." -ForegroundColor Yellow
                            reg import $regFile.FullName /y 2>$null
                            $restoredItems += $regFile.Name
                        } catch {
                            $errors += "Failed to restore registry from $($regFile.Name)`: $_"
                            Write-Warning "Failed to restore registry from $($regFile.Name)"
                        }
                    }
                }

                # Restore PowerShell profiles with unique names
                $profilePaths = @{
                    $PROFILE.AllUsersAllHosts = "AllUsers_AllHosts_profile.ps1"
                    $PROFILE.AllUsersCurrentHost = "AllUsers_CurrentHost_profile.ps1"
                    $PROFILE.CurrentUserAllHosts = "CurrentUser_AllHosts_profile.ps1"
                    $PROFILE.CurrentUserCurrentHost = "CurrentUser_CurrentHost_profile.ps1"
                }

                foreach ($profile in $profilePaths.GetEnumerator()) {
                    $sourcePath = Join-Path $primaryBackupPath $profile.Value
                    if (Test-Path $sourcePath) {
                        if ($WhatIf) {
                            Write-Host "WhatIf: Would restore profile $($profile.Value) to $($profile.Key)"
                        } else {
                            try {
                                $targetDir = Split-Path $profile.Key -Parent
                                if (!(Test-Path $targetDir)) {
                                    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
                                }
                                Copy-Item -Path $sourcePath -Destination $profile.Key -Force
                                Write-Host "Restored profile: $($profile.Value)" -ForegroundColor Green
                                $restoredItems += $profile.Value
                            } catch {
                                $errors += "Failed to restore profile $($profile.Value)`: $_"
                                Write-Warning "Failed to restore profile $($profile.Value)"
                            }
                        }
                    }
                }

                # Restore NuGet package sources
                $nugetSourcesFile = "$primaryBackupPath\nuget_sources.json"
                if (Test-Path $nugetSourcesFile) {
                    if ($WhatIf) {
                        Write-Host "WhatIf: Would restore NuGet sources from $nugetSourcesFile"
                    } else {
                        try {
                            Write-Host "Restoring NuGet package sources..." -ForegroundColor Yellow
                            $nugetSources = Get-Content $nugetSourcesFile | ConvertFrom-Json
                            foreach ($source in $nugetSources) {
                                # Remove existing source if it exists
                                Unregister-PackageSource -Name $source.Name -ErrorAction SilentlyContinue
                                # Register the package source
                                Register-PackageSource -Name $source.Name -Location $source.Location -ProviderName $source.ProviderName -Trusted:$source.IsTrusted -ErrorAction SilentlyContinue
                            }
                            Write-Host "NuGet package sources restored successfully" -ForegroundColor Green
                            $restoredItems += "nuget_sources.json"
                        } catch {
                            $errors += "Failed to restore NuGet sources`: $_"
                            Write-Warning "Failed to restore NuGet sources"
                        }
                    }
                }

                # Restore PSRepository settings
                $psRepositoriesFile = "$primaryBackupPath\ps_repositories.json"
                if (Test-Path $psRepositoriesFile) {
                    if ($WhatIf) {
                        Write-Host "WhatIf: Would restore PS repositories from $psRepositoriesFile"
                    } else {
                        try {
                            Write-Host "Restoring PowerShell repositories..." -ForegroundColor Yellow
                            $psRepositories = Get-Content $psRepositoriesFile | ConvertFrom-Json
                            foreach ($repo in $psRepositories) {
                                # Skip PSGallery as it's built-in
                                if ($repo.Name -ne "PSGallery") {
                                    # Unregister existing repository if it exists
                                    Unregister-PSRepository -Name $repo.Name -ErrorAction SilentlyContinue
                                    # Register the repository
                                    Register-PSRepository -Name $repo.Name -SourceLocation $repo.SourceLocation -PublishLocation $repo.PublishLocation -InstallationPolicy $repo.InstallationPolicy -ErrorAction SilentlyContinue
                                }
                            }
                            Write-Host "PowerShell repositories restored successfully" -ForegroundColor Green
                            $restoredItems += "ps_repositories.json"
                        } catch {
                            $errors += "Failed to restore PS repositories`: $_"
                            Write-Warning "Failed to restore PS repositories"
                        }
                    }
                }

                # Restore installed modules (informational - don't automatically install)
                $modulesFile = "$primaryBackupPath\installed_modules.json"
                if (Test-Path $modulesFile) {
                    if ($WhatIf) {
                        Write-Host "WhatIf: Would restore installed modules from $modulesFile"
                    } else {
                        try {
                            Write-Host "Restoring installed modules information..." -ForegroundColor Yellow
                            $modules = Get-Content $modulesFile | ConvertFrom-Json
                            Write-Host "Found $($modules.Count) modules in backup. Use Install-Module to restore them manually if needed." -ForegroundColor Green
                            $restoredItems += "installed_modules.json"
                        } catch {
                            $errors += "Failed to restore installed modules info`: $_"
                            Write-Warning "Failed to restore installed modules info"
                        }
                    }
                }

                # Restore PSReadLine history
                $historyFile = "$primaryBackupPath\ConsoleHost_history.txt"
                if (Test-Path $historyFile) {
                    if ($WhatIf) {
                        Write-Host "WhatIf: Would restore PSReadLine history from $historyFile"
                    } else {
                        try {
                            Write-Host "Restoring PSReadLine history..." -ForegroundColor Yellow
                            $historyPath = "$env:APPDATA\Microsoft\Windows\PowerShell\PSReadLine"
                            if (!(Test-Path $historyPath)) {
                                New-Item -ItemType Directory -Path $historyPath -Force | Out-Null
                            }
                            Copy-Item -Path $historyFile -Destination "$historyPath\ConsoleHost_history.txt" -Force
                            $restoredItems += "ConsoleHost_history.txt"
                        } catch {
                            $errors += "Failed to restore PSReadLine history`: $_"
                            Write-Warning "Failed to restore PSReadLine history"
                        }
                    }
                }

                # Restore custom formats and types
                $customPaths = @{
                    "Types" = "$env:USERPROFILE\Documents\WindowsPowerShell\Types"
                    "Formats" = "$env:USERPROFILE\Documents\WindowsPowerShell\Formats"
                }

                foreach ($path in $customPaths.GetEnumerator()) {
                    $sourcePath = Join-Path $primaryBackupPath $path.Key
                    if (Test-Path $sourcePath) {
                        if ($WhatIf) {
                            Write-Host "WhatIf: Would restore $($path.Key) from $sourcePath to $($path.Value)"
                        } else {
                            try {
                                Write-Host "Restoring $($path.Key)..." -ForegroundColor Yellow
                                if (!(Test-Path $path.Value)) {
                                    New-Item -ItemType Directory -Path $path.Value -Force | Out-Null
                                }
                                Copy-Item -Path "$sourcePath\*" -Destination $path.Value -Recurse -Force
                                $restoredItems += $path.Key
                            } catch {
                                $errors += "Failed to restore $($path.Key)`: $_"
                                Write-Warning "Failed to restore $($path.Key)"
                            }
                        }
                    }
                }

                # Restore module configurations
                $moduleConfigBackupPath = Join-Path $primaryBackupPath "ModuleConfigs"
                if (Test-Path $moduleConfigBackupPath) {
                    if ($WhatIf) {
                        Write-Host "WhatIf: Would restore module configurations from $moduleConfigBackupPath"
                    } else {
                        try {
                            Write-Host "Restoring module configurations..." -ForegroundColor Yellow
                            $moduleConfigPath = "$env:USERPROFILE\Documents\WindowsPowerShell\Modules"
                            if (!(Test-Path $moduleConfigPath)) {
                                New-Item -ItemType Directory -Path $moduleConfigPath -Force | Out-Null
                            }
                            Copy-Item -Path "$moduleConfigBackupPath\*" -Destination $moduleConfigPath -Recurse -Force
                            $restoredItems += "ModuleConfigs"
                        } catch {
                            $errors += "Failed to restore module configurations`: $_"
                            Write-Warning "Failed to restore module configurations"
                        }
                    }
                }

                # Restore PowerShell configuration directories
                $psConfigPaths = @{
                    "WindowsPowerShell" = "$env:USERPROFILE\Documents\WindowsPowerShell"
                    "PowerShell" = "$env:USERPROFILE\Documents\PowerShell"
                    "SystemPowerShell" = "$env:ProgramFiles\PowerShell"
                }

                foreach ($config in $psConfigPaths.GetEnumerator()) {
                    $sourcePath = Join-Path $primaryBackupPath $config.Key
                    if (Test-Path $sourcePath) {
                        if ($WhatIf) {
                            Write-Host "WhatIf: Would restore $($config.Key) from $sourcePath to $($config.Value)"
                        } else {
                            try {
                                Write-Host "Restoring $($config.Key) configuration..." -ForegroundColor Yellow
                                if (!(Test-Path $config.Value)) {
                                    New-Item -ItemType Directory -Path $config.Value -Force | Out-Null
                                }
                                # Skip system PowerShell if no admin rights
                                if ($config.Key -eq "SystemPowerShell" -and !([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
                                    Write-Host "Skipping system PowerShell restore (requires admin rights)" -ForegroundColor Yellow
                                } else {
                                    Copy-Item -Path "$sourcePath\*" -Destination $config.Value -Recurse -Force
                                    $restoredItems += $config.Key
                                }
                            } catch {
                                $errors += "Failed to restore $($config.Key)`: $_"
                                Write-Warning "Failed to restore $($config.Key)"
                            }
                        }
                    }
                }
                
                # Return object for better testing and validation
                $result = [PSCustomObject]@{
                    Success = $true
                    BackupPath = $primaryBackupPath
                    SharedBackupPath = $sharedBackupPath
                    Feature = "PowerShell Settings"
                    Timestamp = Get-Date
                    Items = $restoredItems
                    Errors = $errors
                }
                
                Write-Host "PowerShell Settings restored successfully from: $primaryBackupPath" -ForegroundColor Green
                if ($errors.Count -eq 0) {
                    Write-Host "`nNote: Please restart your PowerShell session to apply all changes" -ForegroundColor Yellow
                } else {
                    Write-Host "`nWarning: Some settings could not be restored. Check errors for details." -ForegroundColor Yellow
                }
                Write-Verbose "Restore completed successfully"
                return $result
            } else {
                throw "No backup found for PowerShell Settings in either machine or shared paths"
            }
        } catch {
            $errorRecord = $_
            $errorMessage = @(
                "Failed to restore PowerShell Settings"
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
    Export-ModuleMember -Function Restore-PowerShellSettings
}

<#
.SYNOPSIS
Restores PowerShell settings and configuration.

.DESCRIPTION
Restores PowerShell settings from backup, including:
- Registry settings for PowerShell execution policy, module logging, and transcription
- PowerShell profiles (AllUsers and CurrentUser)
- NuGet package sources
- PowerShell repositories
- Installed modules information
- PSReadLine history
- Custom formats and types
- Module configurations
- PowerShell configuration directories
- Both machine-specific and shared settings

.EXAMPLE
Restore-PowerShellSettings -BackupRootPath "C:\Backups" -MachineBackupPath "C:\Backups\Machine" -SharedBackupPath "C:\Backups\Shared"

.NOTES
Test cases to consider:
1. Valid backup paths with proper permissions
2. Invalid/nonexistent backup paths
3. Registry import success/failure
4. Profile restore success/failure
5. Package source registration success/failure
6. Missing backup files
7. Partial restore scenarios
8. Admin rights for system files

.TESTCASES
# Mock test examples:
Describe "Restore-PowerShellSettings" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Test-BackupPath { return "TestPath" }
        Mock Get-ChildItem { return @(
            [PSCustomObject]@{
                Name = "PowerShell.reg"
                FullName = "TestPath\PowerShell.reg"
            }
        )}
        Mock reg { }
        Mock Get-Content { return '[]' | ConvertFrom-Json }
        Mock Copy-Item { }
        Mock New-Item { }
        Mock Register-PackageSource { }
        Mock Register-PSRepository { }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Restore-PowerShellSettings -BackupRootPath "TestPath" -MachineBackupPath "TestPath\Machine" -SharedBackupPath "TestPath\Shared"
        $result.Success | Should -Be $true
        $result.BackupPath | Should -Be "TestPath"
        $result.Feature | Should -Be "PowerShell Settings"
    }

    It "Should handle missing backup gracefully" {
        Mock Test-BackupPath { return $null }
        { Restore-PowerShellSettings -BackupRootPath "TestPath" -MachineBackupPath "TestPath\Machine" -SharedBackupPath "TestPath\Shared" } | Should -Throw
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Restore-PowerShellSettings -BackupRootPath $BackupRootPath -MachineBackupPath $MachineBackupPath -SharedBackupPath $SharedBackupPath
}