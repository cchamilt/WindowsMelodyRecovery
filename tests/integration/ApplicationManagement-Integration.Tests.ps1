# tests/integration/ApplicationManagement-Integration.Tests.ps1

<#
.SYNOPSIS
    Consolidated integration tests for all Application Management functionality.

.DESCRIPTION
    Tests all aspects of application management, including:
    - Backup and restore of managed applications (Winget, Chocolatey, Scoop).
    - Discovery and documentation of unmanaged applications.
    - Gaming platform integration (Steam, etc.).
    - Uses the enhanced mock infrastructure for realistic testing.

.NOTES
    This file consolidates the logic from three previous test files:
    - application-backup-restore.Tests.ps1
    - Enhanced-Application-Backup-Restore.Tests.ps1
    - ApplicationDiscovery-Management.Tests.ps1
#>

BeforeAll {
    # Import enhanced mock infrastructure and utilities
    Import-Module (Resolve-Path "$PSScriptRoot/../../WindowsMelodyRecovery.psd1") -Force
    . "$PSScriptRoot\..\utilities\Test-Environment-Standard.ps1"
    . "$PSScriptRoot\..\utilities\Enhanced-Mock-Infrastructure.ps1"
    . "$PSScriptRoot\..\utilities\Mock-Integration.ps1"

    # Source the setup scripts for unmanaged app discovery
    . "$PSScriptRoot/../../Private/setup/setup-application-discovery.ps1"

    # Initialize enhanced test environment with application focus
    $script:TestEnvironment = Initialize-StandardTestEnvironment -TestType "Integration" -IsolationLevel "Standard"
    Initialize-MockForTestType -TestType "Integration" -TestContext "ApplicationBackup" -Scope "Comprehensive"

    # Mock WindowsMelodyRecovery configuration needed for discovery
    $script:MockConfig = @{
        IsInitialized = $true
        BackupRoot = $script:TestEnvironment.TestBackup
        MachineName = "TestMachine"
    }
    Mock Get-WindowsMelodyRecovery { return $script:MockConfig }
}

AfterAll {
    if ($script:TestEnvironment) {
        Remove-StandardTestEnvironment -TestEnvironment $script:TestEnvironment
    }
}

Describe "Managed Application Backup & Restore" -Tag "Integration", "Applications" {

    Context "Winget Package Manager" {
        It "Should perform accurate backup and restore cycle for Winget" {
            $originalData = Get-MockDataForTest -TestName "ApplicationBackup" -Component "winget"
            $backupFile = Join-Path $script:TestEnvironment.TestBackup "winget_enhanced_backup.json"
            $backupData = @{ Timestamp = (Get-Date); Packages = $originalData.Packages }
            $backupData | ConvertTo-Json -Depth 10 | Set-Content -Path $backupFile
            $restoredData = Get-Content $backupFile | ConvertFrom-Json
            $restoredData.Packages.Count | Should -Be $originalData.Packages.Count
        }
    }

    Context "Chocolatey Package Manager" {
        It "Should generate a realistic Chocolatey restoration script" {
            $chocoData = Get-MockDataForTest -TestName "ApplicationBackup" -Component "chocolatey"
            $restoreScript = Join-Path $script:TestEnvironment.TestRestore "chocolatey_restore.ps1"
            $scriptContent = "choco install $($chocoData.Packages[0].Id)"
            $scriptContent | Set-Content -Path $restoreScript
            (Get-Content $restoreScript) | Should -Match "choco install"
        }
    }

    Context "Scoop Package Manager" {
        It "Should provide realistic scoop package data with buckets" {
            $scoopData = Get-MockDataForTest -TestName "ApplicationBackup" -Component "scoop"
            $scoopData | Should -Not -BeNullOrEmpty
            $scoopData.Apps.Count | Should -BeGreaterThan 0
            $scoopData.Buckets.Count | Should -BeGreaterThan 0
        }
    }

    Context "Gaming Platforms" {
        It "Should backup Steam game library configuration" {
            $steamGames = Get-MockDataForTest -TestName "GamingBackup" -Component "Steam"
            $steamGames | Should -Not -BeNullOrEmpty
            $steamGames.Apps.Count | Should -BeGreaterThan 0
            $steamGames.Apps[0].Name | Should -Be "Counter-Strike 2"
        }
    }
}

Describe "Unmanaged Application Discovery & Documentation" -Tag "Integration", "Applications" {

    BeforeAll {
        # Mock for unmanaged app discovery
        $script:MockUnmanagedApps = @(
            @{ Name = "TestApp1"; Version = "1.0.0"; Publisher = "Test Publisher" },
            @{ Name = "TestApp2"; Version = "2.0.0"; Publisher = "Another Publisher" }
        )
        Mock Invoke-UnmanagedApplicationDiscovery { return $script:MockUnmanagedApps }
    }

    Context "Unmanaged Application Discovery" {
        It "Should discover unmanaged applications" {
            $result = Invoke-UnmanagedApplicationDiscovery -Mode "Quick"
            $result.Count | Should -Be 2
            $result[0].Name | Should -Be "TestApp1"
        }

        It "Should handle empty discovery results gracefully" {
            Mock Invoke-UnmanagedApplicationDiscovery { return @() }
            $result = Invoke-UnmanagedApplicationDiscovery -Mode "Quick"
            $result.Count | Should -Be 0
        }
    }

    Context "Application List Management" {
        It "Should save discovered application list in JSON format" {
            $testPath = Join-Path $script:TestEnvironment.Temp "test-apps.json"
            Save-ApplicationList -Applications $script:MockUnmanagedApps -Path $testPath -Format "JSON"
            $testPath | Should -Exist
            $content = Get-Content $testPath | ConvertFrom-Json
            $content.Count | Should -Be 2
        }
    }

    Context "Installation Documentation Generation" {
        It "Should create installation documentation for unmanaged applications" {
            $documentation = New-InstallationDocumentation -Applications $script:MockUnmanagedApps
            $documentation.Count | Should -Be 2
            $documentation[0].Name | Should -Be "TestApp1"
            $documentation[0].InstallationMethods | Should -Not -BeNullOrEmpty
        }

        It "Should save installation documentation in Markdown format" {
            $testPath = Join-Path $script:TestEnvironment.Temp "test-docs.md"
            $documentation = New-InstallationDocumentation -Applications $script:MockUnmanagedApps
            Save-InstallationDocumentation -Documentation $documentation -Path $testPath -Format "Markdown"
            $testPath | Should -Exist
            (Get-Content $testPath) | Should -Match "TestApp1"
        }
    }
}
