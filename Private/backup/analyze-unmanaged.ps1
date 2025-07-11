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
    Write-Error -Message "Cannot find load-environment.ps1 at: $loadEnvPath"
}

# Get module configuration
$config = Get-WindowsMelodyRecovery
if (!$config.IsInitialized) {
    throw "Module not initialized. Please run Initialize-WindowsMelodyRecovery first."
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
            Write-Information -MessageData "Created backup directory for $BackupType at: $backupPath" -InformationAction Continue
        } catch {
            Write-Error -Message "Failed to create backup directory for $BackupType : $_"
            return $null
        }
    }

    return $backupPath
}

# Improved name matching function
function Compare-AppNames {
    param(
        $name1,
        $name2,
        $publisher = $null
    )

    # Handle null/empty inputs
    if (!$name1 -or !$name2) {
        return $false
    }

    # Normalize names for comparison
    $clean1 = $name1.ToString()
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

    $clean2 = $name2.ToString()
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

    # Exact match after normalization
    if ($clean1 -eq $clean2) {
        return $true
    }

    # Fuzzy matching for common variations
    if ($clean1.Length -gt 3 -and $clean2.Length -gt 3) {
        # Check if one name contains the other (for shortened versions)
        if ($clean1.Contains($clean2) -or $clean2.Contains($clean1)) {
            return $true
        }

        # Check for partial matches with publisher context
        if ($publisher) {
            $publisherWords = $publisher -split '\s+' | Where-Object { $_.Length -gt 2 }
            foreach ($word in $publisherWords) {
                if ($clean1.Contains($word) -and $clean2.Contains($word)) {
                    return $true
                }
            }
        }
    }

    return $false
}

function Analyze-UnmanagedApplications {
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
            Write-Verbose "Starting analysis of Unmanaged Applications..."
            Write-Information -MessageData "Analyzing Unmanaged Applications..." -InformationAction Continue

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

            $backupPath = Initialize-BackupDirectory -Path "UnmanagedApps" -BackupType "Unmanaged Applications Analysis" -BackupRootPath $MachineBackupPath
            $sharedBackupPath = Initialize-BackupDirectory -Path "UnmanagedApps" -BackupType "Shared Unmanaged Applications Analysis" -BackupRootPath $SharedBackupPath -IsShared
            $analyzedItems = @()
            $errors = @()

            if ($backupPath -and $sharedBackupPath) {
                # Step 1: Get all Windows installed applications
                Write-Information -MessageData "Scanning all Windows installed applications..." -InformationAction Continue
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

                $allWindowsApps = @()
                if ($WhatIf) {
                    Write-Information -MessageData "WhatIf: Would scan Windows registry for installed applications" -InformationAction Continue
                } else {
                    try {
                        $allWindowsApps = Get-ItemProperty $uninstallKeys -ErrorAction SilentlyContinue |
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
                                        @{N='InstallDate';E={$_.InstallDate}},
                                        @{N='UninstallString';E={$_.UninstallString}}

                        Write-Information -MessageData "Found $($allWindowsApps.Count) Windows applications" -InformationAction Continue
                    } catch {
                        $errors += "Failed to scan Windows applications: $_"
                        Write-Error -Message "Error: Failed to scan Windows applications"
                    }
                }

                # Step 2: Load managed applications from package managers
                Write-Information -MessageData "Loading package manager data..." -InformationAction Continue
                $managedApps = @()

                # Try machine backup path first, then shared
                $applicationsPaths = @(
                    Join-Path $MachineBackupPath "Applications"
                    Join-Path $SharedBackupPath "Applications"
                )

                $foundApplicationsPath = $null
                foreach ($path in $applicationsPaths) {
                    if (Test-Path $path) {
                        $foundApplicationsPath = $path
                        Write-Information -MessageData "Found package manager data at: $path" -InformationAction Continue
                        break
                    }
                }

                if ($foundApplicationsPath) {
                    # Load Store apps
                    $storeFile = Join-Path $foundApplicationsPath "store-applications.json"
                    if (Test-Path $storeFile) {
                        try {
                            $storeApps = Get-Content $storeFile | ConvertFrom-Json
                            $managedApps += $storeApps | ForEach-Object {
                                @{
                                    Name = $_.Name
                                    Source = "Store"
                                    Manager = "Windows Store"
                                }
                            }
                            Write-Information -MessageData "Loaded $($storeApps.Count) Store apps" -InformationAction Continue
                        } catch {
                            $errors += "Failed to load Store apps: $_"
                        }
                    }

                    # Load Scoop packages
                    $scoopFile = Join-Path $foundApplicationsPath "scoop-applications.json"
                    if (Test-Path $scoopFile) {
                        try {
                            $scoopApps = Get-Content $scoopFile | ConvertFrom-Json
                            $managedApps += $scoopApps | ForEach-Object {
                                @{
                                    Name = $_.Name
                                    Source = "Scoop"
                                    Manager = "Scoop"
                                }
                            }
                            Write-Information -MessageData "Loaded $($scoopApps.Count) Scoop packages" -InformationAction Continue
                        } catch {
                            $errors += "Failed to load Scoop packages: $_"
                        }
                    }

                    # Load Chocolatey packages
                    $chocoFile = Join-Path $foundApplicationsPath "chocolatey-applications.json"
                    if (Test-Path $chocoFile) {
                        try {
                            $chocoApps = Get-Content $chocoFile | ConvertFrom-Json
                            $managedApps += $chocoApps | ForEach-Object {
                                @{
                                    Name = $_.Name
                                    Source = "Chocolatey"
                                    Manager = "Chocolatey"
                                }
                            }
                            Write-Information -MessageData "Loaded $($chocoApps.Count) Chocolatey packages" -InformationAction Continue
                        } catch {
                            $errors += "Failed to load Chocolatey packages: $_"
                        }
                    }

                    # Load Winget packages
                    $wingetFile = Join-Path $foundApplicationsPath "winget-applications.json"
                    if (Test-Path $wingetFile) {
                        try {
                            $wingetApps = Get-Content $wingetFile | ConvertFrom-Json
                            $managedApps += $wingetApps | ForEach-Object {
                                @{
                                    Name = $_.Name
                                    Source = "Winget"
                                    Manager = "Winget"
                                }
                            }
                            Write-Information -MessageData "Loaded $($wingetApps.Count) Winget packages" -InformationAction Continue
                        } catch {
                            $errors += "Failed to load Winget packages: $_"
                        }
                    }
                } else {
                    Write-Warning -Message "Warning: No package manager data found. Run backup-applications.ps1 first."
                    $errors += "No package manager data found"
                }

                # Step 3: Load managed games from game managers
                Write-Information -MessageData "Loading game manager data..." -InformationAction Continue

                $gameManagerPaths = @(
                    Join-Path $MachineBackupPath "GameManagers"
                    Join-Path $SharedBackupPath "GameManagers"
                )

                $foundGameManagerPath = $null
                foreach ($path in $gameManagerPaths) {
                    if (Test-Path $path) {
                        $foundGameManagerPath = $path
                        Write-Information -MessageData "Found game manager data at: $path" -InformationAction Continue
                        break
                    }
                }

                if ($foundGameManagerPath) {
                    $gameManagers = @("steam", "epic", "gog", "ea", "ubisoft", "xbox")
                    foreach ($manager in $gameManagers) {
                        $gameFile = Join-Path $foundGameManagerPath "$manager-games.json"
                        if (Test-Path $gameFile) {
                            try {
                                $games = Get-Content $gameFile | ConvertFrom-Json
                                $managedApps += $games | ForEach-Object {
                                    @{
                                        Name = $_.Name
                                        Source = $manager.ToUpper()
                                        Manager = "$($manager.Substring(0,1).ToUpper() + $manager.Substring(1)) Games"
                                    }
                                }
                                Write-Information -MessageData "Loaded $($games.Count) $manager games" -InformationAction Continue
                            } catch {
                                $errors += "Failed to load $manager games: $_"
                            }
                        }
                    }
                } else {
                    Write-Warning -Message "Warning: No game manager data found. Run backup-gamemanagers.ps1 first."
                    $errors += "No game manager data found"
                }

                # Step 4: Analyze unmanaged applications
                Write-Information -MessageData "Analyzing unmanaged applications..." -InformationAction Continue
                $unmanagedApps = @()

                if ($WhatIf) {
                    Write-Information -MessageData "WhatIf: Would analyze $($allWindowsApps.Count) Windows apps against $($managedApps.Count) managed apps" -InformationAction Continue
                } else {
                    foreach ($windowsApp in $allWindowsApps) {
                        $isManaged = $false
                        $managedBy = $null

                        # Check against all managed apps with improved name matching
                        foreach ($managedApp in $managedApps) {
                            if (Compare-AppNames $windowsApp.Name $managedApp.Name -Publisher $windowsApp.Publisher) {
                                $isManaged = $true
                                $managedBy = $managedApp.Manager
                                break
                            }
                        }

                        if (!$isManaged) {
                            $unmanagedApps += @{
                                Name = $windowsApp.Name
                                Version = $windowsApp.Version
                                Publisher = $windowsApp.Publisher
                                InstallDate = $windowsApp.InstallDate
                                UninstallString = $windowsApp.UninstallString
                                Source = "manual"
                                Priority = "unknown"
                                Category = "unknown"
                            }
                        }
                    }
                }

                # Step 5: Categorize and prioritize unmanaged apps
                Write-Information -MessageData "Categorizing unmanaged applications..." -InformationAction Continue
                if (!$WhatIf) {
                    foreach ($app in $unmanagedApps) {
                        # Categorize by publisher
                        if ($app.Publisher) {
                            $publisher = $app.Publisher.ToLower()
                            if ($publisher -like "*adobe*") {
                                $app.Category = "Creative"
                                $app.Priority = "high"
                            } elseif ($publisher -like "*jetbrains*" -or $publisher -like "*visual studio*" -or $publisher -like "*github*") {
                                $app.Category = "Development"
                                $app.Priority = "high"
                            } elseif ($publisher -like "*google*" -or $publisher -like "*mozilla*" -or $publisher -like "*opera*") {
                                $app.Category = "Web Browser"
                                $app.Priority = "high"
                            } elseif ($publisher -like "*nvidia*" -or $publisher -like "*amd*" -or $publisher -like "*intel*") {
                                $app.Category = "Drivers"
                                $app.Priority = "medium"
                            } elseif ($publisher -like "*microsoft*") {
                                $app.Category = "Microsoft"
                                $app.Priority = "low"
                            } else {
                                $app.Category = "Third-party"
                                $app.Priority = "medium"
                            }
                        }

                        # Categorize by name patterns
                        $appName = $app.Name.ToLower()
                        if ($appName -like "*game*" -or $appName -like "*launcher*") {
                            $app.Category = "Gaming"
                        } elseif ($appName -like "*driver*" -or $appName -like "*codec*") {
                            $app.Category = "Drivers"
                        } elseif ($appName -like "*office*" -or $appName -like "*word*" -or $appName -like "*excel*") {
                            $app.Category = "Productivity"
                            $app.Priority = "high"
                        }
                    }
                }

                # Step 6: Export results
                $analysis = @{
                    Timestamp = Get-Date
                    Summary = @{
                        TotalWindowsApps = $allWindowsApps.Count
                        TotalManagedApps = $managedApps.Count
                        TotalUnmanagedApps = $unmanagedApps.Count
                        ManagedPercentage = if ($allWindowsApps.Count -gt 0) { [Math]::Round(($managedApps.Count / $allWindowsApps.Count) * 100, 2) } else { 0 }
                    }
                    Categories = @{}
                    UnmanagedApps = $unmanagedApps
                    ManagedApps = $managedApps
                    Errors = $errors
                }

                # Group unmanaged apps by category
                $unmanagedApps | Group-Object Category | ForEach-Object {
                    $analysis.Categories[$_.Name] = @{
                        Count = $_.Count
                        Apps = $_.Group
                    }
                }

                # Export main analysis
                if ($WhatIf) {
                    Write-Information -MessageData "WhatIf: Would export unmanaged applications analysis" -InformationAction Continue
                } else {
                    $analysisJson = $analysis | ConvertTo-Json -Depth 10
                    $machineOutputPath = Join-Path $backupPath "unmanaged-analysis.json"
                    $sharedOutputPath = Join-Path $sharedBackupPath "unmanaged-analysis.json"

                    $analysisJson | Out-File $machineOutputPath -Force
                    $analysisJson | Out-File $sharedOutputPath -Force
                    $analyzedItems += "unmanaged-analysis.json"
                }

                # Export user-friendly unmanaged apps list
                if ($WhatIf) {
                    Write-Information -MessageData "WhatIf: Would export user-friendly unmanaged apps list" -InformationAction Continue
                } else {
                    $userFriendlyList = $unmanagedApps | Sort-Object Priority, Category, Name | Select-Object Name, Publisher, Category, Priority, Version, InstallDate
                    $userListJson = $userFriendlyList | ConvertTo-Json -Depth 5
                    $machineUserPath = Join-Path $backupPath "unmanaged-apps.json"
                    $sharedUserPath = Join-Path $sharedBackupPath "unmanaged-apps.json"

                    $userListJson | Out-File $machineUserPath -Force
                    $userListJson | Out-File $sharedUserPath -Force
                    $analyzedItems += "unmanaged-apps.json"
                }

                # Export CSV for easy viewing in Excel
                if ($WhatIf) {
                    Write-Information -MessageData "WhatIf: Would export CSV file for Excel" -InformationAction Continue
                } else {
                    $csvPath = Join-Path $backupPath "unmanaged-apps.csv"
                    $sharedCsvPath = Join-Path $sharedBackupPath "unmanaged-apps.csv"

                    $unmanagedApps | Sort-Object Priority, Category, Name |
                        Select-Object Name, Publisher, Category, Priority, Version, InstallDate |
                        Export-Csv $csvPath -NoTypeInformation -Force

                    Copy-Item $csvPath $sharedCsvPath -Force
                    $analyzedItems += "unmanaged-apps.csv"
                }

                # Output summary
                Write-Information -MessageData "`nUnmanaged Applications Analysis:" -InformationAction Continue
                Write-Warning -Message "Total Windows Apps: $($analysis.Summary.TotalWindowsApps)"
                Write-Warning -Message "Managed Apps: $($analysis.Summary.TotalManagedApps)"
                Write-Warning -Message "Unmanaged Apps: $($analysis.Summary.TotalUnmanagedApps)"
                Write-Warning -Message "Managed Percentage: $($analysis.Summary.ManagedPercentage)%"

                if ($analysis.Categories.Count -gt 0) {
                    Write-Information -MessageData "`nUnmanaged Apps by Category:" -InformationAction Continue
                    $analysis.Categories.GetEnumerator() | Sort-Object Key | ForEach-Object {
                        Write-Information -MessageData "  $($_.Key): $($_.Value.Count)"  -InformationAction Continue-ForegroundColor White
                    }
                }

                if ($unmanagedApps.Count -gt 0) {
                    Write-Verbose -Message "`nTop 10 High-Priority Unmanaged Apps:"
                    $unmanagedApps | Where-Object { $_.Priority -eq "high" } |
                        Sort-Object Name | Select-Object -First 10 | ForEach-Object {
                        Write-Information -MessageData "   -InformationAction Continue- $($_.Name) ($($_.Publisher))" -ForegroundColor White
                    }
                }

                # Return object for better testing and validation
                $result = [PSCustomObject]@{
                    Success = $true
                    BackupPath = $backupPath
                    SharedBackupPath = $sharedBackupPath
                    Feature = "Unmanaged Applications Analysis"
                    Timestamp = Get-Date
                    Items = $analyzedItems
                    Errors = $errors
                    Analysis = $analysis
                }

                Write-Information -MessageData "Unmanaged Applications analysis completed successfully!" -InformationAction Continue
                Write-Information -MessageData "Results saved to: $backupPath" -InformationAction Continue
                Write-Information -MessageData "Shared results saved to: $sharedBackupPath" -InformationAction Continue
                Write-Warning -Message "`nIMPORTANT: Review 'unmanaged-apps.json' to see what you need to manually install!"
                Write-Verbose "Analysis completed successfully"
                return $result
            }
            return $false
        } catch {
            $errorRecord = $_
            $errorMessage = @(
                "Failed to analyze Unmanaged Applications"
                "Error Message: $($errorRecord.Exception.Message)"
                "Error Type: $($errorRecord.Exception.GetType().FullName)"
                "Script Line Number: $($errorRecord.InvocationInfo.ScriptLineNumber)"
                "Script Name: $($errorRecord.InvocationInfo.ScriptName)"
                "Statement: $($errorRecord.InvocationInfo.Line.Trim())"
                if ($errorRecord.Exception.StackTrace) { "Stack Trace: $($errorRecord.Exception.StackTrace)" }
                if ($errorRecord.Exception.InnerException) { "Inner Exception: $($errorRecord.Exception.InnerException.Message)" }
            ) -join "`n"

            Write-Error $errorMessage
            Write-Verbose "Analysis failed"
            throw  # Re-throw for proper error handling
        }
    }
}

function Compare-PostRestoreApplications {
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
            Write-Verbose "Running in test mode for post-restore analysis"
        }
    }

    process {
        try {
            Write-Verbose "Starting post-restore analysis..."
            Write-Information -MessageData "Analyzing post-restore application status..." -InformationAction Continue

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

            $analyzedItems = @()
            $errors = @()

            # Find the original unmanaged analysis
            $unmanagedPaths = @(
                Join-Path $MachineBackupPath "UnmanagedApps"
                Join-Path $SharedBackupPath "UnmanagedApps"
            )

            $originalAnalysisPath = $null
            foreach ($path in $unmanagedPaths) {
                $analysisFile = Join-Path $path "unmanaged-analysis.json"
                if (Test-Path $analysisFile) {
                    $originalAnalysisPath = $analysisFile
                    Write-Information -MessageData "Found original unmanaged analysis at: $analysisFile" -InformationAction Continue
                    break
                }
            }

            if (!$originalAnalysisPath) {
                Write-Warning -Message "No original unmanaged analysis found - running fresh analysis instead"
                # Fall back to running a fresh analysis
                return Analyze-UnmanagedApplications -BackupRootPath $BackupRootPath -MachineBackupPath $MachineBackupPath -SharedBackupPath $SharedBackupPath -Force:$Force -WhatIf:$WhatIf
            }

            # Load the original unmanaged analysis
            if ($WhatIf) {
                Write-Information -MessageData "WhatIf: Would load original unmanaged analysis" -InformationAction Continue
            } else {
                try {
                    $originalAnalysis = Get-Content $originalAnalysisPath | ConvertFrom-Json
                    $originalUnmanagedApps = $originalAnalysis.UnmanagedApps
                    Write-Information -MessageData "Loaded $($originalUnmanagedApps.Count) originally unmanaged applications" -InformationAction Continue
                } catch {
                    $errors += "Failed to load original unmanaged analysis: $_"
                    Write-Error -Message "Failed to load original unmanaged analysis: $_"
                    return $false
                }
            }

            # Get current Windows installed applications
            Write-Information -MessageData "Scanning current Windows installed applications..." -InformationAction Continue
            $currentWindowsApps = @()
            if ($WhatIf) {
                Write-Information -MessageData "WhatIf: Would scan current Windows applications" -InformationAction Continue
            } else {
                try {
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

                    $currentWindowsApps = Get-ItemProperty $uninstallKeys -ErrorAction SilentlyContinue |
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
                                    @{N='InstallDate';E={$_.InstallDate}},
                                    @{N='UninstallString';E={$_.UninstallString}}

                    Write-Information -MessageData "Found $($currentWindowsApps.Count) current Windows applications" -InformationAction Continue
                } catch {
                    $errors += "Failed to scan current Windows applications: $_"
                    Write-Error -Message "Error: Failed to scan current Windows applications"
                }
            }

            # Compare original unmanaged apps against current system
            Write-Information -MessageData "Comparing original unmanaged apps against current system..." -InformationAction Continue
            $restoredApps = @()
            $stillUnmanagedApps = @()

            if ($WhatIf) {
                Write-Information -MessageData "WhatIf: Would compare $($originalUnmanagedApps.Count) originally unmanaged apps against current system" -InformationAction Continue
            } else {
                foreach ($originalApp in $originalUnmanagedApps) {
                    $isNowInstalled = $false

                    # Check if this app is now installed
                    foreach ($currentApp in $currentWindowsApps) {
                        if (Compare-AppNames $originalApp.Name $currentApp.Name -Publisher $originalApp.Publisher) {
                            $isNowInstalled = $true
                            $restoredApps += @{
                                OriginalName = $originalApp.Name
                                CurrentName = $currentApp.Name
                                Publisher = $originalApp.Publisher
                                Category = $originalApp.Category
                                Priority = $originalApp.Priority
                                RestoreMethod = "unknown"  # Could be enhanced to track how it was restored
                            }
                            break
                        }
                    }

                    if (!$isNowInstalled) {
                        $stillUnmanagedApps += $originalApp
                    }
                }
            }

            # Create post-restore analysis
            $postRestoreAnalysis = @{
                Timestamp = Get-Date
                OriginalAnalysisTimestamp = if ($originalAnalysis.Timestamp) { $originalAnalysis.Timestamp } else { "Unknown" }
                Summary = @{
                    OriginalUnmanagedApps = $originalUnmanagedApps.Count
                    RestoredApps = $restoredApps.Count
                    StillUnmanagedApps = $stillUnmanagedApps.Count
                    RestoreSuccessRate = if ($originalUnmanagedApps.Count -gt 0) {
                        [Math]::Round(($restoredApps.Count / $originalUnmanagedApps.Count) * 100, 2)
                    } else { 100 }
                    TotalCurrentApps = $currentWindowsApps.Count
                }
                RestoredApps = $restoredApps
                StillUnmanagedApps = $stillUnmanagedApps
                OriginalAnalysis = $originalAnalysis.Summary
                Errors = $errors
            }

            # Create output directory
            $outputPath = Initialize-BackupDirectory -Path "PostRestoreAnalysis" -BackupType "Post-Restore Analysis" -BackupRootPath $MachineBackupPath
            $sharedOutputPath = Initialize-BackupDirectory -Path "PostRestoreAnalysis" -BackupType "Shared Post-Restore Analysis" -BackupRootPath $SharedBackupPath -IsShared

            if ($outputPath -and $sharedOutputPath) {
                # Export post-restore analysis
                if ($WhatIf) {
                    Write-Information -MessageData "WhatIf: Would export post-restore analysis" -InformationAction Continue
                } else {
                    $analysisJson = $postRestoreAnalysis | ConvertTo-Json -Depth 10
                    $machineOutputFile = Join-Path $outputPath "post-restore-analysis.json"
                    $sharedOutputFile = Join-Path $sharedOutputPath "post-restore-analysis.json"

                    $analysisJson | Out-File $machineOutputFile -Force
                    $analysisJson | Out-File $sharedOutputFile -Force
                    $analyzedItems += "post-restore-analysis.json"
                }

                # Export still unmanaged apps (what the user still needs to install manually)
                if ($WhatIf) {
                    Write-Information -MessageData "WhatIf: Would export still unmanaged apps list" -InformationAction Continue
                } else {
                    $stillUnmanagedList = $stillUnmanagedApps | Sort-Object Priority, Category, Name | Select-Object Name, Publisher, Category, Priority, Version, InstallDate
                    $stillUnmanagedJson = $stillUnmanagedList | ConvertTo-Json -Depth 5
                    $machineStillUnmanagedFile = Join-Path $outputPath "still-unmanaged-apps.json"
                    $sharedStillUnmanagedFile = Join-Path $sharedOutputPath "still-unmanaged-apps.json"

                    $stillUnmanagedJson | Out-File $machineStillUnmanagedFile -Force
                    $stillUnmanagedJson | Out-File $sharedStillUnmanagedFile -Force
                    $analyzedItems += "still-unmanaged-apps.json"
                }

                # Export CSV for easy viewing in Excel
                if ($WhatIf) {
                    Write-Information -MessageData "WhatIf: Would export CSV file for Excel" -InformationAction Continue
                } else {
                    $csvPath = Join-Path $outputPath "still-unmanaged-apps.csv"
                    $sharedCsvPath = Join-Path $sharedOutputPath "still-unmanaged-apps.csv"

                    $stillUnmanagedApps | Sort-Object Priority, Category, Name |
                        Select-Object Name, Publisher, Category, Priority, Version, InstallDate |
                        Export-Csv $csvPath -NoTypeInformation -Force

                    Copy-Item $csvPath $sharedCsvPath -Force
                    $analyzedItems += "still-unmanaged-apps.csv"
                }

                # Export restored apps list
                if ($WhatIf) {
                    Write-Information -MessageData "WhatIf: Would export restored apps list" -InformationAction Continue
                } else {
                    $restoredList = $restoredApps | Sort-Object Category, Priority, OriginalName | Select-Object OriginalName, CurrentName, Publisher, Category, Priority, RestoreMethod
                    $restoredJson = $restoredList | ConvertTo-Json -Depth 5
                    $machineRestoredFile = Join-Path $outputPath "restored-apps.json"
                    $sharedRestoredFile = Join-Path $sharedOutputPath "restored-apps.json"

                    $restoredJson | Out-File $machineRestoredFile -Force
                    $restoredJson | Out-File $sharedRestoredFile -Force
                    $analyzedItems += "restored-apps.json"
                }

                # Output summary
                Write-Information -MessageData "`nPost-Restore Analysis Results:" -InformationAction Continue
                Write-Warning -Message "Original Unmanaged Apps: $($postRestoreAnalysis.Summary.OriginalUnmanagedApps)"
                Write-Information -MessageData "Successfully Restored: $($postRestoreAnalysis.Summary.RestoredApps)" -InformationAction Continue
                Write-Error -Message "Still Need Manual Install: $($postRestoreAnalysis.Summary.StillUnmanagedApps)"
                Write-Information -MessageData "Restore Success Rate: $($postRestoreAnalysis.Summary.RestoreSuccessRate)%" -InformationAction Continue

                if ($stillUnmanagedApps.Count -gt 0) {
                    Write-Verbose -Message "`nTop 10 High-Priority Apps Still Needing Manual Installation:"
                    $stillUnmanagedApps | Where-Object { $_.Priority -eq "high" } |
                        Sort-Object Name | Select-Object -First 10 | ForEach-Object {
                        Write-Information -MessageData "   -InformationAction Continue- $($_.Name) ($($_.Publisher))" -ForegroundColor White
                    }
                } else {
                    Write-Information -MessageData "`nAll originally unmanaged applications have been successfully restored!" -InformationAction Continue
                }

                # Return object for better testing and validation
                $result = [PSCustomObject]@{
                    Success = $true
                    BackupPath = $outputPath
                    SharedBackupPath = $sharedOutputPath
                    Feature = "Post-Restore Analysis"
                    Timestamp = Get-Date
                    Items = $analyzedItems
                    Errors = $errors
                    Analysis = $postRestoreAnalysis
                }

                Write-Information -MessageData "Post-restore analysis completed successfully!" -InformationAction Continue
                Write-Information -MessageData "Results saved to: $outputPath" -InformationAction Continue
                Write-Information -MessageData "Shared results saved to: $sharedOutputPath" -InformationAction Continue
                if ($stillUnmanagedApps.Count -gt 0) {
                    Write-Warning -Message "`nIMPORTANT: Review 'still-unmanaged-apps.json' and 'still-unmanaged-apps.csv' for remaining manual installations!"
                } else {
                    Write-Information -MessageData "`nCONGRATULATIONS: All applications have been successfully restored!" -InformationAction Continue
                }
                Write-Verbose "Post-restore analysis completed successfully"
                return $result
            }
            return $false
        } catch {
            $errorRecord = $_
            $errorMessage = @(
                "Failed to analyze post-restore applications"
                "Error Message: $($errorRecord.Exception.Message)"
                "Error Type: $($errorRecord.Exception.GetType().FullName)"
                "Script Line Number: $($errorRecord.InvocationInfo.ScriptLineNumber)"
                "Script Name: $($errorRecord.InvocationInfo.ScriptName)"
                "Statement: $($errorRecord.InvocationInfo.Line.Trim())"
                if ($errorRecord.Exception.StackTrace) { "Stack Trace: $($errorRecord.Exception.StackTrace)" }
                if ($errorRecord.Exception.InnerException) { "Inner Exception: $($errorRecord.Exception.InnerException.Message)" }
            ) -join "`n"

            Write-Error $errorMessage
            Write-Verbose "Post-restore analysis failed"
            throw  # Re-throw for proper error handling
        }
    }
}

function Compare-PostRestoreApplications {
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
            Write-Verbose "Running in test mode for post-restore analysis"
        }
    }

    process {
        try {
            Write-Verbose "Starting post-restore analysis..."
            Write-Information -MessageData "Analyzing post-restore application status..." -InformationAction Continue

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

            $analyzedItems = @()
            $errors = @()

            # Find the original unmanaged analysis
            $unmanagedPaths = @(
                Join-Path $MachineBackupPath "UnmanagedApps"
                Join-Path $SharedBackupPath "UnmanagedApps"
            )

            $originalAnalysisPath = $null
            foreach ($path in $unmanagedPaths) {
                $analysisFile = Join-Path $path "unmanaged-analysis.json"
                if (Test-Path $analysisFile) {
                    $originalAnalysisPath = $analysisFile
                    Write-Information -MessageData "Found original unmanaged analysis at: $analysisFile" -InformationAction Continue
                    break
                }
            }

            if (!$originalAnalysisPath) {
                Write-Warning -Message "No original unmanaged analysis found - running fresh analysis instead"
                # Fall back to running a fresh analysis
                return Analyze-UnmanagedApplications -BackupRootPath $BackupRootPath -MachineBackupPath $MachineBackupPath -SharedBackupPath $SharedBackupPath -Force:$Force -WhatIf:$WhatIf
            }

            # Load the original unmanaged analysis
            if ($WhatIf) {
                Write-Information -MessageData "WhatIf: Would load original unmanaged analysis" -InformationAction Continue
            } else {
                try {
                    $originalAnalysis = Get-Content $originalAnalysisPath | ConvertFrom-Json
                    $originalUnmanagedApps = $originalAnalysis.UnmanagedApps
                    Write-Information -MessageData "Loaded $($originalUnmanagedApps.Count) originally unmanaged applications" -InformationAction Continue
                } catch {
                    $errors += "Failed to load original unmanaged analysis: $_"
                    Write-Error -Message "Failed to load original unmanaged analysis: $_"
                    return $false
                }
            }

            # Get current Windows installed applications
            Write-Information -MessageData "Scanning current Windows installed applications..." -InformationAction Continue
            $currentWindowsApps = @()
            if ($WhatIf) {
                Write-Information -MessageData "WhatIf: Would scan current Windows applications" -InformationAction Continue
            } else {
                try {
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

                    $currentWindowsApps = Get-ItemProperty $uninstallKeys -ErrorAction SilentlyContinue |
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
                                    @{N='InstallDate';E={$_.InstallDate}},
                                    @{N='UninstallString';E={$_.UninstallString}}

                    Write-Information -MessageData "Found $($currentWindowsApps.Count) current Windows applications" -InformationAction Continue
                } catch {
                    $errors += "Failed to scan current Windows applications: $_"
                    Write-Error -Message "Error: Failed to scan current Windows applications"
                }
            }

            # Compare original unmanaged apps against current system
            Write-Information -MessageData "Comparing original unmanaged apps against current system..." -InformationAction Continue
            $restoredApps = @()
            $stillUnmanagedApps = @()

            if ($WhatIf) {
                Write-Information -MessageData "WhatIf: Would compare $($originalUnmanagedApps.Count) originally unmanaged apps against current system" -InformationAction Continue
            } else {
                foreach ($originalApp in $originalUnmanagedApps) {
                    $isNowInstalled = $false

                    # Check if this app is now installed
                    foreach ($currentApp in $currentWindowsApps) {
                        if (Compare-AppNames $originalApp.Name $currentApp.Name -Publisher $originalApp.Publisher) {
                            $isNowInstalled = $true
                            $restoredApps += @{
                                OriginalName = $originalApp.Name
                                CurrentName = $currentApp.Name
                                Publisher = $originalApp.Publisher
                                Category = $originalApp.Category
                                Priority = $originalApp.Priority
                                RestoreMethod = "unknown"  # Could be enhanced to track how it was restored
                            }
                            break
                        }
                    }

                    if (!$isNowInstalled) {
                        $stillUnmanagedApps += $originalApp
                    }
                }
            }

            # Create post-restore analysis
            $postRestoreAnalysis = @{
                Timestamp = Get-Date
                OriginalAnalysisTimestamp = if ($originalAnalysis.Timestamp) { $originalAnalysis.Timestamp } else { "Unknown" }
                Summary = @{
                    OriginalUnmanagedApps = $originalUnmanagedApps.Count
                    RestoredApps = $restoredApps.Count
                    StillUnmanagedApps = $stillUnmanagedApps.Count
                    RestoreSuccessRate = if ($originalUnmanagedApps.Count -gt 0) {
                        [Math]::Round(($restoredApps.Count / $originalUnmanagedApps.Count) * 100, 2)
                    } else { 100 }
                    TotalCurrentApps = $currentWindowsApps.Count
                }
                RestoredApps = $restoredApps
                StillUnmanagedApps = $stillUnmanagedApps
                OriginalAnalysis = $originalAnalysis.Summary
                Errors = $errors
            }

            # Create output directory
            $outputPath = Initialize-BackupDirectory -Path "PostRestoreAnalysis" -BackupType "Post-Restore Analysis" -BackupRootPath $MachineBackupPath
            $sharedOutputPath = Initialize-BackupDirectory -Path "PostRestoreAnalysis" -BackupType "Shared Post-Restore Analysis" -BackupRootPath $SharedBackupPath -IsShared

            if ($outputPath -and $sharedOutputPath) {
                # Export post-restore analysis
                if ($WhatIf) {
                    Write-Information -MessageData "WhatIf: Would export post-restore analysis" -InformationAction Continue
                } else {
                    $analysisJson = $postRestoreAnalysis | ConvertTo-Json -Depth 10
                    $machineOutputFile = Join-Path $outputPath "post-restore-analysis.json"
                    $sharedOutputFile = Join-Path $sharedOutputPath "post-restore-analysis.json"

                    $analysisJson | Out-File $machineOutputFile -Force
                    $analysisJson | Out-File $sharedOutputFile -Force
                    $analyzedItems += "post-restore-analysis.json"
                }

                # Export still unmanaged apps (what the user still needs to install manually)
                if ($WhatIf) {
                    Write-Information -MessageData "WhatIf: Would export still unmanaged apps list" -InformationAction Continue
                } else {
                    $stillUnmanagedList = $stillUnmanagedApps | Sort-Object Priority, Category, Name | Select-Object Name, Publisher, Category, Priority, Version, InstallDate
                    $stillUnmanagedJson = $stillUnmanagedList | ConvertTo-Json -Depth 5
                    $machineStillUnmanagedFile = Join-Path $outputPath "still-unmanaged-apps.json"
                    $sharedStillUnmanagedFile = Join-Path $sharedOutputPath "still-unmanaged-apps.json"

                    $stillUnmanagedJson | Out-File $machineStillUnmanagedFile -Force
                    $stillUnmanagedJson | Out-File $sharedStillUnmanagedFile -Force
                    $analyzedItems += "still-unmanaged-apps.json"
                }

                # Export CSV for easy viewing in Excel
                if ($WhatIf) {
                    Write-Information -MessageData "WhatIf: Would export CSV file for Excel" -InformationAction Continue
                } else {
                    $csvPath = Join-Path $outputPath "still-unmanaged-apps.csv"
                    $sharedCsvPath = Join-Path $sharedOutputPath "still-unmanaged-apps.csv"

                    $stillUnmanagedApps | Sort-Object Priority, Category, Name |
                        Select-Object Name, Publisher, Category, Priority, Version, InstallDate |
                        Export-Csv $csvPath -NoTypeInformation -Force

                    Copy-Item $csvPath $sharedCsvPath -Force
                    $analyzedItems += "still-unmanaged-apps.csv"
                }

                # Export restored apps list
                if ($WhatIf) {
                    Write-Information -MessageData "WhatIf: Would export restored apps list" -InformationAction Continue
                } else {
                    $restoredList = $restoredApps | Sort-Object Category, Priority, OriginalName | Select-Object OriginalName, CurrentName, Publisher, Category, Priority, RestoreMethod
                    $restoredJson = $restoredList | ConvertTo-Json -Depth 5
                    $machineRestoredFile = Join-Path $outputPath "restored-apps.json"
                    $sharedRestoredFile = Join-Path $sharedOutputPath "restored-apps.json"

                    $restoredJson | Out-File $machineRestoredFile -Force
                    $restoredJson | Out-File $sharedRestoredFile -Force
                    $analyzedItems += "restored-apps.json"
                }

                # Output summary
                Write-Information -MessageData "`nPost-Restore Analysis Results:" -InformationAction Continue
                Write-Warning -Message "Original Unmanaged Apps: $($postRestoreAnalysis.Summary.OriginalUnmanagedApps)"
                Write-Information -MessageData "Successfully Restored: $($postRestoreAnalysis.Summary.RestoredApps)" -InformationAction Continue
                Write-Error -Message "Still Need Manual Install: $($postRestoreAnalysis.Summary.StillUnmanagedApps)"
                Write-Information -MessageData "Restore Success Rate: $($postRestoreAnalysis.Summary.RestoreSuccessRate)%" -InformationAction Continue

                if ($stillUnmanagedApps.Count -gt 0) {
                    Write-Verbose -Message "`nTop 10 High-Priority Apps Still Needing Manual Installation:"
                    $stillUnmanagedApps | Where-Object { $_.Priority -eq "high" } |
                        Sort-Object Name | Select-Object -First 10 | ForEach-Object {
                        Write-Information -MessageData "   -InformationAction Continue- $($_.Name) ($($_.Publisher))" -ForegroundColor White
                    }
                } else {
                    Write-Information -MessageData "`nAll originally unmanaged applications have been successfully restored!" -InformationAction Continue
                }

                # Return object for better testing and validation
                $result = [PSCustomObject]@{
                    Success = $true
                    BackupPath = $outputPath
                    SharedBackupPath = $sharedOutputPath
                    Feature = "Post-Restore Analysis"
                    Timestamp = Get-Date
                    Items = $analyzedItems
                    Errors = $errors
                    Analysis = $postRestoreAnalysis
                }

                Write-Information -MessageData "Post-restore analysis completed successfully!" -InformationAction Continue
                Write-Information -MessageData "Results saved to: $outputPath" -InformationAction Continue
                Write-Information -MessageData "Shared results saved to: $sharedOutputPath" -InformationAction Continue
                if ($stillUnmanagedApps.Count -gt 0) {
                    Write-Warning -Message "`nIMPORTANT: Review 'still-unmanaged-apps.json' and 'still-unmanaged-apps.csv' for remaining manual installations!"
                } else {
                    Write-Information -MessageData "`nCONGRATULATIONS: All applications have been successfully restored!" -InformationAction Continue
                }
                Write-Verbose "Post-restore analysis completed successfully"
                return $result
            }
            return $false
        } catch {
            $errorRecord = $_
            $errorMessage = @(
                "Failed to analyze post-restore applications"
                "Error Message: $($errorRecord.Exception.Message)"
                "Error Type: $($errorRecord.Exception.GetType().FullName)"
                "Script Line Number: $($errorRecord.InvocationInfo.ScriptLineNumber)"
                "Script Name: $($errorRecord.InvocationInfo.ScriptName)"
                "Statement: $($errorRecord.InvocationInfo.Line.Trim())"
                if ($errorRecord.Exception.StackTrace) { "Stack Trace: $($errorRecord.Exception.StackTrace)" }
                if ($errorRecord.Exception.InnerException) { "Inner Exception: $($errorRecord.Exception.InnerException.Message)" }
            ) -join "`n"

            Write-Error $errorMessage
            Write-Verbose "Post-restore analysis failed"
            throw  # Re-throw for proper error handling
        }
    }
}

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Analyze-UnmanagedApplications -BackupRootPath $BackupRootPath -MachineBackupPath $MachineBackupPath -SharedBackupPath $SharedBackupPath
}
