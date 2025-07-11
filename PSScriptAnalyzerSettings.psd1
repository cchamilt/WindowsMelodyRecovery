@{
    # General settings
    Severity = @('Error', 'Warning', 'Information')

    # Rules to exclude project-wide
    ExcludeRules = @(
        # Exclude Write-Host rule for test files and user-facing scripts
        # These will be handled manually with context-aware fixes
        'PSAvoidUsingWriteHost',

        # Exclude unused parameter warnings for test files
        # Test files often have unused parameters for mocking
        'PSReviewUnusedParameter',

        # Exclude output type warnings for now
        # These require significant refactoring
        'PSUseOutputTypeCorrectly',

        # Exclude positional parameter warnings for simple cases
        'PSAvoidUsingPositionalParameters',

        # Exclude BOM warnings for now
        'PSUseBOMForUnicodeEncodedFile'
    )

    # Include these rules only for production code, not tests
    IncludeRules = @(
        'PSUseShouldProcessForStateChangingFunctions',
        'PSUseApprovedVerbs',
        'PSUseSingularNouns'
    )

    # Rules to apply only to specific paths
    Rules = @{
        # Apply strict rules to Public functions
        PSUseApprovedVerbs = @{
            Whitelist = @('Backup', 'Restore', 'Sync', 'Test', 'Get', 'Set', 'Remove', 'Install', 'Update', 'Initialize', 'Setup')
        }

        # Allow certain nouns for this domain
        PSUseSingularNouns = @{
            Whitelist = @('WindowsMelodyRecovery', 'Prerequisites', 'Tasks', 'Scripts', 'Settings')
        }
    }

    # Custom rule paths can be added here if needed
    CustomRulePath = @()
}