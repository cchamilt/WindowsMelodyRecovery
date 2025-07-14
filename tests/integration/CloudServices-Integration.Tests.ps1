# tests/integration/CloudServices-Integration.Tests.ps1

<#
.SYNOPSIS
    Consolidated integration tests for all cloud service functionality.

.DESCRIPTION
    Tests all aspects of cloud provider integration, including:
    - Provider detection and path resolution
    - Simulated backup and restore workflows
    - Mocked connectivity and failover logic

.NOTES
    This file consolidates the logic from three previous test files:
    - cloud-provider-detection.Tests.ps1
    - cloud-backup-restore.Tests.ps1
    - cloud-connectivity.Tests.ps1
#>

BeforeAll {
    # Import the unified test environment library and initialize it for Integration tests.
    . (Join-Path $PSScriptRoot "..\utilities\Test-Environment.ps1")
    $script:TestEnvironment = Initialize-WmrTestEnvironment -SuiteName 'Integration'

    # Import the main module to make functions available for testing.
    Import-Module (Join-Path $script:TestEnvironment.ModuleRoot "WindowsMelodyRecovery.psd1") -Force

    # Import mock cloud provider functions
    . (Join-Path $script:TestEnvironment.ModuleRoot "tests/mock-data/cloud/cloud-provider-detection.ps1")

    # Use paths from the initialized environment
    $script:TestRoot = $script:TestEnvironment.TestRoot
    $script:TestBackupRoot = $script:TestEnvironment.TestBackup
    $script:TestRestoreRoot = $script:TestEnvironment.TestRestore

    # Create common test data for backup/restore tests
    $script:TestData = @{
        "system_settings.json" = @{ display = @{ resolution = "1920x1080" } } | ConvertTo-Json;
        "applications.json"    = @{ installed = @( @{ name = "VSCode" } ) } | ConvertTo-Json;
    }
    foreach ($file in $script:TestData.Keys) {
        $filePath = Join-Path $script:TestBackupRoot $file
        $script:TestData[$file] | Out-File -FilePath $filePath -Encoding UTF8
    }
}

AfterAll {
    # Clean up the test environment created in BeforeAll.
    Remove-WmrTestEnvironment
}

Describe "Cloud Services Integration Tests" -Tag "Integration", "Cloud" {

    Context "Cloud Provider Detection & Path Resolution" {
        # Tests from cloud-provider-detection.Tests.ps1
        It "Should detect all expected providers" {
            $providers = Get-MockCloudProviders
            $providerNames = $providers | ForEach-Object { $_.Name }
            $providerNames | Should -Contain "OneDrive"
            $providerNames | Should -Contain "GoogleDrive"
            $providerNames.Count | Should -BeGreaterOrEqual 5
        }

        It "Should resolve paths correctly for all providers" {
            $providers = Get-MockCloudProviders
            foreach ($provider in $providers) {
                $provider.LocalPath | Should -Not -BeNullOrEmpty
                $provider.BackupPath | Should -Not -BeNullOrEmpty
                $provider.BackupPath | Should -Match "WindowsMelodyRecovery"
            }
        }
    }

    Context "Cloud Backup and Restore Workflows" {
        # Tests from cloud-backup-restore.Tests.ps1
        It "Should backup and restore data for OneDrive" {
            $oneDrive = (Get-MockCloudProviders) | Where-Object { $_.Name -eq "OneDrive" }
            $backupPath = Join-Path $oneDrive.BackupPath "TestBackup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            New-Item -Path $backupPath -ItemType Directory -Force | Out-Null
            Copy-Item -Path "$($script:TestBackupRoot)\*" -Destination $backupPath -Recurse
            Test-Path (Join-Path $backupPath "system_settings.json") | Should -Be $true

            $restorePath = Join-Path $script:TestRestoreRoot "OneDrive-Restore"
            New-Item -Path $restorePath -ItemType Directory -Force | Out-Null
            Copy-Item -Path "$($backupPath)\*" -Destination $restorePath -Recurse
            Test-Path (Join-Path $restorePath "system_settings.json") | Should -Be $true
            (Get-Content (Join-Path $restorePath "system_settings.json")) | Should -Be (Get-Content (Join-Path $script:TestBackupRoot "system_settings.json"))
        }

        It "Should backup and restore data for Google Drive" {
            $googleDrive = (Get-MockCloudProviders) | Where-Object { $_.Name -eq "GoogleDrive" }
            $backupPath = Join-Path $googleDrive.BackupPath "TestBackup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            New-Item -Path $backupPath -ItemType Directory -Force | Out-Null
            Copy-Item -Path "$($script:TestBackupRoot)\*" -Destination $backupPath -Recurse
            Test-Path (Join-Path $backupPath "applications.json") | Should -Be $true

            $restorePath = Join-Path $script:TestRestoreRoot "GoogleDrive-Restore"
            New-Item -Path $restorePath -ItemType Directory -Force | Out-Null
            Copy-Item -Path "$($backupPath)\*" -Destination $restorePath -Recurse
            Test-Path (Join-Path $restorePath "applications.json") | Should -Be $true
            (Get-Content (Join-Path $restorePath "applications.json")) | Should -Be (Get-Content (Join-Path $script:TestBackupRoot "applications.json"))
        }
    }

    Context "Cloud Connectivity and Failover" {
        # Tests from cloud-connectivity.Tests.ps1
        It "Should test connectivity for all providers" {
            $providers = Get-MockCloudProviders
            foreach ($provider in $providers) {
                $result = Test-CloudProviderConnectivity -ProviderName $provider.Name
                $result | Should -Not -BeNullOrEmpty
                $result.Available | Should -Be $true
            }
        }

        It "Should return a prioritized failover order" {
            $failoverOrder = Get-CloudProviderFailoverOrder
            $failoverOrder | Should -Not -BeNullOrEmpty
            $failoverOrder.Count | Should -BeGreaterThan 0
            $failoverOrder[0].Available | Should -Be $true
        }

        It "Should handle non-existent provider gracefully" {
            $result = Test-CloudProviderConnectivity -ProviderName "NonExistentProvider"
            $result.Available | Should -Be $false
            $result.Error | Should -Match "Provider not found"
        }
    }
}
