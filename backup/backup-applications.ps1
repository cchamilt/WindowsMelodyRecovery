[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$BackupRootPath = $null
)

# Load environment if not provided
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path (Split-Path $scriptPath -Parent) "scripts\load-environment.ps1")

if (!$BackupRootPath) {
    if (!(Load-Environment)) {
        Write-Host "Failed to load environment configuration" -ForegroundColor Red
        exit 1
    }
    $BackupRootPath = "$env:BACKUP_ROOT\$env:MACHINE_NAME"
}

# Main backup function that can be called by master script
function Backup-Applications {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath
    )
    
    try {
        Write-Host "Backing up Application List..." -ForegroundColor Blue
        $backupPath = Initialize-BackupDirectory -Path "Applications" -BackupType "Applications" -BackupRootPath $BackupRootPath
        
        if ($backupPath) {
            # Initialize collections for each package manager
            $applications = @{
                Store = @()
                Scoop = @()
                Chocolatey = @()
                Winget = @()
                Unmanaged = @()
            }

            # Get Store applications first
            Write-Host "Scanning Windows Store applications..." -ForegroundColor Blue
            $applications.Store = Get-AppxPackage | Select-Object Name, PackageFullName, Version | ForEach-Object {
                @{
                    Name = $_.Name
                    ID = $_.PackageFullName
                    Version = $_.Version
                    Source = "store"
                }
            }

            # Get Scoop applications if available
            Write-Host "Scanning Scoop applications..." -ForegroundColor Blue
            if (Get-Command scoop -ErrorAction SilentlyContinue) {
                $applications.Scoop = scoop list | ForEach-Object {
                    if ($_ -match "(?<name>.*?)\s+(?<version>[\d\.]+)") {
                        @{
                            Name = $matches.name.Trim()
                            Version = $matches.version
                            Source = "scoop"
                        }
                    }
                }
            }

            # Get Chocolatey applications if available
            Write-Host "Scanning Chocolatey applications..." -ForegroundColor Blue
            if (Get-Command choco -ErrorAction SilentlyContinue) {
                $applications.Chocolatey = choco list -lo -r | ForEach-Object {
                    $parts = $_ -split '\|'
                    @{
                        Name = $parts[0]
                        Version = $parts[1]
                        Source = "chocolatey"
                    }
                }
            }

            # Get all applications recognized by Winget
            Write-Host "Scanning Winget applications..." -ForegroundColor Blue
            $wingetApps = @()
            $wingetSearch = winget list
            
            try {
                $wingetLines = $wingetSearch -split "`n" | Select-Object -Skip 3
                foreach ($line in $wingetLines) {
                    if ($line -match "^(.+?)\s{2,}([^\s]+)\s{2,}(.+)$") {
                        $wingetApps += @{
                            Name = $Matches[1].Trim()
                            ID = $Matches[2]
                            Version = $Matches[3].Trim()
                            Source = "winget"
                        }
                        Write-Host "Found winget app: $($Matches[1].Trim())" -ForegroundColor Cyan
                    }
                }
            } catch {
                Write-Host "Warning: Error parsing winget output - $($_.Exception.Message)" -ForegroundColor Yellow
            }

            # Remove apps from winget list that are managed by other package managers
            $managedApps = @()
            $managedApps += $applications.Store.Name
            $managedApps += $applications.Scoop.Name
            $managedApps += $applications.Chocolatey.Name

            $applications.Winget = $wingetApps | Where-Object { $_.Name -notin $managedApps }

            # Get traditional Windows applications
            Write-Host "Scanning traditional Windows applications..." -ForegroundColor Blue
            $uninstallKeys = @(
                "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
                "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
                "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
            )

            # Known Windows/System Component Publishers to filter out
            $systemPublishers = @(
                "Microsoft Corporation",
                "Microsoft Windows",
                "Windows",
                "Microsoft"
            )

            # Known Windows/System Component patterns to filter out
            $systemPatterns = @(
                "Windows \w+ Runtime",
                "Microsoft \.NET",
                "Microsoft Visual C\+\+",
                "Microsoft Edge",
                "Microsoft Defender",
                "Microsoft Office",
                "Office 16 Click-to-Run",
                "Windows SDK",
                "Windows Software Development Kit",
                "Windows Driver Kit",
                "Microsoft Update Health Tools",
                "Microsoft Teams"
            )

            $traditionalApps = Get-ItemProperty $uninstallKeys | 
                Where-Object { 
                    $_.DisplayName -and 
                    # Filter out system components based on patterns
                    ($systemPatterns | ForEach-Object { $_.DisplayName -notmatch $_ }) -notcontains $false -and
                    # Only include Microsoft published items that aren't system components
                    !($_.Publisher -in $systemPublishers -and 
                      ($_.SystemComponent -eq 1 -or $_.ParentKeyName -or $_.ReleaseType -eq "Runtime" -or $_.DisplayName -like "*Runtime*"))
                } |
                Select-Object @{N='Name';E={$_.DisplayName}}, 
                            @{N='Version';E={$_.DisplayVersion}},
                            @{N='Publisher';E={$_.Publisher}},
                            @{N='InstallDate';E={$_.InstallDate}}

            # Improved name matching function
            function Compare-AppNames {
                param(
                    $name1, 
                    $name2,
                    $publisher = $null
                )
                
                # Normalize names for comparison
                $clean1 = $name1
                $clean1 = $clean1 -replace '[\(\)\[\]\{\}]', ''
                $clean1 = $clean1 -replace '\s+', ' '
                $clean1 = $clean1 -replace ' - ', ' '
                $clean1 = $clean1 -replace '64-bit|32-bit|\(x64\)|\(x86\)', ''
                $clean1 = $clean1 -replace 'Executables', ''
                $clean1 = $clean1 -replace '®|™', ''
                $clean1 = $clean1 -replace '\s+$', ''
                $clean1 = $clean1 -replace '\s*\(?git [a-f0-9]+\)?', ''
                $clean1 = $clean1 -replace '\s+\d+(\.\d+)*(\s+|$)', ''
                $clean1 = $clean1 -replace 'Installed for Current User', ''
                $clean1 = $clean1 -replace '\(User\)', ''
                $clean1 = $clean1 -replace '\(remove only\)', ''
                $clean1 = $clean1 -replace 'version', ''
                $clean1 = $clean1.Trim()

                $clean2 = $name2
                $clean2 = $clean2 -replace '[\(\)\[\]\{\}]', ''
                $clean2 = $clean2 -replace '\s+', ' '
                $clean2 = $clean2 -replace ' - ', ' '
                $clean2 = $clean2 -replace '64-bit|32-bit|\(x64\)|\(x86\)', ''
                $clean2 = $clean2 -replace 'Executables', ''
                $clean2 = $clean2 -replace '®|™', ''
                $clean2 = $clean2 -replace '\s+$', ''
                $clean2 = $clean2 -replace '\s*\(?git [a-f0-9]+\)?', ''
                $clean2 = $clean2 -replace '\s+\d+(\.\d+)*(\s+|$)', ''
                $clean2 = $clean2 -replace 'Installed for Current User', ''
                $clean2 = $clean2 -replace '\(User\)', ''
                $clean2 = $clean2 -replace '\(remove only\)', ''
                $clean2 = $clean2 -replace 'version', ''
                $clean2 = $clean2.Trim()

                return $clean1 -eq $clean2
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

            # Get Steam games if installed
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

            Write-Host "Steam installation paths found: $($steamPaths.Count)" -ForegroundColor Cyan

            # For each Steam installation
            foreach ($steamPath in $steamPaths) {
                Write-Host "Processing Steam path: $steamPath" -ForegroundColor Cyan
                $manifestPath = Join-Path $steamPath "steamapps"
                if (Test-Path $manifestPath) {
                    Write-Host "Scanning manifest path: $manifestPath" -ForegroundColor Cyan
                    $manifestFiles = Get-ChildItem "$manifestPath\appmanifest_*.acf"
                    Write-Host "Found $($manifestFiles.Count) manifest files" -ForegroundColor Cyan
                    
                    foreach ($manifest in $manifestFiles) {
                        Write-Host "Processing manifest: $($manifest.Name)" -ForegroundColor Cyan
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
                                Write-Host "Found game: $($appState.AppState.name) (ID: $($appState.AppState.appid))" -ForegroundColor Cyan
                            }
                        }
                        catch {
                            Write-Host "Failed to parse manifest: $_" -ForegroundColor Yellow
                            Write-Host "Manifest content: $($content.Substring(0, [Math]::Min($content.Length, 200)))..." -ForegroundColor Yellow
                        }
                    }
                }
            }

            # Get Epic Games if installed
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

            # Add games to applications collection
            $applications["Steam"] = $steamGames
            $applications["Epic"] = $epicGames

            # Add game names to managed apps list to exclude from unmanaged
            $managedApps += $steamGames.Name
            $managedApps += $epicGames.Name

            # Filter out apps that are managed by package managers with improved matching
            $applications.Unmanaged = $traditionalApps | Where-Object { 
                $app = $_
                $isManaged = $false
                
                # Check against all managed apps with improved name matching
                foreach ($managedApp in $managedApps) {
                    if (Compare-AppNames $app.Name $managedApp -Publisher $app.Publisher) {
                        $isManaged = $true
                        break
                    }
                }
                
                # Check against winget apps
                if (!$isManaged) {
                    foreach ($wingetApp in $applications.Winget) {
                        if (Compare-AppNames $app.Name $wingetApp.Name -Publisher $app.Publisher) {
                            $isManaged = $true
                            break
                        }
                    }
                }
                
                !$isManaged
            } | ForEach-Object {
                @{
                    Name = $_.Name
                    Version = $_.Version
                    Publisher = $_.Publisher
                    InstallDate = $_.InstallDate
                    Source = "manual"
                }
            }

            # Update summary to include games
            Write-Host "Steam Games: $($steamGames.Count)" -ForegroundColor Yellow
            Write-Host "Epic Games: $($epicGames.Count)" -ForegroundColor Yellow

            # Export each list to separate JSON files
            $applications.GetEnumerator() | ForEach-Object {
                $_.Value | ConvertTo-Json -Depth 10 | 
                Out-File (Join-Path $backupPath "$($_.Key.ToLower())-applications.json") -Force
            }

            # Output summary
            Write-Host "`nApplication Summary:" -ForegroundColor Green
            Write-Host "Store Applications: $($applications.Store.Count)" -ForegroundColor Yellow
            Write-Host "Scoop Packages: $($applications.Scoop.Count)" -ForegroundColor Yellow
            Write-Host "Chocolatey Packages: $($applications.Chocolatey.Count)" -ForegroundColor Yellow
            Write-Host "Winget Packages: $($applications.Winget.Count)" -ForegroundColor Yellow
            Write-Host "Steam Games: $($applications.Steam.Count)" -ForegroundColor Yellow
            Write-Host "Epic Games: $($applications.Epic.Count)" -ForegroundColor Yellow
            Write-Host "Unmanaged Applications: $($applications.Unmanaged.Count)" -ForegroundColor Yellow
            
            Write-Host "Applications list backed up successfully to: $backupPath" -ForegroundColor Green
            return $true
        }
        return $false
    } catch {
        $errorRecord = $_
        $errorMessage = @(
            "Failed to backup Applications"
            "Error Message: $($errorRecord.Exception.Message)"
            "Error Type: $($errorRecord.Exception.GetType().FullName)"
            "Script Line Number: $($errorRecord.InvocationInfo.ScriptLineNumber)"
            "Script Name: $($errorRecord.InvocationInfo.ScriptName)"
            "Statement: $($errorRecord.InvocationInfo.Line.Trim())"
            if ($errorRecord.Exception.StackTrace) { "Stack Trace: $($errorRecord.Exception.StackTrace)" }
            if ($errorRecord.Exception.InnerException) { "Inner Exception: $($errorRecord.Exception.InnerException.Message)" }
        ) -join "`n"
        
        Write-Host $errorMessage -ForegroundColor Red
        return $false
    }
}

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Backup-Applications -BackupRootPath $BackupRootPath
} 