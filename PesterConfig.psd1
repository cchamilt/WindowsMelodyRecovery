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
        Container = @{
            Parallel = $false  # Ensure tests run sequentially for now until we fix isolation
        }
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
        CoveragePercentTarget = 80
    }
    
    Output = @{
        Verbosity = 'Detailed'
        RenderMode = 'Console'
        StackTraceVerbosity = 'Full'
        CIFormat = 'Auto'
    }
    
    TestResult = @{
        Enabled = $true
        OutputPath = 'test-results/pester/test-results.xml'
        OutputFormat = 'NUnitXml'
        TestSuiteName = 'WindowsMelodyRecovery'
    }
    
    Should = @{
        ErrorAction = 'Continue'
        MaxConsecutiveFailures = 3  # Stop after 3 consecutive failures in a describe block
    }
    
    Filter = @{
        Tag = @()
        ExcludeTag = @('Slow', 'Integration')
        Line = $null
        ExcludeLine = $null
    }
    
    Debug = @{
        ShowNavigationMarkers = $true
        WriteDebugMessages = $true
        WriteVerboseMessages = $true
        WriteProgressMessages = $true
    }
} 