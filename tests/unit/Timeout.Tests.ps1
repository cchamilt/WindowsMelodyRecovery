Describe "Timeout Tests" {
    BeforeAll {
    # Load Docker test bootstrap for cross-platform compatibility
    . (Join-Path $PSScriptRoot "../utilities/Docker-Test-Bootstrap.ps1")

        # Import test utilities for timeout functions
        . (Join-Path $PSScriptRoot "../utilities/Test-Utilities.ps1")
    }

    Context "Test-Level Timeouts" {
        It "Should complete before timeout" {
            # This test should complete normally
            Start-Sleep -Seconds 2
            $true | Should -Be $true
        }

        It "Should timeout when using Start-TestWithTimeout" {
            # Test the timeout function directly
            $timeoutTest = {
                Start-TestWithTimeout -ScriptBlock {
                    Start-Sleep -Seconds 10
                } -TimeoutSeconds 5 -TestName "Quick timeout test" -Type "Test"
            }

            # Test should throw timeout exception
            $timeoutTest | Should -Throw "*exceeded timeout*"
        }
    }

    Context "Error Reporting" {
        It "Should include test name in timeout error" {
            $testName = "Named timeout test"
            $timeoutTest = {
                Start-TestWithTimeout -ScriptBlock {
                    Start-Sleep -Seconds 10
                } -TimeoutSeconds 5 -TestName $testName -Type "Test"
            }

            # Error should include test name
            $timeoutTest | Should -Throw "*$testName*"
        }
    }

    Context "Timeout Configuration" {
        It "Should respect custom timeout values from PesterConfig" {
            # Get configured test timeout
            $timeout = Get-TestTimeout -Type "Test"
            $timeout | Should -BeGreaterThan 0
            
            # Test with just under the timeout
            $timeoutTest = {
                Start-TestWithTimeout -ScriptBlock {
                    Start-Sleep -Seconds 2
                } -TimeoutSeconds $timeout -TestName "Config timeout test" -Type "Test"
            }

            # Should not throw
            $timeoutTest | Should -Not -Throw
        }
    }
} 
