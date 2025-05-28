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

function Backup-UbisoftGames {
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
            Write-Verbose "Starting backup of Ubisoft Games..."
            Write-Host "Backing up Ubisoft Games..." -ForegroundColor Blue
            
            # Validate inputs before proceeding
            if (!(Test-Path $BackupRootPath)) {
                throw [System.IO.DirectoryNotFoundException]"Backup root path not found: $BackupRootPath"
            }
            
            $backupPath = Initialize-BackupDirectory -Path "Applications" -BackupType "Ubisoft Games" -BackupRootPath $BackupRootPath
            
            if ($backupPath) {
                $backedUpItems = @()
                $errors = @()
                $ubisoftGames = @()
                
                # Check for Ubisoft Connect installation
                $ubisoftPath = "C:\Program Files (x86)\Ubisoft\Ubisoft Game Launcher"
                if (Test-Path $ubisoftPath) {
                    Write-Host "Found Ubisoft Connect installation" -ForegroundColor Green
                    
                    # Get installed games from Ubisoft Connect
                    $manifestPath = Join-Path $ubisoftPath "games"
                    if (Test-Path $manifestPath) {
                        if ($WhatIf) {
                            Write-Host "WhatIf: Would scan Ubisoft Connect games directory"
                        } else {
                            try {
                                $gameDirs = Get-ChildItem -Path $manifestPath -Directory
                                foreach ($gameDir in $gameDirs) {
                                    try {
                                        $manifestFile = Join-Path $gameDir.FullName "manifest.yml"
                                        if (Test-Path $manifestFile) {
                                            $content = Get-Content $manifestFile -Raw
                                            if ($content -match "name:\s*'([^']+)'") {
                                                $gameName = $matches[1]
                                                $ubisoftGames += @{
                                                    Name = $gameName
                                                    Id = $gameDir.Name
                                                    Platform = "Ubisoft"
                                                    InstallLocation = $gameDir.FullName
                                                }
                                            }
                                        }
                                    }
                                    catch {
                                        $errors += "Error reading game directory $($gameDir.Name): $_"
                                    }
                                }
                                $backedUpItems += "Ubisoft games from manifests"
                            }
                            catch {
                                $errors += "Error reading Ubisoft games directory: $_"
                            }
                        }
                    } else {
                        $errors += "Ubisoft games directory not found at: $manifestPath"
                    }
                } else {
                    Write-Host "Ubisoft Connect not found at: $ubisoftPath" -ForegroundColor Yellow
                }

                # Update applications.json
                if ($WhatIf) {
                    Write-Host "WhatIf: Would update Ubisoft applications.json"
                } else {
                    try {
                        $applicationsPath = Join-Path $backupPath "ubisoft-applications.json"
                        if (Test-Path $applicationsPath) {
                            $applications = Get-Content $applicationsPath | ConvertFrom-Json
                        }
                        else {
                            $applications = @{}
                        }

                        $applications.Ubisoft = $ubisoftGames
                        $applications | ConvertTo-Json -Depth 10 | Set-Content $applicationsPath
                        $backedUpItems += "Ubisoft applications.json"
                    } catch {
                        $errors += "Failed to update Ubisoft applications.json: $_"
                    }
                }
                
                # Return object for better testing and validation
                $result = [PSCustomObject]@{
                    Success = $true
                    BackupPath = $backupPath
                    Feature = "Ubisoft Games"
                    Timestamp = Get-Date
                    Items = $backedUpItems
                    Errors = $errors
                    GameCount = $ubisoftGames.Count
                }
                
                Write-Host "Backed up $($ubisoftGames.Count) Ubisoft games to: $backupPath" -ForegroundColor Green
                Write-Verbose "Backup completed successfully"
                return $result
            }
            return $false
        } catch {
            $errorRecord = $_
            $errorMessage = @(
                "Failed to backup Ubisoft Games"
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
    Export-ModuleMember -Function Backup-UbisoftGames
}

<#
.SYNOPSIS
Backs up Ubisoft Games settings and configurations.

.DESCRIPTION
Creates a backup of Ubisoft Games information, including game titles, IDs, and installation locations from Ubisoft Connect.

.EXAMPLE
Backup-UbisoftGames -BackupRootPath "C:\Backups"

.NOTES
Test cases to consider:
1. Valid backup path with proper permissions
2. Invalid/nonexistent backup path
3. Empty backup path
4. No permissions to write
5. Ubisoft Connect installation exists/doesn't exist
6. Ubisoft games directory exists/doesn't exist
7. Game manifest parsing success/failure
8. JSON parsing success/failure
9. Applications.json update success/failure
10. Multiple games with different configurations

.TESTCASES
# Mock test examples:
Describe "Backup-UbisoftGames" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Initialize-BackupDirectory { return "TestPath" }
        Mock Get-ChildItem { 
            return @(
                [PSCustomObject]@{
                    FullName = "TestPath\game1"
                    Name = "game1"
                }
            )
        }
        Mock Get-Content { return "name: 'Test Game'" }
        Mock ConvertFrom-Json { return @{} }
        Mock ConvertTo-Json { return '{"Ubisoft":[{"Name":"Test Game","Id":"game1","Platform":"Ubisoft","InstallLocation":"TestPath\game1"}]}' }
        Mock Set-Content { }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Backup-UbisoftGames -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.BackupPath | Should -Be "TestPath"
        $result.Feature | Should -Be "Ubisoft Games"
        $result.GameCount | Should -Be 1
    }

    It "Should handle missing Ubisoft Connect gracefully" {
        Mock Test-Path { return $false }
        $result = Backup-UbisoftGames -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.GameCount | Should -Be 0
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Backup-UbisoftGames -BackupRootPath $BackupRootPath
} 