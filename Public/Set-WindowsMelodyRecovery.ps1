function Set-WindowsMelodyRecovery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$BackupRoot,

        [Parameter(Mandatory = $false)]
        [string]$MachineName,

        [Parameter(Mandatory = $false)]
        [string]$CloudProvider,

        [Parameter(Mandatory = $false)]
        [string]$WindowsMelodyRecoveryPath,

        [Parameter(Mandatory = $false)]
        [string]$EmailAddress,

        [Parameter(Mandatory = $false)]
        [int]$RetentionDays,

        [Parameter(Mandatory = $false)]
        [bool]$EnableEmailNotifications
    )

    # Update the global configuration
    if ($BackupRoot) {
        $script:Config.BackupRoot = $BackupRoot
    }

    if ($MachineName) {
        $script:Config.MachineName = $MachineName
    }

    if ($CloudProvider) {
        $script:Config.CloudProvider = $CloudProvider
    }

    if ($WindowsMelodyRecoveryPath) {
        $script:Config.WindowsMelodyRecoveryPath = $WindowsMelodyRecoveryPath
    }

    if ($EmailAddress) {
        $script:Config.EmailSettings.ToAddress = $EmailAddress
    }

    if ($RetentionDays) {
        $script:Config.BackupSettings.RetentionDays = $RetentionDays
    }

    if ($PSBoundParameters.ContainsKey('EnableEmailNotifications')) {
        $script:Config.NotificationSettings.EnableEmail = $EnableEmailNotifications
    }

    # Mark as initialized
    $script:Config.IsInitialized = $true

    Write-Verbose "Configuration updated: BackupRoot=$BackupRoot, MachineName=$MachineName, CloudProvider=$CloudProvider, EmailAddress=$EmailAddress"

    return $script:Config
}






