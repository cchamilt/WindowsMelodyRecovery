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
            Write-Host "Created backup directory for $BackupType at: $backupPath" -ForegroundColor Green
        } catch {
            Write-Host "Failed to create backup directory for $BackupType : $_" -ForegroundColor Red
            return $null
        }
    }
    
    return $backupPath
}

function Backup-Applications {
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
            Write-Verbose "Starting backup of Package Managers..."
            Write-Host "Backing up Package Managers..." -ForegroundColor Blue
            
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
            
            $backupPath = Initialize-BackupDirectory -Path "Applications" -BackupType "Package Managers" -BackupRootPath $MachineBackupPath
            $sharedBackupPath = Initialize-BackupDirectory -Path "Applications" -BackupType "Shared Package Managers" -BackupRootPath $SharedBackupPath -IsShared
            $backedUpItems = @()
            $errors = @()
            
            if ($backupPath -and $sharedBackupPath) {
                # Initialize collections for each package manager
                $applications = @{
                    Store = @()
                    Scoop = @()
                    Chocolatey = @()
                    Winget = @()
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

                # Export each list to separate JSON files in both machine and shared paths
                $applications.GetEnumerator() | ForEach-Object {
                    $jsonContent = $_.Value | ConvertTo-Json -Depth 10
                    $machineOutputPath = Join-Path $backupPath "$($_.Key.ToLower())-applications.json"
                    $sharedOutputPath = Join-Path $sharedBackupPath "$($_.Key.ToLower())-applications.json"
                    
                    if ($WhatIf) {
                        Write-Host "WhatIf: Would export $($_.Key) applications to $machineOutputPath and $sharedOutputPath"
                    } else {
                        $jsonContent | Out-File $machineOutputPath -Force
                        $jsonContent | Out-File $sharedOutputPath -Force
                        $backedUpItems += "$($_.Key.ToLower())-applications.json"
                    }
                }

                # Output summary
                Write-Host "`nPackage Manager Summary:" -ForegroundColor Green
                Write-Host "Store Applications: $($applications.Store.Count)" -ForegroundColor Yellow
                Write-Host "Scoop Packages: $($applications.Scoop.Count)" -ForegroundColor Yellow
                Write-Host "Chocolatey Packages: $($applications.Chocolatey.Count)" -ForegroundColor Yellow
                Write-Host "Winget Packages: $($applications.Winget.Count)" -ForegroundColor Yellow
                
                # Return object for better testing and validation
                $result = [PSCustomObject]@{
                    Success = $true
                    BackupPath = $backupPath
                    SharedBackupPath = $sharedBackupPath
                    Feature = "Package Managers"
                    Timestamp = Get-Date
                    Items = $backedUpItems
                    Errors = $errors
                }
                
                Write-Host "Package Managers backed up successfully to: $backupPath" -ForegroundColor Green
                Write-Host "Shared Package Managers backed up successfully to: $sharedBackupPath" -ForegroundColor Green
                Write-Verbose "Backup completed successfully"
                return $result
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
            
            Write-Error $errorMessage
            Write-Verbose "Backup failed"
            throw  # Re-throw for proper error handling
        }
    }
}

<#
.SYNOPSIS
Backs up package manager configurations and installed packages.

.DESCRIPTION
Creates a backup of package manager configurations and installed packages including:
- Windows Store apps
- Scoop packages and buckets
- Chocolatey packages and sources
- Winget packages and sources
- Package lists exported as JSON files for each manager
- Both machine-specific and shared settings

Note: Game managers are handled by backup-gamemanagers.ps1
Note: Unmanaged applications analysis is handled by analyze-unmanaged.ps1

.EXAMPLE
Backup-Applications -BackupRootPath "C:\Backups" -MachineBackupPath "C:\Backups\Machine" -SharedBackupPath "C:\Backups\Shared"

.NOTES
Test cases to consider:
1. Valid backup paths with proper permissions
2. Invalid/nonexistent backup paths
3. Empty backup paths
4. No permissions to write
5. Package managers installed/not installed
6. Package manager command availability
7. Package export success/failure
8. JSON export success/failure

.TESTCASES
# Mock test examples:
Describe "Backup-Applications" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Initialize-BackupDirectory { return "TestPath" }
        Mock Get-AppxPackage { return @() }
        Mock Get-Command { return $true }
        Mock Invoke-Expression { return "Test Output" }
        Mock ConvertTo-Json { return "{}" }
        Mock Out-File { }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Backup-Applications -BackupRootPath "TestPath" -MachineBackupPath "TestPath\Machine" -SharedBackupPath "TestPath\Shared"
        $result.Success | Should -Be $true
        $result.BackupPath | Should -Be "TestPath"
        $result.SharedBackupPath | Should -Be "TestPath\Shared"
        $result.Feature | Should -Be "Package Managers"
    }

    It "Should handle missing package managers gracefully" {
        Mock Get-Command { return $false }
        $result = Backup-Applications -BackupRootPath "TestPath" -MachineBackupPath "TestPath\Machine" -SharedBackupPath "TestPath\Shared"
        $result.Success | Should -Be $true
    }

    It "Should export package manager lists" {
        Mock Get-AppxPackage { return @([PSCustomObject]@{Name="TestApp";Version="1.0"}) }
        $result = Backup-Applications -BackupRootPath "TestPath" -MachineBackupPath "TestPath\Machine" -SharedBackupPath "TestPath\Shared"
        $result.Items | Should -Contain "store-applications.json"
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Backup-Applications -BackupRootPath $BackupRootPath -MachineBackupPath $MachineBackupPath -SharedBackupPath $SharedBackupPath
} 