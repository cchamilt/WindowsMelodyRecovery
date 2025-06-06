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

function Restore-GameManagers {
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
            Write-Verbose "Starting restore of Game Managers..."
            Write-Host "Restoring Game Manager Games..." -ForegroundColor Blue
            
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
            
            # Find game managers backup using fallback logic
            $gameManagersPath = Test-BackupPath -Path "GameManagers" -BackupType "Game Managers" -MachineBackupPath $MachineBackupPath -SharedBackupPath $SharedBackupPath
            
            if ($gameManagersPath) {
                # Define game manager configurations
                $gameManagers = @{
                    "Steam" = @{
                        Name = "Steam"
                        ProcessName = "steam"
                        ConfigNote = "Games will be detected when you launch Steam and log in"
                        InstallNote = "Use Steam to reinstall your games from your library"
                    }
                    "Epic" = @{
                        Name = "Epic Games"
                        ProcessName = "epicgameslauncher"
                        ConfigNote = "Games will be detected when you launch Epic Games Launcher and log in"
                        InstallNote = "Use Epic Games Launcher to reinstall your games from your library"
                    }
                    "GOG" = @{
                        Name = "GOG Galaxy"
                        ProcessName = "goggalaxy"
                        ConfigNote = "Games will be detected when you launch GOG Galaxy and log in"
                        InstallNote = "Use GOG Galaxy to reinstall your games from your library"
                    }
                    "EA" = @{
                        Name = "EA Desktop"
                        ProcessName = "eadesktop"
                        ConfigNote = "Games will be detected when you launch EA Desktop and log in"
                        InstallNote = "Use EA Desktop to reinstall your games from your library"
                    }
                    "Ubisoft" = @{
                        Name = "Ubisoft Connect"
                        ProcessName = "ubisoftconnect"
                        ConfigNote = "Games will be detected when you launch Ubisoft Connect and log in"
                        InstallNote = "Use Ubisoft Connect to reinstall your games from your library"
                    }
                    "Xbox" = @{
                        Name = "Xbox Game Pass"
                        ProcessName = "gamingservices"
                        ConfigNote = "Games will be available through Xbox app and Microsoft Store"
                        InstallNote = "Use Xbox app to reinstall your Game Pass games"
                    }
                }
                
                $totalGames = 0
                $restoredGames = @{}
                
                # Process each game manager
                foreach ($manager in $gameManagers.GetEnumerator()) {
                    $managerKey = $manager.Key
                    $managerConfig = $manager.Value
                    $gameFile = Join-Path $gameManagersPath "$($managerKey.ToLower())-games.json"
                    
                    if (Test-Path $gameFile) {
                        if ($WhatIf) {
                            Write-Host "WhatIf: Would process $($managerConfig.Name) games from $gameFile"
                        } else {
                            try {
                                Write-Host "`nProcessing $($managerConfig.Name) games..." -ForegroundColor Cyan
                                $games = Get-Content $gameFile | ConvertFrom-Json
                                
                                if ($games.Count -gt 0) {
                                    Write-Host "Found $($games.Count) $($managerConfig.Name) games in backup" -ForegroundColor Green
                                    $totalGames += $games.Count
                                    $restoredGames[$managerKey] = $games
                                    
                                    # Create a summary file for this manager in the restore location
                                    $summaryFile = Join-Path $MachineBackupPath "GameManagers\$($managerKey.ToLower())-restore-summary.txt"
                                    $summaryContent = @"
$($managerConfig.Name) Games Restore Summary
Generated: $(Get-Date)

Games to Restore ($($games.Count) total):
$($games | ForEach-Object { "- $($_.Name)" } | Out-String)

Instructions:
1. Ensure $($managerConfig.Name) is installed and running
2. Log into your account
3. $($managerConfig.ConfigNote)
4. $($managerConfig.InstallNote)

Note: Game save data and settings may need to be restored separately if you backed them up.
"@
                                    $summaryContent | Out-File $summaryFile -Force -Encoding UTF8
                                    
                                    Write-Host "Game list summary saved to: $summaryFile" -ForegroundColor Green
                                    $restoredItems += "$($managerConfig.Name) games list ($($games.Count) games)"
                                } else {
                                    Write-Host "No games found for $($managerConfig.Name)" -ForegroundColor Yellow
                                }
                            } catch {
                                $errors += "Failed to process $($managerConfig.Name) games: $_"
                                Write-Host "Failed to process $($managerConfig.Name) games: $_" -ForegroundColor Red
                            }
                        }
                    } else {
                        Write-Host "No $($managerConfig.Name) games backup found" -ForegroundColor Gray
                    }
                }
                
                # Create master restore summary
                if ($WhatIf) {
                    Write-Host "WhatIf: Would create master game restore summary"
                } else {
                    if ($totalGames -gt 0) {
                        $masterSummaryFile = Join-Path $MachineBackupPath "GameManagers\master-game-restore-summary.txt"
                        $masterSummaryContent = @"
Master Game Restore Summary
Generated: $(Get-Date)
Total Games to Restore: $totalGames

By Platform:
$($restoredGames.GetEnumerator() | ForEach-Object { "$($_.Key): $($_.Value.Count) games" } | Out-String)

Detailed Game Lists:
$($restoredGames.GetEnumerator() | ForEach-Object { 
    "`n$($_.Key) Games:"
    $_.Value | ForEach-Object { "  - $($_.Name)" }
} | Out-String)

General Restore Instructions:
1. Install all required game managers (should be done by restore-applications.ps1)
2. Launch each game manager and log into your accounts
3. Your game libraries should sync automatically
4. Reinstall games as needed from your libraries
5. Restore game save data if you backed it up separately

Platform-Specific Notes:
- Steam: Games appear in Library after login
- Epic Games: Games appear in Library after login
- GOG Galaxy: Games appear in Library after login, may need to scan for installed games
- EA Desktop: Games appear in Library after login
- Ubisoft Connect: Games appear in Library after login
- Xbox Game Pass: Games available through Xbox app, may need Game Pass subscription

Important: This restore shows you what games you had, but doesn't automatically install them.
You'll need to reinstall each game through its respective platform.
"@
                        $masterSummaryContent | Out-File $masterSummaryFile -Force -Encoding UTF8
                        
                        Write-Host "`nMaster game restore summary created!" -ForegroundColor Green
                        Write-Host "Summary saved to: $masterSummaryFile" -ForegroundColor Green
                        $restoredItems += "Master game restore summary"
                        
                        # Display summary to user
                        Write-Host "`n=== GAME RESTORE SUMMARY ===" -ForegroundColor Yellow
                        Write-Host "Total Games Found: $totalGames" -ForegroundColor White
                        Write-Host "Platforms:" -ForegroundColor White
                        $restoredGames.GetEnumerator() | ForEach-Object {
                            Write-Host "  $($_.Key): $($_.Value.Count) games" -ForegroundColor Cyan
                        }
                        
                        Write-Host "`n=== NEXT STEPS ===" -ForegroundColor Yellow
                        Write-Host "1. Launch each game manager and log into your accounts" -ForegroundColor White
                        Write-Host "2. Your game libraries should sync automatically" -ForegroundColor White
                        Write-Host "3. Reinstall games as needed from your libraries" -ForegroundColor White
                        Write-Host "4. Check the summary files for detailed game lists" -ForegroundColor White
                        
                        Write-Host "`nIMPORTANT: Games are not automatically installed - you need to reinstall them through each platform!" -ForegroundColor Yellow
                    } else {
                        Write-Host "No games found in any game manager backups" -ForegroundColor Yellow
                    }
                }
            } else {
                Write-Host "No game managers backup found" -ForegroundColor Yellow
                $errors += "No game managers backup found"
            }
            
            # Return object for better testing and validation
            $result = [PSCustomObject]@{
                Success = $true
                BackupPath = $gameManagersPath
                SharedBackupPath = $SharedBackupPath
                Feature = "Game Managers"
                Timestamp = Get-Date
                Items = $restoredItems
                Errors = $errors
                TotalGames = $totalGames
                RestoredGames = $restoredGames
            }
            
            Write-Host "Game managers restore completed successfully!" -ForegroundColor Green
            Write-Verbose "Restore completed successfully"
            return $result
        } catch {
            $errorRecord = $_
            $errorMessage = @(
                "Failed to restore Game Managers"
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
    Export-ModuleMember -Function Restore-GameManagers
}

<#
.SYNOPSIS
Restores game manager game lists and provides restore instructions.

.DESCRIPTION
Restores game lists from all game managers (Steam, Epic, GOG, EA, Ubisoft, Xbox) and creates
detailed restore summaries with instructions. Note that this doesn't automatically install games,
but provides the information needed to reinstall them through each platform.

Key features:
- Processes game lists from all supported game managers
- Creates platform-specific restore summaries
- Generates master restore summary with all games
- Provides clear instructions for manual game restoration
- Smart fallback logic (machine-specific backup first, then shared)
- Comprehensive error handling and logging

.EXAMPLE
Restore-GameManagers -BackupRootPath "C:\Backups" -MachineBackupPath "C:\Backups\Machine" -SharedBackupPath "C:\Backups\Shared"

.NOTES
Prerequisites:
- Game managers backup must exist (run backup-gamemanagers.ps1 first)
- Game managers should be installed (done by restore-applications.ps1)

Process:
1. Load game lists from all game manager backups
2. Create platform-specific restore summaries
3. Generate master summary with all games and instructions
4. Provide clear next steps for manual game restoration

Important: This script provides restore information but doesn't automatically install games.
Users need to reinstall games through each game manager's interface.

Test cases to consider:
1. Valid backup paths with proper permissions
2. Invalid/nonexistent backup paths
3. Missing game manager backups
4. Empty game lists
5. JSON parsing success/failure
6. File creation success/failure
7. Summary generation

.TESTCASES
# Mock test examples:
Describe "Restore-GameManagers" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Test-BackupPath { return "TestPath" }
        Mock Get-Content { return '[{"Name":"Test Game","ID":"123"}]' }
        Mock ConvertFrom-Json { return @(@{Name="Test Game"; ID="123"}) }
        Mock Out-File { }
        Mock Join-Path { return "TestPath" }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Restore-GameManagers -BackupRootPath "TestPath" -MachineBackupPath "TestPath\Machine" -SharedBackupPath "TestPath\Shared"
        $result.Success | Should -Be $true
        $result.Feature | Should -Be "Game Managers"
    }

    It "Should handle missing backup gracefully" {
        Mock Test-BackupPath { return $null }
        $result = Restore-GameManagers -BackupRootPath "TestPath" -MachineBackupPath "TestPath\Machine" -SharedBackupPath "TestPath\Shared"
        $result.Success | Should -Be $true
        $result.Errors | Should -Contain "No game managers backup found"
    }

    It "Should process multiple game managers" {
        $result = Restore-GameManagers -BackupRootPath "TestPath" -MachineBackupPath "TestPath\Machine" -SharedBackupPath "TestPath\Shared"
        $result.Success | Should -Be $true
        $result.TotalGames | Should -BeGreaterThan 0
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Restore-GameManagers -BackupRootPath $BackupRootPath -MachineBackupPath $MachineBackupPath -SharedBackupPath $SharedBackupPath
}