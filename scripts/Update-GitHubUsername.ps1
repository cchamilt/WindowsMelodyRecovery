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

Write-Information -MessageData "🔧 Updating GitHub username from '$OldUsername' to '$NewUsername'" -InformationAction Continue

$UpdatedFiles = 0
$TotalReplacements = 0

foreach ($File in $FilesToUpdate) {
    if (-not (Test-Path $File)) {
        Write-Warning "File not found: $File"
        continue
    }

    Write-Information -MessageData "📄 Processing: $File" -InformationAction Continue

    $Content = Get-Content $File -Raw
    $OriginalContent = $Content

    # Replace old username with new username
    $Content = $Content -replace $OldUsername, $NewUsername

    # Count replacements in this file
    $Replacements = ($OriginalContent.Split($OldUsername).Count - 1)

    if ($Replacements -gt 0) {
        $TotalReplacements += $Replacements

        if ($WhatIfPreference) {
            Write-Warning -Message "  ✏️  Would replace $Replacements instances of '$OldUsername'"
        }
 else {
            $Content | Set-Content $File -NoNewline
            Write-Information -MessageData "  ✅ Replaced $Replacements instances of '$OldUsername'" -InformationAction Continue
            $UpdatedFiles++
        }
    }
 else {
        Write-Verbose -Message "  ℹ️  No replacements needed"
    }
}

# Summary
Write-Information -MessageData "" -InformationAction Continue
if ($WhatIfPreference) {
    Write-Information -MessageData "📊 Summary (WhatIf mode):" -InformationAction Continue
    Write-Warning -Message "  - Files that would be updated: $($FilesToUpdate.Count)"
    Write-Warning -Message "  - Total replacements that would be made: $TotalReplacements"
    Write-Information -MessageData "" -InformationAction Continue
    Write-Information -MessageData "💡 Run without -WhatIf to apply changes" -InformationAction Continue
}
 else {
    Write-Information -MessageData "📊 Summary:" -InformationAction Continue
    Write-Information -MessageData "  - Files updated: $UpdatedFiles" -InformationAction Continue
    Write-Information -MessageData "  - Total replacements made: $TotalReplacements" -InformationAction Continue

    if ($UpdatedFiles -gt 0) {
        Write-Information -MessageData "" -InformationAction Continue
        Write-Information -MessageData "✅ GitHub username updated successfully!" -InformationAction Continue
        Write-Information -MessageData "🔗 Your GitHub Actions badges and links should now work correctly" -InformationAction Continue
        Write-Information -MessageData "" -InformationAction Continue
        Write-Information -MessageData "📋 Next steps:" -InformationAction Continue
        Write-Verbose -Message "  1. Commit and push your changes"
        Write-Verbose -Message "  2. Check that GitHub Actions workflows are triggered"
        Write-Verbose -Message "  3. Verify that badges display correctly in README.md"
    }
}

# Validation
if (-not $WhatIfPreference -and $UpdatedFiles -gt 0) {
    Write-Information -MessageData "" -InformationAction Continue
    Write-Information -MessageData "🔍 Validating updates..." -InformationAction Continue

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
        Write-Information -MessageData "✅ All files validated successfully" -InformationAction Continue
    }
 else {
        Write-Warning "⚠️  $ValidationErrors files may need manual review"
    }
}







