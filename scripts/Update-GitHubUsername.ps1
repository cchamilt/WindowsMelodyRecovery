#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Updates GitHub username placeholders in README and other files

.DESCRIPTION
    This script replaces all instances of "YOUR_USERNAME" with the actual GitHub username
    in README.md and other documentation files.

.PARAMETER GitHubUsername
    The actual GitHub username to replace "YOUR_USERNAME" with

.PARAMETER WhatIf
    Shows what changes would be made without actually making them

.EXAMPLE
    .\scripts\Update-GitHubUsername.ps1 -GitHubUsername "myusername"
    
.EXAMPLE
    .\scripts\Update-GitHubUsername.ps1 -GitHubUsername "myusername" -WhatIf
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [string]$GitHubUsername
)

# Files to update
$FilesToUpdate = @(
    "README.md",
    ".github/README.md",
    "docs/CONTRIBUTING.md",
    "docs/INSTALLATION.md"
)

# Validate GitHub username
if ($GitHubUsername -notmatch '^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$') {
    Write-Error "Invalid GitHub username format: $GitHubUsername"
    exit 1
}

Write-Host "🔧 Updating GitHub username from 'YOUR_USERNAME' to '$GitHubUsername'" -ForegroundColor Green

$UpdatedFiles = 0
$TotalReplacements = 0

foreach ($File in $FilesToUpdate) {
    if (-not (Test-Path $File)) {
        Write-Warning "File not found: $File"
        continue
    }
    
    Write-Host "📄 Processing: $File" -ForegroundColor Cyan
    
    $Content = Get-Content $File -Raw
    $OriginalContent = $Content
    
    # Replace YOUR_USERNAME with actual username
    $Content = $Content -replace 'YOUR_USERNAME', $GitHubUsername
    
    # Count replacements in this file
    $Replacements = ($OriginalContent.Split('YOUR_USERNAME').Count - 1)
    
    if ($Replacements -gt 0) {
        $TotalReplacements += $Replacements
        
        if ($WhatIfPreference) {
            Write-Host "  ✏️  Would replace $Replacements instances of 'YOUR_USERNAME'" -ForegroundColor Yellow
        } else {
            $Content | Set-Content $File -NoNewline
            Write-Host "  ✅ Replaced $Replacements instances of 'YOUR_USERNAME'" -ForegroundColor Green
            $UpdatedFiles++
        }
    } else {
        Write-Host "  ℹ️  No replacements needed" -ForegroundColor Gray
    }
}

# Summary
Write-Host ""
if ($WhatIfPreference) {
    Write-Host "📊 Summary (WhatIf mode):" -ForegroundColor Cyan
    Write-Host "  - Files that would be updated: $($FilesToUpdate.Count)" -ForegroundColor Yellow
    Write-Host "  - Total replacements that would be made: $TotalReplacements" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "💡 Run without -WhatIf to apply changes" -ForegroundColor Blue
} else {
    Write-Host "📊 Summary:" -ForegroundColor Cyan
    Write-Host "  - Files updated: $UpdatedFiles" -ForegroundColor Green
    Write-Host "  - Total replacements made: $TotalReplacements" -ForegroundColor Green
    
    if ($UpdatedFiles -gt 0) {
        Write-Host ""
        Write-Host "✅ GitHub username updated successfully!" -ForegroundColor Green
        Write-Host "🔗 Your GitHub Actions badges should now work correctly" -ForegroundColor Blue
        Write-Host ""
        Write-Host "📋 Next steps:" -ForegroundColor Cyan
        Write-Host "  1. Commit and push your changes to the testing branch" -ForegroundColor Gray
        Write-Host "  2. Check that GitHub Actions workflows are triggered" -ForegroundColor Gray
        Write-Host "  3. Verify that badges display correctly in README.md" -ForegroundColor Gray
    }
}

# Validation
if (-not $WhatIfPreference -and $UpdatedFiles -gt 0) {
    Write-Host ""
    Write-Host "🔍 Validating updates..." -ForegroundColor Cyan
    
    $ValidationErrors = 0
    
    foreach ($File in $FilesToUpdate) {
        if (Test-Path $File) {
            $Content = Get-Content $File -Raw
            if ($Content -match 'YOUR_USERNAME') {
                Write-Warning "Still found 'YOUR_USERNAME' in $File - manual review needed"
                $ValidationErrors++
            }
        }
    }
    
    if ($ValidationErrors -eq 0) {
        Write-Host "✅ All files validated successfully" -ForegroundColor Green
    } else {
        Write-Warning "⚠️  $ValidationErrors files may need manual review"
    }
} 