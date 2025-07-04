# tests/unit/ApplicationState.Tests.ps1

BeforeAll {
    # Import the WindowsMelodyRecovery module to make functions available
    $ModulePath = if (Test-Path "./WindowsMelodyRecovery.psm1") {
        "./WindowsMelodyRecovery.psm1"
    } elseif (Test-Path "/workspace/WindowsMelodyRecovery.psm1") {
        "/workspace/WindowsMelodyRecovery.psm1"
    } else {
        throw "Cannot find WindowsMelodyRecovery.psm1 module"
    }
    Import-Module $ModulePath -Force

    # Dot-source ApplicationState.ps1 to ensure all functions are available
    . "$PSScriptRoot/../../Private/Core/ApplicationState.ps1"

    # Setup a temporary directory for state files
    $script:TempStateDir = Join-Path $PSScriptRoot "..\..\Temp\ApplicationStateTests"
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

    # Define a simple parse script that works with the mock data
    $script:CommonParseScript = 'param([string]$InputObject)
$apps = @()
$lines = $InputObject -split "`n"
foreach ($line in $lines) {
    $parts = $line -split "\s+"
    if ($parts.Count -ge 3) {
        $apps += @{ Name = $parts[0]; Id = $parts[1]; Version = $parts[2] }
    }
}
$apps | ConvertTo-Json -Compress'

    # Define a simple install script that uses the test directory
    $script:CommonInstallScript = "param([string]`$AppListJson)
`$apps = `$AppListJson | ConvertFrom-Json
foreach (`$app in `$apps) {
    Write-Host `"Simulating install of `$(`$app.Name) (ID: `$(`$app.Id), Version: `$(`$app.Version))`"
    Set-Content -Path (Join-Path '$script:InstalledAppsDir' `"`$(`$app.Id).installed`") -Value `"Installed`" -Force
}"

    # Define a simple uninstall script that uses the test directory
    $script:CommonUninstallScript = "param([string]`$AppListJson)
`$apps = `$AppListJson | ConvertFrom-Json
foreach (`$app in `$apps) {
    Write-Host `"Simulating uninstall of `$(`$app.Name) (ID: `$(`$app.Id))`"
    Remove-Item -Path (Join-Path '$script:InstalledAppsDir' `"`$(`$app.Id).installed`") -ErrorAction SilentlyContinue
}"
}

AfterAll {
    # Clean up temporary directories
    Remove-Item -Path $script:TempStateDir -Recurse -Force -ErrorAction SilentlyContinue
}

Describe "Get-WmrApplicationState" {

    It "should discover and parse winget applications" {
        # Mock Invoke-Expression for winget list
        Mock Invoke-Expression {
            param($Command)
            if ($Command -eq "winget list --source winget") {
                return @"
Name                 Id               Version
------------------------------------------------
Microsoft Edge       Microsoft.Edge   100.0.1
Windows Terminal     Microsoft.WindowsTerminal 1.0.0
Package A            App.PackageA     1.2.3
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
        $content[0].Name | Should -Be "Microsoft"
        $content[1].Id | Should -Be "Microsoft.WindowsTerminal"
        $content[2].Version | Should -Be "1.2.3"
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

        Get-WmrApplicationState -AppConfig $appConfig -StateFilesDirectory $script:TempStateDir

        $stateFilePath = Join-Path $script:TempStateDir "apps/empty_winget_list.json"
        (Test-Path $stateFilePath) | Should -Be $true
        $content = (Get-Content -Path $stateFilePath -Raw -Encoding Utf8) | ConvertFrom-Json
        $content.Count | Should -Be 0
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

        { Get-WmrApplicationState -AppConfig $appConfig -StateFilesDirectory $script:TempStateDir } | Should -Not -Throw
        (Test-Path (Join-Path $script:TempStateDir "apps/failing_discovery.json")) | Should -Be $false
    }
}

Describe "Set-WmrApplicationState" {

    It "should install applications from state file using install_script" {
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

    It "should warn if state file does not exist" {
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

Describe "Uninstall-WmrApplicationState" {

    It "should uninstall applications from state file using uninstall_script" {
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

    It "should warn if uninstall_script is not defined" {
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