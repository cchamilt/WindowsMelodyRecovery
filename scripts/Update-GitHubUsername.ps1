#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Updates GitHub username in repository files

.DESCRIPTION
    This script replaces GitHub username references in README.md and other documentation files.
    Useful when forking the repository or changing GitHub usernames.

.PARAMETER OldUsername
    The current GitHub username to replace

.PARAMETER NewUsername
    The new GitHub username to use

.EXAMPLE
    .\scripts\Update-GitHubUsername.ps1 -OldUsername "cchamilt" -NewUsername "newusername"

.EXAMPLE
    .\scripts\Update-GitHubUsername.ps1 -OldUsername "cchamilt" -NewUsername "newusername" -WhatIf
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [string]$OldUsername,

    [Parameter(Mandatory = $true)]
    [string]$NewUsername
)

# Files to update
$FilesToUpdate = @(
    "README.md",
    ".github/README.md",
    "docs/CONTRIBUTING.md",
    "docs/INSTALLATION.md"
)

# Validate GitHub usernames
if ($OldUsername -notmatch '^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$') {
    Write-Error "Invalid old GitHub username format: $OldUsername"
    exit 1
}

if ($NewUsername -notmatch '^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$') {
    Write-Error "Invalid new GitHub username format: $NewUsername"
    exit 1
}

Write-Host "🔧 Updating GitHub username from '$OldUsername' to '$NewUsername'" -ForegroundColor Green

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

    # Replace old username with new username
    $Content = $Content -replace $OldUsername, $NewUsername

    # Count replacements in this file
    $Replacements = ($OriginalContent.Split($OldUsername).Count - 1)

    if ($Replacements -gt 0) {
        $TotalReplacements += $Replacements

        if ($WhatIfPreference) {
            Write-Host "  ✏️  Would replace $Replacements instances of '$OldUsername'" -ForegroundColor Yellow
        } else {
            $Content | Set-Content $File -NoNewline
            Write-Host "  ✅ Replaced $Replacements instances of '$OldUsername'" -ForegroundColor Green
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
        Write-Host "🔗 Your GitHub Actions badges and links should now work correctly" -ForegroundColor Blue
        Write-Host ""
        Write-Host "📋 Next steps:" -ForegroundColor Cyan
        Write-Host "  1. Commit and push your changes" -ForegroundColor Gray
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
            if ($Content -match $OldUsername) {
                Write-Warning "Still found '$OldUsername' in $File - manual review needed"
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