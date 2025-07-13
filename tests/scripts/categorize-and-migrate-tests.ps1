# categorize-and-migrate-tests.ps1
# Automatically categorize and migrate tests based on analysis results

[CmdletBinding()]
param(
    [string]$AnalysisFile = "test-analysis-results.json",
    [switch]$WhatIf = $false,
    [switch]$CreateDirectories = $true
)

# Target directory structure
$TargetDirectories = @{
    'Docker' = @{
        'Unit' = 'tests/docker/unit'
        'Integration' = 'tests/docker/integration'
        'FileOperations' = 'tests/docker/file-operations'
    }
    'Windows' = @{
        'Unit' = 'tests/windows-only/unit'
        'Integration' = 'tests/windows-only/integration'
        'FileOperations' = 'tests/windows-only/file-operations'
        'EndToEnd' = 'tests/windows-only/end-to-end'
    }
    'Shared' = @{
        'Utilities' = 'tests/shared/utilities'
        'MockData' = 'tests/shared/mock-data'
        'Scripts' = 'tests/shared/scripts'
    }
}

function Initialize-DirectoryStructure {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    Write-Information -MessageData "📁 Creating target directory structure..." -InformationAction Continue

    foreach ($envType in $TargetDirectories.Keys) {
        foreach ($testType in $TargetDirectories[$envType].Keys) {
            $targetPath = $TargetDirectories[$envType][$testType]

            if (-not (Test-Path $targetPath)) {
                if ($WhatIf) {
                    Write-Warning -Message "  Would create: $targetPath"
                }
                else {
                    New-Item -Path $targetPath -ItemType Directory -Force | Out-Null
                    Write-Information -MessageData "  ✅ Created: $targetPath" -InformationAction Continue
                }
            }
            else {
                Write-Verbose -Message "  ✓ Exists: $targetPath"
            }
        }
    }
}

function Get-TestMigrationPlan {
    [CmdletBinding()]
    param([string]$AnalysisFilePath)

    if (-not (Test-Path $AnalysisFilePath)) {
        throw "Analysis file not found: $AnalysisFilePath"
    }

    $analysisData = Get-Content $AnalysisFilePath -Raw | ConvertFrom-Json

    $migrationPlan = @{
        DockerMigrations = @()
        WindowsMigrations = @()
        Summary = @{
            TotalFiles = 0
            DockerFiles = 0
            WindowsFiles = 0
        }
    }

    # Group failures by test file and target environment
    $fileGroups = @{}

    foreach ($failure in $analysisData.Analysis.FailureAnalysis) {
        $testFile = $failure.TestFile
        $targetEnv = $failure.TargetEnvironment

        if (-not $fileGroups.ContainsKey($testFile)) {
            $fileGroups[$testFile] = @{
                'Docker-Fixable' = [System.Collections.ArrayList]@()
                'Windows-Only' = [System.Collections.ArrayList]@()
            }
        }

        $fileGroups[$testFile][$targetEnv].Add($failure) | Out-Null
    }

    # Determine migration strategy for each file
    foreach ($testFile in $fileGroups.Keys) {
        $failures = $fileGroups[$testFile]
        $dockerFailures = $failures['Docker-Fixable'].Count
        $windowsFailures = $failures['Windows-Only'].Count

        $migration = @{
            SourceFile = "tests/unit/$testFile"
            TestFile = $testFile
            DockerFailures = $dockerFailures
            WindowsFailures = $windowsFailures
            Strategy = ""
            TargetPath = ""
            Action = ""
        }

        # Determine migration strategy
        if ($windowsFailures -gt 0 -and $dockerFailures -eq 0) {
            # Pure Windows-only tests
            $migration.Strategy = "Windows-Only"
            $migration.TargetPath = $TargetDirectories.Windows.Unit + "/$testFile"
            $migration.Action = "Move to Windows-only directory"
            $migrationPlan.WindowsMigrations += $migration
            $migrationPlan.Summary.WindowsFiles++
        }
        elseif ($dockerFailures -gt 0 -and $windowsFailures -eq 0) {
            # Docker-fixable tests
            $migration.Strategy = "Docker-Fixable"
            $migration.TargetPath = $TargetDirectories.Docker.Unit + "/$testFile"
            $migration.Action = "Fix for Docker compatibility and move"
            $migrationPlan.DockerMigrations += $migration
            $migrationPlan.Summary.DockerFiles++
        }
        elseif ($windowsFailures -gt $dockerFailures) {
            # Mostly Windows issues - move to Windows-only
            $migration.Strategy = "Windows-Dominant"
            $migration.TargetPath = $TargetDirectories.Windows.Unit + "/$testFile"
            $migration.Action = "Move to Windows-only (mixed issues, Windows-dominant)"
            $migrationPlan.WindowsMigrations += $migration
            $migrationPlan.Summary.WindowsFiles++
        }
        else {
            # Keep in Docker environment and fix
            $migration.Strategy = "Docker-Fixable-Mixed"
            $migration.TargetPath = $TargetDirectories.Docker.Unit + "/$testFile"
            $migration.Action = "Fix Docker issues, add Windows-only test variants"
            $migrationPlan.DockerMigrations += $migration
            $migrationPlan.Summary.DockerFiles++
        }

        $migrationPlan.Summary.TotalFiles++
    }

    return $migrationPlan
}

function Move-TestFile {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$SourcePath,
        [string]$TargetPath,
        [string]$Action
    )

    if (-not (Test-Path $SourcePath)) {
        Write-Warning "Source file not found: $SourcePath"
        return $false
    }

    # Ensure target directory exists
    $targetDir = Split-Path $TargetPath -Parent
    if (-not (Test-Path $targetDir)) {
        if ($WhatIf) {
            Write-Warning -Message "    Would create directory: $targetDir"
        }
        else {
            New-Item -Path $targetDir -ItemType Directory -Force | Out-Null
        }
    }

    if ($WhatIf) {
        Write-Warning -Message "    Would move: $SourcePath → $TargetPath"
        Write-Warning -Message "    Action: $Action"
    }
    else {
        try {
            Move-Item -Path $SourcePath -Destination $TargetPath -Force
            Write-Information -MessageData "    ✅ Moved: $SourcePath → $TargetPath" -InformationAction Continue
            Write-Information -MessageData "    Action: $Action" -InformationAction Continue
            return $true
        }
        catch {
            Write-Error "Failed to move $SourcePath to $TargetPath`: $($_.Exception.Message)"
            return $false
        }
    }
    return $true
}

function New-WindowsOnlyTestSafeguard {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $safeguardScript = @'
# Windows-Only Test Safeguards
# This script ensures Windows-only tests run safely and only in appropriate environments

BeforeAll {
    # Ensure we're on Windows
    if ($PSVersionTable.Platform -eq 'Unix') {
        Write-Warning "Skipping Windows-only tests on non-Windows platform"
        return
    }

    # Ensure we're in CI/CD or explicitly authorized environment
    $isCI = $env:CI -eq 'true' -or $env:GITHUB_ACTIONS -eq 'true' -or $env:TF_BUILD -eq 'true'
    $isAuthorized = $env:WMR_ALLOW_WINDOWS_TESTS -eq 'true'

    if (-not $isCI -and -not $isAuthorized) {
        Write-Warning "Windows-only tests should only run in CI/CD environments or with explicit authorization"
        Write-Information -MessageData "To run locally, set environment variable: `$env:WMR_ALLOW_WINDOWS_TESTS = 'true'" -InformationAction Continue
        return
    }

    # Create restore point if running destructive tests
    if ($env:WMR_CREATE_RESTORE_POINT -eq 'true') {
        try {
            $restorePoint = Checkpoint-Computer -Description "WindowsMelodyRecovery Test Restore Point" -RestorePointType "MODIFY_SETTINGS"
            Write-Information -MessageData "Created restore point: $restorePoint" -InformationAction Continue
        } catch {
            Write-Warning "Failed to create restore point: $($_.Exception.Message)"
        }
    }
}

AfterAll {
    # Cleanup operations after Windows-only tests
    if ($PSVersionTable.Platform -ne 'Unix') {
        Write-Information -MessageData "Windows-only test cleanup completed" -InformationAction Continue
    }
}
'@

    $safeguardPath = $TargetDirectories.Windows.Unit + "/WindowsTestSafeguards.ps1"

    if ($WhatIf) {
        Write-Warning -Message "Would create Windows test safeguards at: $safeguardPath"
    }
    else {
        $safeguardScript | Out-File -FilePath $safeguardPath -Encoding UTF8
        Write-Information -MessageData "✅ Created Windows test safeguards: $safeguardPath" -InformationAction Continue
    }
}

function New-DockerTestEnhancement {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $enhancementScript = @'
# Docker Test Enhancements
# Additional mocking and utilities for Docker-based testing

BeforeAll {
    # Load enhanced Docker bootstrap
    . (Join-Path $PSScriptRoot "../../shared/utilities/Docker-Test-Bootstrap.ps1")

    # Additional Docker-specific mocks for path issues
    if (Test-DockerEnvironment) {
        # Enhanced path validation mocking
        Mock Test-Path {
            param([string]$Path)
            if ($Path -like "*C:*" -and $Path -notlike "/mock-c/*") {
                $convertedPath = Get-WmrTestPath -WindowsPath $Path
                return Test-Path $convertedPath
            }
            return $true
        } -ModuleName 'WindowsMelodyRecovery'

        # Enhanced file operation mocking
        Mock Get-Content {
            param([string]$Path)
            if ($Path -like "*C:*" -and $Path -notlike "/mock-c/*") {
                $convertedPath = Get-WmrTestPath -WindowsPath $Path
                if (Test-Path $convertedPath) {
                    return Get-Content $convertedPath
                }
            }
            return @()
        } -ModuleName 'WindowsMelodyRecovery'
    }
}
'@

    $enhancementPath = $TargetDirectories.Docker.Unit + "/DockerTestEnhancements.ps1"

    if ($WhatIf) {
        Write-Warning -Message "Would create Docker test enhancements at: $enhancementPath"
    }
    else {
        $enhancementScript | Out-File -FilePath $enhancementPath -Encoding UTF8
        Write-Information -MessageData "✅ Created Docker test enhancements: $enhancementPath" -InformationAction Continue
    }
}

function Export-MigrationReport {
    [CmdletBinding()]
    param(
        [hashtable]$MigrationPlan,
        [string]$OutputPath = "test-migration-report.json"
    )

    $report = @{
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Summary = $MigrationPlan.Summary
        DockerMigrations = $MigrationPlan.DockerMigrations
        WindowsMigrations = $MigrationPlan.WindowsMigrations
        NextSteps = @(
            "Run Docker tests to validate 100% pass rate",
            "Set up Windows CI/CD environment for Windows-only tests",
            "Create GitHub Actions workflows",
            "Update documentation"
        )
    }

    $report | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputPath -Encoding UTF8
    Write-Information -MessageData "✅ Migration report exported to: $OutputPath" -InformationAction Continue
}

# Main execution
Write-Information -MessageData "🚀 Starting test categorization and migration..." -InformationAction Continue

# Initialize directory structure
if ($CreateDirectories) {
    Initialize-DirectoryStructure -WhatIf:$WhatIf
}

# Get migration plan
Write-Information -MessageData "`n📋 Analyzing test migration requirements..." -InformationAction Continue
$migrationPlan = Get-TestMigrationPlan -AnalysisFilePath $AnalysisFile

# Display migration summary
Write-Information -MessageData "`n📊 MIGRATION SUMMARY" -InformationAction Continue
Write-Information -MessageData "===================" -InformationAction Continue
Write-Information -MessageData "Total Test Files to Migrate: $($migrationPlan.Summary.TotalFiles)"  -InformationAction Continue-ForegroundColor White
Write-Information -MessageData "Docker Environment: $($migrationPlan.Summary.DockerFiles) files" -InformationAction Continue
Write-Verbose -Message "Windows CI/CD: $($migrationPlan.Summary.WindowsFiles) files"

# Execute Docker migrations
Write-Information -MessageData "`n🐳 DOCKER ENVIRONMENT MIGRATIONS" -InformationAction Continue
foreach ($migration in $migrationPlan.DockerMigrations) {
    Write-Information -MessageData "📝 $($migration.TestFile)"  -InformationAction Continue-ForegroundColor White
    Write-Information -MessageData "  Strategy: $($migration.Strategy)" -InformationAction Continue
    $success = Move-TestFile -SourcePath $migration.SourceFile -TargetPath $migration.TargetPath -Action $migration.Action -WhatIf:$WhatIf
}

# Execute Windows migrations
Write-Verbose -Message "`n🪟 WINDOWS CI/CD MIGRATIONS"
foreach ($migration in $migrationPlan.WindowsMigrations) {
    Write-Information -MessageData "📝 $($migration.TestFile)"  -InformationAction Continue-ForegroundColor White
    Write-Verbose -Message "  Strategy: $($migration.Strategy)"
    $success = Move-TestFile -SourcePath $migration.SourceFile -TargetPath $migration.TargetPath -Action $migration.Action -WhatIf:$WhatIf
}

# Create safeguards and enhancements
Write-Warning -Message "`n🛡️ Creating test environment safeguards..."
New-WindowsOnlyTestSafeguards -WhatIf:$WhatIf
New-DockerTestEnhancements -WhatIf:$WhatIf

# Export migration report
Export-MigrationReport -MigrationPlan $migrationPlan

# Display next steps
Write-Information -MessageData "`n🎯 NEXT STEPS:" -InformationAction Continue
Write-Information -MessageData "1. Fix remaining Docker -InformationAction Continue-compatible tests for 100% pass rate" -ForegroundColor White
Write-Information -MessageData "2. Validate Docker environment: docker exec wmr -InformationAction Continue-test-runner pwsh -Command 'Invoke-Pester tests/docker/unit/'" -ForegroundColor White
Write-Information -MessageData "3. Create GitHub Actions workflows for dual CI/CD"  -InformationAction Continue-ForegroundColor White
Write-Information -MessageData "4. Test Windows environment with safeguards"  -InformationAction Continue-ForegroundColor White

Write-Information -MessageData "`n✅ Test categorization and migration completed!" -InformationAction Continue

if ($WhatIf) {
    Write-Warning -Message "`n⚠️  This was a dry run. Use -WhatIf:`$false to execute the migration."
}







