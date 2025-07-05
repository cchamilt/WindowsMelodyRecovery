#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Test Utilities for Windows Melody Recovery Integration Tests

.DESCRIPTION
    Common utility functions for test execution, reporting, and environment management.
#>

# Test execution utilities
function Invoke-TestWithRetry {
    param(
        [scriptblock]$TestScript,
        [int]$MaxRetries = 3,
        [int]$RetryDelaySeconds = 5
    )
    
    for ($i = 1; $i -le $MaxRetries; $i++) {
        try {
            $result = & $TestScript
            return $result
        } catch {
            if ($i -eq $MaxRetries) {
                throw "Test failed after $MaxRetries attempts: $($_.Exception.Message)"
            }
            Write-Host "Test attempt $i failed, retrying in $RetryDelaySeconds seconds..." -ForegroundColor Yellow
            Start-Sleep -Seconds $RetryDelaySeconds
        }
    }
}

function Write-TestResult {
    param(
        [string]$TestName,
        [bool]$Passed,
        [string]$Message = "",
        [object]$Details = $null
    )
    
    $status = if ($Passed) { "✓ PASS" } else { "✗ FAIL" }
    $color = if ($Passed) { "Green" } else { "Red" }
    
    Write-Host "$status $TestName" -ForegroundColor $color
    if ($Message) {
        Write-Host "  $Message" -ForegroundColor Gray
    }
    if ($Details) {
        Write-Host "  Details: $($Details | ConvertTo-Json -Compress)" -ForegroundColor Gray
    }
}

function Get-TestSummary {
    param(
        [array]$TestResults
    )
    
    $summary = @{
        Total = $TestResults.Count
        Passed = ($TestResults | Where-Object { $_.Result -eq "Passed" }).Count
        Failed = ($TestResults | Where-Object { $_.Result -eq "Failed" }).Count
        Duration = ($TestResults | Measure-Object -Property Duration -Sum).Sum
    }
    
    return $summary
}

# Test utilities module
$script:ModuleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

# Only export functions if we're in a module context
if ($MyInvocation.MyCommand.Path) {  # Check if we're in a script file
    # Create module scope for functions
    New-Module -Name TestUtilities -ScriptBlock {
        function Start-TestWithTimeout {
            <#
            .SYNOPSIS
                Executes a test block with timeout protection.
            
            .DESCRIPTION
                Runs a test block with configurable timeout protection. If the test exceeds
                the specified timeout, it will be terminated and marked as failed.
            
            .PARAMETER ScriptBlock
                The test script block to execute.
            
            .PARAMETER TimeoutSeconds
                The maximum time in seconds to allow the test to run.
            
            .PARAMETER TestName
                The name of the test for logging purposes.
            
            .PARAMETER Type
                The type of timeout (Test, Describe, Context, Block, or Global).
            
            .EXAMPLE
                Start-TestWithTimeout -ScriptBlock { Test-Something } -TimeoutSeconds 300 -TestName "My Test" -Type "Test"
            #>
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $true)]
                [scriptblock]$ScriptBlock,
                
                [Parameter(Mandatory = $true)]
                [int]$TimeoutSeconds,
                
                [Parameter(Mandatory = $true)]
                [string]$TestName,
                
                [Parameter(Mandatory = $true)]
                [ValidateSet('Test', 'Describe', 'Context', 'Block', 'Global')]
                [string]$Type
            )
            
            try {
                $job = Start-Job -ScriptBlock $ScriptBlock
                
                $completed = Wait-Job -Job $job -Timeout $TimeoutSeconds
                
                if ($completed -eq $null) {
                    Stop-Job -Job $job
                    Remove-Job -Job $job -Force
                    throw "Test '$TestName' exceeded timeout of $TimeoutSeconds seconds"
                }
                
                $result = Receive-Job -Job $job
                Remove-Job -Job $job
                
                return $result
            }
            catch {
                Write-Warning "$Type '$TestName' failed: $_"
                throw
            }
        }

        function Get-TestTimeout {
            <#
            .SYNOPSIS
                Gets the configured timeout value for a test type.
            
            .DESCRIPTION
                Retrieves the timeout value from PesterConfig.psd1 for the specified test type.
                Falls back to default values if not configured.
            
            .PARAMETER Type
                The type of timeout to retrieve (Test, Describe, Context, Block, or Global).
            
            .EXAMPLE
                Get-TestTimeout -Type "Test"
            #>
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $true)]
                [ValidateSet('Test', 'Describe', 'Context', 'Block', 'Global')]
                [string]$Type
            )
            
            # Default timeout values (in seconds)
            $defaultTimeouts = @{
                Test = 300       # 5 minutes
                Describe = 1800  # 30 minutes
                Context = 900    # 15 minutes
                Block = 3600     # 1 hour
                Global = 7200    # 2 hours
            }
            
            try {
                # Try to get configuration from PesterConfig.psd1
                $configPath = Join-Path $script:ModuleRoot "PesterConfig.psd1"
                if ($configPath -and (Test-Path $configPath)) {
                    $config = Import-PowerShellDataFile $configPath
                    if ($config.Run.Timeout."${Type}Timeout") {
                        return $config.Run.Timeout."${Type}Timeout"
                    }
                }
            }
            catch {
                Write-Warning "Failed to load timeout configuration: $_"
            }
            
            # Fall back to default timeout
            return $defaultTimeouts[$Type]
        }

        # Export the functions
        Export-ModuleMember -Function Start-TestWithTimeout, Get-TestTimeout
    } | Import-Module
} 