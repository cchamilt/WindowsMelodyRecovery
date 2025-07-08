#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Migrates all test runners to use standardized test environment

.DESCRIPTION
    Updates all test runner scripts to use the new standardized test environment
    instead of inconsistent local implementations. Provides backup and rollback.

.PARAMETER DryRun
    Show what would be changed without making actual changes.

.PARAMETER Backup
    Create backups of original files before modification.

.EXAMPLE
    .\migrate-to-standard-environment.ps1 -DryRun
    .\migrate-to-standard-environment.ps1 -Backup
#>

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Backup = $true
)

Write-Host "🔧 Migrating Test Runners to Standardized Environment" -ForegroundColor Cyan
Write-Host "   Dry Run: $DryRun | Backup: $Backup" -ForegroundColor Gray
Write-Host ""

# Define migration patterns
$MigrationPatterns = @{
    # Replace old environment import
    OldImport = @{
        Pattern = '\. \(Join-Path \$PSScriptRoot "\.\.\\utilities\\Test-Environment\.ps1"\)'
        Replacement = '. (Join-Path $PSScriptRoot "..\utilities\Test-Environment-Standard.ps1")'
    }
    
    # Replace local Initialize-TestEnvironment functions
    LocalFunction = @{
        Pattern = 'function Initialize-TestEnvironment \{[^}]*\}'
        Replacement = '# Removed local Initialize-TestEnvironment - using standardized version'
        Multiline = $true
    }
    
    # Replace function calls
    FunctionCalls = @{
        'Initialize-TestEnvironment' = 'Initialize-StandardTestEnvironment'
        'Remove-TestEnvironment' = 'Remove-StandardTestEnvironment'
        'Get-TestPaths' = 'Get-StandardTestPaths'
    }
    
    # Replace environment variable patterns
    EnvironmentVars = @{
        '$testPaths = Initialize-TestEnvironment' = '$testPaths = Initialize-StandardTestEnvironment -TestType "Integration"'
        '$testPaths = Initialize-TestEnvironment -Force' = '$testPaths = Initialize-StandardTestEnvironment -TestType "Integration" -Force'
    }
}

# Find all test runner scripts
$TestRunners = @()
$TestRunners += Get-ChildItem -Path $PSScriptRoot -Filter "run-*.ps1"
$TestRunners += Get-ChildItem -Path $PSScriptRoot -Filter "test-*.ps1"
$TestRunners += Get-ChildItem -Path $PSScriptRoot -Filter "reset-*.ps1"

Write-Host "📋 Found $($TestRunners.Count) test runner scripts to migrate:" -ForegroundColor Yellow
foreach ($runner in $TestRunners) {
    Write-Host "  • $($runner.Name)" -ForegroundColor Gray
}
Write-Host ""

# Create backup directory if needed
if ($Backup -and -not $DryRun) {
    $backupDir = Join-Path $PSScriptRoot "..\backups\environment-migration-$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss')"
    New-Item -Path $backupDir -ItemType Directory -Force | Out-Null
    Write-Host "📁 Created backup directory: $backupDir" -ForegroundColor Cyan
}

$migrationResults = @()

foreach ($runner in $TestRunners) {
    Write-Host "🔧 Processing $($runner.Name)..." -ForegroundColor Yellow
    
    $result = @{
        FileName = $runner.Name
        FilePath = $runner.FullName
        Changes = @()
        Success = $true
        Error = $null
    }
    
    try {
        $content = Get-Content -Path $runner.FullName -Raw
        $originalContent = $content
        $changesMade = $false
        
        # 1. Update import statement
        if ($content -match $MigrationPatterns.OldImport.Pattern) {
            $content = $content -replace $MigrationPatterns.OldImport.Pattern, $MigrationPatterns.OldImport.Replacement
            $result.Changes += "Updated environment import statement"
            $changesMade = $true
        }
        
        # 2. Remove local Initialize-TestEnvironment functions
        if ($content -match 'function Initialize-TestEnvironment') {
            # Find and remove the entire function block
            $lines = $content -split "`n"
            $newLines = @()
            $inFunction = $false
            $braceCount = 0
            
            for ($i = 0; $i -lt $lines.Count; $i++) {
                $line = $lines[$i]
                
                if ($line -match '^function Initialize-TestEnvironment') {
                    $inFunction = $true
                    $braceCount = 0
                    $newLines += "# Removed local Initialize-TestEnvironment function - using standardized version"
                    $result.Changes += "Removed local Initialize-TestEnvironment function"
                    $changesMade = $true
                    continue
                }
                
                if ($inFunction) {
                    $braceCount += ($line.ToCharArray() | Where-Object { $_ -eq '{' }).Count
                    $braceCount -= ($line.ToCharArray() | Where-Object { $_ -eq '}' }).Count
                    
                    if ($braceCount -le 0) {
                        $inFunction = $false
                    }
                    continue
                }
                
                $newLines += $line
            }
            
            $content = $newLines -join "`n"
        }
        
        # 3. Update function calls
        foreach ($oldFunc in $MigrationPatterns.FunctionCalls.Keys) {
            $newFunc = $MigrationPatterns.FunctionCalls[$oldFunc]
            if ($content -match $oldFunc) {
                $content = $content -replace $oldFunc, $newFunc
                $result.Changes += "Updated function call: $oldFunc -> $newFunc"
                $changesMade = $true
            }
        }
        
        # 4. Update environment variable patterns
        foreach ($oldPattern in $MigrationPatterns.EnvironmentVars.Keys) {
            $newPattern = $MigrationPatterns.EnvironmentVars[$oldPattern]
            if ($content -match [regex]::Escape($oldPattern)) {
                $content = $content -replace [regex]::Escape($oldPattern), $newPattern
                $result.Changes += "Updated environment pattern: $oldPattern"
                $changesMade = $true
            }
        }
        
        # 5. Add test type parameters based on file name
        $testType = "All"
        if ($runner.Name -like "*unit*") { $testType = "Unit" }
        elseif ($runner.Name -like "*integration*") { $testType = "Integration" }
        elseif ($runner.Name -like "*file-operation*") { $testType = "FileOperations" }
        elseif ($runner.Name -like "*end-to-end*") { $testType = "EndToEnd" }
        
        # Update Initialize-StandardTestEnvironment calls to include test type
        $initPattern = 'Initialize-StandardTestEnvironment(?!\s+-TestType)'
        if ($content -match $initPattern) {
            $content = $content -replace $initPattern, "Initialize-StandardTestEnvironment -TestType `"$testType`""
            $result.Changes += "Added TestType parameter: $testType"
            $changesMade = $true
        }
        
        # Show changes if dry run
        if ($DryRun) {
            if ($changesMade) {
                Write-Host "  📝 Would make the following changes:" -ForegroundColor Green
                foreach ($change in $result.Changes) {
                    Write-Host "    - $change" -ForegroundColor Gray
                }
            } else {
                Write-Host "  ✅ No changes needed" -ForegroundColor Green
            }
        } else {
            # Make actual changes
            if ($changesMade) {
                # Create backup if requested
                if ($Backup) {
                    $backupPath = Join-Path $backupDir $runner.Name
                    Copy-Item -Path $runner.FullName -Destination $backupPath
                }
                
                # Write updated content
                Set-Content -Path $runner.FullName -Value $content -Encoding UTF8
                
                Write-Host "  ✅ Successfully migrated with $($result.Changes.Count) changes" -ForegroundColor Green
                foreach ($change in $result.Changes) {
                    Write-Host "    - $change" -ForegroundColor Gray
                }
            } else {
                Write-Host "  ✅ No changes needed" -ForegroundColor Green
            }
        }
        
    } catch {
        $result.Success = $false
        $result.Error = $_.Exception.Message
        Write-Host "  ❌ Failed to migrate: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    $migrationResults += $result
    Write-Host ""
}

# Generate migration report
$reportPath = Join-Path $PSScriptRoot "..\test-results\reports\environment-migration-$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').json"
if (-not (Test-Path (Split-Path $reportPath -Parent))) {
    New-Item -Path (Split-Path $reportPath -Parent) -ItemType Directory -Force | Out-Null
}

$migrationReport = @{
    Timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
    DryRun = $DryRun
    Backup = $Backup
    Summary = @{
        TotalFiles = $migrationResults.Count
        SuccessfulMigrations = ($migrationResults | Where-Object { $_.Success }).Count
        FailedMigrations = ($migrationResults | Where-Object { -not $_.Success }).Count
        FilesWithChanges = ($migrationResults | Where-Object { $_.Changes.Count -gt 0 }).Count
    }
    Results = $migrationResults
}

$migrationReport | ConvertTo-Json -Depth 10 | Set-Content -Path $reportPath -Encoding UTF8

# Summary
Write-Host "📊 Migration Summary:" -ForegroundColor Cyan
Write-Host "  • Total Files: $($migrationReport.Summary.TotalFiles)" -ForegroundColor Gray
Write-Host "  • Successful: $($migrationReport.Summary.SuccessfulMigrations)" -ForegroundColor Green
Write-Host "  • Failed: $($migrationReport.Summary.FailedMigrations)" -ForegroundColor $(if ($migrationReport.Summary.FailedMigrations -eq 0) { "Green" } else { "Red" })
Write-Host "  • Files with Changes: $($migrationReport.Summary.FilesWithChanges)" -ForegroundColor Yellow
Write-Host "  • Report: $reportPath" -ForegroundColor Cyan

if ($Backup -and -not $DryRun -and $migrationReport.Summary.FilesWithChanges -gt 0) {
    Write-Host "  • Backups: $backupDir" -ForegroundColor Cyan
}

Write-Host ""

if ($DryRun) {
    Write-Host "🔍 Dry run completed - no files were modified" -ForegroundColor Yellow
    Write-Host "   Run without -DryRun to apply the changes" -ForegroundColor Gray
} else {
    if ($migrationReport.Summary.FailedMigrations -eq 0) {
        Write-Host "🎉 All test runners successfully migrated to standardized environment!" -ForegroundColor Green
    } else {
        Write-Host "⚠️  Some migrations failed - check the report for details" -ForegroundColor Yellow
    }
}

# Return migration results for programmatic use
return $migrationReport 