@{
    Run = @{
        Path = @()
        PassThru = $true
    }

    Output = @{
        Verbosity = 'Normal'
        RenderMode = 'Plaintext'
    }

    TestResult = @{
        Enabled = $true
        OutputFormat = 'JUnitXml'
        OutputPath = 'test-results/pester-test-results.xml'
    }

    CodeCoverage = @{
        Enabled = $true
        # Include only core production code
        Path = @(
            # Public API functions
            'Public/*.ps1',
            # Core module logic only (exclude setup, backup, restore scripts)
            'Private/Core/*.ps1',
            # Main module file
            'WindowsMelodyRecovery.psm1'
        )
        # Exclude test files, templates, and setup scripts
        ExcludeTests = $true
        ExcludePath = @(
            # Test files and utilities
            'tests/**/*',
            # Configuration templates
            'Templates/**/*',
            # Setup and deployment scripts
            'Private/scripts/**/*',
            'Private/tasks/**/*',
            'Private/setup/**/*',
            'Private/backup/**/*',
            'Private/restore/**/*',
            # TUI components (optional - can be included if needed)
            'TUI/**/*',
            # Mock data and test utilities
            '**/mock-*',
            '**/test-*',
            # Example files
            'example-*',
            # Temporary and build files
            'Temp/**/*',
            'test-*/**/*',
            'logs/**/*'
        )
        OutputFormat = 'JaCoCo'
        OutputPath = 'test-results/coverage/coverage.xml'
        CoveragePercentTarget = 75
    }

    # Filter configuration
    Filter = @{
        Tag = @()
        ExcludeTag = @('WindowsOnly', 'RequiresAdmin', 'Slow', 'Manual')
        Line = @()
        ExcludeLine = @()
    }

    # Should configuration
    Should = @{
        ErrorAction = 'Continue'
    }
}
