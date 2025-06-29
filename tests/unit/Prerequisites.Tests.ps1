# tests/unit/Prerequisites.Tests.ps1

BeforeAll {
    # Dot-source required modules
    . (Join-Path $PSScriptRoot "..\..\Private\Core\PathUtilities.ps1")
    . (Join-Path $PSScriptRoot "..\..\Private\Core\Prerequisites.ps1")

    # Create a dummy script for prerequisite testing
    $script:TempScriptPath = Join-Path $PSScriptRoot "..\..\Temp\test_prereq_script.ps1"
    $script:TempScriptDir = Split-Path -Path $script:TempScriptPath
    if (-not (Test-Path $script:TempScriptDir -PathType Container)) {
        New-Item -ItemType Directory -Path $script:TempScriptDir -Force | Out-Null
    }
    "Write-Output 'Script Ran Successfully'" | Set-Content -Path $script:TempScriptPath -Encoding Utf8
}

AfterAll {
    # Clean up dummy files
    Remove-Item -Path $script:TempScriptPath -Force -ErrorAction SilentlyContinue
}

Describe "Test-WmrPrerequisites" {

    Context "Application Prerequisites" {
        It "should pass if application check_command output matches expected_output" {
            # Mock winget --version command
            Mock Invoke-Expression {
                param($Command)
                if ($Command -eq "winget --version") {
                    return "v1.5.1234"
                } else { throw "Unexpected Command"}
            }

            $templateConfig = @{
                metadata = @{ name = "App Test" }
                prerequisites = @(
                    @{ type = "application"; name = "Winget"; check_command = "winget --version"; expected_output = "^v\d+\.\d+\.\d+$"; on_missing = "fail_backup" }
                )
            }
            { Test-WmrPrerequisites -TemplateConfig $templateConfig -Operation "Backup" } | Should Not Throw
        }

        It "should warn if application check_command output does not match and on_missing is 'warn'" {
            Mock Invoke-Expression {
                param($Command)
                if ($Command -eq "winget --version") {
                    return "WrongVersion"
                } else { throw "Unexpected Command"}
            }

            $templateConfig = @{
                metadata = @{ name = "App Test" }
                prerequisites = @(
                    @{ type = "application"; name = "Winget"; check_command = "winget --version"; expected_output = "^v\d+\.\d+\.\d+$"; on_missing = "warn" }
                )
            }
            { Test-WmrPrerequisites -TemplateConfig $templateConfig -Operation "Backup" } | Should Not Throw
            # Verify that a warning was written (Pester doesn't have direct Should Write-Warning assertion)
            # This typically requires inspecting output streams, but for now, rely on no throw.
        }

        It "should fail if application check_command output does not match and on_missing is 'fail_backup'" {
            Mock Invoke-Expression {
                param($Command)
                if ($Command -eq "winget --version") {
                    return "WrongVersion"
                } else { throw "Unexpected Command"}
            }

            $templateConfig = @{
                metadata = @{ name = "App Test" }
                prerequisites = @(
                    @{ type = "application"; name = "Winget"; check_command = "winget --version"; expected_output = "^v\d+\.\d+\.\d+$"; on_missing = "fail_backup" }
                )
            }
            { Test-WmrPrerequisites -TemplateConfig $templateConfig -Operation "Backup" } | Should Throw "Prerequisite 'Winget' failed. Cannot proceed with Backup operation as 'fail_backup' is set."
        }
    }

    Context "Registry Prerequisites" {
        BeforeEach {
            # Create a dummy registry key for testing
            New-Item -Path "HKCU:\SOFTWARE\WmrTest" -Force | Out-Null
            Set-ItemProperty -Path "HKCU:\SOFTWARE\WmrTest" -Name "TestValue" -Value "Expected" -Force | Out-Null
            Set-ItemProperty -Path "HKCU:\SOFTWARE\WmrTest" -Name "AnotherValue" -Value "123" -Force | Out-Null
        }

        AfterEach {
            Remove-Item -Path "HKCU:\SOFTWARE\WmrTest" -Recurse -Force -ErrorAction SilentlyContinue
        }

        It "should pass if registry value matches expected_value" {
            $templateConfig = @{
                metadata = @{ name = "Reg Test" }
                prerequisites = @(
                    @{ type = "registry"; name = "Test Reg Value"; path = "HKCU:\SOFTWARE\WmrTest"; key_name = "TestValue"; expected_value = "Expected"; on_missing = "fail_restore" }
                )
            }
            { Test-WmrPrerequisites -TemplateConfig $templateConfig -Operation "Restore" } | Should Not Throw
        }

        It "should pass if registry key exists when checking key only" {
            $templateConfig = @{
                metadata = @{ name = "Reg Test" }
                prerequisites = @(
                    @{ type = "registry"; name = "Test Reg Key"; path = "HKCU:\SOFTWARE\WmrTest"; on_missing = "fail_restore" }
                )
            }
            { Test-WmrPrerequisites -TemplateConfig $templateConfig -Operation "Restore" } | Should Not Throw
        }

        It "should fail if registry value does not match and on_missing is 'fail_restore'" {
            $templateConfig = @{
                metadata = @{ name = "Reg Test" }
                prerequisites = @(
                    @{ type = "registry"; name = "Test Reg Value"; path = "HKCU:\SOFTWARE\WmrTest"; key_name = "TestValue"; expected_value = "Wrong"; on_missing = "fail_restore" }
                )
            }
            { Test-WmrPrerequisites -TemplateConfig $templateConfig -Operation "Restore" } | Should Throw "Prerequisite 'Test Reg Value' failed. Cannot proceed with Restore operation as 'fail_restore' is set."
        }

        It "should fail if registry key does not exist and on_missing is 'fail_restore'" {
            $templateConfig = @{
                metadata = @{ name = "Reg Test" }
                prerequisites = @(
                    @{ type = "registry"; name = "Non Existent Key"; path = "HKCU:\SOFTWARE\NonExistent"; on_missing = "fail_restore" }
                )
            }
            { Test-WmrPrerequisites -TemplateConfig $templateConfig -Operation "Restore" } | Should Throw "Prerequisite 'Non Existent Key' failed. Cannot proceed with Restore operation as 'fail_restore' is set."
        }
    }

    Context "Script Prerequisites" {
        It "should pass if inline script output matches expected_output" {
            $templateConfig = @{
                metadata = @{ name = "Script Test" }
                prerequisites = @(
                    @{ type = "script"; name = "Inline Script"; inline_script = "Write-Output 'Hello World'"; expected_output = "Hello World"; on_missing = "warn" }
                )
            }
            { Test-WmrPrerequisites -TemplateConfig $templateConfig -Operation "Backup" } | Should Not Throw
        }

        It "should pass if script from path output matches expected_output" {
            $templateConfig = @{
                metadata = @{ name = "Script Test" }
                prerequisites = @(
                    @{ type = "script"; name = "Path Script"; path = $script:TempScriptPath; expected_output = "Script Ran Successfully"; on_missing = "fail_backup" }
                )
            }
            { Test-WmrPrerequisites -TemplateConfig $templateConfig -Operation "Backup" } | Should Not Throw
        }

        It "should fail if script output does not match and on_missing is 'fail_backup'" {
            $templateConfig = @{
                metadata = @{ name = "Script Test" }
                prerequisites = @(
                    @{ type = "script"; name = "Inline Script Fail"; inline_script = "Write-Output 'Wrong Output'"; expected_output = "Correct Output"; on_missing = "fail_backup" }
                )
            }
            { Test-WmrPrerequisites -TemplateConfig $templateConfig -Operation "Backup" } | Should Throw "Prerequisite 'Inline Script Fail' failed. Cannot proceed with Backup operation as 'fail_backup' is set."
        }
    }

    Context "Combined Prerequisites and Operations" {
        It "should return true if all prerequisites pass for Backup" {
            Mock Invoke-Expression {
                param($Command)
                if ($Command -eq "winget --version") { return "v1.0.0" }
            }
            New-Item -Path "HKCU:\SOFTWARE\WmrCombinedTest" -Force | Out-Null

            $templateConfig = @{
                metadata = @{ name = "Combined Test" }
                prerequisites = @(
                    @{ type = "application"; name = "Winget"; check_command = "winget --version"; expected_output = "^v\d"; on_missing = "warn" }
                    @{ type = "registry"; name = "Combined Key"; path = "HKCU:\SOFTWARE\WmrCombinedTest"; on_missing = "warn" }
                )
            }
            $result = Test-WmrPrerequisites -TemplateConfig $templateConfig -Operation "Backup"
            $result | Should Be $true

            Remove-Item -Path "HKCU:\SOFTWARE\WmrCombinedTest" -Recurse -Force -ErrorAction SilentlyContinue
            Unmock Invoke-Expression
        }

        It "should return false if any fail_backup prerequisite fails during Backup" {
            Mock Invoke-Expression {
                param($Command)
                if ($Command -eq "winget --version") { return "WrongVersion" }
            }

            $templateConfig = @{
                metadata = @{ name = "Combined Test" }
                prerequisites = @(
                    @{ type = "application"; name = "Winget Critical"; check_command = "winget --version"; expected_output = "^v\d"; on_missing = "fail_backup" }
                )
            }
            { Test-WmrPrerequisites -TemplateConfig $templateConfig -Operation "Backup" } | Should Throw "Prerequisite 'Winget Critical' failed. Cannot proceed with Backup operation as 'fail_backup' is set."
            Unmock Invoke-Expression
        }
    }
} 