# tests/utilities/PesterSetup.ps1

function Initialize-WmrTestEnvironment {
    # Ensure we're using Pester 5.x
    if (-not (Get-Module -Name Pester)) {
        Import-Module Pester -MinimumVersion 5.0.0
    }

    # Configure Pester for our needs
    $config = New-PesterConfiguration
    $config.Output.Verbosity = 'Detailed'
    $config.TestResult.Enabled = $true
    $config.TestResult.OutputFormat = 'NUnitXml'
    $config.TestResult.OutputPath = 'test-results.xml'

    # Initialize TestDrive if not already done
    if (-not (Get-PSDrive -Name TestDrive -ErrorAction SilentlyContinue)) {
        $null = New-PSDrive -Name TestDrive -PSProvider FileSystem -Root (New-Item -ItemType Directory -Path (Join-Path $env:TEMP ([System.Guid]::NewGuid().ToString())) -Force)
    }

    return $config
}





