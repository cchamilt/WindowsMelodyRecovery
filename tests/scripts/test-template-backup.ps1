#!/usr/bin/env pwsh
<#
.SYNOPSIS
Test wrapper for backing up templates to test directories.

.DESCRIPTION
This script provides a test environment for template-based backups without cluttering
the development environment. It redirects backup operations to the test-backups directory.
Backup operations are inherently safe as they only read system state without making changes.

.PARAMETER TemplatePath
Path to the template file to test, or "ALL" to test all templates.

.EXAMPLE
.\test-template-backup.ps1 -TemplatePath "word.yaml"

.EXAMPLE
.\test-template-backup.ps1 -TemplatePath "ALL"

.NOTES
This uses the test-backups directory for safe testing.
Backup operations are read-only and safe by design.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$TemplatePath
)

# Ensure we're in the project root
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Push-Location $scriptRoot

# Define consistent test directory structure
$testDirectories = @{
    BackupsRoot = Join-Path $scriptRoot "test-backups"
}

$testPaths = @{
    MachineBackup = Join-Path $testDirectories.BackupsRoot "TEST-MACHINE"
}

function Initialize-TestDirectories {
    if (-not (Test-Path $testDirectories.BackupsRoot)) {
        New-Item -ItemType Directory -Path $testDirectories.BackupsRoot -Force | Out-Null
    }

    if (-not (Test-Path $testPaths.MachineBackup)) {
        New-Item -ItemType Directory -Path $testPaths.MachineBackup -Force | Out-Null
    }
}

function Get-TestConfig {
    return @{
        BackupRoot = $testDirectories.BackupsRoot
        MachineName = "TEST-MACHINE"
    }
}

function Show-DirectoryContents {
    param(
        [string]$Path,
        [string]$BasePathForDisplay
    )

    if (Test-Path $Path) {
        Get-ChildItem $Path -Recurse | ForEach-Object {
            $relativePath = $_.FullName.Replace($BasePathForDisplay, "").TrimStart('\', '/')
            if ($_.PSIsContainer) {
                Write-Information -MessageData "📁 $relativePath" -InformationAction Continue
            } else {
                $size = if ($_.Length -lt 1KB) { "$($_.Length) B" } elseif ($_.Length -lt 1MB) { "{0:N1} KB" -f ($_.Length / 1KB) } else { "{0:N1} MB" -f ($_.Length / 1MB) }
                Write-Verbose -Message "📄 $relativePath ($size)"
            }
        }
    }
}

try {
    # Initialize test directories
    Initialize-TestDirectories

    # Import the module
    Import-Module .\WindowsMelodyRecovery.psm1 -Force -WarningAction SilentlyContinue

    # Get current config and set test config
    $originalConfig = Get-WindowsMelodyRecovery
    $testConfig = Get-TestConfig
    $global:WindowsMelodyRecovery = [PSCustomObject]$testConfig

    Write-Information -MessageData "=== TEMPLATE BACKUP TEST ===" -InformationAction Continue
    Write-Warning -Message "Template: $TemplatePath"
    Write-Warning -Message "Test Backup Directory: $($testDirectories.BackupsRoot)"
    Write-Information -MessageData "" -InformationAction Continue

    if ($TemplatePath -eq "ALL") {
        # Test all templates
        Write-Information -MessageData "Testing all available templates..." -InformationAction Continue
        $templatesPath = Join-Path $scriptRoot "Templates\System"
        $templateFiles = Get-ChildItem -Path $templatesPath -Filter "*.yaml" -ErrorAction SilentlyContinue

        $successCount = 0
        $failCount = 0

        foreach ($templateFile in $templateFiles) {
            Write-Information -MessageData "`n--- Testing: $($templateFile.Name) ---" -InformationAction Continue
            try {
                . (Join-Path $scriptRoot "Private\Core\InvokeWmrTemplate.ps1")

                # Pass the machine backup directory directly - templates handle their own subdirectories
                Invoke-WmrTemplate -TemplatePath $templateFile.FullName -Operation "Backup" -StateFilesDirectory $testPaths.MachineBackup
                Write-Information -MessageData "✓ $($templateFile.Name) backup completed successfully" -InformationAction Continue
                $successCount++
            } catch {
                Write-Error -Message "✗ $($templateFile.Name) backup failed: $($_.Exception.Message)"
                $failCount++
            }
        }

        Write-Information -MessageData "`n=== BACKUP SUMMARY ===" -InformationAction Continue
        Write-Information -MessageData "Successful: $successCount" -InformationAction Continue
        Write-Error -Message "Failed: $failCount"
        Write-Warning -Message "Total: $($successCount + $failCount)"

    } else {
        # Test single template
        $templateFullPath = if (Test-Path $TemplatePath) {
            $TemplatePath
        } else {
            Join-Path $scriptRoot "Templates\System\$TemplatePath"
        }

        if (-not (Test-Path $templateFullPath)) {
            throw "Template file not found: $templateFullPath"
        }

        . (Join-Path $scriptRoot "Private\Core\InvokeWmrTemplate.ps1")

        $templateName = (Get-Item $templateFullPath).BaseName

        # Pass the machine backup directory directly - templates handle their own subdirectories
        Invoke-WmrTemplate -TemplatePath $templateFullPath -Operation "Backup" -StateFilesDirectory $testPaths.MachineBackup
        Write-Information -MessageData "✓ Template backup completed successfully" -InformationAction Continue

        # Show what was backed up
        Write-Information -MessageData "`n=== BACKUP CONTENTS ===" -InformationAction Continue
        $componentBackupDir = Join-Path $testPaths.MachineBackup $templateName
        Show-DirectoryContents -Path $componentBackupDir -BasePathForDisplay $componentBackupDir
    }

    Write-Information -MessageData "`nTest backup completed! Use test-template-restore.ps1 to test restore operations." -InformationAction Continue

} catch {
    Write-Error -Message "Test backup failed: $($_.Exception.Message)"
    Write-Information -MessageData $_.ScriptStackTrace  -InformationAction Continue-ForegroundColor DarkRed
    exit 1
} finally {
    # Restore original config
    if ($originalConfig) {
        $global:WindowsMelodyRecovery = $originalConfig
    }
    Pop-Location
}






