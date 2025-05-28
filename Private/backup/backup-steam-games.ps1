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

function Backup-SteamGames {
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
            Write-Verbose "Starting backup of Steam Games..."
            Write-Host "Backing up Steam Games..." -ForegroundColor Blue
            
            # Validate inputs before proceeding
            if (!(Test-Path $BackupRootPath)) {
                throw [System.IO.DirectoryNotFoundException]"Backup root path not found: $BackupRootPath"
            }
            
            $backupPath = Initialize-BackupDirectory -Path "Applications" -BackupType "Steam Games" -BackupRootPath $BackupRootPath
            
            if ($backupPath) {
                $backedUpItems = @()
                $errors = @()
                $steamGames = @()
                
                # Check for Steam installation
                $steamPath = "C:\Program Files (x86)\Steam"
                if (Test-Path $steamPath) {
                    Write-Host "Found Steam installation" -ForegroundColor Green
                    
                    # Get installed games from Steam
                    $libraryFoldersPath = Join-Path $steamPath "steamapps\libraryfolders.vdf"
                    if (Test-Path $libraryFoldersPath) {
                        if ($WhatIf) {
                            Write-Host "WhatIf: Would scan Steam library folders for games"
                        } else {
                            try {
                                # Parse libraryfolders.vdf to get all Steam library locations
                                $libraryFolders = @()
                                $content = Get-Content $libraryFoldersPath
                                foreach ($line in $content) {
                                    if ($line -match '"path"\s+"([^"]+)"') {
                                        $libraryFolders += $matches[1]
                                    }
                                }
                                
                                # Add default Steam library if not already included
                                $defaultLibrary = Join-Path $steamPath "steamapps"
                                if ($libraryFolders -notcontains $defaultLibrary) {
                                    $libraryFolders += $defaultLibrary
                                }
                                
                                # Scan each library for installed games
                                foreach ($library in $libraryFolders) {
                                    $manifestPath = Join-Path $library "steamapps"
                                    if (Test-Path $manifestPath) {
                                        $manifestFiles = Get-ChildItem -Path $manifestPath -Filter "*.acf"
                                        foreach ($manifest in $manifestFiles) {
                                            try {
                                                $content = Get-Content $manifest.FullName
                                                $gameInfo = @{}
                                                foreach ($line in $content) {
                                                    if ($line -match '"([^"]+)"\s+"([^"]+)"') {
                                                        $gameInfo[$matches[1]] = $matches[2]
                                                    }
                                                }
                                                
                                                if ($gameInfo.ContainsKey("appid") -and $gameInfo.ContainsKey("name")) {
                                                    $steamGames += @{
                                                        Name = $gameInfo["name"]
                                                        Id = $gameInfo["appid"]
                                                        Platform = "Steam"
                                                        InstallDir = $gameInfo["installdir"]
                                                        Library = $library
                                                    }
                                                }
                                            }
                                            catch {
                                                $errors += "Error reading manifest $($manifest.Name): $_"
                                            }
                                        }
                                    }
                                }
                                $backedUpItems += "Steam games from manifests"
                            }
                            catch {
                                $errors += "Error reading Steam library folders: $_"
                            }
                        }
                    } else {
                        $errors += "Steam library folders file not found at: $libraryFoldersPath"
                    }
                } else {
                    Write-Host "Steam not found at: $steamPath" -ForegroundColor Yellow
                }

                # Update applications.json
                if ($WhatIf) {
                    Write-Host "WhatIf: Would update Steam applications.json"
                } else {
                    try {
                        $applicationsPath = Join-Path $backupPath "steam-applications.json"
                        if (Test-Path $applicationsPath) {
                            $applications = Get-Content $applicationsPath | ConvertFrom-Json
                        }
                        else {
                            $applications = @{}
                        }

                        $applications.Steam = $steamGames
                        $applications | ConvertTo-Json -Depth 10 | Set-Content $applicationsPath
                        $backedUpItems += "Steam applications.json"
                    } catch {
                        $errors += "Failed to update Steam applications.json: $_"
                    }
                }
                
                # Return object for better testing and validation
                $result = [PSCustomObject]@{
                    Success = $true
                    BackupPath = $backupPath
                    Feature = "Steam Games"
                    Timestamp = Get-Date
                    Items = $backedUpItems
                    Errors = $errors
                    GameCount = $steamGames.Count
                }
                
                Write-Host "Backed up $($steamGames.Count) Steam games to: $backupPath" -ForegroundColor Green
                Write-Verbose "Backup completed successfully"
                return $result
            }
            return $false
        } catch {
            $errorRecord = $_
            $errorMessage = @(
                "Failed to backup Steam Games"
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
    Export-ModuleMember -Function Backup-SteamGames
}

<#
.SYNOPSIS
Backs up Steam Games settings and configurations.

.DESCRIPTION
Creates a backup of Steam Games information, including game titles, IDs, and installation locations from Steam library manifests.

.EXAMPLE
Backup-SteamGames -BackupRootPath "C:\Backups"

.NOTES
Test cases to consider:
1. Valid backup path with proper permissions
2. Invalid/nonexistent backup path
3. Empty backup path
4. No permissions to write
5. Steam installation exists/doesn't exist
6. Steam library folders file exists/doesn't exist
7. Multiple Steam libraries
8. Manifest parsing success/failure
9. JSON parsing success/failure
10. Applications.json update success/failure

.TESTCASES
# Mock test examples:
Describe "Backup-SteamGames" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Initialize-BackupDirectory { return "TestPath" }
        Mock Get-Content { 
            param($Path)
            if ($Path -like "*libraryfolders.vdf") {
                return @(
                    '"path" "C:\SteamLibrary"',
                    '"path" "D:\SteamLibrary"'
                )
            } else {
                return @(
                    '"appid" "123"',
                    '"name" "Test Game"',
                    '"installdir" "TestGame"'
                )
            }
        }
        Mock Get-ChildItem { 
            return @(
                [PSCustomObject]@{
                    FullName = "TestPath\game1.acf"
                }
            )
        }
        Mock ConvertFrom-Json { return @{} }
        Mock ConvertTo-Json { return '{"Steam":[{"Name":"Test Game","Id":"123","Platform":"Steam","InstallDir":"TestGame","Library":"C:\SteamLibrary"}]}' }
        Mock Set-Content { }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Backup-SteamGames -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.BackupPath | Should -Be "TestPath"
        $result.Feature | Should -Be "Steam Games"
        $result.GameCount | Should -Be 1
    }

    It "Should handle missing Steam installation gracefully" {
        Mock Test-Path { return $false }
        $result = Backup-SteamGames -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.GameCount | Should -Be 0
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Backup-SteamGames -BackupRootPath $BackupRootPath
} 