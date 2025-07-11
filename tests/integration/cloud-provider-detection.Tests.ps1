#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Integration tests for cloud provider detection and path resolution

.DESCRIPTION
    Tests cloud provider detection, path resolution, connectivity testing,
    and failover scenarios for all supported cloud storage providers.
#>

Describe "Cloud Provider Detection and Path Resolution Tests" {
    BeforeAll {
        # Import the module with standardized pattern
        try {
            $ModulePath = Resolve-Path "$PSScriptRoot/../../WindowsMelodyRecovery.psd1"
            Import-Module $ModulePath -Force -ErrorAction Stop
        } catch {
            throw "Cannot find or import WindowsMelodyRecovery module: $($_.Exception.Message)"
        }

        # Import cloud provider detection functions
        $CloudDetectionScript = if (Test-Path "$PSScriptRoot\..\mock-data\cloud\cloud-provider-detection.ps1") {
            "$PSScriptRoot\..\mock-data\cloud\cloud-provider-detection.ps1"
        } elseif (Test-Path "/workspace/tests/mock-data/cloud/cloud-provider-detection.ps1") {
            "/workspace/tests/mock-data/cloud/cloud-provider-detection.ps1"
        } else {
            throw "Cannot find cloud-provider-detection.ps1 script"
        }
        . $CloudDetectionScript

        # Set up test environment
        $script:MockCloudRoot = if (Test-Path "/workspace/tests/mock-data/cloud") {
            "/workspace/tests/mock-data/cloud"
        } else {
            "$PSScriptRoot\..\mock-data\cloud"
        }

        # Ensure mock cloud providers exist
        $requiredProviders = @("OneDrive", "GoogleDrive", "Dropbox", "Box", "Custom")
        foreach ($provider in $requiredProviders) {
            $providerPath = Join-Path $script:MockCloudRoot $provider
            if (-not (Test-Path $providerPath)) {
                New-Item -Path $providerPath -ItemType Directory -Force | Out-Null
                New-Item -Path (Join-Path $providerPath "WindowsMelodyRecovery") -ItemType Directory -Force | Out-Null
            }
        }
    }

    Context "Cloud Provider Detection" {
        It "Should detect OneDrive provider" {
            $providers = Get-MockCloudProviders
            $oneDrive = $providers | Where-Object { $_.Name -eq "OneDrive" }

            $oneDrive | Should -Not -BeNullOrEmpty
            $oneDrive.Name | Should -Be "OneDrive"
            $oneDrive.Type | Should -Be "personal"
            $oneDrive.Available | Should -Be $true
        }

        It "Should detect Google Drive provider" {
            $providers = Get-MockCloudProviders
            $googleDrive = $providers | Where-Object { $_.Name -eq "GoogleDrive" }

            $googleDrive | Should -Not -BeNullOrEmpty
            $googleDrive.Name | Should -Be "GoogleDrive"
            $googleDrive.Type | Should -Be "personal"
            $googleDrive.Available | Should -Be $true
        }

        It "Should detect Dropbox provider" {
            $providers = Get-MockCloudProviders
            $dropbox = $providers | Where-Object { $_.Name -eq "Dropbox" }

            $dropbox | Should -Not -BeNullOrEmpty
            $dropbox.Name | Should -Be "Dropbox"
            $dropbox.Type | Should -Be "personal"
            $dropbox.Available | Should -Be $true
        }

        It "Should detect Box provider" {
            $providers = Get-MockCloudProviders
            $box = $providers | Where-Object { $_.Name -eq "Box" }

            $box | Should -Not -BeNullOrEmpty
            $box.Name | Should -Be "Box"
            $box.Type | Should -Be "business"
            $box.Available | Should -Be $true
        }

        It "Should detect Custom provider" {
            $providers = Get-MockCloudProviders
            $custom = $providers | Where-Object { $_.Name -eq "Custom" }

            $custom | Should -Not -BeNullOrEmpty
            $custom.Name | Should -Be "Custom"
            $custom.Type | Should -Be "custom"
            $custom.Available | Should -Be $true
        }

        It "Should detect all expected providers" {
            $providers = Get-MockCloudProviders
            $providerNames = $providers | ForEach-Object { $_.Name }

            $providerNames | Should -Contain "OneDrive"
            $providerNames | Should -Contain "GoogleDrive"
            $providerNames | Should -Contain "Dropbox"
            $providerNames | Should -Contain "Box"
            $providerNames | Should -Contain "Custom"
            $providers.Count | Should -BeGreaterOrEqual 5
        }
    }

    Context "Path Resolution" {
        It "Should resolve OneDrive paths correctly" {
            $providers = Get-MockCloudProviders
            $oneDrive = $providers | Where-Object { $_.Name -eq "OneDrive" }

            $oneDrive.LocalPath | Should -Not -BeNullOrEmpty
            $oneDrive.BackupPath | Should -Not -BeNullOrEmpty
            $oneDrive.LocalPath | Should -Match "OneDrive"
            $oneDrive.BackupPath | Should -Match "WindowsMelodyRecovery"
        }

        It "Should resolve Google Drive paths correctly" {
            $providers = Get-MockCloudProviders
            $googleDrive = $providers | Where-Object { $_.Name -eq "GoogleDrive" }

            $googleDrive.LocalPath | Should -Not -BeNullOrEmpty
            $googleDrive.BackupPath | Should -Not -BeNullOrEmpty
            $googleDrive.LocalPath | Should -Match "Google Drive"
            $googleDrive.BackupPath | Should -Match "WindowsMelodyRecovery"
        }

        It "Should resolve Dropbox paths correctly" {
            $providers = Get-MockCloudProviders
            $dropbox = $providers | Where-Object { $_.Name -eq "Dropbox" }

            $dropbox.LocalPath | Should -Not -BeNullOrEmpty
            $dropbox.BackupPath | Should -Not -BeNullOrEmpty
            $dropbox.LocalPath | Should -Match "Dropbox"
            $dropbox.BackupPath | Should -Match "WindowsMelodyRecovery"
        }

        It "Should resolve Box paths correctly" {
            $providers = Get-MockCloudProviders
            $box = $providers | Where-Object { $_.Name -eq "Box" }

            $box.LocalPath | Should -Not -BeNullOrEmpty
            $box.BackupPath | Should -Not -BeNullOrEmpty
            $box.LocalPath | Should -Match "Box"
            $box.BackupPath | Should -Match "WindowsMelodyRecovery"
        }

        It "Should resolve Custom paths correctly" {
            $providers = Get-MockCloudProviders
            $custom = $providers | Where-Object { $_.Name -eq "Custom" }

            $custom.LocalPath | Should -Not -BeNullOrEmpty
            $custom.BackupPath | Should -Not -BeNullOrEmpty
            $custom.LocalPath | Should -Match "CustomCloud"
            $custom.BackupPath | Should -Match "WindowsMelodyRecovery"
        }
    }

    Context "Storage Information" {
        It "Should provide storage information for all providers" {
            $providers = Get-MockCloudProviders

            foreach ($provider in $providers) {
                $provider.StorageUsed | Should -Not -BeNullOrEmpty
                $provider.StorageTotal | Should -Not -BeNullOrEmpty
                $provider.StorageUsed | Should -Match "TB|GB|MB"
                $provider.StorageTotal | Should -Match "TB|GB|MB"
            }
        }

        It "Should provide realistic storage sizes" {
            $providers = Get-MockCloudProviders
            $oneDrive = $providers | Where-Object { $_.Name -eq "OneDrive" }
            $googleDrive = $providers | Where-Object { $_.Name -eq "GoogleDrive" }
            $dropbox = $providers | Where-Object { $_.Name -eq "Dropbox" }

            # OneDrive should have TB storage
            $oneDrive.StorageTotal | Should -Match "TB"

            # Google Drive should have GB storage
            $googleDrive.StorageTotal | Should -Match "GB"

            # Dropbox should have TB storage
            $dropbox.StorageTotal | Should -Match "TB"
        }
    }

    Context "Sync Status Detection" {
        It "Should detect sync status for all providers" {
            $providers = Get-MockCloudProviders

            foreach ($provider in $providers) {
                $provider.SyncStatus | Should -Not -BeNullOrEmpty
                $provider.SyncStatus | Should -BeIn @("up_to_date", "syncing", "paused", "error")
            }
        }

        It "Should provide last sync information" {
            $providers = Get-MockCloudProviders

            foreach ($provider in $providers) {
                $provider.LastSync | Should -Not -BeNullOrEmpty
                $provider.LastSync | Should -Match "^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$"
            }
        }
    }

    Context "Provider Features" {
        It "Should list features for OneDrive" {
            $providers = Get-MockCloudProviders
            $oneDrive = $providers | Where-Object { $_.Name -eq "OneDrive" }

            $oneDrive.Features | Should -Not -BeNullOrEmpty
            $oneDrive.Features.files_on_demand | Should -Not -BeNullOrEmpty
            $oneDrive.Features.version_history | Should -Not -BeNullOrEmpty
        }

        It "Should list features for Google Drive" {
            $providers = Get-MockCloudProviders
            $googleDrive = $providers | Where-Object { $_.Name -eq "GoogleDrive" }

            $googleDrive.Features | Should -Not -BeNullOrEmpty
            $googleDrive.Features.offline_access | Should -Not -BeNullOrEmpty
            $googleDrive.Features.version_history | Should -Not -BeNullOrEmpty
        }

        It "Should list features for Dropbox" {
            $providers = Get-MockCloudProviders
            $dropbox = $providers | Where-Object { $_.Name -eq "Dropbox" }

            $dropbox.Features | Should -Not -BeNullOrEmpty
            $dropbox.Features.smart_sync | Should -Not -BeNullOrEmpty
            $dropbox.Features.version_history | Should -Not -BeNullOrEmpty
        }
    }

    Context "Account Information" {
        It "Should provide account information for all providers" {
            $providers = Get-MockCloudProviders

            foreach ($provider in $providers) {
                $provider.Account | Should -Not -BeNullOrEmpty
                $provider.Account.email | Should -Not -BeNullOrEmpty
                $provider.Account.name | Should -Not -BeNullOrEmpty
                $provider.Account.id | Should -Not -BeNullOrEmpty
            }
        }

        It "Should have realistic account information" {
            $providers = Get-MockCloudProviders
            $oneDrive = $providers | Where-Object { $_.Name -eq "OneDrive" }
            $googleDrive = $providers | Where-Object { $_.Name -eq "GoogleDrive" }

            $oneDrive.Account.email | Should -Match "@outlook\.com$"
            $googleDrive.Account.email | Should -Match "@gmail\.com$"
        }
    }
}