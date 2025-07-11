#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Integration tests for cloud provider connectivity and failover

.DESCRIPTION
    Tests cloud provider connectivity, failover scenarios, and backup/restore
    operations across multiple cloud storage providers.
#>

Describe "Cloud Provider Connectivity Tests" {
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
        $script:TestBackupRoot = if ($env:TEMP) {
            Join-Path $env:TEMP "WMR-Cloud-Tests"
        } else {
            "/tmp/WMR-Cloud-Tests"
        }

        New-Item -Path $script:TestBackupRoot -ItemType Directory -Force | Out-Null
    }

    Context "Individual Provider Connectivity" {
        It "Should test OneDrive connectivity" {
            $result = Test-CloudProviderConnectivity -ProviderName "OneDrive"

            $result | Should -Not -BeNullOrEmpty
            $result.Provider | Should -Be "OneDrive"
            $result.Available | Should -Be $true
            $result.ResponseTime | Should -BeGreaterThan 0
            $result.TestTime | Should -Match "^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$"
        }

        It "Should test Google Drive connectivity" {
            $result = Test-CloudProviderConnectivity -ProviderName "GoogleDrive"

            $result | Should -Not -BeNullOrEmpty
            $result.Provider | Should -Be "GoogleDrive"
            $result.Available | Should -Be $true
            $result.ResponseTime | Should -BeGreaterThan 0
            $result.TestTime | Should -Match "^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$"
        }

        It "Should test Dropbox connectivity" {
            $result = Test-CloudProviderConnectivity -ProviderName "Dropbox"

            $result | Should -Not -BeNullOrEmpty
            $result.Provider | Should -Be "Dropbox"
            $result.Available | Should -Be $true
            $result.ResponseTime | Should -BeGreaterThan 0
            $result.TestTime | Should -Match "^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$"
        }

        It "Should test Box connectivity" {
            $result = Test-CloudProviderConnectivity -ProviderName "Box"

            $result | Should -Not -BeNullOrEmpty
            $result.Provider | Should -Be "Box"
            $result.Available | Should -Be $true
            $result.ResponseTime | Should -BeGreaterThan 0
            $result.TestTime | Should -Match "^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$"
        }

        It "Should test Custom provider connectivity" {
            $result = Test-CloudProviderConnectivity -ProviderName "Custom"

            $result | Should -Not -BeNullOrEmpty
            $result.Provider | Should -Be "Custom"
            $result.Available | Should -Be $true
            $result.ResponseTime | Should -BeGreaterThan 0
            $result.TestTime | Should -Match "^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$"
        }

        It "Should handle non-existent provider gracefully" {
            $result = Test-CloudProviderConnectivity -ProviderName "NonExistentProvider"

            $result | Should -Not -BeNullOrEmpty
            $result.Provider | Should -Be "NonExistentProvider"
            $result.Available | Should -Be $false
            $result.Error | Should -Match "Provider not found"
        }
    }

    Context "Failover Order and Priority" {
        It "Should return prioritized failover order" {
            $failoverOrder = Get-CloudProviderFailoverOrder

            $failoverOrder | Should -Not -BeNullOrEmpty
            $failoverOrder.Count | Should -BeGreaterThan 0

            # First provider should be available
            $failoverOrder[0].Available | Should -Be $true
        }

        It "Should prioritize providers with higher storage" {
            $failoverOrder = Get-CloudProviderFailoverOrder

            # Find providers with TB storage
            $tbProviders = $failoverOrder | Where-Object { $_.StorageTotal -match "TB" }
            $gbProviders = $failoverOrder | Where-Object { $_.StorageTotal -match "GB" -and $_.StorageTotal -notmatch "TB" }

            if ($tbProviders.Count -gt 0 -and $gbProviders.Count -gt 0) {
                # TB providers should generally come before GB providers
                $firstTbIndex = $failoverOrder.IndexOf($tbProviders[0])
                $firstGbIndex = $failoverOrder.IndexOf($gbProviders[0])

                $firstTbIndex | Should -BeLessThan $firstGbIndex
            }
        }

        It "Should prioritize up-to-date providers over syncing providers" {
            $failoverOrder = Get-CloudProviderFailoverOrder

            $upToDateProviders = $failoverOrder | Where-Object { $_.SyncStatus -eq "up_to_date" }
            $syncingProviders = $failoverOrder | Where-Object { $_.SyncStatus -eq "syncing" }

            if ($upToDateProviders.Count -gt 0 -and $syncingProviders.Count -gt 0) {
                # Up-to-date providers should generally come before syncing providers
                $firstUpToDateIndex = $failoverOrder.IndexOf($upToDateProviders[0])
                $firstSyncingIndex = $failoverOrder.IndexOf($syncingProviders[0])

                $firstUpToDateIndex | Should -BeLessThan $firstSyncingIndex
            }
        }
    }

    Context "Batch Connectivity Testing" {
        It "Should test all providers in batch" {
            $providers = Get-MockCloudProviders
            $results = @()

            foreach ($provider in $providers) {
                $result = Test-CloudProviderConnectivity -ProviderName $provider.Name
                $results += $result
            }

            $results.Count | Should -Be $providers.Count

            # All results should have required properties
            foreach ($result in $results) {
                $result.Provider | Should -Not -BeNullOrEmpty
                $result.Available | Should -Not -BeNullOrEmpty
                $result.TestTime | Should -Not -BeNullOrEmpty
            }
        }

        It "Should identify fastest responding provider" {
            $providers = Get-MockCloudProviders
            $results = @()

            foreach ($provider in $providers) {
                $result = Test-CloudProviderConnectivity -ProviderName $provider.Name
                if ($result.Available) {
                    $results += $result
                }
            }

            $results.Count | Should -BeGreaterThan 0

            # Find fastest provider
            $fastestProvider = $results | Sort-Object ResponseTime | Select-Object -First 1
            $fastestProvider.ResponseTime | Should -BeGreaterThan 0
            $fastestProvider.ResponseTime | Should -BeLessThan 1000  # Should be reasonable response time
        }
    }

    Context "Error Handling and Edge Cases" {
        It "Should handle connectivity test with null provider name" {
            { Test-CloudProviderConnectivity -ProviderName $null } | Should -Throw
        }

        It "Should handle connectivity test with empty provider name" {
            { Test-CloudProviderConnectivity -ProviderName "" } | Should -Throw
        }

        It "Should handle provider detection when directories are missing" {
            # Temporarily rename a provider directory
            $mockCloudRoot = if (Test-Path "/workspace/tests/mock-data/cloud") {
                "/workspace/tests/mock-data/cloud"
            } else {
                "$PSScriptRoot\..\mock-data\cloud"
            }

            $testProviderPath = Join-Path $mockCloudRoot "TestProvider"
            $hiddenProviderPath = Join-Path $mockCloudRoot "TestProvider_Hidden"

            if (Test-Path $testProviderPath) {
                Rename-Item -Path $testProviderPath -NewName "TestProvider_Hidden"
            }

            try {
                $providers = Get-MockCloudProviders
                $testProvider = $providers | Where-Object { $_.Name -eq "TestProvider" }
                $testProvider | Should -BeNullOrEmpty
            } finally {
                # Restore the directory if it was renamed
                if (Test-Path $hiddenProviderPath) {
                    Rename-Item -Path $hiddenProviderPath -NewName "TestProvider"
                }
            }
        }
    }

    Context "Performance and Reliability" {
        It "Should complete provider detection within reasonable time" {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $providers = Get-MockCloudProviders
            $stopwatch.Stop()

            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 5000  # Should complete within 5 seconds
            $providers.Count | Should -BeGreaterThan 0
        }

        It "Should complete connectivity tests within reasonable time" {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $result = Test-CloudProviderConnectivity -ProviderName "OneDrive"
            $stopwatch.Stop()

            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 3000  # Should complete within 3 seconds
            $result | Should -Not -BeNullOrEmpty
        }

        It "Should handle multiple concurrent connectivity tests" {
            $providers = Get-MockCloudProviders | Select-Object -First 3  # Test first 3 providers
            $jobs = @()

            foreach ($provider in $providers) {
                $job = Start-Job -ScriptBlock {
                    param($ProviderName, $ScriptPath)
                    . $ScriptPath
                    Test-CloudProviderConnectivity -ProviderName $ProviderName
                } -ArgumentList $provider.Name, $CloudDetectionScript
                $jobs += $job
            }

            # Wait for all jobs to complete
            $results = $jobs | Wait-Job | Receive-Job
            $jobs | Remove-Job

            $results.Count | Should -Be $providers.Count

            # All results should be valid
            foreach ($result in $results) {
                $result.Provider | Should -Not -BeNullOrEmpty
                $result.Available | Should -Not -BeNullOrEmpty
            }
        }
    }
}