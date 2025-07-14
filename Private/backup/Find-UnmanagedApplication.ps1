<#
.SYNOPSIS
    Analyze and identify applications not managed by known package managers.

.DESCRIPTION
    Scans Windows installed applications and compares them against managed applications
    from package managers (Winget, Chocolatey, Scoop, Windows Store) to identify
    unmanaged applications that should be documented for backup/restore purposes.

.PARAMETER BackupRootPath
    Root path for backup operations.

.PARAMETER MachineBackupPath
    Machine-specific backup path.

.PARAMETER SharedBackupPath
    Shared backup path for common applications.

.PARAMETER Force
    Force execution even if backup paths don't exist.

.PARAMETER WhatIf
    Show what would be done without making changes.

.EXAMPLE
    .\analyze-unmanaged.ps1 -BackupRootPath "C:\Backups" -MachineBackupPath "C:\Backups\Machine1" -SharedBackupPath "C:\Backups\Shared"
#>

[CmdletBinding(SupportsShouldProcess)]
[OutputType([PSCustomObject])]
param(
    [Parameter(Mandatory = $false)]
    [string]$BackupRootPath,

    [Parameter(Mandatory = $false)]
    [string]$MachineBackupPath,

    [Parameter(Mandatory = $false)]
    [string]$SharedBackupPath,

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

function Get-WmrInstalledApplication {
    <#
    .SYNOPSIS
        Get all installed Windows applications from registry.
    #>
    [OutputType([System.Object[]])]
    param()

    $uninstallKeys = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    $systemPublishers = @("Microsoft Corporation", "Microsoft Windows", "Windows", "Microsoft")

    try {
        $apps = Get-ItemProperty $uninstallKeys -ErrorAction SilentlyContinue |
            Where-Object {
                $_.DisplayName -and
                $_.Publisher -notin $systemPublishers -and
                $_.SystemComponent -ne 1 -and
                $_.DisplayName -notmatch "Windows.*Runtime|Microsoft \.NET|Microsoft Visual C\+\+|Office.*Click-to-Run"
            } |
            Select-Object @{N = 'Name'; E = { $_.DisplayName } },
            @{N = 'Version'; E = { $_.DisplayVersion } },
            @{N = 'Publisher'; E = { $_.Publisher } }

        Write-Information "Found $($apps.Count) installed applications" -InformationAction Continue
        return $apps
    }
    catch {
        Write-Warning "Failed to scan installed applications: $_"
        return @()
    }
}

function Get-WmrManagedApplication {
    <#
    .SYNOPSIS
        Load applications managed by package managers from backup files.
    #>
    [OutputType([System.Object[]])]
    param(
        [string]$ApplicationsPath
    )

    $managedApps = @()

    if (-not (Test-Path $ApplicationsPath)) {
        Write-Warning "Applications backup path not found: $ApplicationsPath"
        return $managedApps
    }

    # Load each package manager's applications
    $packageManagers = @{
        "winget-applications.json" = "Winget"
        "chocolatey-applications.json" = "Chocolatey"
        "scoop-applications.json" = "Scoop"
        "store-applications.json" = "Store"
    }

    foreach ($file in $packageManagers.Keys) {
        $filePath = Join-Path $ApplicationsPath $file
        if (Test-Path $filePath) {
            try {
                $apps = Get-Content $filePath | ConvertFrom-Json
                $managedApps += $apps | ForEach-Object {
                    [PSCustomObject]@{
                        Name = $_.Name
                        Manager = $packageManagers[$file]
                    }
                }
                Write-Verbose "Loaded $($apps.Count) $($packageManagers[$file]) applications"
            }
            catch {
                Write-Warning "Failed to load $file`: $_"
            }
        }
    }

    Write-Information "Loaded $($managedApps.Count) managed applications" -InformationAction Continue
    return $managedApps
}

function Compare-WmrApplicationName {
    <#
    .SYNOPSIS
        Simple name comparison for matching installed vs managed apps.
    #>
    [OutputType([bool])]
    param(
        [string]$Name1,
        [string]$Name2
    )

    if (-not $Name1 -or -not $Name2) { return $false }

    # Normalize names by removing common variations
    $clean1 = $Name1 -replace '[\(\)\[\]]|64-bit|32-bit|\(x64\)|\(x86\)|®|™', '' -replace '\s+', ' '
    $clean2 = $Name2 -replace '[\(\)\[\]]|64-bit|32-bit|\(x64\)|\(x86\)|®|™', '' -replace '\s+', ' '

    # Check exact match or containment
    return ($clean1.Trim() -eq $clean2.Trim()) -or
    ($clean1.Length -gt 3 -and $clean2.Length -gt 3 -and
    ($clean1.Contains($clean2.Trim()) -or $clean2.Contains($clean1.Trim())))
}

function Find-WmrUnmanagedApplication {
    <#
    .SYNOPSIS
        Identify applications not managed by any package manager.
    #>
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$MachineBackupPath,

        [Parameter(Mandatory)]
        [string]$SharedBackupPath
    )

    Write-Information "Analyzing unmanaged applications..." -InformationAction Continue

    # Get all installed applications
    $installedApps = Get-WmrInstalledApplication

    # Load managed applications from both machine and shared paths
    $managedApps = @()
    $managedApps += Get-WmrManagedApplication -ApplicationsPath (Join-Path $MachineBackupPath "Applications")
    $managedApps += Get-WmrManagedApplication -ApplicationsPath (Join-Path $SharedBackupPath "Applications")

    # Find unmanaged applications
    $unmanagedApps = @()

    foreach ($app in $installedApps) {
        $isManaged = $false

        foreach ($managedApp in $managedApps) {
            if (Compare-WmrApplicationName -Name1 $app.Name -Name2 $managedApp.Name) {
                $isManaged = $true
                break
            }
        }

        if (-not $isManaged) {
            $unmanagedApps += $app
        }
    }

    # Create analysis results
    $results = [PSCustomObject]@{
        TotalInstalled = $installedApps.Count
        TotalManaged = $managedApps.Count
        TotalUnmanaged = $unmanagedApps.Count
        UnmanagedApplications = $unmanagedApps
        Timestamp = Get-Date
        ComputerName = $env:COMPUTERNAME
    }

    Write-Information "Analysis complete: $($results.TotalUnmanaged) unmanaged applications found" -InformationAction Continue
    return $results
}

function Save-WmrUnmanagedAnalysis {
    <#
    .SYNOPSIS
        Save unmanaged applications analysis to backup directories.
    #>
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Results,

        [Parameter(Mandatory)]
        [string]$MachineBackupPath,

        [Parameter(Mandatory)]
        [string]$SharedBackupPath
    )

    # Create backup directories
    $machineUnmanagedPath = Join-Path $MachineBackupPath "UnmanagedApps"
    $sharedUnmanagedPath = Join-Path $SharedBackupPath "UnmanagedApps"

    foreach ($path in @($machineUnmanagedPath, $sharedUnmanagedPath)) {
        if (-not (Test-Path $path)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
            Write-Verbose "Created directory: $path"
        }
    }

    # Save to machine-specific backup
    $machineFile = Join-Path $machineUnmanagedPath "unmanaged-analysis.json"
    $Results | ConvertTo-Json -Depth 3 | Set-Content -Path $machineFile -Encoding UTF8
    Write-Information "Saved analysis to: $machineFile" -InformationAction Continue

    # Save summary to shared backup
    $summary = [PSCustomObject]@{
        TotalInstalled = $Results.TotalInstalled
        TotalManaged = $Results.TotalManaged
        TotalUnmanaged = $Results.TotalUnmanaged
        Timestamp = $Results.Timestamp
        ComputerName = $Results.ComputerName
    }
    $summaryFile = Join-Path $sharedUnmanagedPath "unmanaged-summary.json"
    $summary | ConvertTo-Json -Depth 3 | Set-Content -Path $summaryFile -Encoding UTF8
    Write-Information "Saved summary to: $summaryFile" -InformationAction Continue

    # Save to a single file for easy import
    $unmanagedAppsFile = Join-Path $machineUnmanagedPath "unmanaged-apps.json"
    $Results.UnmanagedApplications | ConvertTo-Json -Depth 3 | Set-Content -Path $unmanagedAppsFile -Encoding UTF8
    Write-Information "Saved unmanaged applications list to: $unmanagedAppsFile" -InformationAction Continue
}

Export-ModuleMember -Function 'Get-WmrInstalledApplication', 'Get-WmrManagedApplication', 'Compare-WmrApplicationName', 'Find-WmrUnmanagedApplication', 'Save-WmrUnmanagedAnalysis'







