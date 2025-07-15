#!/usr/bin/env pwsh
<#
.SYNOPSIS
    General Purpose Test Helper Functions for Windows Melody Recovery.

.DESCRIPTION
    This script provides a collection of generic, non-mocking helper functions
    for use across the Pester test suite. It includes utilities for handling
    test execution flow, such as retries and timeouts.
#>

function Invoke-TestWithRetry {
    <#
    .SYNOPSIS
        Executes a script block with a retry mechanism.
    #>
    param(
        [scriptblock]$TestScript,
        [int]$MaxRetries = 3,
        [int]$RetryDelaySeconds = 5
    )

    for ($i = 1; $i -le $MaxRetries; $i++) {
        try {
            $result = & $TestScript
            return $result
        }
        catch {
            if ($i -eq $MaxRetries) {
                throw "Test failed after $MaxRetries attempts: $($_.Exception.Message)"
            }
            Write-Warning -Message "Test attempt $i failed, retrying in $RetryDelaySeconds seconds..."
            Start-Sleep -Seconds $RetryDelaySeconds
        }
    }
}

function Start-TestWithTimeout {
    <#
    .SYNOPSIS
        Executes a test block with timeout protection.
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

        if ($null -eq $completed) {
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
        Gets the configured timeout value for a test type from PesterConfig.psd1.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Test', 'Describe', 'Context', 'Block', 'Global')]
        [string]$Type
    )

    # Default timeout values (in seconds)
    $defaultTimeouts = @{
        Test     = 300       # 5 minutes
        Describe = 1800  # 30 minutes
        Context  = 900    # 15 minutes
        Block    = 3600     # 1 hour
        Global   = 7200    # 2 hours
    }

    try {
        # This assumes the script is run from a context where $script:ModuleRoot is set
        # by the main test environment script.
        $configPath = Join-Path $script:ModuleRoot "PesterConfig.psd1"
        if ($script:ModuleRoot -and $configPath -and (Test-Path $configPath)) {
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

Export-ModuleMember -Function Invoke-TestWithRetry, Start-TestWithTimeout, Get-TestTimeout
