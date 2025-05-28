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

function Backup-EAGames {
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
            Write-Verbose "Starting backup of EA Games..."
            Write-Host "Backing up EA Games..." -ForegroundColor Blue
            
            # Validate inputs before proceeding
            if (!(Test-Path $BackupRootPath)) {
                throw [System.IO.DirectoryNotFoundException]"Backup root path not found: $BackupRootPath"
            }
            
            $backupPath = Initialize-BackupDirectory -Path "Applications" -BackupType "EA Games" -BackupRootPath $BackupRootPath
            
            if ($backupPath) {
                $backedUpItems = @()
                $errors = @()
                $eaGames = @()
                
                # Check for EA app installation
                $eaPath = "$env:LOCALAPPDATA\Electronic Arts\EA Desktop\EA Desktop"
                if (Test-Path $eaPath) {
                    Write-Host "Found EA app installation" -ForegroundColor Green
                    
                    # EA stores game info in multiple locations
                    $contentPath = "$env:PROGRAMDATA\Electronic Arts\EA Desktop\Downloaded"
                    $manifestPath = "$env:LOCALAPPDATA\Electronic Arts\EA Desktop\Downloaded"

                    if ($WhatIf) {
                        Write-Host "WhatIf: Would scan EA games from content and manifest paths"
                    } else {
                        # Scan content path
                        if (Test-Path $contentPath) {
                            try {
                                Get-ChildItem $contentPath -Filter "*.json" | ForEach-Object {
                                    try {
                                        $content = Get-Content $_.FullName | ConvertFrom-Json
                                        if ($content.gameTitle) {
                                            $eaGames += @{
                                                Name = $content.gameTitle
                                                Id = $content.gameId
                                                Platform = "EA"
                                                InstallPath = $content.installPath
                                            }
                                        }
                                    }
                                    catch {
                                        $errors += "Error reading EA game info from $($_.FullName): $_"
                                    }
                                }
                                $backedUpItems += "EA games from content path"
                            } catch {
                                $errors += "Failed to scan EA content path: $_"
                            }
                        }

                        # Scan manifest path
                        if (Test-Path $manifestPath) {
                            try {
                                Get-ChildItem $manifestPath -Filter "*.json" | ForEach-Object {
                                    try {
                                        $manifest = Get-Content $_.FullName | ConvertFrom-Json
                                        if ($manifest.gameTitle -and ($manifest.gameTitle -notin $eaGames.Name)) {
                                            $eaGames += @{
                                                Name = $manifest.gameTitle
                                                Id = $manifest.gameId
                                                Platform = "EA"
                                                InstallPath = $manifest.installPath
                                            }
                                        }
                                    }
                                    catch {
                                        $errors += "Error reading EA manifest from $($_.FullName): $_"
                                    }
                                }
                                $backedUpItems += "EA games from manifest path"
                            } catch {
                                $errors += "Failed to scan EA manifest path: $_"
                            }
                        }
                    }
                }

                # Update applications.json
                if ($WhatIf) {
                    Write-Host "WhatIf: Would update EA applications.json"
                } else {
                    try {
                        $applicationsPath = Join-Path $backupPath "ea-applications.json"
                        if (Test-Path $applicationsPath) {
                            $applications = Get-Content $applicationsPath | ConvertFrom-Json
                        }
                        else {
                            $applications = @{}
                        }

                        $applications.EA = $eaGames
                        $applications | ConvertTo-Json -Depth 10 | Set-Content $applicationsPath
                        $backedUpItems += "EA applications.json"
                    } catch {
                        $errors += "Failed to update EA applications.json: $_"
                    }
                }
                
                # Return object for better testing and validation
                $result = [PSCustomObject]@{
                    Success = $true
                    BackupPath = $backupPath
                    Feature = "EA Games"
                    Timestamp = Get-Date
                    Items = $backedUpItems
                    Errors = $errors
                    GameCount = $eaGames.Count
                }
                
                Write-Host "Backed up $($eaGames.Count) EA games to: $backupPath" -ForegroundColor Green
                Write-Verbose "Backup completed successfully"
                return $result
            }
            return $false
        } catch {
            $errorRecord = $_
            $errorMessage = @(
                "Failed to backup EA Games"
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
    Export-ModuleMember -Function Backup-EAGames
}

<#
.SYNOPSIS
Backs up EA Games settings and configurations.

.DESCRIPTION
Creates a backup of EA Games information, including game titles, IDs, and installation paths from both content and manifest locations.

.EXAMPLE
Backup-EAGames -BackupRootPath "C:\Backups"

.NOTES
Test cases to consider:
1. Valid backup path with proper permissions
2. Invalid/nonexistent backup path
3. Empty backup path
4. No permissions to write
5. EA app installation exists/doesn't exist
6. Content path exists/doesn't exist
7. Manifest path exists/doesn't exist
8. JSON parsing success/failure
9. File access success/failure
10. Applications.json update success/failure

.TESTCASES
# Mock test examples:
Describe "Backup-EAGames" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Initialize-BackupDirectory { return "TestPath" }
        Mock Get-ChildItem { return @(
            [PSCustomObject]@{
                FullName = "TestGame.json"
            }
        )}
        Mock Get-Content { return '{"gameTitle":"Test Game","gameId":"123","installPath":"C:\Games"}' }
        Mock ConvertFrom-Json { return @{
            gameTitle = "Test Game"
            gameId = "123"
            installPath = "C:\Games"
        }}
        Mock ConvertTo-Json { return '{"EA":[{"Name":"Test Game","Id":"123","Platform":"EA","InstallPath":"C:\Games"}]}' }
        Mock Set-Content { }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Backup-EAGames -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.BackupPath | Should -Be "TestPath"
        $result.Feature | Should -Be "EA Games"
        $result.GameCount | Should -Be 1
    }

    It "Should handle missing EA app gracefully" {
        Mock Test-Path { return $false }
        $result = Backup-EAGames -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.GameCount | Should -Be 0
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Backup-EAGames -BackupRootPath $BackupRootPath
} 