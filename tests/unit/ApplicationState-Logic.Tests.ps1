# ApplicationState Logic Tests
# Tests the core logic of ApplicationState.ps1 functions without file operations

BeforeAll {
    # Load Docker test bootstrap for cross-platform compatibility
    . (Join-Path $PSScriptRoot "../utilities/Docker-Test-Bootstrap.ps1")

    # Import the module with standardized pattern
    try {
        $ModulePath = Resolve-Path "$PSScriptRoot/../../WindowsMelodyRecovery.psd1"
        Import-Module $ModulePath -Force -ErrorAction Stop
    } catch {
        throw "Cannot find or import WindowsMelodyRecovery module: $($_.Exception.Message)"
    }

    # Dot-source ApplicationState.ps1 to ensure all functions are available
    . (Join-Path (Split-Path $ModulePath) "Private\Core\ApplicationState.ps1")

    # Mock all file operations
    Mock Test-Path { return $true } -ParameterFilter { $Path -like "*exists*" }
    Mock Test-Path { return $false } -ParameterFilter { $Path -like "*missing*" }
    Mock New-Item { return @{ FullName = $Path } }
    Mock Set-Content { }
    Mock Get-Content { return "[]" }
    Mock Remove-Item { }

    # Mock encryption functions for testing purposes
    Mock Protect-WmrData {
        param([byte[]]$DataBytes)
        return [System.Convert]::ToBase64String($DataBytes) # Simply Base64 encode for mock
    }
    Mock Unprotect-WmrData {
        param([string]$EncodedData)
        return [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($EncodedData)) # Simply Base64 decode for mock
    }
    # Mock Read-Host to prevent interactive prompts
    # PSScriptAnalyzer suppression: Test requires known plaintext password
    [System.Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidUsingConvertToSecureStringWithPlainText', '')]
    Mock Read-Host { return (ConvertTo-SecureString "TestPassphrase123!" -AsPlainText -Force) } -ParameterFilter { $AsSecureString }

    # Define a parse script that properly handles spaces in application names and empty input
    $script:CommonParseScript = 'param([string]$InputObject)
$apps = @()

# Handle empty input
if ([string]::IsNullOrWhiteSpace($InputObject)) {
    return "[]"
}

$lines = $InputObject -split "`n" | Where-Object { $_ -match "\S" }  # Skip empty lines
if ($lines.Count -lt 3) {  # Need at least header, divider, and one app
    return "[]"
}

foreach ($line in $lines | Select-Object -Skip 2) {  # Skip header and divider
    if ($line -match "\S") {  # Skip empty lines
        # Use regex to match fixed-width columns, allowing for variable spacing
        if ($line -match "^(.+?)\s+([^\s]+)\s+([^\s]+)\s*$") {
            $name = $matches[1].Trim()
            $id = $matches[2].Trim()
            $version = $matches[3].Trim()
            $apps += @{ Name = $name; Id = $id; Version = $version }
        }
    }
}
$apps | ConvertTo-Json -Compress'

    # Define a simple install script for logic testing
    $script:CommonInstallScript = "param([string]`$AppListJson)
`$apps = `$AppListJson | ConvertFrom-Json
foreach (`$app in `$apps) {
    Write-Information -MessageData `"Simulating install of `$(`$app.Name) (ID: `$(`$app.Id), Version: `$(`$app.Version))`" -InformationAction Continue
}"

    # Define a simple uninstall script for logic testing
    $script:CommonUninstallScript = "param([string]`$AppListJson)
`$apps = `$AppListJson | ConvertFrom-Json
foreach (`$app in `$apps) {
    Write-Information -MessageData `"Simulating uninstall of `$(`$app.Name) (ID: `$(`$app.Id))`" -InformationAction Continue
}"
}

Describe "ApplicationState Logic Tests" -Tag "Unit", "Logic" {

    Context "Application Discovery and Parsing Logic" {

        It "should parse winget application output correctly" {
            # Mock Invoke-Expression for winget list
            Mock Invoke-Expression {
                param($Command)
                if ($Command -eq "winget list --source winget") {
                    return @"
Name                 Id                    Version
------------------------------------------------
Microsoft Edge       Microsoft.Edge        100.0.1
Windows Terminal    Microsoft.WindowsTerminal 1.0.0
Package A           App.PackageA          1.2.3
"@
                } else { throw "Unexpected Command: $Command" }
            }

            # Mock Get-Content to return the expected parsed JSON
            Mock Get-Content {
                return '[{"Name":"Microsoft Edge","Id":"Microsoft.Edge","Version":"100.0.1"},{"Name":"Windows Terminal","Id":"Microsoft.WindowsTerminal","Version":"1.0.0"},{"Name":"Package A","Id":"App.PackageA","Version":"1.2.3"}]'
            }

            $appConfig = @{
                name = "Winget Test Apps"
                type = "winget"
                dynamic_state_path = "apps/winget_list.json"
                discovery_command = "winget list --source winget"
                parse_script = $script:CommonParseScript
                install_script = "dummy"
                uninstall_script = "dummy"
            }

            $result = Get-WmrApplicationState -AppConfig $appConfig -StateFilesDirectory (Get-WmrTestPath -WindowsPath (Get-WmrTestPath -WindowsPath "C:\MockStateDir"))

            # Verify the function was called and Set-Content was invoked
            Should -Invoke Set-Content -Times 1
            Should -Invoke Invoke-Expression -Times 1
        }

        It "should handle empty discovery command output" {
            Mock Invoke-Expression {
                param($Command)
                if ($Command -eq "winget list") {
                    return ""
                }
            }

            $appConfig = @{
                name = "Empty Winget List"
                type = "winget"
                dynamic_state_path = "apps/empty_winget_list.json"
                discovery_command = "winget list"
                parse_script = $script:CommonParseScript
                install_script = "dummy"
                uninstall_script = "dummy"
            }

            $result = Get-WmrApplicationState -AppConfig $appConfig -StateFilesDirectory (Get-WmrTestPath -WindowsPath (Get-WmrTestPath -WindowsPath "C:\MockStateDir"))

            # Should handle empty output gracefully
            Should -Invoke Invoke-Expression -Times 1
        }

        It "should warn if discovery command fails" {
            Mock Invoke-Expression {
                param($Command)
                throw "Command failed unexpectedly"
            }

            $appConfig = @{
                name = "Failing Discovery"
                type = "custom"
                dynamic_state_path = "apps/failing_discovery.json"
                discovery_command = "nonexistent-command"
                parse_script = $script:CommonParseScript
                install_script = "dummy"
            }

            { Get-WmrApplicationState -AppConfig $appConfig -StateFilesDirectory (Get-WmrTestPath -WindowsPath (Get-WmrTestPath -WindowsPath "C:\MockStateDir")) } | Should -Not -Throw
            Should -Invoke Invoke-Expression -Times 1
        }
    }

    Context "Application Installation Logic" {

        It "should process install script correctly" {
            # Mock Test-Path to return true for the state file
            Mock Test-Path { return $true } -ParameterFilter { $Path -like "*install_list.json" }

            # Mock Get-Content to return app list JSON
            Mock Get-Content {
                return '[{"Name":"TestApp1","Id":"Test.App1","Version":"1.0.0"},{"Name":"TestApp2","Id":"Test.App2","Version":"2.0.0"}]'
            } -ParameterFilter { $Path -like "*install_list.json" }

            $appConfig = @{
                name = "Install Test Apps"
                type = "custom"
                dynamic_state_path = "apps/install_list.json"
                discovery_command = "dummy"
                parse_script = "dummy"
                install_script = $script:CommonInstallScript
            }

            { Set-WmrApplicationState -AppConfig $appConfig -StateFilesDirectory (Get-WmrTestPath -WindowsPath (Get-WmrTestPath -WindowsPath "C:\MockStateDir")) } | Should -Not -Throw
            Should -Invoke Get-Content -Times 1
        }

        It "should handle missing state file gracefully" {
            # Mock Test-Path to return false for missing file
            Mock Test-Path { return $false } -ParameterFilter { $Path -like "*non_existent*" }

            $appConfig = @{
                name = "Missing State Install"
                type = "custom"
                dynamic_state_path = "apps/non_existent_list.json"
                discovery_command = "dummy"
                parse_script = "dummy"
                install_script = $script:CommonInstallScript
            }

            { Set-WmrApplicationState -AppConfig $appConfig -StateFilesDirectory (Get-WmrTestPath -WindowsPath (Get-WmrTestPath -WindowsPath "C:\MockStateDir")) } | Should -Not -Throw
            Should -Invoke Test-Path -Times 1
        }
    }

    Context "Application Uninstallation Logic" {

        It "should process uninstall script correctly" {
            # Mock Test-Path to return true for the state file
            Mock Test-Path { return $true } -ParameterFilter { $Path -like "*uninstall_list.json" }

            # Mock Get-Content to return app list JSON
            Mock Get-Content {
                return '[{"Name":"TestApp1","Id":"Test.App1","Version":"1.0.0"},{"Name":"TestApp2","Id":"Test.App2","Version":"2.0.0"}]'
            } -ParameterFilter { $Path -like "*uninstall_list.json" }

            $appConfig = @{
                name = "App to Uninstall"
                type = "custom"
                dynamic_state_path = "apps/uninstall_list.json"
                discovery_command = "dummy"
                parse_script = "dummy"
                install_script = "dummy"
                uninstall_script = $script:CommonUninstallScript
            }

            { Uninstall-WmrApplicationState -AppConfig $appConfig -StateFilesDirectory (Get-WmrTestPath -WindowsPath (Get-WmrTestPath -WindowsPath "C:\MockStateDir")) } | Should -Not -Throw
            Should -Invoke Get-Content -Times 1
        }

        It "should handle missing uninstall script gracefully" {
            # Mock Test-Path to return true for the state file
            Mock Test-Path { return $true } -ParameterFilter { $Path -like "*no_uninstall_list.json" }

            $appConfig = @{
                name = "No Uninstall Script"
                type = "custom"
                dynamic_state_path = "apps/no_uninstall_list.json"
                discovery_command = "dummy"
                parse_script = "dummy"
                install_script = "dummy"
                # uninstall_script is intentionally missing
            }

            { Uninstall-WmrApplicationState -AppConfig $appConfig -StateFilesDirectory (Get-WmrTestPath -WindowsPath (Get-WmrTestPath -WindowsPath "C:\MockStateDir")) } | Should -Not -Throw
        }
    }

    Context "Configuration Validation Logic" {

        It "should validate required configuration properties" {
            $validConfig = @{
                name = "Valid App Config"
                type = "winget"
                dynamic_state_path = "apps/valid_config.json"
                discovery_command = "winget list"
                parse_script = $script:CommonParseScript
                install_script = "dummy"
                uninstall_script = "dummy"
            }

            { Get-WmrApplicationState -AppConfig $validConfig -StateFilesDirectory (Get-WmrTestPath -WindowsPath (Get-WmrTestPath -WindowsPath "C:\MockStateDir")) } | Should -Not -Throw
        }

        It "should handle missing required properties gracefully" {
            $incompleteConfig = @{
                name = "Incomplete Config"
                type = "winget"
                # Missing dynamic_state_path, discovery_command, parse_script, install_script
            }

            { Get-WmrApplicationState -AppConfig $incompleteConfig -StateFilesDirectory (Get-WmrTestPath -WindowsPath (Get-WmrTestPath -WindowsPath "C:\MockStateDir")) } | Should -Not -Throw
        }
    }

    Context "Parse Script Logic Validation" {

        It "should handle parse script execution correctly" {
            $testInput = @"
Name                 Id                    Version
------------------------------------------------
Test App             Test.App              1.0.0
Another App          Another.App           2.0.0
"@

            # Execute the parse script directly to test logic
            $result = Invoke-Expression -Command "& { $script:CommonParseScript } -InputObject '$testInput'"
            $parsed = $result | ConvertFrom-Json

            $parsed.Count | Should -Be 2
            $parsed[0].Name | Should -Be "Test App"
            $parsed[0].Id | Should -Be "Test.App"
            $parsed[0].Version | Should -Be "1.0.0"
            $parsed[1].Name | Should -Be "Another App"
            $parsed[1].Id | Should -Be "Another.App"
            $parsed[1].Version | Should -Be "2.0.0"
        }

        It "should handle empty input in parse script" {
            $result = Invoke-Expression -Command "& { $script:CommonParseScript } -InputObject ''"
            $result | Should -Be "[]"
        }

        It "should handle malformed input in parse script" {
            $malformedInput = "This is not a properly formatted application list"
            $result = Invoke-Expression -Command "& { $script:CommonParseScript } -InputObject '$malformedInput'"
            $result | Should -Be "[]"
        }
    }
}









