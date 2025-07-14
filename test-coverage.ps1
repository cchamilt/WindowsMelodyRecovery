# Test script to verify code coverage is working
$config = New-PesterConfiguration
$config.Run.Path = 'FileState-FileOperations.Tests.ps1'
$config.Filter.FullName = '*should recreate directory structure from dynamic_state_path metadata*'
$config.CodeCoverage.Enabled = $true
$config.CodeCoverage.Path = '../../Private/Core/FileState.ps1'
$config.Output.Verbosity = 'Detailed'

$result = Invoke-Pester -Configuration $config

Write-Host "Code Coverage Results:"
Write-Host "Covered: $($result.CodeCoverage.CoveredPercent)%"
Write-Host "Commands Analyzed: $($result.CodeCoverage.CommandsAnalyzedCount)"
Write-Host "Commands Executed: $($result.CodeCoverage.CommandsExecutedCount)"
Write-Host "Commands Missed: $($result.CodeCoverage.CommandsMissedCount)"
