# fix-docker-tests.ps1
# Enhanced script to fix unit tests for Docker compatibility

[CmdletBinding()]
param(
    [string]$TestPath = "tests/unit/",
    [switch]$WhatIf
)

function Add-DockerBootstrap {
    param(
        [string]$TestFile
    )

    $content = Get-Content -Path $TestFile -Raw

    # Skip if already has Docker bootstrap
    if ($content -match "Docker-Test-Bootstrap\.ps1") {
        Write-Information -MessageData "✓ $TestFile already has Docker bootstrap" -InformationAction Continue
        return
    }

    # Find BeforeAll block or create one
    if ($content -match "BeforeAll\s*\{") {
        # Add bootstrap at the beginning of BeforeAll
        $newContent = $content -replace "(BeforeAll\s*\{)", "`$1`n    # Load Docker test bootstrap for cross-platform compatibility`n    . (Join-Path `$PSScriptRoot `"../utilities/Docker-Test-Bootstrap.ps1`")`n"
    }
    else {
        # Add BeforeAll block with bootstrap before first Describe
        $newContent = $content -replace "(Describe\s+)", "BeforeAll {`n    # Load Docker test bootstrap for cross-platform compatibility`n    . (Join-Path `$PSScriptRoot `"../utilities/Docker-Test-Bootstrap.ps1`")`n}`n`n`$1"
    }

    if ($WhatIf) {
        Write-Warning -Message "Would add Docker bootstrap to: $TestFile"
    }
    else {
        Set-Content -Path $TestFile -Value $newContent -Encoding UTF8
        Write-Information -MessageData "✓ Added Docker bootstrap to: $TestFile" -InformationAction Continue
    }
}

function Repair-PathUsage {
    param(
        [string]$TestFile
    )

    $content = Get-Content -Path $TestFile -Raw
    $changed = $false

    # Replace hardcoded C:\ paths with Get-WmrTestPath calls
    $patterns = @(
        @{ Pattern = '"C:\\([^"]+)"'; Replacement = '(Get-WmrTestPath -WindowsPath "C:\$1")' },
        @{ Pattern = "'C:\\([^']+)'"; Replacement = '(Get-WmrTestPath -WindowsPath "C:\$1")' },
        @{ Pattern = '"C:/([^"]+)"'; Replacement = '(Get-WmrTestPath -WindowsPath "C:/$1")' },
        @{ Pattern = "'C:/([^']+)'"; Replacement = '(Get-WmrTestPath -WindowsPath "C:/$1")' }
    )

    foreach ($pattern in $patterns) {
        if ($content -match $pattern.Pattern) {
            $content = $content -replace $pattern.Pattern, $pattern.Replacement
            $changed = $true
        }
    }

    if ($changed) {
        if ($WhatIf) {
            Write-Warning -Message "Would fix path usage in: $TestFile"
        }
        else {
            Set-Content -Path $TestFile -Value $content -Encoding UTF8
            Write-Information -MessageData "✓ Fixed path usage in: $TestFile" -InformationAction Continue
        }
    }
}

function Repair-ExportModuleMember {
    param(
        [string]$FilePath
    )

    $content = Get-Content -Path $FilePath -Raw

    # Check if file has Export-ModuleMember
    if ($content -match "Export-ModuleMember") {
        # Replace Export-ModuleMember with comment
        $newContent = $content -replace "Export-ModuleMember[^`n]*", "# Functions are available when dot-sourced"

        if ($WhatIf) {
            Write-Warning -Message "Would fix Export-ModuleMember in: $FilePath"
        }
        else {
            Set-Content -Path $FilePath -Value $newContent -Encoding UTF8
            Write-Information -MessageData "✓ Fixed Export-ModuleMember in: $FilePath" -InformationAction Continue
        }
    }
}

# Get all unit test files
$testFiles = Get-ChildItem -Path $TestPath -Filter "*.Tests.ps1" -Recurse

Write-Information -MessageData "🔧 Fixing $($testFiles.Count) unit test files for Docker compatibility..." -InformationAction Continue

foreach ($testFile in $testFiles) {
    Write-Information -MessageData "`n📝 Processing: $($testFile.Name)"  -InformationAction Continue-ForegroundColor White

    # Add Docker bootstrap
    Add-DockerBootstrap -TestFile $testFile.FullName

    # Fix path usage
    Repair-PathUsage -TestFile $testFile.FullName
}

# Fix Export-ModuleMember issues in source files
$sourceFiles = @(
    "Private/Core/ConditionalProcessing.ps1",
    "Private/Core/ConfigurationMerging.ps1",
    "Private/Core/TemplateResolution.ps1",
    "Private/Core/TemplateInheritance.ps1",
    "Private/Core/MachineContext.ps1"
)

Write-Information -MessageData "`n🔧 Fixing Export-ModuleMember issues in source files..." -InformationAction Continue

foreach ($sourceFile in $sourceFiles) {
    if (Test-Path $sourceFile) {
        Write-Information -MessageData "`n📝 Processing: $sourceFile"  -InformationAction Continue-ForegroundColor White
        Repair-ExportModuleMember -FilePath $sourceFile
    }
}

Write-Information -MessageData "`n✅ Docker test fixes completed!" -InformationAction Continue
Write-Information -MessageData "Next steps:" -InformationAction Continue
Write-Information -MessageData "1. Run tests: docker exec wmr -InformationAction Continue-test-runner pwsh -Command 'cd /workspace && Invoke-Pester -Path ./tests/unit/ -PassThru'" -ForegroundColor White
Write-Information -MessageData "2. Check results and fix remaining issues"  -InformationAction Continue-ForegroundColor White







