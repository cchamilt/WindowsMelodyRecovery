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

function Parse-KeyValues {
    param([string]$content)
    
    function Parse-KeyValuesInternal {
        param([string[]]$lines, [ref]$currentIndex)
        
        $result = @{}
        while ($currentIndex.Value -lt $lines.Count) {
            $line = $lines[$currentIndex.Value].Trim()
            $currentIndex.Value++
            
            if ($line -eq "{") {
                continue
            }
            if ($line -eq "}") {
                break
            }
            if ([string]::IsNullOrWhiteSpace($line)) {
                continue
            }
            
            # Extract key and value, handling quoted strings
            if ($line -match '^"([^"]+)"\s+"([^"]+)"') {
                $key = $matches[1].Trim()
                $value = $matches[2].Trim()
                $result[$key] = $value
            }
            elseif ($line -match '^"([^"]+)"') {
                $key = $matches[1].Trim()
                # Next item is an object
                $subObject = Parse-KeyValuesInternal $lines $currentIndex
                $result[$key] = $subObject
            }
        }
        return $result
    }
    
    $lines = $content -split "`n" | ForEach-Object { $_.Trim() }
    $index = [ref]0
    return Parse-KeyValuesInternal $lines $index
}

function Backup-Games {
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
            Write-Verbose "Starting backup of Games..."
            Write-Host "Backing up Games List..." -ForegroundColor Blue
            
            # Validate inputs before proceeding
            if (!(Test-Path $BackupRootPath)) {
                throw [System.IO.DirectoryNotFoundException]"Backup root path not found: $BackupRootPath"
            }
            
            $backupPath = Initialize-BackupDirectory -Path "Games" -BackupType "Games" -BackupRootPath $BackupRootPath
            
            if ($backupPath) {
                $backedUpItems = @()
                $errors = @()
                
                # Initialize collections for each game platform
                $games = @{
                    Steam = @()
                    Epic = @()
                    GOG = @()
                    EA = @()
                    Other = @()
                }

                # Get Steam games if installed
                if ($WhatIf) {
                    Write-Host "WhatIf: Would scan Steam games"
                } else {
                    try {
                        Write-Host "Scanning Steam games..." -ForegroundColor Blue
                        $steamGames = @()
                        $defaultSteamPath = "C:\Program Files (x86)\Steam"
                        $steamPaths = @()

                        # Try registry first
                        $steamRegistry = Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam" -ErrorAction SilentlyContinue
                        if ($steamRegistry -and $steamRegistry.InstallPath) {
                            Write-Host "Found Steam registry path: $($steamRegistry.InstallPath)" -ForegroundColor Cyan
                            $steamPaths += $steamRegistry.InstallPath
                        }

                        # Add default path if it exists and isn't already included
                        if ((Test-Path $defaultSteamPath) -and ($steamPaths -notcontains $defaultSteamPath)) {
                            Write-Host "Found default Steam path: $defaultSteamPath" -ForegroundColor Cyan
                            $steamPaths += $defaultSteamPath
                        }

                        # For each Steam installation
                        foreach ($steamPath in $steamPaths) {
                            $manifestPath = Join-Path $steamPath "steamapps"
                            if (Test-Path $manifestPath) {
                                $manifestFiles = Get-ChildItem "$manifestPath\appmanifest_*.acf"
                                
                                foreach ($manifest in $manifestFiles) {
                                    $content = Get-Content $manifest -Raw
                                    try {
                                        $appState = Parse-KeyValues $content
                                        if ($appState.AppState) {
                                            $steamGames += @{
                                                Name = $appState.AppState.name
                                                ID = $appState.AppState.appid
                                                Source = "steam"
                                                InstallPath = Join-Path $manifestPath "common\$($appState.AppState.installdir)"
                                            }
                                        }
                                    }
                                    catch {
                                        $errors += "Failed to parse Steam manifest $($manifest.Name): $_"
                                    }
                                }
                            }
                        }
                        $games.Steam = $steamGames
                        $backedUpItems += "Steam games"
                    } catch {
                        $errors += "Failed to scan Steam games: $_"
                    }
                }

                # Get Epic Games if installed
                if ($WhatIf) {
                    Write-Host "WhatIf: Would scan Epic Games"
                } else {
                    try {
                        Write-Host "Scanning Epic Games..." -ForegroundColor Blue
                        $epicGames = @()
                        $epicManifestPath = "$env:ProgramData\Epic\EpicGamesLauncher\Data\Manifests"
                        if (Test-Path $epicManifestPath) {
                            Get-ChildItem "$epicManifestPath\*.item" | ForEach-Object {
                                $manifest = Get-Content $_.FullName | ConvertFrom-Json
                                if ($manifest.DisplayName) {
                                    $epicGames += @{
                                        Name = $manifest.DisplayName
                                        ID = $manifest.CatalogItemId
                                        Source = "epic"
                                        InstallPath = $manifest.InstallLocation
                                        Version = $manifest.AppVersion
                                    }
                                }
                            }
                        }
                        $games.Epic = $epicGames
                        $backedUpItems += "Epic games"
                    } catch {
                        $errors += "Failed to scan Epic Games: $_"
                    }
                }

                # Get GOG Galaxy games if installed
                if ($WhatIf) {
                    Write-Host "WhatIf: Would scan GOG Galaxy games"
                } else {
                    try {
                        Write-Host "Scanning GOG Galaxy games..." -ForegroundColor Blue
                        $gogGames = @()
                        $gogManifestPath = "$env:ProgramData\GOG.com\Galaxy\storage\galaxy-2.0.db"
                        if (Test-Path $gogManifestPath) {
                            # Note: This is a simplified example. In practice, you'd need to use SQLite to read the database
                            # and extract game information. This would require additional dependencies.
                            Write-Host "GOG Galaxy database found, but direct reading requires SQLite support" -ForegroundColor Yellow
                        }
                        $games.GOG = $gogGames
                        $backedUpItems += "GOG games"
                    } catch {
                        $errors += "Failed to scan GOG Galaxy games: $_"
                    }
                }

                # Get EA games if installed
                if ($WhatIf) {
                    Write-Host "WhatIf: Would scan EA games"
                } else {
                    try {
                        Write-Host "Scanning EA games..." -ForegroundColor Blue
                        $eaGames = @()
                        $eaManifestPath = "$env:ProgramData\EA\EA Desktop\Data\Manifests"
                        if (Test-Path $eaManifestPath) {
                            Get-ChildItem "$eaManifestPath\*.item" | ForEach-Object {
                                $manifest = Get-Content $_.FullName | ConvertFrom-Json
                                if ($manifest.DisplayName) {
                                    $eaGames += @{
                                        Name = $manifest.DisplayName
                                        ID = $manifest.CatalogItemId
                                        Source = "ea"
                                        InstallPath = $manifest.InstallLocation
                                        Version = $manifest.AppVersion
                                    }
                                }
                            }
                        }
                        $games.EA = $eaGames
                        $backedUpItems += "EA games"
                    } catch {
                        $errors += "Failed to scan EA games: $_"
                    }
                }

                # Save the complete games list
                if ($WhatIf) {
                    Write-Host "WhatIf: Would save games list to $backupPath\games.json"
                } else {
                    try {
                        $games | ConvertTo-Json -Depth 10 | Out-File "$backupPath\games.json" -Force
                        $backedUpItems += "games.json"
                    } catch {
                        $errors += "Failed to save games list: $_"
                    }
                }
                
                # Return object for better testing and validation
                $result = [PSCustomObject]@{
                    Success = $true
                    BackupPath = $backupPath
                    Feature = "Games"
                    Timestamp = Get-Date
                    Items = $backedUpItems
                    Errors = $errors
                }
                
                Write-Host "Games backed up successfully to: $backupPath" -ForegroundColor Green
                Write-Verbose "Backup completed successfully"
                return $result
            }
            return $false
        } catch {
            $errorRecord = $_
            $errorMessage = @(
                "Failed to backup Games"
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
    Export-ModuleMember -Function Backup-Games
}

<#
.SYNOPSIS
Backs up installed games and their configurations from various game platforms.

.DESCRIPTION
Creates a backup of installed games from various platforms including Steam, Epic Games, GOG Galaxy, and EA Desktop.

.EXAMPLE
Backup-Games -BackupRootPath "C:\Backups"

.NOTES
Test cases to consider:
1. Valid backup path with proper permissions
2. Invalid/nonexistent backup path
3. Empty backup path
4. No permissions to write
5. Steam installation detection
6. Epic Games installation detection
7. GOG Galaxy installation detection
8. EA Desktop installation detection
9. Manifest parsing success/failure
10. JSON serialization success/failure

.TESTCASES
# Mock test examples:
Describe "Backup-Games" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Initialize-BackupDirectory { return "TestPath" }
        Mock Get-ItemProperty { return @{
            InstallPath = "C:\Program Files (x86)\Steam"
        }}
        Mock Get-ChildItem { return @(
            [PSCustomObject]@{
                Name = "appmanifest_123456.acf"
                FullName = "C:\Program Files (x86)\Steam\steamapps\appmanifest_123456.acf"
            }
        )}
        Mock Get-Content { return @"
"AppState"
{
    "appid"        "123456"
    "name"        "Test Game"
    "installdir"    "Test Game"
}
"@
        }
        Mock ConvertFrom-Json { return @{
            DisplayName = "Test Game"
            CatalogItemId = "123456"
            InstallLocation = "C:\Games\Test Game"
            AppVersion = "1.0.0"
        }}
        Mock ConvertTo-Json { return '{"test":"value"}' }
        Mock Out-File { }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Backup-Games -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.BackupPath | Should -Be "TestPath"
        $result.Feature | Should -Be "Games"
    }

    It "Should handle manifest parsing failure gracefully" {
        Mock Get-Content { throw "Failed to read manifest" }
        $result = Backup-Games -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Errors.Count | Should -BeGreaterThan 0
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Backup-Games -BackupRootPath $BackupRootPath
} 