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

function Backup-EpicGames {
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
            Write-Verbose "Starting backup of Epic Games..."
            Write-Host "Backing up Epic Games..." -ForegroundColor Blue
            
            # Validate inputs before proceeding
            if (!(Test-Path $BackupRootPath)) {
                throw [System.IO.DirectoryNotFoundException]"Backup root path not found: $BackupRootPath"
            }
            
            $backupPath = Initialize-BackupDirectory -Path "Applications" -BackupType "Epic Games" -BackupRootPath $BackupRootPath
            
            if ($backupPath) {
                $backedUpItems = @()
                $errors = @()
                $epicGames = @()
                
                # Check for Epic Games Launcher installation
                $epicPath = "C:\Program Files\Epic Games\Launcher"
                if (Test-Path $epicPath) {
                    Write-Host "Found Epic Games Launcher installation" -ForegroundColor Green
                    
                    # Get installed games from Epic Games Launcher
                    $manifestPath = "$env:ProgramData\Epic\EpicGamesLauncher\Data\Manifests"
                    if (Test-Path $manifestPath) {
                        if ($WhatIf) {
                            Write-Host "WhatIf: Would scan Epic Games manifests for games"
                        } else {
                            try {
                                $manifestFiles = Get-ChildItem -Path $manifestPath -Filter "*.item"
                                foreach ($manifest in $manifestFiles) {
                                    try {
                                        $content = Get-Content $manifest.FullName | ConvertFrom-Json
                                        $epicGames += @{
                                            Name = $content.DisplayName
                                            Id = $content.AppName
                                            Platform = "Epic"
                                            InstallLocation = $content.InstallLocation
                                            Version = $content.AppVersionString
                                        }
                                    }
                                    catch {
                                        $errors += "Error reading manifest $($manifest.Name): $_"
                                    }
                                }
                                $backedUpItems += "Epic games from manifests"
                            }
                            catch {
                                $errors += "Error reading Epic Games manifests: $_"
                            }
                        }
                    } else {
                        $errors += "Epic Games manifests not found at: $manifestPath"
                    }
                } else {
                    Write-Host "Epic Games Launcher not found at: $epicPath" -ForegroundColor Yellow
                }

                # Update applications.json
                if ($WhatIf) {
                    Write-Host "WhatIf: Would update Epic applications.json"
                } else {
                    try {
                        $applicationsPath = Join-Path $backupPath "epic-applications.json"
                        if (Test-Path $applicationsPath) {
                            $applications = Get-Content $applicationsPath | ConvertFrom-Json
                        }
                        else {
                            $applications = @{}
                        }

                        $applications.Epic = $epicGames
                        $applications | ConvertTo-Json -Depth 10 | Set-Content $applicationsPath
                        $backedUpItems += "Epic applications.json"
                    } catch {
                        $errors += "Failed to update Epic applications.json: $_"
                    }
                }
                
                # Return object for better testing and validation
                $result = [PSCustomObject]@{
                    Success = $true
                    BackupPath = $backupPath
                    Feature = "Epic Games"
                    Timestamp = Get-Date
                    Items = $backedUpItems
                    Errors = $errors
                    GameCount = $epicGames.Count
                }
                
                Write-Host "Backed up $($epicGames.Count) Epic games to: $backupPath" -ForegroundColor Green
                Write-Verbose "Backup completed successfully"
                return $result
            }
            return $false
        } catch {
            $errorRecord = $_
            $errorMessage = @(
                "Failed to backup Epic Games"
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
    Export-ModuleMember -Function Backup-EpicGames
}

<#
.SYNOPSIS
Backs up Epic Games settings and configurations.

.DESCRIPTION
Creates a backup of Epic Games information, including game titles, IDs, and installation locations from the Epic Games Launcher manifests.

.EXAMPLE
Backup-EpicGames -BackupRootPath "C:\Backups"

.NOTES
Test cases to consider:
1. Valid backup path with proper permissions
2. Invalid/nonexistent backup path
3. Empty backup path
4. No permissions to write
5. Epic Games Launcher installation exists/doesn't exist
6. Epic Games manifests exist/don't exist
7. Manifest parsing success/failure
8. JSON parsing success/failure
9. Applications.json update success/failure
10. Multiple games with different configurations

.TESTCASES
# Mock test examples:
Describe "Backup-EpicGames" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Initialize-BackupDirectory { return "TestPath" }
        Mock Get-ChildItem { 
            return @(
                [PSCustomObject]@{
                    FullName = "TestPath\game1.item"
                }
            )
        }
        Mock Get-Content { return '{"DisplayName":"Test Game","AppName":"testgame","InstallLocation":"C:\Games\Test","AppVersionString":"1.0"}' }
        Mock ConvertFrom-Json { 
            return [PSCustomObject]@{
                DisplayName = "Test Game"
                AppName = "testgame"
                InstallLocation = "C:\Games\Test"
                AppVersionString = "1.0"
            }
        }
        Mock ConvertTo-Json { return '{"Epic":[{"Name":"Test Game","Id":"testgame","Platform":"Epic","InstallLocation":"C:\Games\Test","Version":"1.0"}]}' }
        Mock Set-Content { }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Backup-EpicGames -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.BackupPath | Should -Be "TestPath"
        $result.Feature | Should -Be "Epic Games"
        $result.GameCount | Should -Be 1
    }

    It "Should handle missing Epic Games Launcher gracefully" {
        Mock Test-Path { return $false }
        $result = Backup-EpicGames -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.GameCount | Should -Be 0
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Backup-EpicGames -BackupRootPath $BackupRootPath
} 