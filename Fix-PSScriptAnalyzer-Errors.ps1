#!/usr/bin/env pwsh

<#
.SYNOPSIS
Fixes PSScriptAnalyzer ERROR violations for ConvertTo-SecureString with plaintext.

.DESCRIPTION
This script automatically adds PSScriptAnalyzer suppression comments to fix
PSAvoidUsingConvertToSecureStringWithPlainText error violations.

.PARAMETER WhatIf
Shows what would be changed without making actual changes.
#>

param(
    [switch]$WhatIf
)

# Get all PSScriptAnalyzer errors for ConvertTo-SecureString
$errors = Invoke-ScriptAnalyzer -Path . -Recurse | Where-Object {
    $_.Severity -eq 'Error' -and
    $_.RuleName -eq 'PSAvoidUsingConvertToSecureStringWithPlainText'
}

Write-Host "Found $($errors.Count) PSScriptAnalyzer errors to fix:" -ForegroundColor Yellow

foreach ($violation in $errors) {
    $filePath = $violation.ScriptPath
    $lineNumber = $violation.Line

    Write-Host "  ${filePath}:${lineNumber}" -ForegroundColor Cyan

    if (-not $WhatIf) {
        try {
            # Read the file content
            $content = Get-Content -Path $filePath -Raw
            $lines = $content -split "`r?`n"

            # Insert suppression comment before the offending line
            $insertIndex = $lineNumber - 1
            if ($insertIndex -ge 0 -and $insertIndex -lt $lines.Count) {

                # Get the indentation of the current line
                $currentLine = $lines[$insertIndex]
                $indentation = ""
                if ($currentLine -match "^(\s*)") {
                    $indentation = $matches[1]
                }

                # Create suppression comment with same indentation
                $suppressionComment = "${indentation}# PSScriptAnalyzer suppression: Test requires known plaintext password"
                $suppressionAttribute = "${indentation}[System.Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidUsingConvertToSecureStringWithPlainText', '')]"

                # Check if suppression already exists
                if ($insertIndex -gt 0 -and $lines[$insertIndex - 1] -match "SuppressMessage.*PSAvoidUsingConvertToSecureStringWithPlainText") {
                    Write-Host "    Already has suppression, skipping" -ForegroundColor Green
                    continue
                }

                # Insert the suppression lines
                $newLines = @()
                $newLines += $lines[0..($insertIndex - 1)]
                $newLines += $suppressionComment
                $newLines += $suppressionAttribute
                $newLines += $lines[$insertIndex..($lines.Count - 1)]

                # Write back to file
                $newContent = $newLines -join "`r`n"
                Set-Content -Path $filePath -Value $newContent -Encoding UTF8
                Write-Host "    Fixed!" -ForegroundColor Green
            }
        }
        catch {
            Write-Host "    Error: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

Write-Host "`nCompleted fixing PSScriptAnalyzer errors." -ForegroundColor Green

if ($WhatIf) {
    Write-Host "Use -WhatIf:`$false to actually apply the fixes." -ForegroundColor Yellow
}