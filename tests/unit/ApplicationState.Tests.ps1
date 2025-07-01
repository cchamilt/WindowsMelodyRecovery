# tests/unit/ApplicationState.Tests.ps1

BeforeAll {
    # Import the WindowsMelodyRecovery module to make functions available
    Import-Module WindowsMelodyRecovery -Force

    # Setup a temporary directory for state files
    $script:TempStateDir = Join-Path $PSScriptRoot "..\..\Temp\ApplicationStateTests"
    if (-not (Test-Path $script:TempStateDir -PathType Container)) {
        New-Item -ItemType Directory -Path $script:TempStateDir -Force | Out-Null
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

    # Define a common parse script for mocking purposes
    $script:CommonParseScript = @"
param([string]$InputObject)
$apps = @()
$lines = $InputObject -split "`n"
# Skip headers, process lines like "Name  ID  Version"
foreach ($line in $lines) {
    if ($line -match '^(?<Name>.+?)\s{2,}(?<Id>\S+)\s{2,}(?<Version>\S+)$') {
        $apps += @{ Name = $($Matches.Name.Trim()); Id = $($Matches.Id); Version = $($Matches.Version) }
    }
}
$apps | ConvertTo-Json -Compress
"@

    # Define a common install script for mocking purposes
    $script:CommonInstallScript = @"
param([string]$AppListJson)
$apps = $AppListJson | ConvertFrom-Json
foreach ($app in $apps) {
    Write-Host "Simulating install of $($app.Name) (ID: $($app.Id), Version: $($app.Version))"
    # Add a dummy file to simulate installation success
    New-Item -Path (Join-Path (Get-Item -Path $PSScriptRoot).Parent.Parent "InstalledApps") -ItemType Directory -Force | Out-Null
    Set-Content -Path (Join-Path (Join-Path (Get-Item -Path $PSScriptRoot).Parent.Parent "InstalledApps") "$($app.Id).installed") -Value "Installed" -Force
}
"@

    # Define a common uninstall script for mocking purposes
    $script:CommonUninstallScript = @"
param([string]$AppListJson)
$apps = $AppListJson | ConvertFrom-Json
foreach ($app in $apps) {
    Write-Host "Simulating uninstall of $($app.Name) (ID: $($app.Id))"
    # Remove the dummy file to simulate uninstallation
    Remove-Item -Path (Join-Path (Join-Path (Get-Item -Path $PSScriptRoot).Parent.Parent "InstalledApps") "$($app.Id).installed") -ErrorAction SilentlyContinue
}
"@
}

AfterAll {
    # Clean up temporary directories and dummy installed app files
    Remove-Item -Path $script:TempStateDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path (Join-Path (Get-Item -Path $PSScriptRoot).Parent.Parent "InstalledApps") -Recurse -Force -ErrorAction SilentlyContinue

    # Unmock functions
    # Note: In Pester 5+, mocks are automatically cleaned up
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
        (Test-Path $stateFilePath) | Should Be $true
        $content = (Get-Content -Path $stateFilePath -Raw -Encoding Utf8) | ConvertFrom-Json

        $content.Count | Should Be 3
        $content[0].Name | Should Be "Microsoft Edge"
        $content[1].Id | Should Be "Microsoft.WindowsTerminal"
        $content[2].Version | Should Be "1.2.3"

        # Unmock not needed in Pester 5+
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
        (Test-Path $stateFilePath) | Should Be $true
        $content = (Get-Content -Path $stateFilePath -Raw -Encoding Utf8) | ConvertFrom-Json
        $content.Count | Should Be 0

        # Unmock not needed in Pester 5+
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

        { Get-WmrApplicationState -AppConfig $appConfig -StateFilesDirectory $script:TempStateDir } | Should Not Throw # Should emit a warning
        (Test-Path (Join-Path $script:TempStateDir "apps/failing_discovery.json")) | Should Be $false # No state file should be created

        # Unmock not needed in Pester 5+
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
        (Test-Path (Join-Path (Join-Path (Get-Item -Path $PSScriptRoot).Parent.Parent "InstalledApps") "Test.App1.installed")) | Should Be $true
        (Test-Path (Join-Path (Join-Path (Get-Item -Path $PSScriptRoot).Parent.Parent "InstalledApps") "Test.App2.installed")) | Should Be $true
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

        { Set-WmrApplicationState -AppConfig $appConfig -StateFilesDirectory $script:TempStateDir } | Should Not Throw # Should emit a warning
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
        (Test-Path (Join-Path (Join-Path (Get-Item -Path $PSScriptRoot).Parent.Parent "InstalledApps") "App.Uninstall.installed")) | Should Be $true

        # Now, perform uninstallation
        Uninstall-WmrApplicationState -AppConfig $initialAppConfig -StateFilesDirectory $script:TempStateDir

        # Verify simulation of uninstallation by checking dummy files
        (Test-Path (Join-Path (Join-Path (Get-Item -Path $PSScriptRoot).Parent.Parent "InstalledApps") "App.Uninstall.installed")) | Should Be $false
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

        { Uninstall-WmrApplicationState -AppConfig $appConfig -StateFilesDirectory $script:TempStateDir } | Should Not Throw # Should emit a warning
    }
} 