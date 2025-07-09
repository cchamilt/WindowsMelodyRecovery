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
        Write-Host "✓ $TestFile already has Docker bootstrap" -ForegroundColor Green
        return
    }
    
    # Find BeforeAll block or create one
    if ($content -match "BeforeAll\s*\{") {
        # Add bootstrap at the beginning of BeforeAll
        $newContent = $content -replace "(BeforeAll\s*\{)", "`$1`n    # Load Docker test bootstrap for cross-platform compatibility`n    . (Join-Path `$PSScriptRoot `"../utilities/Docker-Test-Bootstrap.ps1`")`n"
    } else {
        # Add BeforeAll block with bootstrap before first Describe
        $newContent = $content -replace "(Describe\s+)", "BeforeAll {`n    # Load Docker test bootstrap for cross-platform compatibility`n    . (Join-Path `$PSScriptRoot `"../utilities/Docker-Test-Bootstrap.ps1`")`n}`n`n`$1"
    }
    
    if ($WhatIf) {
        Write-Host "Would add Docker bootstrap to: $TestFile" -ForegroundColor Yellow
    } else {
        Set-Content -Path $TestFile -Value $newContent -Encoding UTF8
        Write-Host "✓ Added Docker bootstrap to: $TestFile" -ForegroundColor Green
    }
}

function Fix-PathUsage {
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
            Write-Host "Would fix path usage in: $TestFile" -ForegroundColor Yellow
        } else {
            Set-Content -Path $TestFile -Value $content -Encoding UTF8
            Write-Host "✓ Fixed path usage in: $TestFile" -ForegroundColor Green
        }
    }
}

function Fix-ExportModuleMember {
    param(
        [string]$FilePath
    )
    
    $content = Get-Content -Path $FilePath -Raw
    
    # Check if file has Export-ModuleMember
    if ($content -match "Export-ModuleMember") {
        # Replace Export-ModuleMember with comment
        $newContent = $content -replace "Export-ModuleMember[^`n]*", "# Functions are available when dot-sourced"
        
        if ($WhatIf) {
            Write-Host "Would fix Export-ModuleMember in: $FilePath" -ForegroundColor Yellow
        } else {
            Set-Content -Path $FilePath -Value $newContent -Encoding UTF8
            Write-Host "✓ Fixed Export-ModuleMember in: $FilePath" -ForegroundColor Green
        }
    }
}

# Get all unit test files
$testFiles = Get-ChildItem -Path $TestPath -Filter "*.Tests.ps1" -Recurse

Write-Host "🔧 Fixing $($testFiles.Count) unit test files for Docker compatibility..." -ForegroundColor Cyan

foreach ($testFile in $testFiles) {
    Write-Host "`n📝 Processing: $($testFile.Name)" -ForegroundColor White
    
    # Add Docker bootstrap
    Add-DockerBootstrap -TestFile $testFile.FullName
    
    # Fix path usage
    Fix-PathUsage -TestFile $testFile.FullName
}

# Fix Export-ModuleMember issues in source files
$sourceFiles = @(
    "Private/Core/ConfigurationValidation.ps1",
    "Private/Core/Prerequisites.ps1",
    "Private/Core/PathUtilities.ps1"
)

Write-Host "`n🔧 Fixing Export-ModuleMember issues in source files..." -ForegroundColor Cyan

foreach ($sourceFile in $sourceFiles) {
    if (Test-Path $sourceFile) {
        Write-Host "`n📝 Processing: $sourceFile" -ForegroundColor White
        Fix-ExportModuleMember -FilePath $sourceFile
    }
}

Write-Host "`n✅ Docker test fixes completed!" -ForegroundColor Green
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "1. Run tests: docker exec wmr-test-runner pwsh -Command 'cd /workspace && Invoke-Pester -Path ./tests/unit/ -PassThru'" -ForegroundColor White
Write-Host "2. Check results and fix remaining issues" -ForegroundColor White 