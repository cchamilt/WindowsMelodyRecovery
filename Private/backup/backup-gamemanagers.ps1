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

# Helper function to parse Steam VDF files
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

function Backup-GameManagers {
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
            Write-Verbose "Starting backup of Game Managers..."
            Write-Host "Backing up Game Managers..." -ForegroundColor Blue
            
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
            
            $backupPath = Initialize-BackupDirectory -Path "GameManagers" -BackupType "Game Managers" -BackupRootPath $MachineBackupPath
            $sharedBackupPath = Initialize-BackupDirectory -Path "GameManagers" -BackupType "Shared Game Managers" -BackupRootPath $SharedBackupPath -IsShared
            $backedUpItems = @()
            $errors = @()
            
            if ($backupPath -and $sharedBackupPath) {
                # Initialize collections for each game platform
                $games = @{
                    Steam = @()
                    Epic = @()
                    GOG = @()
                    EA = @()
                    Ubisoft = @()
                    Xbox = @()
                }

                # Get Steam games if installed
                Write-Host "Scanning Steam games..." -ForegroundColor Blue
                if ($WhatIf) {
                    Write-Host "WhatIf: Would scan Steam games from registry and manifests"
                } else {
                    try {
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
                            Write-Host "Processing Steam path: $steamPath" -ForegroundColor Cyan
                            $manifestPath = Join-Path $steamPath "steamapps"
                            if (Test-Path $manifestPath) {
                                Write-Host "Scanning manifest path: $manifestPath" -ForegroundColor Cyan
                                $manifestFiles = Get-ChildItem "$manifestPath\appmanifest_*.acf" -ErrorAction SilentlyContinue
                                Write-Host "Found $($manifestFiles.Count) manifest files" -ForegroundColor Cyan
                                
                                foreach ($manifest in $manifestFiles) {
                                    try {
                                        $content = Get-Content $manifest -Raw
                                        $appState = Parse-KeyValues $content
                                        if ($appState.AppState) {
                                            $steamGames += @{
                                                Name = $appState.AppState.name
                                                ID = $appState.AppState.appid
                                                Source = "steam"
                                                InstallPath = Join-Path $manifestPath "common\$($appState.AppState.installdir)"
                                                Version = $appState.AppState.buildid
                                            }
                                            Write-Host "Found game: $($appState.AppState.name) (ID: $($appState.AppState.appid))" -ForegroundColor Cyan
                                        }
                                    }
                                    catch {
                                        $errors += "Failed to parse Steam manifest $($manifest.Name): $_"
                                        Write-Host "Warning: Failed to parse manifest: $($manifest.Name)" -ForegroundColor Yellow
                                    }
                                }
                            }
                        }
                        $games.Steam = $steamGames
                        Write-Host "Found $($steamGames.Count) Steam games" -ForegroundColor Green
                    } catch {
                        $errors += "Failed to scan Steam games: $_"
                        Write-Host "Warning: Failed to scan Steam games" -ForegroundColor Yellow
                    }
                }

                # Get Epic Games if installed
                Write-Host "Scanning Epic Games..." -ForegroundColor Blue
                if ($WhatIf) {
                    Write-Host "WhatIf: Would scan Epic Games from manifests"
                } else {
                    try {
                        $epicGames = @()
                        $epicManifestPath = "$env:ProgramData\Epic\EpicGamesLauncher\Data\Manifests"
                        if (Test-Path $epicManifestPath) {
                            $manifestFiles = Get-ChildItem "$epicManifestPath\*.item" -ErrorAction SilentlyContinue
                            foreach ($manifest in $manifestFiles) {
                                try {
                                    $content = Get-Content $manifest.FullName | ConvertFrom-Json
                                    if ($content.DisplayName) {
                                        $epicGames += @{
                                            Name = $content.DisplayName
                                            ID = $content.CatalogItemId
                                            Source = "epic"
                                            InstallPath = $content.InstallLocation
                                            Version = $content.AppVersion
                                        }
                                        Write-Host "Found Epic game: $($content.DisplayName)" -ForegroundColor Cyan
                                    }
                                }
                                catch {
                                    $errors += "Failed to parse Epic manifest $($manifest.Name): $_"
                                    Write-Host "Warning: Failed to parse Epic manifest: $($manifest.Name)" -ForegroundColor Yellow
                                }
                            }
                            Write-Host "Found $($epicGames.Count) Epic games" -ForegroundColor Green
                        } else {
                            Write-Host "Epic Games Launcher not found" -ForegroundColor Yellow
                        }
                        $games.Epic = $epicGames
                    } catch {
                        $errors += "Failed to scan Epic games: $_"
                        Write-Host "Warning: Failed to scan Epic games" -ForegroundColor Yellow
                    }
                }

                # Get GOG games if installed
                Write-Host "Scanning GOG games..." -ForegroundColor Blue
                if ($WhatIf) {
                    Write-Host "WhatIf: Would scan GOG games from database"
                } else {
                    try {
                        $gogGames = @()
                        $gogPath = "C:\Program Files (x86)\GOG Galaxy"
                        if (Test-Path $gogPath) {
                            # Try to read from GOG Galaxy database
                            $dbPath = "$env:ProgramData\GOG.com\Galaxy\storage\galaxy-2.0.db"
                            if (Test-Path $dbPath) {
                                # Note: This requires SQLite, but we'll provide a fallback
                                if (Get-Command sqlite3 -ErrorAction SilentlyContinue) {
                                    try {
                                        $query = "SELECT gamePieceId, title FROM GamePieces WHERE gamePieceTypeId = 'original_title'"
                                        $games_result = sqlite3 $dbPath $query
                                        foreach ($game in $games_result) {
                                            $id, $title = $game -split '\|'
                                            $gogGames += @{
                                                Name = $title
                                                ID = $id
                                                Source = "gog"
                                                InstallPath = ""
                                                Version = ""
                                            }
                                        }
                                        Write-Host "Found $($gogGames.Count) GOG games from database" -ForegroundColor Green
                                    } catch {
                                        $errors += "Failed to query GOG database: $_"
                                        Write-Host "Warning: Failed to query GOG database, SQLite may not be available" -ForegroundColor Yellow
                                    }
                                } else {
                                    Write-Host "SQLite not available for GOG database query" -ForegroundColor Yellow
                                    $errors += "SQLite not available for GOG database query"
                                }
                            } else {
                                Write-Host "GOG Galaxy database not found" -ForegroundColor Yellow
                            }
                        } else {
                            Write-Host "GOG Galaxy not found" -ForegroundColor Yellow
                        }
                        $games.GOG = $gogGames
                    } catch {
                        $errors += "Failed to scan GOG games: $_"
                        Write-Host "Warning: Failed to scan GOG games" -ForegroundColor Yellow
                    }
                }

                # Get EA games if installed
                Write-Host "Scanning EA games..." -ForegroundColor Blue
                if ($WhatIf) {
                    Write-Host "WhatIf: Would scan EA games from manifests and content"
                } else {
                    try {
                        $eaGames = @()
                        $eaPath = "$env:LOCALAPPDATA\Electronic Arts\EA Desktop\EA Desktop"
                        if (Test-Path $eaPath) {
                            # EA stores game info in multiple locations
                            $contentPath = "$env:PROGRAMDATA\Electronic Arts\EA Desktop\Downloaded"
                            $manifestPath = "$env:LOCALAPPDATA\Electronic Arts\EA Desktop\Downloaded"

                            # Scan content path
                            if (Test-Path $contentPath) {
                                $contentFiles = Get-ChildItem $contentPath -Filter "*.json" -ErrorAction SilentlyContinue
                                foreach ($file in $contentFiles) {
                                    try {
                                        $content = Get-Content $file.FullName | ConvertFrom-Json
                                        if ($content.gameTitle) {
                                            $eaGames += @{
                                                Name = $content.gameTitle
                                                ID = $content.gameId
                                                Source = "ea"
                                                InstallPath = $content.installPath
                                                Version = ""
                                            }
                                            Write-Host "Found EA game: $($content.gameTitle)" -ForegroundColor Cyan
                                        }
                                    }
                                    catch {
                                        $errors += "Failed to parse EA content file $($file.Name): $_"
                                    }
                                }
                            }

                            # Scan manifest path
                            if (Test-Path $manifestPath) {
                                $manifestFiles = Get-ChildItem $manifestPath -Filter "*.json" -ErrorAction SilentlyContinue
                                foreach ($file in $manifestFiles) {
                                    try {
                                        $manifest = Get-Content $file.FullName | ConvertFrom-Json
                                        if ($manifest.gameTitle -and ($manifest.gameTitle -notin $eaGames.Name)) {
                                            $eaGames += @{
                                                Name = $manifest.gameTitle
                                                ID = $manifest.gameId
                                                Source = "ea"
                                                InstallPath = $manifest.installPath
                                                Version = ""
                                            }
                                            Write-Host "Found EA game: $($manifest.gameTitle)" -ForegroundColor Cyan
                                        }
                                    }
                                    catch {
                                        $errors += "Failed to parse EA manifest file $($file.Name): $_"
                                    }
                                }
                            }
                            Write-Host "Found $($eaGames.Count) EA games" -ForegroundColor Green
                        } else {
                            Write-Host "EA Desktop not found" -ForegroundColor Yellow
                        }
                        $games.EA = $eaGames
                    } catch {
                        $errors += "Failed to scan EA games: $_"
                        Write-Host "Warning: Failed to scan EA games" -ForegroundColor Yellow
                    }
                }

                # Get Ubisoft games if installed
                Write-Host "Scanning Ubisoft games..." -ForegroundColor Blue
                if ($WhatIf) {
                    Write-Host "WhatIf: Would scan Ubisoft games from manifests"
                } else {
                    try {
                        $ubisoftGames = @()
                        $ubisoftPath = "C:\Program Files (x86)\Ubisoft\Ubisoft Game Launcher"
                        if (Test-Path $ubisoftPath) {
                            $manifestPath = Join-Path $ubisoftPath "games"
                            if (Test-Path $manifestPath) {
                                $gameDirs = Get-ChildItem -Path $manifestPath -Directory -ErrorAction SilentlyContinue
                                foreach ($gameDir in $gameDirs) {
                                    try {
                                        $manifestFile = Join-Path $gameDir.FullName "manifest.yml"
                                        if (Test-Path $manifestFile) {
                                            $content = Get-Content $manifestFile -Raw
                                            if ($content -match "name:\s*'([^']+)'") {
                                                $gameName = $matches[1]
                                                $ubisoftGames += @{
                                                    Name = $gameName
                                                    ID = $gameDir.Name
                                                    Source = "ubisoft"
                                                    InstallPath = $gameDir.FullName
                                                    Version = ""
                                                }
                                                Write-Host "Found Ubisoft game: $gameName" -ForegroundColor Cyan
                                            }
                                        }
                                    }
                                    catch {
                                        $errors += "Failed to parse Ubisoft game directory $($gameDir.Name): $_"
                                    }
                                }
                                Write-Host "Found $($ubisoftGames.Count) Ubisoft games" -ForegroundColor Green
                            } else {
                                Write-Host "Ubisoft games directory not found" -ForegroundColor Yellow
                            }
                        } else {
                            Write-Host "Ubisoft Connect not found" -ForegroundColor Yellow
                        }
                        $games.Ubisoft = $ubisoftGames
                    } catch {
                        $errors += "Failed to scan Ubisoft games: $_"
                        Write-Host "Warning: Failed to scan Ubisoft games" -ForegroundColor Yellow
                    }
                }

                # Get Xbox Game Pass games if installed
                Write-Host "Scanning Xbox Game Pass games..." -ForegroundColor Blue
                if ($WhatIf) {
                    Write-Host "WhatIf: Would scan Xbox Game Pass games from Windows Store"
                } else {
                    try {
                        $xboxGames = @()
                        # Xbox Game Pass games are typically installed as Store apps
                        $storeApps = Get-AppxPackage | Where-Object { 
                            $_.Publisher -like "*Microsoft*" -and 
                            $_.Name -notlike "*Microsoft.Windows*" -and
                            $_.Name -notlike "*Microsoft.Office*" -and
                            $_.PackageFullName -like "*_8wekyb3d8bbwe"
                        }
                        
                        foreach ($app in $storeApps) {
                            $xboxGames += @{
                                Name = $app.Name
                                ID = $app.PackageFullName
                                Source = "xbox"
                                InstallPath = $app.InstallLocation
                                Version = $app.Version
                            }
                        }
                        Write-Host "Found $($xboxGames.Count) potential Xbox Game Pass games" -ForegroundColor Green
                        $games.Xbox = $xboxGames
                    } catch {
                        $errors += "Failed to scan Xbox Game Pass games: $_"
                        Write-Host "Warning: Failed to scan Xbox Game Pass games" -ForegroundColor Yellow
                    }
                }

                # Export each platform to separate JSON files in both machine and shared paths
                $games.GetEnumerator() | ForEach-Object {
                    $platform = $_.Key.ToLower()
                    $platformGames = $_.Value
                    $jsonContent = $platformGames | ConvertTo-Json -Depth 10
                    $machineOutputPath = Join-Path $backupPath "$platform-games.json"
                    $sharedOutputPath = Join-Path $sharedBackupPath "$platform-games.json"
                    
                    if ($WhatIf) {
                        Write-Host "WhatIf: Would export $($_.Key) games to $machineOutputPath and $sharedOutputPath"
                    } else {
                        $jsonContent | Out-File $machineOutputPath -Force
                        $jsonContent | Out-File $sharedOutputPath -Force
                        $backedUpItems += "$platform-games.json"
                    }
                }

                # Export summary of all games
                $summary = @{
                    TotalGames = ($games.Values | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum
                    Platforms = @{}
                }
                $games.GetEnumerator() | ForEach-Object {
                    $summary.Platforms[$_.Key] = @{
                        Count = $_.Value.Count
                        Games = $_.Value | Select-Object Name, ID, Source
                    }
                }

                $summaryJson = $summary | ConvertTo-Json -Depth 10
                $machineOutputPath = Join-Path $backupPath "games-summary.json"
                $sharedOutputPath = Join-Path $sharedBackupPath "games-summary.json"
                
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export games summary to $machineOutputPath and $sharedOutputPath"
                } else {
                    $summaryJson | Out-File $machineOutputPath -Force
                    $summaryJson | Out-File $sharedOutputPath -Force
                    $backedUpItems += "games-summary.json"
                }

                # Output summary
                Write-Host "`nGame Managers Summary:" -ForegroundColor Green
                Write-Host "Steam Games: $($games.Steam.Count)" -ForegroundColor Yellow
                Write-Host "Epic Games: $($games.Epic.Count)" -ForegroundColor Yellow
                Write-Host "GOG Games: $($games.GOG.Count)" -ForegroundColor Yellow
                Write-Host "EA Games: $($games.EA.Count)" -ForegroundColor Yellow
                Write-Host "Ubisoft Games: $($games.Ubisoft.Count)" -ForegroundColor Yellow
                Write-Host "Xbox Game Pass: $($games.Xbox.Count)" -ForegroundColor Yellow
                Write-Host "Total Games: $($summary.TotalGames)" -ForegroundColor Cyan
                
                # Return object for better testing and validation
                $result = [PSCustomObject]@{
                    Success = $true
                    BackupPath = $backupPath
                    SharedBackupPath = $sharedBackupPath
                    Feature = "Game Managers"
                    Timestamp = Get-Date
                    Items = $backedUpItems
                    Errors = $errors
                    Summary = $summary
                }
                
                Write-Host "Game Managers backed up successfully to: $backupPath" -ForegroundColor Green
                Write-Host "Shared Game Managers backed up successfully to: $sharedBackupPath" -ForegroundColor Green
                Write-Verbose "Backup completed successfully"
                return $result
            }
            return $false
        } catch {
            $errorRecord = $_
            $errorMessage = @(
                "Failed to backup Game Managers"
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

<#
.SYNOPSIS
Backs up game manager settings and game lists.

.DESCRIPTION
Creates a backup of game managers and their installed games, including:
- Steam games and manifests
- Epic Games Launcher games
- GOG Galaxy games
- EA Desktop games
- Ubisoft Connect games
- Xbox Game Pass games
- Game lists exported as JSON files for each platform
- Summary of all games across platforms
- Both machine-specific and shared settings

.EXAMPLE
Backup-GameManagers -BackupRootPath "C:\Backups" -MachineBackupPath "C:\Backups\Machine" -SharedBackupPath "C:\Backups\Shared"

.NOTES
Test cases to consider:
1. Valid backup paths with proper permissions
2. Invalid/nonexistent backup paths
3. Empty backup paths
4. No permissions to write
5. Game managers installed/not installed
6. Game manifests exist/don't exist
7. Database access success/failure
8. JSON parsing success/failure
9. Partial platform failures

.TESTCASES
# Mock test examples:
Describe "Backup-GameManagers" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Initialize-BackupDirectory { return "TestPath" }
        Mock Get-ItemProperty { return @{ InstallPath = "C:\Steam" } }
        Mock Get-ChildItem { return @() }
        Mock Get-Content { return "" }
        Mock Get-AppxPackage { return @() }
        Mock ConvertFrom-Json { return @{} }
        Mock ConvertTo-Json { return "{}" }
        Mock Out-File { }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Backup-GameManagers -BackupRootPath "TestPath" -MachineBackupPath "TestPath\Machine" -SharedBackupPath "TestPath\Shared"
        $result.Success | Should -Be $true
        $result.BackupPath | Should -Be "TestPath"
        $result.SharedBackupPath | Should -Be "TestPath\Shared"
        $result.Feature | Should -Be "Game Managers"
    }

    It "Should handle missing game managers gracefully" {
        Mock Test-Path { return $false }
        $result = Backup-GameManagers -BackupRootPath "TestPath" -MachineBackupPath "TestPath\Machine" -SharedBackupPath "TestPath\Shared"
        $result.Success | Should -Be $true
        $result.Summary.TotalGames | Should -Be 0
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Backup-GameManagers -BackupRootPath $BackupRootPath -MachineBackupPath $MachineBackupPath -SharedBackupPath $SharedBackupPath
} 