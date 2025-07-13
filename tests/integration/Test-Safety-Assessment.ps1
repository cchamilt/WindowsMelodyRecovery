# Windows Melody Recovery - Integration Test Safety Assessment
# Identifies dangerous operations and marks tests for CI-only execution

<#
.SYNOPSIS
    Assesses integration tests for safety and identifies CI-only operations

.DESCRIPTION
    Scans integration tests to identify operations that require admin privileges,
    modify system state, or could be dangerous on development machines.
    Creates safety tags and CI-only execution markers.

.PARAMETER TestDirectory
    Directory containing integration tests to assess

.PARAMETER OutputReport
    Generate detailed safety report

.EXAMPLE
    .\Test-Safety-Assessment.ps1 -OutputReport
#>

[CmdletBinding()]
param(
    [string]$TestDirectory = "$PSScriptRoot",
    [switch]$OutputReport
)

# Define dangerous operation patterns
$DangerousPatterns = @{
    'SystemModification' = @(
        'HKEY_LOCAL_MACHINE',
        'HKLM:',
        'Set-Service',
        'Stop-Service',
        'Start-Service',
        'Install-WindowsFeature',
        'Enable-WindowsOptionalFeature',
        'Disable-WindowsOptionalFeature',
        'Set-ExecutionPolicy.*RemoteSigned',
        'Set-ExecutionPolicy.*Unrestricted',
        'New-ScheduledTask.*System',
        'Register-ScheduledTask.*System'
    )
    'AdminRequired' = @(
        'RequireAdministrator',
        'Test-WmrAdminPrivilege.*-ThrowIfNotAdmin',
        'RunAs.*Administrator',
        'UAC',
        'Elevate'
    )
    'FileSystemDangerous' = @(
        'C:\\Windows\\',
        'C:\\Program Files\\',
        'C:\\Program Files \(x86\)\\',
        'Remove-Item.*-Path.*C:\\',
        'System32',
        'SysWOW64'
    )
    'NetworkDangerous' = @(
        'Invoke-WebRequest.*-UseBasicParsing.*http:',
        'Download.*-Uri.*http:',
        'Set-NetFirewallRule',
        'New-NetFirewallRule',
        'netsh'
    )
    'RegistryDangerous' = @(
        'Remove-Item.*HKLM:',
        'Remove-ItemProperty.*HKLM:',
        'Set-ItemProperty.*HKLM:',
        'New-Item.*HKLM:'
    )
}

# Define safe operation patterns (allowed in dev)
$SafePatterns = @(
    'HKEY_CURRENT_USER',
    'HKCU:',
    'TestDrive',
    'test-backup',
    'test-restore',
    'Mock.*-Path',
    'Mock.*Get-',
    'Mock.*Set-',
    'Mock.*New-',
    'Mock.*Remove-'
)

function Test-OperationSafety {
    param(
        [string]$Content,
        [string]$FilePath
    )

    $safetyReport = @{
        IsSafe = $true
        Violations = @()
        Warnings = @()
        RequiresCIOnly = $false
        SafeForDev = $true
    }

    # Check for dangerous patterns
    foreach ($category in $DangerousPatterns.Keys) {
        foreach ($pattern in $DangerousPatterns[$category]) {
            if ($Content -match $pattern) {
                $violation = @{
                    Category = $category
                    Pattern = $pattern
                    Line = ($Content -split "`n" | Select-String $pattern | Select-Object -First 1).LineNumber
                    Severity = switch ($category) {
                        'SystemModification' { 'Critical' }
                        'AdminRequired' { 'High' }
                        'FileSystemDangerous' { 'High' }
                        'NetworkDangerous' { 'Medium' }
                        'RegistryDangerous' { 'High' }
                        default { 'Medium' }
                    }
                }
                $safetyReport.Violations += $violation

                if ($violation.Severity -in @('Critical', 'High')) {
                    $safetyReport.IsSafe = $false
                    $safetyReport.RequiresCIOnly = $true
                    $safetyReport.SafeForDev = $false
                }
            }
        }
    }

    # Check for mitigating safe patterns
    $hasSafeMitigations = $false
    foreach ($safePattern in $SafePatterns) {
        if ($Content -match $safePattern) {
            $hasSafeMitigations = $true
            break
        }
    }

    # If violations but has safe mitigations, downgrade severity
    if ($safetyReport.Violations.Count -gt 0 -and $hasSafeMitigations) {
        $safetyReport.Warnings += "File has potential violations but uses safe patterns (mocking, test directories)"
        $safetyReport.IsSafe = $true
        $safetyReport.SafeForDev = $true
        $safetyReport.RequiresCIOnly = $false
    }

    return $safetyReport
}

function Add-SafetyTag {
    param(
        [string]$FilePath,
        [object]$SafetyReport
    )

    $content = Get-Content $FilePath -Raw
    $needsUpdate = $false

    # Add CI-only tag if needed
    if ($SafetyReport.RequiresCIOnly -and $content -notmatch 'Tag.*"CI-Only"') {
        $content = $content -replace '(Describe\s+"[^"]+"\s+)-Tag\s+"[^"]*"', '$1-Tag "Integration", "CI-Only"'
        if ($content -notmatch 'Tag.*"CI-Only"') {
            $content = $content -replace '(Describe\s+"[^"]+")(\s+{)', '$1 -Tag "Integration", "CI-Only"$2'
        }
        $needsUpdate = $true
        Write-Warning "Added CI-Only tag to $FilePath"
    }

    # Add safety comments
    if ($SafetyReport.Violations.Count -gt 0) {
        $safetyComment = @"
<#
SAFETY ASSESSMENT: $(if ($SafetyReport.RequiresCIOnly) { "CI-ONLY EXECUTION REQUIRED" } else { "SAFE FOR DEVELOPMENT" })
Generated by Test-Safety-Assessment.ps1

$(if ($SafetyReport.Violations) {
"VIOLATIONS FOUND:
" + ($SafetyReport.Violations | ForEach-Object { "- $($_.Category): $($_.Pattern) (Severity: $($_.Severity))" }) -join "`n"
})

$(if ($SafetyReport.Warnings) {
"WARNINGS:
" + ($SafetyReport.Warnings -join "`n")
})

$(if ($SafetyReport.RequiresCIOnly) {
"This test should only run in CI/CD environments with proper isolation.
Use -Tag 'CI-Only' to restrict execution."
})
#>

"@

        if ($content -notmatch 'SAFETY ASSESSMENT:') {
            $content = $safetyComment + $content
            $needsUpdate = $true
        }
    }

    if ($needsUpdate) {
        Set-Content -Path $FilePath -Value $content -Encoding UTF8
        Write-Warning -Message "Updated safety tags for $FilePath"
    }
}

# Main assessment process
Write-Information -MessageData "🔒 Windows Melody Recovery - Integration Test Safety Assessment" -InformationAction Continue
Write-Information -MessageData "" -InformationAction Continue

$testFiles = Get-ChildItem -Path $TestDirectory -Filter "*.Tests.ps1" | Where-Object { $_.Name -notlike "*Safety*" }
$assessmentResults = @()

Write-Warning -Message "📋 Assessing $($testFiles.Count) integration test files..."
Write-Information -MessageData "" -InformationAction Continue

foreach ($testFile in $testFiles) {
    Write-Verbose -Message "🔍 Analyzing $($testFile.Name)..."

    $content = Get-Content $testFile.FullName -Raw
    $safetyReport = Test-OperationSafety -Content $content -FilePath $testFile.FullName
    $safetyReport.FileName = $testFile.Name
    $safetyReport.FilePath = $testFile.FullName

    $assessmentResults += $safetyReport

    # Status indicator
    $status = if ($safetyReport.RequiresCIOnly) { "❌ CI-ONLY" }
    elseif ($safetyReport.Violations.Count -gt 0) { "⚠️  WARNINGS" }
    else { "✅ SAFE" }

    Write-Information -MessageData "  $status $($testFile.Name)"  -InformationAction Continue-ForegroundColor $(
        if ($safetyReport.RequiresCIOnly) { "Red" }
        elseif ($safetyReport.Violations.Count -gt 0) { "Yellow" }
        else { "Green" }
    )

    # Add safety tags if violations found
    if ($safetyReport.Violations.Count -gt 0) {
        Add-SafetyTags -FilePath $testFile.FullName -SafetyReport $safetyReport
    }
}

# Generate summary
Write-Information -MessageData "" -InformationAction Continue
Write-Information -MessageData "📊 Safety Assessment Summary:" -InformationAction Continue

$safeTests = $assessmentResults | Where-Object { $_.IsSafe -and $_.Violations.Count -eq 0 }
$warningTests = $assessmentResults | Where-Object { $_.IsSafe -and $_.Violations.Count -gt 0 }
$ciOnlyTests = $assessmentResults | Where-Object { $_.RequiresCIOnly }

Write-Information -MessageData "  • Safe for Development: $($safeTests.Count)" -InformationAction Continue
Write-Warning -Message "  • Warnings (Safe with Mitigations): $($warningTests.Count)"
Write-Error -Message "  • CI-Only Required: $($ciOnlyTests.Count)"
Write-Verbose -Message "  • Total Tests Assessed: $($assessmentResults.Count)"

if ($ciOnlyTests.Count -gt 0) {
    Write-Information -MessageData "" -InformationAction Continue
    Write-Error -Message "🚨 CI-Only Tests:"
    foreach ($test in $ciOnlyTests) {
        Write-Error -Message "  • $($test.FileName)"
        foreach ($violation in $test.Violations) {
            Write-Verbose -Message "    - $($violation.Category): $($violation.Pattern)"
        }
    }
}

if ($warningTests.Count -gt 0) {
    Write-Information -MessageData "" -InformationAction Continue
    Write-Warning -Message "⚠️  Tests with Warnings:"
    foreach ($test in $warningTests) {
        Write-Warning -Message "  • $($test.FileName)"
        foreach ($warning in $test.Warnings) {
            Write-Verbose -Message "    - $warning"
        }
    }
}

# Output detailed report if requested
if ($OutputReport) {
    # Use the project root test-results directory
    $projectRoot = Split-Path (Split-Path $TestDirectory -Parent) -Parent
    $reportsDir = Join-Path $projectRoot "test-results\reports"
    if (-not (Test-Path $reportsDir)) {
        New-Item -Path $reportsDir -ItemType Directory -Force | Out-Null
    }

    $reportPath = Join-Path $reportsDir "Safety-Assessment-Report.json"
    $assessmentResults | ConvertTo-Json -Depth 10 | Set-Content -Path $reportPath -Encoding UTF8
    Write-Information -MessageData "" -InformationAction Continue
    Write-Information -MessageData "📄 Detailed report saved to: $reportPath" -InformationAction Continue
}

Write-Information -MessageData "" -InformationAction Continue
if ($ciOnlyTests.Count -eq 0) {
    Write-Information -MessageData "🎉 All integration tests are safe for development execution!" -InformationAction Continue
}
else {
    Write-Warning -Message "⚠️  $($ciOnlyTests.Count) test(s) require CI-only execution for safety."
}

# Return assessment results for programmatic use
return @{
    TotalTests = $assessmentResults.Count
    SafeTests = $safeTests.Count
    WarningTests = $warningTests.Count
    CIOnlyTests = $ciOnlyTests.Count
    Results = $assessmentResults
}







