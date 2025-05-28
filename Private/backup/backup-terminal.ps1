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

function Backup-TerminalSettings {
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
            Write-Verbose "Starting backup of Terminal Settings..."
            Write-Host "Backing up Terminal Settings..." -ForegroundColor Blue
            
            # Validate inputs before proceeding
            if (!(Test-Path $BackupRootPath)) {
                throw [System.IO.DirectoryNotFoundException]"Backup root path not found: $BackupRootPath"
            }
            
            $backupPath = Initialize-BackupDirectory -Path "Terminal" -BackupType "Terminal Settings" -BackupRootPath $BackupRootPath
            
            if ($backupPath) {
                $backedUpItems = @()
                
                # Windows Terminal settings
                $terminalSettingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
                if (Test-Path $terminalSettingsPath) {
                    $destinationPath = "$backupPath\terminal-settings.json"
                    if ($WhatIf) {
                        Write-Host "WhatIf: Would copy $terminalSettingsPath to $destinationPath"
                    } else {
                        Copy-Item -Path $terminalSettingsPath -Destination $destinationPath -Force
                        $backedUpItems += "terminal-settings.json"
                    }
                }

                # Windows Terminal Preview settings
                $previewSettingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json"
                if (Test-Path $previewSettingsPath) {
                    $destinationPath = "$backupPath\terminal-preview-settings.json"
                    if ($WhatIf) {
                        Write-Host "WhatIf: Would copy $previewSettingsPath to $destinationPath"
                    } else {
                        Copy-Item -Path $previewSettingsPath -Destination $destinationPath -Force
                        $backedUpItems += "terminal-preview-settings.json"
                    }
                }
                
                # Return object for better testing and validation
                $result = [PSCustomObject]@{
                    Success = $true
                    BackupPath = $backupPath
                    Feature = "Terminal Settings"
                    Timestamp = Get-Date
                    Items = $backedUpItems
                    Errors = @()
                }
                
                Write-Host "Terminal Settings backed up successfully to: $backupPath" -ForegroundColor Green
                Write-Verbose "Backup completed successfully"
                return $result
            }
            return $false
        } catch {
            $errorRecord = $_
            $errorMessage = @(
                "Failed to backup Terminal Settings"
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
    Export-ModuleMember -Function Backup-TerminalSettings
}

<#
.SYNOPSIS
Backs up Windows Terminal settings and configuration.

.DESCRIPTION
Creates a backup of Windows Terminal and Windows Terminal Preview settings, including themes, profiles, and keybindings.

.EXAMPLE
Backup-TerminalSettings -BackupRootPath "C:\Backups"

.NOTES
Test cases to consider:
1. Valid backup path with proper permissions
2. Invalid/nonexistent backup path
3. Empty backup path
4. No permissions to write
5. Terminal settings file exists/doesn't exist
6. Preview settings file exists/doesn't exist

.TESTCASES
# Mock test examples:
Describe "Backup-TerminalSettings" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Initialize-BackupDirectory { return "TestPath" }
        Mock Copy-Item { }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Backup-TerminalSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.BackupPath | Should -Be "TestPath"
        $result.Feature | Should -Be "Terminal Settings"
    }

    It "Should handle missing settings files gracefully" {
        Mock Test-Path { return $false }
        $result = Backup-TerminalSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.Items.Count | Should -Be 0
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Backup-TerminalSettings -BackupRootPath $BackupRootPath
} 