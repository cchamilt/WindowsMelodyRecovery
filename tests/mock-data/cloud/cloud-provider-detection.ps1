# Cloud Provider Detection Script for Mock Testing
# This script simulates the detection of various cloud storage providers

function Get-MockCloudProvider {
    <#
    .SYNOPSIS
    Detects available cloud storage providers in the mock environment

    .DESCRIPTION
    Returns information about available cloud storage providers including
    OneDrive, Google Drive, Dropbox, Box, and Custom storage solutions

    .EXAMPLE
    Get-MockCloudProviders
    #>

    $providers = @()
    $mockCloudRoot = if (Test-Path "/mock-data/cloud") { "/mock-data/cloud" } else { "$PSScriptRoot" }

    # OneDrive Detection
    $oneDrivePath = Join-Path $mockCloudRoot "OneDrive"
    if (Test-Path $oneDrivePath) {
        $oneDriveInfo = Get-Content (Join-Path $oneDrivePath "WindowsMelodyRecovery\cloud-provider-info.json") | ConvertFrom-Json
        $syncStatus = Get-Content (Join-Path $oneDrivePath ".sync_status") -Raw

        $providers += @{
            Name = "OneDrive"
            Type = "personal"
            Available = $true
            LocalPath = $oneDriveInfo.paths.local_root
            BackupPath = $oneDriveInfo.paths.backup_folder
            SyncStatus = ($syncStatus | Select-String "SYNC_STATUS=(.+)" | ForEach-Object { $_.Matches[0].Groups[1].Value })
            StorageUsed = $oneDriveInfo.storage.used_human
            StorageTotal = $oneDriveInfo.storage.total_human
            LastSync = $oneDriveInfo.sync.last_sync
            Features = $oneDriveInfo.features
            Account = $oneDriveInfo.account
        }
    }

    # Google Drive Detection
    $googleDrivePath = Join-Path $mockCloudRoot "GoogleDrive"
    if (Test-Path $googleDrivePath) {
        $googleDriveInfo = Get-Content (Join-Path $googleDrivePath "WindowsMelodyRecovery\cloud-provider-info.json") | ConvertFrom-Json
        $syncStatus = Get-Content (Join-Path $googleDrivePath ".sync_status") -Raw

        $providers += @{
            Name = "GoogleDrive"
            Type = "personal"
            Available = $true
            LocalPath = $googleDriveInfo.paths.local_root
            BackupPath = $googleDriveInfo.paths.backup_folder
            SyncStatus = ($syncStatus | Select-String "SYNC_STATUS=(.+)" | ForEach-Object { $_.Matches[0].Groups[1].Value })
            StorageUsed = $googleDriveInfo.storage.used_human
            StorageTotal = $googleDriveInfo.storage.total_human
            LastSync = $googleDriveInfo.sync.last_sync
            Features = $googleDriveInfo.features
            Account = $googleDriveInfo.account
        }
    }

    # Dropbox Detection
    $dropboxPath = Join-Path $mockCloudRoot "Dropbox"
    if (Test-Path $dropboxPath) {
        $dropboxInfo = Get-Content (Join-Path $dropboxPath "WindowsMelodyRecovery\cloud-provider-info.json") | ConvertFrom-Json
        $syncStatus = Get-Content (Join-Path $dropboxPath ".sync_status") -Raw

        $providers += @{
            Name = "Dropbox"
            Type = "personal"
            Available = $true
            LocalPath = $dropboxInfo.paths.local_root
            BackupPath = $dropboxInfo.paths.backup_folder
            SyncStatus = ($syncStatus | Select-String "SYNC_STATUS=(.+)" | ForEach-Object { $_.Matches[0].Groups[1].Value })
            StorageUsed = $dropboxInfo.storage.used_human
            StorageTotal = $dropboxInfo.storage.total_human
            LastSync = $dropboxInfo.sync.last_sync
            Features = $dropboxInfo.features
            Account = $dropboxInfo.account
        }
    }

    # Box Detection
    $boxPath = Join-Path $mockCloudRoot "Box"
    if (Test-Path $boxPath) {
        $boxInfo = Get-Content (Join-Path $boxPath "WindowsMelodyRecovery\cloud-provider-info.json") | ConvertFrom-Json

        $providers += @{
            Name = "Box"
            Type = "business"
            Available = $true
            LocalPath = $boxInfo.paths.local_root
            BackupPath = $boxInfo.paths.backup_folder
            SyncStatus = $boxInfo.sync.status
            StorageUsed = $boxInfo.storage.used_human
            StorageTotal = $boxInfo.storage.total_human
            LastSync = $boxInfo.sync.last_sync
            Features = $boxInfo.features
            Account = $boxInfo.account
        }
    }

    # Custom Storage Detection
    $customPath = Join-Path $mockCloudRoot "Custom"
    if (Test-Path $customPath) {
        $customInfo = Get-Content (Join-Path $customPath "WindowsMelodyRecovery\cloud-provider-info.json") | ConvertFrom-Json

        $providers += @{
            Name = "Custom"
            Type = "custom"
            Available = $true
            LocalPath = $customInfo.paths.local_root
            BackupPath = $customInfo.paths.backup_folder
            SyncStatus = $customInfo.sync.status
            StorageUsed = $customInfo.storage.used_human
            StorageTotal = $customInfo.storage.total_human
            LastSync = $customInfo.sync.last_sync
            Features = $customInfo.features
            Account = $customInfo.account
        }
    }

    return $providers
}

function Test-CloudProviderConnectivity {
    <#
    .SYNOPSIS
    Tests connectivity to cloud storage providers

    .DESCRIPTION
    Simulates testing connectivity to various cloud storage providers
    and returns status information

    .PARAMETER ProviderName
    Name of the cloud provider to test

    .EXAMPLE
    Test-CloudProviderConnectivity -ProviderName "OneDrive"
    #>

    param(
        [Parameter(Mandatory = $true)]
        [string]$ProviderName
    )

    $providers = Get-MockCloudProviders
    $provider = $providers | Where-Object { $_.Name -eq $ProviderName }

    if (-not $provider) {
        return @{
            Provider = $ProviderName
            Available = $false
            Error = "Provider not found or not installed"
            TestTime = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
        }
    }

    # Simulate connectivity test
    $testResults = @{
        Provider = $ProviderName
        Available = $provider.Available
        LocalPathExists = (Test-Path $provider.LocalPath -ErrorAction SilentlyContinue)
        BackupPathExists = (Test-Path $provider.BackupPath -ErrorAction SilentlyContinue)
        SyncStatus = $provider.SyncStatus
        LastSync = $provider.LastSync
        ResponseTime = (Get-Random -Minimum 50 -Maximum 200)
        TestTime = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
    }

    return $testResults
}

function Get-CloudProviderFailoverOrder {
    <#
    .SYNOPSIS
    Returns the recommended failover order for cloud providers

    .DESCRIPTION
    Provides a prioritized list of cloud providers based on availability,
    sync status, and storage capacity

    .EXAMPLE
    Get-CloudProviderFailoverOrder
    #>

    $providers = Get-MockCloudProviders
    $prioritized = @()

    # Priority 1: Up-to-date providers with high storage
    $prioritized += $providers | Where-Object {
        $_.SyncStatus -eq "up_to_date" -and
        $_.StorageTotal -match "TB|[5-9][0-9][0-9] GB"
    } | Sort-Object @{Expression = { $_.StorageTotal }; Descending = $true }

    # Priority 2: Syncing providers with good storage
    $prioritized += $providers | Where-Object {
        $_.SyncStatus -eq "syncing" -and
        $_.StorageTotal -match "TB|[1-9][0-9][0-9] GB"
    } | Sort-Object @{Expression = { $_.StorageTotal }; Descending = $true }

    # Priority 3: All other available providers
    $prioritized += $providers | Where-Object {
        $_.Available -and
        $_ -notin $prioritized
    } | Sort-Object @{Expression = { $_.StorageTotal }; Descending = $true }

    return $prioritized
}

# Functions are available for dot-sourcing in tests
# Export-ModuleMember -Function Get-MockCloudProviders, Test-CloudProviderConnectivity, Get-CloudProviderFailoverOrder







