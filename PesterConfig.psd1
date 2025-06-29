@{
    Run = @{
        Path = @(
            'tests/unit',
            'tests/integration'
        )
        ExcludePath = @(
            'tests/mock-data',
            'tests/mock-scripts'
        )
        TestExtension = '.Tests.ps1'
        PassThru = $true
    }
    
    CodeCoverage = @{
        Enabled = $true
        Path = @(
            'Public/*.ps1',
            'Private/**/*.ps1',
            'WindowsMelodyRecovery.psm1'
        )
        ExcludePath = @(
            'tests/**/*',
            'docs/**/*',
            'Templates/**/*',
            'example-profiles/**/*'
        )
        OutputPath = 'test-results/coverage/coverage.xml'
        OutputFormat = 'JaCoCo'
    }
    
    Output = @{
        Verbosity = 'Normal'
        RenderMode = 'Console'
    }
    
    TestResult = @{
        Enabled = $true
        OutputPath = 'test-results/pester/test-results.xml'
        OutputFormat = 'NUnitXml'
    }
    
    Should = @{
        ErrorAction = 'Continue'
    }
    
    Filter = @{
        Tag = @()
        ExcludeTag = @('Slow', 'Integration')
    }
} 