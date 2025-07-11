@{
    # PSScriptAnalyzer configuration for Windows Melody Recovery project
    # PSGallery-compatible settings for production-quality code

    Severity = @('Error', 'Warning', 'Information')

    # Enforce all PSGallery standards - no shortcuts
    ExcludeRules = @()

    Rules = @{
        PSUseCompatibleCmdlets = @{
            compatibility = @('5.1', '7.0', '7.1', '7.2', '7.3', '7.4')
        }

        PSPlaceOpenBrace = @{
            Enable = $true
            OnSameLine = $true
            NewLineAfter = $true
        }

        PSPlaceCloseBrace = @{
            Enable = $true
            NewLineAfter = $true
        }

        PSUseConsistentIndentation = @{
            Enable = $true
            IndentationSize = 4
        }

        PSUseConsistentWhitespace = @{
            Enable = $true
            CheckInnerBrace = $true
            CheckOpenBrace = $true
            CheckOperator = $true
            CheckPipe = $true
            CheckSeparator = $true
        }
    }
}