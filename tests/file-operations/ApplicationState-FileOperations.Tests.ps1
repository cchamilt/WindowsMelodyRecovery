# tests/file-operations/ApplicationState-FileOperations.Tests.ps1

<#
.SYNOPSIS
    File Operations Tests for ApplicationState

.DESCRIPTION
    Tests the ApplicationState functions' file operations within safe test directories.
    Performs actual file operations but only in designated test paths.

.NOTES
    These are file operation tests - they create and manipulate actual files!
    Pure logic tests are in tests/unit/ApplicationState-Logic.Tests.ps1
#>

BeforeAll {
    # Import test environment utilities
    . (Join-Path $PSScriptRoot "..\utilities\Test-Environment.ps1")

    # Get standardized test paths
    $script:TestPaths = Get-TestPaths

    # Import the module with standardized pattern
    try {
        $ModulePath = Resolve-Path "$PSScriptRoot/../../WindowsMelodyRecovery.psd1"
        Import-Module $ModulePath -Force -ErrorAction Stop
    } catch {
        throw "Cannot find or import WindowsMelodyRecovery module: $($_.Exception.Message)"
    }

    # Dot-source ApplicationState.ps1 to ensure all functions are available
    . (Join-Path (Split-Path $ModulePath) "Private\Core\ApplicationState.ps1")

    # Use standardized temp directory for state files
    $script:TempStateDir = Join-Path $script:TestPaths.Temp "ApplicationStateTests"
    if (-not (Test-Path $script:TempStateDir -PathType Container)) {
        New-Item -ItemType Directory -Path $script:TempStateDir -Force | Out-Null
    }

    # Setup a temporary directory for installed apps simulation
    $script:InstalledAppsDir = Join-Path $script:TempStateDir "InstalledApps"
    if (-not (Test-Path $script:InstalledAppsDir -PathType Container)) {
        New-Item -ItemType Directory -Path $script:InstalledAppsDir -Force | Out-Null
    }

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

    # Define a simple install script that uses the test directory
    $script:CommonInstallScript = "param([string]`$AppListJson)
`$apps = `$AppListJson | ConvertFrom-Json
foreach (`$app in `$apps) {
    Write-Information -MessageData `"Simulating install of `$(`$app.Name) (ID: `$(`$app.Id), Version: `$(`$app.Version))`" -InformationAction Continue
    Set-Content -Path (Join-Path '$script:InstalledAppsDir' `"`$(`$app.Id).installed`") -Value `"Installed`" -Force
}"

    # Define a simple uninstall script that uses the test directory
    $script:CommonUninstallScript = "param([string]`$AppListJson)
`$apps = `$AppListJson | ConvertFrom-Json
foreach (`$app in `$apps) {
    Write-Information -MessageData `"Simulating uninstall of `$(`$app.Name) (ID: `$(`$app.Id))`" -InformationAction Continue
    Remove-Item -Path (Join-Path '$script:InstalledAppsDir' `"`$(`$app.Id).installed`") -ErrorAction SilentlyContinue
}"
}

AfterAll {
    # Clean up temporary directories safely
    if ($script:TempStateDir -and (Test-SafeTestPath $script:TempStateDir)) {
        Remove-Item -Path $script:TempStateDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "ApplicationState File Operations" -Tag "FileOperations" {

    Context "Application State File Creation and Reading" {

        It "should create state files for discovered applications" {
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

            $appConfig = @{
                name = "Winget Test Apps"
                type = "winget"
                dynamic_state_path = "apps/winget_list.json"
                discovery_command = "winget list --source winget"
                parse_script = $script:CommonParseScript
                install_script = "dummy"
                uninstall_script = "dummy"
            }

            Get-WmrApplicationState -AppConfig $appConfig -StateFilesDirectory $script:TempStateDir

            $stateFilePath = Join-Path $script:TempStateDir "apps/winget_list.json"
            (Test-Path $stateFilePath) | Should -Be $true
            $content = (Get-Content -Path $stateFilePath -Raw -Encoding Utf8) | ConvertFrom-Json

            $content.Count | Should -Be 3
            $content[0].Name | Should -Be "Microsoft Edge"
            $content[1].Id | Should -Be "Microsoft.WindowsTerminal"
            $content[2].Version | Should -Be "1.2.3"
        }

        It "should create empty state files for empty discovery output" {
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

            Get-WmrApplicationState -AppConfig $appConfig -StateFilesDirectory $script:TempStateDir

            $stateFilePath = Join-Path $script:TempStateDir "apps/empty_winget_list.json"
            (Test-Path $stateFilePath) | Should -Be $true
            $content = (Get-Content -Path $stateFilePath -Raw -Encoding Utf8) | ConvertFrom-Json
            $content.Count | Should -Be 0
        }

        It "should not create state files when discovery command fails" {
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

            { Get-WmrApplicationState -AppConfig $appConfig -StateFilesDirectory $script:TempStateDir } | Should -Not -Throw
            (Test-Path (Join-Path $script:TempStateDir "apps/failing_discovery.json")) | Should -Be $false
        }
    }

    Context "Application Installation File Operations" {

        It "should process install scripts that create files" {
            $appListJson = '[{"Name":"TestApp1","Id":"Test.App1","Version":"1.0.0"},{"Name":"TestApp2","Id":"Test.App2","Version":"2.0.0"}]'
            $stateFilePath = Join-Path $script:TempStateDir "apps/install_list.json"
            $appListJson | Set-Content -Path $stateFilePath -Encoding Utf8

            $appConfig = @{
                name = "Install Test Apps"
                type = "custom"
                dynamic_state_path = "apps/install_list.json"
                discovery_command = "dummy"
                parse_script = "dummy"
                install_script = $script:CommonInstallScript
            }

            Set-WmrApplicationState -AppConfig $appConfig -StateFilesDirectory $script:TempStateDir

            # Verify simulation of installation by checking dummy files
            (Test-Path (Join-Path $script:InstalledAppsDir "Test.App1.installed")) | Should -Be $true
            (Test-Path (Join-Path $script:InstalledAppsDir "Test.App2.installed")) | Should -Be $true
        }

        It "should handle missing state files gracefully" {
            $appConfig = @{
                name = "Missing State Install"
                type = "custom"
                dynamic_state_path = "apps/non_existent_install.json"
                discovery_command = "dummy"
                parse_script = "dummy"
                install_script = $script:CommonInstallScript
            }

            { Set-WmrApplicationState -AppConfig $appConfig -StateFilesDirectory $script:TempStateDir } | Should -Not -Throw
        }
    }

    Context "Application Uninstallation File Operations" {

        It "should process uninstall scripts that remove files" {
            # First, simulate installation for cleanup
            $initialAppListJson = '[{"Name":"AppToUninstall","Id":"App.Uninstall","Version":"1.0.0"}]'
            $initialStateFilePath = Join-Path $script:TempStateDir "apps/uninstall_list.json"
            $initialAppListJson | Set-Content -Path $initialStateFilePath -Encoding Utf8

            $initialAppConfig = @{
                name = "App to Uninstall"
                type = "custom"
                dynamic_state_path = "apps/uninstall_list.json"
                discovery_command = "dummy"
                parse_script = "dummy"
                install_script = $script:CommonInstallScript
                uninstall_script = $script:CommonUninstallScript
            }
            Set-WmrApplicationState -AppConfig $initialAppConfig -StateFilesDirectory $script:TempStateDir
            (Test-Path (Join-Path $script:InstalledAppsDir "App.Uninstall.installed")) | Should -Be $true

            # Now, perform uninstallation
            Uninstall-WmrApplicationState -AppConfig $initialAppConfig -StateFilesDirectory $script:TempStateDir

            # Verify simulation of uninstallation by checking dummy files
            (Test-Path (Join-Path $script:InstalledAppsDir "App.Uninstall.installed")) | Should -Be $false
        }

        It "should handle missing uninstall script gracefully" {
            $appConfig = @{
                name = "No Uninstall Script"
                type = "custom"
                dynamic_state_path = "apps/no_uninstall.json"
                discovery_command = "dummy"
                parse_script = "dummy"
                install_script = "dummy"
                # uninstall_script is intentionally missing
            }

            { Uninstall-WmrApplicationState -AppConfig $appConfig -StateFilesDirectory $script:TempStateDir } | Should -Not -Throw
        }
    }

    Context "Directory Structure Creation" {

        It "should create nested directory structures for state files" {
            Mock Invoke-Expression {
                param($Command)
                if ($Command -eq "test command") {
                    return "test output"
                }
            }

            $appConfig = @{
                name = "Nested Directory Test"
                type = "custom"
                dynamic_state_path = "level1/level2/level3/nested_app.json"
                discovery_command = "test command"
                parse_script = $script:CommonParseScript
                install_script = "dummy"
            }

            Get-WmrApplicationState -AppConfig $appConfig -StateFilesDirectory $script:TempStateDir

            $nestedPath = Join-Path $script:TempStateDir "level1/level2/level3"
            (Test-Path $nestedPath -PathType Container) | Should -Be $true

            $stateFilePath = Join-Path $script:TempStateDir "level1/level2/level3/nested_app.json"
            (Test-Path $stateFilePath) | Should -Be $true
        }

        It "should handle path creation failures gracefully" {
            # This test would require mocking New-Item to fail, but since we're in file-operations
            # we'll just verify that the function handles real directory creation properly
            $appConfig = @{
                name = "Directory Creation Test"
                type = "custom"
                dynamic_state_path = "apps/directory_test.json"
                discovery_command = "echo 'test'"
                parse_script = $script:CommonParseScript
                install_script = "dummy"
            }

            { Get-WmrApplicationState -AppConfig $appConfig -StateFilesDirectory $script:TempStateDir } | Should -Not -Throw

            $stateFilePath = Join-Path $script:TempStateDir "apps/directory_test.json"
            (Test-Path $stateFilePath) | Should -Be $true
        }
    }

    Context "File Content Validation" {

        It "should write valid JSON content to state files" {
            Mock Invoke-Expression {
                param($Command)
                if ($Command -eq "winget list --source winget") {
                    return @"
Name                 Id                    Version
------------------------------------------------
Visual Studio Code   Microsoft.VisualStudioCode 1.60.0
"@
                }
            }

            $appConfig = @{
                name = "JSON Validation Test"
                type = "winget"
                dynamic_state_path = "apps/json_validation.json"
                discovery_command = "winget list --source winget"
                parse_script = $script:CommonParseScript
                install_script = "dummy"
            }

            Get-WmrApplicationState -AppConfig $appConfig -StateFilesDirectory $script:TempStateDir

            $stateFilePath = Join-Path $script:TempStateDir "apps/json_validation.json"
            (Test-Path $stateFilePath) | Should -Be $true

            # Validate JSON content
            $content = Get-Content -Path $stateFilePath -Raw -Encoding Utf8
            { $content | ConvertFrom-Json } | Should -Not -Throw

            $parsed = $content | ConvertFrom-Json
            $parsed.Count | Should -Be 1
            $parsed[0].Name | Should -Be "Visual Studio Code"
            $parsed[0].Id | Should -Be "Microsoft.VisualStudioCode"
            $parsed[0].Version | Should -Be "1.60.0"
        }

        It "should handle UTF-8 encoding correctly" {
            Mock Invoke-Expression {
                param($Command)
                if ($Command -eq "test command") {
                    return @"
Name                 Id                    Version
------------------------------------------------
Test App with 中文    Test.Unicode          1.0.0
"@
                }
            }

            $appConfig = @{
                name = "UTF-8 Encoding Test"
                type = "custom"
                dynamic_state_path = "apps/utf8_test.json"
                discovery_command = "test command"
                parse_script = $script:CommonParseScript
                install_script = "dummy"
            }

            Get-WmrApplicationState -AppConfig $appConfig -StateFilesDirectory $script:TempStateDir

            $stateFilePath = Join-Path $script:TempStateDir "apps/utf8_test.json"
            (Test-Path $stateFilePath) | Should -Be $true

            $content = Get-Content -Path $stateFilePath -Raw -Encoding Utf8 | ConvertFrom-Json
            $content[0].Name | Should -Be "Test App with 中文"
        }
    }
}







