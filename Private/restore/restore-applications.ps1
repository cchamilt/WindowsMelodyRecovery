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

# Define Test-BackupPath function
function Test-BackupPath {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Path,
        
        [Parameter(Mandatory=$true)]
        [string]$BackupType,
        
        [Parameter(Mandatory=$true)]
        [string]$MachineBackupPath,
        
        [Parameter(Mandatory=$true)]
        [string]$SharedBackupPath
    )
    
    # First check machine-specific backup
    $machinePath = Join-Path $MachineBackupPath $Path
    if (Test-Path $machinePath) {
        Write-Host "Using machine-specific $BackupType backup from: $machinePath" -ForegroundColor Green
        return $machinePath
    }
    
    # Fall back to shared backup
    $sharedPath = Join-Path $SharedBackupPath $Path
    if (Test-Path $sharedPath) {
        Write-Host "Using shared $BackupType backup from: $sharedPath" -ForegroundColor Green
        return $sharedPath
    }
    
    Write-Host "No $BackupType backup found" -ForegroundColor Yellow
    return $null
}

function Restore-Applications {
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
            Write-Verbose "Starting restore of Applications..."
            Write-Host "Restoring Applications..." -ForegroundColor Blue
            
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
            
            $restoredItems = @()
            $errors = @()
            
            # Find applications backup using fallback logic
            $applicationsPath = Test-BackupPath -Path "Applications" -BackupType "Applications" -MachineBackupPath $MachineBackupPath -SharedBackupPath $SharedBackupPath
            
            if ($applicationsPath) {
                # Check and install package managers first
                Write-Host "Checking package managers..." -ForegroundColor Yellow

                # Check and install Winget if needed
                if (!(Get-Command winget -ErrorAction SilentlyContinue)) {
                    if ($WhatIf) {
                        Write-Host "WhatIf: Would install Winget..." -ForegroundColor Yellow
                    } else {
                        Write-Host "Installing Winget..." -ForegroundColor Yellow
                        try {
                            Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe
                            $restoredItems += "Winget installation"
                        } catch {
                            $errors += "Failed to install Winget: $_"
                        }
                    }
                }

                # Check and install Chocolatey if needed
                if (!(Get-Command choco -ErrorAction SilentlyContinue)) {
                    if ($WhatIf) {
                        Write-Host "WhatIf: Would install Chocolatey..." -ForegroundColor Yellow
                    } else {
                        Write-Host "Installing Chocolatey..." -ForegroundColor Yellow
                        try {
                            Set-ExecutionPolicy Bypass -Scope Process -Force
                            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
                            Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
                            $restoredItems += "Chocolatey installation"
                        } catch {
                            $errors += "Failed to install Chocolatey: $_"
                        }
                    }
                }

                # Install game managers only if they were previously installed AND we have games for them
                Write-Host "`nChecking Game Managers..." -ForegroundColor Blue
                $gameManagersPath = Test-BackupPath -Path "GameManagers" -BackupType "Game Managers" -MachineBackupPath $MachineBackupPath -SharedBackupPath $SharedBackupPath
                
                if ($gameManagersPath) {
                    # First, check which game managers were actually installed before (from package manager backups)
                    $originallyInstalledGameManagers = @()
                    
                    # Check package manager backups for game manager installations
                    $packageManagers = @("winget", "chocolatey", "scoop", "store")
                    foreach ($packageManager in $packageManagers) {
                        $packageFile = Join-Path $applicationsPath "$packageManager-applications.json"
                        if (Test-Path $packageFile) {
                            try {
                                $packages = Get-Content $packageFile | ConvertFrom-Json
                                foreach ($package in $packages) {
                                    $packageName = $package.Name.ToLower()
                                    if ($packageName -like "*steam*") {
                                        $originallyInstalledGameManagers += "Steam"
                                    } elseif ($packageName -like "*epic*" -or $packageName -like "*games launcher*") {
                                        $originallyInstalledGameManagers += "Epic"
                                    } elseif ($packageName -like "*gog*" -or $packageName -like "*galaxy*") {
                                        $originallyInstalledGameManagers += "GOG"
                                    } elseif ($packageName -like "*ea*" -or $packageName -like "*origin*" -or $packageName -like "*desktop*") {
                                        $originallyInstalledGameManagers += "EA"
                                    } elseif ($packageName -like "*ubisoft*" -or $packageName -like "*connect*") {
                                        $originallyInstalledGameManagers += "Ubisoft"
                                    } elseif ($packageName -like "*xbox*") {
                                        $originallyInstalledGameManagers += "Xbox"
                                    }
                                }
                            } catch {
                                $errors += "Failed to process $packageManager applications for game manager detection: $_"
                            }
                        }
                    }
                    
                    # Remove duplicates
                    $originallyInstalledGameManagers = $originallyInstalledGameManagers | Sort-Object -Unique
                    
                    if ($originallyInstalledGameManagers.Count -gt 0) {
                        Write-Host "Found originally installed game managers: $($originallyInstalledGameManagers -join ', ')" -ForegroundColor Cyan
                        
                        # Define game manager winget IDs
                        $gameManagerApps = @{
                            "Steam" = "Valve.Steam"
                            "Epic" = "EpicGames.EpicGamesLauncher"
                            "GOG" = "GOG.Galaxy"
                            "EA" = "ElectronicArts.EADesktop"
                            "Ubisoft" = "Ubisoft.Connect"
                            "Xbox" = "Microsoft.XboxApp"
                        }
                        
                        # Only install game managers that were originally installed AND have game data
                        foreach ($manager in $originallyInstalledGameManagers) {
                            $gameFile = Join-Path $gameManagersPath "$($manager.ToLower())-games.json"
                            
                            # Check if we have games for this manager
                            $hasGames = $false
                            if (Test-Path $gameFile) {
                                try {
                                    $games = Get-Content $gameFile | ConvertFrom-Json
                                    $hasGames = $games.Count -gt 0
                                } catch {
                                    $errors += "Failed to read $manager games file: $_"
                                }
                            }
                            
                            if ($hasGames -and $gameManagerApps.ContainsKey($manager)) {
                                if ($WhatIf) {
                                    Write-Host "WhatIf: Would install $manager via winget (ID: $($gameManagerApps[$manager])) - was previously installed with $($games.Count) games" -ForegroundColor Cyan
                                } else {
                                    Write-Host "Installing $manager game manager (was previously installed with $($games.Count) games)..." -ForegroundColor Cyan
                                    try {
                                        $result = winget install --id $gameManagerApps[$manager] --accept-package-agreements --accept-source-agreements --silent
                                        if ($LASTEXITCODE -eq 0) {
                                            Write-Host "$manager installed successfully" -ForegroundColor Green
                                            $restoredItems += "$manager game manager"
                                        } else {
                                            Write-Host "$manager installation may have failed (exit code: $LASTEXITCODE)" -ForegroundColor Yellow
                                            $errors += "$manager installation returned exit code: $LASTEXITCODE"
                                        }
                                    } catch {
                                        $errors += "Failed to install $manager: $_"
                                        Write-Host "Failed to install $manager: $_" -ForegroundColor Red
                                    }
                                }
                            } elseif ($gameManagerApps.ContainsKey($manager)) {
                                Write-Host "Skipping $manager - was installed but no games found to manage" -ForegroundColor Yellow
                            } else {
                                Write-Host "Skipping $manager - winget installation not configured" -ForegroundColor Yellow
                            }
                        }
                    } else {
                        Write-Host "No game managers were found in original package manager installations - skipping game manager installation" -ForegroundColor Yellow
                    }
                } else {
                    Write-Host "No game manager data found - skipping game manager installation" -ForegroundColor Yellow
                }

                # Restore package manager applications
                Write-Host "`nRestoring Package Manager Applications..." -ForegroundColor Blue
                
                # Install Store applications
                $storeFile = Join-Path $applicationsPath "store-applications.json"
                if (Test-Path $storeFile) {
                    if ($WhatIf) {
                        Write-Host "WhatIf: Would restore Store applications"
                    } else {
                        try {
                            $storeApps = Get-Content $storeFile | ConvertFrom-Json
                            Write-Host "Installing $($storeApps.Count) Store applications..." -ForegroundColor Yellow
                            foreach ($app in $storeApps) {
                                if ($app.PackageFamilyName) {
                                    Write-Host "Installing Store app: $($app.Name)..." -ForegroundColor Cyan
                                    try {
                                        winget install --id $app.PackageFamilyName --source msstore --accept-package-agreements --accept-source-agreements --silent
                                        $restoredItems += "Store app: $($app.Name)"
                                    } catch {
                                        $errors += "Failed to install Store app $($app.Name): $_"
                                    }
                                }
                            }
                        } catch {
                            $errors += "Failed to process Store applications: $_"
                        }
                    }
                }

                # Install Scoop applications
                $scoopFile = Join-Path $applicationsPath "scoop-applications.json"
                if (Test-Path $scoopFile) {
                    if ($WhatIf) {
                        Write-Host "WhatIf: Would restore Scoop applications"
                    } else {
                        try {
                            # Install Scoop if not present
                            if (!(Get-Command scoop -ErrorAction SilentlyContinue)) {
                                Write-Host "Installing Scoop..." -ForegroundColor Yellow
                                Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
                                Invoke-Expression (New-Object System.Net.WebClient).DownloadString('https://get.scoop.sh')
                                $restoredItems += "Scoop installation"
                            }
                            
                            $scoopApps = Get-Content $scoopFile | ConvertFrom-Json
                            Write-Host "Installing $($scoopApps.Count) Scoop packages..." -ForegroundColor Yellow
                            foreach ($app in $scoopApps) {
                                Write-Host "Installing Scoop package: $($app.Name)..." -ForegroundColor Cyan
                                try {
                                    scoop install $app.Name
                                    $restoredItems += "Scoop package: $($app.Name)"
                                } catch {
                                    $errors += "Failed to install Scoop package $($app.Name): $_"
                                }
                            }
                        } catch {
                            $errors += "Failed to process Scoop applications: $_"
                        }
                    }
                }

                # Install Chocolatey applications
                $chocoFile = Join-Path $applicationsPath "chocolatey-applications.json"
                if (Test-Path $chocoFile) {
                    if ($WhatIf) {
                        Write-Host "WhatIf: Would restore Chocolatey applications"
                    } else {
                        try {
                            if (Get-Command choco -ErrorAction SilentlyContinue) {
                                $chocoApps = Get-Content $chocoFile | ConvertFrom-Json
                                Write-Host "Installing $($chocoApps.Count) Chocolatey packages..." -ForegroundColor Yellow
                                foreach ($app in $chocoApps) {
                                    Write-Host "Installing Chocolatey package: $($app.Name)..." -ForegroundColor Cyan
                                    try {
                                        choco install $app.Name -y
                                        $restoredItems += "Chocolatey package: $($app.Name)"
                                    } catch {
                                        $errors += "Failed to install Chocolatey package $($app.Name): $_"
                                    }
                                }
                            } else {
                                $errors += "Chocolatey not available for package installation"
                            }
                        } catch {
                            $errors += "Failed to process Chocolatey applications: $_"
                        }
                    }
                }

                # Install Winget applications
                $wingetFile = Join-Path $applicationsPath "winget-applications.json"
                if (Test-Path $wingetFile) {
                    if ($WhatIf) {
                        Write-Host "WhatIf: Would restore Winget applications"
                    } else {
                        try {
                            if (Get-Command winget -ErrorAction SilentlyContinue) {
                                $wingetApps = Get-Content $wingetFile | ConvertFrom-Json
                                Write-Host "Installing $($wingetApps.Count) Winget applications..." -ForegroundColor Yellow
                                foreach ($app in $wingetApps) {
                                    if ($app.Id) {
                                        Write-Host "Installing Winget app: $($app.Name)..." -ForegroundColor Cyan
                                        try {
                                            winget install --id $app.Id --source $app.Source --accept-package-agreements --accept-source-agreements --silent
                                            $restoredItems += "Winget app: $($app.Name)"
                                        } catch {
                                            $errors += "Failed to install Winget app $($app.Name): $_"
                                        }
                                    }
                                }
                            } else {
                                $errors += "Winget not available for package installation"
                            }
                        } catch {
                            $errors += "Failed to process Winget applications: $_"
                        }
                    }
                }

                Write-Host "`nPackage manager applications restoration completed" -ForegroundColor Green
                
                # Run post-restore analysis to compare against original unmanaged apps
                Write-Host "`nAnalyzing post-restore application status..." -ForegroundColor Blue
                if ($WhatIf) {
                    Write-Host "WhatIf: Would run post-restore applications analysis" -ForegroundColor Yellow
                } else {
                    try {
                        $analyzeScript = Join-Path $modulePath "Private\backup\analyze-unmanaged.ps1"
                        if (Test-Path $analyzeScript) {
                            . $analyzeScript
                            if (Get-Command Compare-PostRestoreApplications -ErrorAction SilentlyContinue) {
                                $params = @{
                                    BackupRootPath = $BackupRootPath
                                    MachineBackupPath = $MachineBackupPath
                                    SharedBackupPath = $SharedBackupPath
                                }
                                $analysisResult = & Compare-PostRestoreApplications @params -ErrorAction Stop
                                if ($analysisResult.Success) {
                                    Write-Host "`nPost-restore analysis completed!" -ForegroundColor Green
                                    Write-Host "Results saved to: $($analysisResult.BackupPath)" -ForegroundColor Green
                                    
                                    # Show summary information
                                    if ($analysisResult.Analysis -and $analysisResult.Analysis.Summary) {
                                        $summary = $analysisResult.Analysis.Summary
                                        Write-Host "`n=== APPLICATION RESTORE SUMMARY ===" -ForegroundColor Yellow
                                        Write-Host "Original Unmanaged Apps: $($summary.OriginalUnmanagedApps)" -ForegroundColor White
                                        Write-Host "Successfully Restored: $($summary.RestoredApps)" -ForegroundColor Green
                                        Write-Host "Still Need Manual Install: $($summary.StillUnmanagedApps)" -ForegroundColor Red
                                        Write-Host "Restore Success Rate: $($summary.RestoreSuccessRate)%" -ForegroundColor Cyan
                                        
                                        if ($summary.StillUnmanagedApps -gt 0) {
                                            Write-Host "`nIMPORTANT: Check 'still-unmanaged-apps.json' and 'still-unmanaged-apps.csv' for remaining manual installations!" -ForegroundColor Yellow
                                        } else {
                                            Write-Host "`nCONGRATULATIONS: All originally unmanaged applications have been successfully restored!" -ForegroundColor Green
                                        }
                                    }
                                    $restoredItems += "Post-restore analysis"
                                }
                            } else {
                                Write-Host "Compare-PostRestoreApplications function not found - skipping post-restore analysis" -ForegroundColor Yellow
                            }
                        } else {
                            Write-Host "Analysis script not found - skipping post-restore analysis" -ForegroundColor Yellow
                        }
                    } catch {
                        $errors += "Failed to run post-restore applications analysis: $_"
                        Write-Host "Failed to run post-restore applications analysis: $_" -ForegroundColor Red
                    }
                }
            } else {
                Write-Host "No applications backup found" -ForegroundColor Yellow
                $errors += "No applications backup found"
            }
            
            # Return object for better testing and validation
            $result = [PSCustomObject]@{
                Success = $true
                BackupPath = $applicationsPath
                SharedBackupPath = $SharedBackupPath
                Feature = "Applications"
                Timestamp = Get-Date
                Items = $restoredItems
                Errors = $errors
            }
            
            Write-Host "Applications restored successfully!" -ForegroundColor Green
            Write-Verbose "Restore completed successfully"
            return $result
        } catch {
            $errorRecord = $_
            $errorMessage = @(
                "Failed to restore Applications"
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
    Export-ModuleMember -Function Restore-Applications
}

<#
.SYNOPSIS
Restores package manager applications and installs game managers.

.DESCRIPTION
Restores applications from package managers (Store, Scoop, Chocolatey, Winget) and installs 
game managers via winget as dependencies. Also runs unmanaged applications analysis at the 
end to identify what still needs manual installation.

Key features:
- Installs package managers if missing (Winget, Chocolatey, Scoop)
- Installs game managers first via winget (Steam, Epic, GOG, EA, Ubisoft, Xbox)
- Restores applications from all package managers
- Smart fallback logic (machine-specific backup first, then shared)
- Runs unmanaged applications analysis to show what needs manual installation
- Comprehensive error handling and logging

.EXAMPLE
Restore-Applications -BackupRootPath "C:\Backups" -MachineBackupPath "C:\Backups\Machine" -SharedBackupPath "C:\Backups\Shared"

.NOTES
Prerequisites:
- Applications backup must exist (run backup-applications.ps1 first)
- Game managers backup should exist for game manager installation
- Internet connection required for package manager installations

Process:
1. Install missing package managers (Winget, Chocolatey, Scoop)
2. Install game managers via winget (based on backup data)
3. Restore applications from all package managers
4. Run unmanaged analysis to identify manual installation requirements

Test cases to consider:
1. Valid backup paths with proper permissions
2. Invalid/nonexistent backup paths
3. Missing package manager backups
4. Package manager installation success/failure
5. Game manager installation success/failure
6. Application installation success/failure
7. Network connectivity issues
8. Unmanaged analysis execution

.TESTCASES
# Mock test examples:
Describe "Restore-Applications" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Test-BackupPath { return "TestPath" }
        Mock Get-Command { return $true }
        Mock Get-Content { return '[]' }
        Mock ConvertFrom-Json { return @() }
        Mock winget { }
        Mock choco { }
        Mock scoop { }
        Mock Add-AppxPackage { }
        Mock Invoke-Expression { }
        Mock Set-ExecutionPolicy { }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Restore-Applications -BackupRootPath "TestPath" -MachineBackupPath "TestPath\Machine" -SharedBackupPath "TestPath\Shared"
        $result.Success | Should -Be $true
        $result.Feature | Should -Be "Applications"
    }

    It "Should handle missing backup gracefully" {
        Mock Test-BackupPath { return $null }
        $result = Restore-Applications -BackupRootPath "TestPath" -MachineBackupPath "TestPath\Machine" -SharedBackupPath "TestPath\Shared"
        $result.Success | Should -Be $true
        $result.Errors | Should -Contain "No applications backup found"
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Restore-Applications -BackupRootPath $BackupRootPath -MachineBackupPath $MachineBackupPath -SharedBackupPath $SharedBackupPath
} 