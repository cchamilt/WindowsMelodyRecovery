#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Fixes common PSScriptAnalyzer violations in Windows Melody Recovery project

.DESCRIPTION
    This script systematically fixes the most common PSScriptAnalyzer violations:
    - Write-Host usage (1,870 violations)
    - Unused parameters (195 violations)
    - Trailing whitespace (80 violations)
    - Other common issues

.PARAMETER DryRun
    Shows what would be changed without making actual changes

.PARAMETER FixWriteHost
    Fixes Write-Host violations by replacing with appropriate alternatives

.PARAMETER FixTrailingWhitespace
    Removes trailing whitespace from files

.PARAMETER FixUnusedParameters
    Adds SuppressMessageAttribute for unused parameters where appropriate

.PARAMETER Path
    Path to analyze (default: current directory)

.EXAMPLE
    .\Fix-PSScriptAnalyzerIssues.ps1 -DryRun
    .\Fix-PSScriptAnalyzerIssues.ps1 -FixWriteHost -FixTrailingWhitespace
#>

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$FixWriteHost,
    [switch]$FixTrailingWhitespace,
    [switch]$FixUnusedParameters,
    [string]$Path = "."
)

# Import PSScriptAnalyzer if not already loaded
if (-not (Get-Module -Name PSScriptAnalyzer -ListAvailable)) {
    Write-Warning "PSScriptAnalyzer not found. Installing..."
    Install-Module -Name PSScriptAnalyzer -Force -Scope CurrentUser
}

function Write-FixStatus {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Information -MessageData $Message -InformationAction Continue
}

function Fix-WriteHostUsage {
    param(
        [string]$FilePath,
        [switch]$DryRun
    )

    $content = Get-Content -Path $FilePath -Raw
    $originalContent = $content
    $changesMade = 0

    # Pattern-based replacements for Write-Host
    $replacements = @(
        # Status messages with colors
        @{
            Pattern = 'Write-Host\s+"([^"]+)"\s+-ForegroundColor\s+Green'
            Replacement = 'Write-Information -MessageData "$1" -InformationAction Continue'
            Description = "Status messages (Green)"
        },
        @{
            Pattern = 'Write-Host\s+"([^"]+)"\s+-ForegroundColor\s+Blue'
            Replacement = 'Write-Information -MessageData "$1" -InformationAction Continue'
            Description = "Status messages (Blue)"
        },
        @{
            Pattern = 'Write-Host\s+"([^"]+)"\s+-ForegroundColor\s+Yellow'
            Replacement = 'Write-Warning -Message "$1"'
            Description = "Warning messages (Yellow)"
        },
        @{
            Pattern = 'Write-Host\s+"([^"]+)"\s+-ForegroundColor\s+Red'
            Replacement = 'Write-Error -Message "$1"'
            Description = "Error messages (Red)"
        },
        @{
            Pattern = 'Write-Host\s+"([^"]+)"\s+-ForegroundColor\s+Cyan'
            Replacement = 'Write-Information -MessageData "$1" -InformationAction Continue'
            Description = "Info messages (Cyan)"
        },
        @{
            Pattern = 'Write-Host\s+"([^"]+)"\s+-ForegroundColor\s+Magenta'
            Replacement = 'Write-Verbose -Message "$1"'
            Description = "Verbose messages (Magenta)"
        },
        @{
            Pattern = 'Write-Host\s+"([^"]+)"\s+-ForegroundColor\s+Gray'
            Replacement = 'Write-Verbose -Message "$1"'
            Description = "Verbose messages (Gray)"
        },
        @{
            Pattern = 'Write-Host\s+"([^"]+)"\s+-ForegroundColor\s+DarkGray'
            Replacement = 'Write-Debug -Message "$1"'
            Description = "Debug messages (DarkGray)"
        },
        # Simple Write-Host without colors
        @{
            Pattern = 'Write-Host\s+"([^"]+)"(?!\s+-ForegroundColor)'
            Replacement = 'Write-Information -MessageData "$1" -InformationAction Continue'
            Description = "Simple messages"
        },
        # Write-Host with variables
        @{
            Pattern = 'Write-Host\s+([^-\r\n]+)(?!\s+-ForegroundColor)'
            Replacement = 'Write-Information -MessageData $1 -InformationAction Continue'
            Description = "Variable messages"
        }
    )

    foreach ($replacement in $replacements) {
        $matches = [regex]::Matches($content, $replacement.Pattern)
        if ($matches.Count -gt 0) {
            $content = $content -replace $replacement.Pattern, $replacement.Replacement
            $changesMade += $matches.Count
            Write-FixStatus "  Fixed $($matches.Count) $($replacement.Description) instances"
        }
    }

    if ($changesMade -gt 0) {
        if (-not $DryRun) {
            Set-Content -Path $FilePath -Value $content -Encoding UTF8
            Write-FixStatus "  ✅ Fixed $changesMade Write-Host issues in $FilePath" -Color Green
        } else {
            Write-FixStatus "  🔍 Would fix $changesMade Write-Host issues in $FilePath" -Color Yellow
        }
    }

    return $changesMade
}

function Fix-TrailingWhitespace {
    param(
        [string]$FilePath,
        [switch]$DryRun
    )

    $content = Get-Content -Path $FilePath
    $changedLines = 0
    $fixedContent = @()

    foreach ($line in $content) {
        $trimmedLine = $line.TrimEnd()
        if ($line -ne $trimmedLine) {
            $changedLines++
        }
        $fixedContent += $trimmedLine
    }

    if ($changedLines -gt 0) {
        if (-not $DryRun) {
            Set-Content -Path $FilePath -Value $fixedContent -Encoding UTF8
            Write-FixStatus "  ✅ Fixed $changedLines trailing whitespace issues in $FilePath" -Color Green
        } else {
            Write-FixStatus "  🔍 Would fix $changedLines trailing whitespace issues in $FilePath" -Color Yellow
        }
    }

    return $changedLines
}

function Add-SuppressMessageForUnusedParams {
    param(
        [string]$FilePath,
        [switch]$DryRun
    )

    # This is more complex and would need detailed analysis
    # For now, we'll just identify the files that need attention
    $violations = Invoke-ScriptAnalyzer -Path $FilePath -IncludeRule PSReviewUnusedParameter

    if ($violations.Count -gt 0) {
        Write-FixStatus "  📋 Found $($violations.Count) unused parameter issues in $FilePath" -Color Yellow
        foreach ($violation in $violations) {
            Write-FixStatus "    - Line $($violation.Line): $($violation.Message)" -Color Gray
        }
    }

    return $violations.Count
}

# Main execution
Write-FixStatus "🔧 Starting PSScriptAnalyzer fixes..." -Color Cyan
Write-FixStatus "Path: $Path" -Color Gray

if ($DryRun) {
    Write-FixStatus "🔍 DRY RUN MODE - No changes will be made" -Color Yellow
}

# Get all PowerShell files
$psFiles = Get-ChildItem -Path $Path -Recurse -Filter "*.ps1" | Where-Object {
    $_.Name -notlike "Fix-PSScriptAnalyzerIssues.ps1" -and
    $_.FullName -notlike "*\.git\*" -and
    $_.FullName -notlike "*\node_modules\*"
}

Write-FixStatus "Found $($psFiles.Count) PowerShell files to analyze" -Color Gray

$totalWriteHostFixes = 0
$totalWhitespaceFixes = 0
$totalUnusedParamIssues = 0

foreach ($file in $psFiles) {
    Write-FixStatus "Processing: $($file.Name)" -Color White

    if ($FixWriteHost) {
        $writeHostFixes = Fix-WriteHostUsage -FilePath $file.FullName -DryRun:$DryRun
        $totalWriteHostFixes += $writeHostFixes
    }

    if ($FixTrailingWhitespace) {
        $whitespaceFixes = Fix-TrailingWhitespace -FilePath $file.FullName -DryRun:$DryRun
        $totalWhitespaceFixes += $whitespaceFixes
    }

    if ($FixUnusedParameters) {
        $unusedParamIssues = Add-SuppressMessageForUnusedParams -FilePath $file.FullName -DryRun:$DryRun
        $totalUnusedParamIssues += $unusedParamIssues
    }
}

# Summary
Write-FixStatus "`n📊 Summary:" -Color Cyan
Write-FixStatus "Files processed: $($psFiles.Count)" -Color White
if ($FixWriteHost) {
    Write-FixStatus "Write-Host fixes: $totalWriteHostFixes" -Color Green
}
if ($FixTrailingWhitespace) {
    Write-FixStatus "Trailing whitespace fixes: $totalWhitespaceFixes" -Color Green
}
if ($FixUnusedParameters) {
    Write-FixStatus "Unused parameter issues found: $totalUnusedParamIssues" -Color Yellow
}

if ($DryRun) {
    Write-FixStatus "`n🔍 This was a dry run. Use without -DryRun to apply changes." -Color Yellow
} else {
    Write-FixStatus "`n✅ PSScriptAnalyzer fixes completed!" -Color Green
}

# Show remaining issues
Write-FixStatus "`n📋 Checking remaining violations..." -Color Cyan
$remainingIssues = Invoke-ScriptAnalyzer -Path $Path -Recurse -ReportSummary
Write-FixStatus "Remaining violations: $($remainingIssues.Count)" -Color White

$groupedIssues = $remainingIssues | Group-Object RuleName | Sort-Object Count -Descending | Select-Object -First 5
Write-FixStatus "`nTop 5 remaining issues:" -Color Gray
foreach ($issue in $groupedIssues) {
    Write-FixStatus "  $($issue.Name): $($issue.Count)" -Color Gray
}