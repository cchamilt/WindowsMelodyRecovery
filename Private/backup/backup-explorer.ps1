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

function Backup-ExplorerSettings {
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
            Write-Verbose "Starting backup of Explorer Settings..."
            Write-Host "Backing up Explorer Settings..." -ForegroundColor Blue
            
            # Validate inputs before proceeding
            if (!(Test-Path $BackupRootPath)) {
                throw [System.IO.DirectoryNotFoundException]"Backup root path not found: $BackupRootPath"
            }
            
            $backupPath = Initialize-BackupDirectory -Path "Explorer" -BackupType "Explorer Settings" -BackupRootPath $BackupRootPath
            
            if ($backupPath) {
                $backedUpItems = @()
                
                # Export Explorer view settings
                $explorerKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer"
                $advancedKey = "$explorerKey\Advanced"
                
                # Create registry backup
                $regFile = "$backupPath\explorer-settings.reg"
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export registry key $explorerKey to $regFile"
                } else {
                    reg export "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer" $regFile /y | Out-Null
                    $backedUpItems += "explorer-settings.reg"
                }

                # Export Quick Access locations
                $quickAccess = @{
                    Pinned = @()
                    Recent = @()
                }

                # Get Quick Access shell application
                $shell = New-Object -ComObject Shell.Application
                $quickAccessShell = $shell.Namespace("shell:::{679f85cb-0220-4080-b29b-5540cc05aab6}")

                # Export pinned folders
                foreach ($folder in $quickAccessShell.Items()) {
                    if ($folder.IsPinnedToNameSpaceTree) {
                        $quickAccess.Pinned += $folder.Path
                    }
                }

                # Export Quick Access settings to JSON
                $jsonFile = "$backupPath\quick-access.json"
                if ($WhatIf) {
                    Write-Host "WhatIf: Would export Quick Access settings to $jsonFile"
                } else {
                    $quickAccess | ConvertTo-Json | Out-File $jsonFile -Force
                    $backedUpItems += "quick-access.json"
                }
                
                # Return object for better testing and validation
                $result = [PSCustomObject]@{
                    Success = $true
                    BackupPath = $backupPath
                    Feature = "Explorer Settings"
                    Timestamp = Get-Date
                    Items = $backedUpItems
                    Errors = @()
                }
                
                Write-Host "Explorer Settings backed up successfully to: $backupPath" -ForegroundColor Green
                Write-Verbose "Backup completed successfully"
                return $result
            }
            return $false
        } catch {
            $errorRecord = $_
            $errorMessage = @(
                "Failed to backup Explorer Settings"
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
    Export-ModuleMember -Function Backup-ExplorerSettings
}

<#
.SYNOPSIS
Backs up Windows Explorer settings and configuration.

.DESCRIPTION
Creates a backup of Windows Explorer settings, including view preferences, Quick Access locations, and pinned folders.

.EXAMPLE
Backup-ExplorerSettings -BackupRootPath "C:\Backups"

.NOTES
Test cases to consider:
1. Valid backup path with proper permissions
2. Invalid/nonexistent backup path
3. Empty backup path
4. No permissions to write
5. Registry export success/failure
6. Quick Access export success/failure
7. Shell COM object creation success/failure

.TESTCASES
# Mock test examples:
Describe "Backup-ExplorerSettings" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Initialize-BackupDirectory { return "TestPath" }
        Mock reg { }
        Mock ConvertTo-Json { return '{"Pinned":[],"Recent":[]}' }
        Mock Out-File { }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Backup-ExplorerSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.BackupPath | Should -Be "TestPath"
        $result.Feature | Should -Be "Explorer Settings"
    }

    It "Should handle registry export failure gracefully" {
        Mock reg { throw "Registry export failed" }
        { Backup-ExplorerSettings -BackupRootPath "TestPath" } | Should -Throw
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Backup-ExplorerSettings -BackupRootPath $BackupRootPath
} 