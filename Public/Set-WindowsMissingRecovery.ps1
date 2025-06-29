function Set-WindowsMissingRecovery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$BackupRoot,
        
        [Parameter(Mandatory=$false)]
        [string]$MachineName,
        
        [Parameter(Mandatory=$false)]
        [string]$CloudProvider,
        
        [Parameter(Mandatory=$false)]
        [string]$WindowsMissingRecoveryPath
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
    
    if ($WindowsMissingRecoveryPath) {
        $script:Config.WindowsMissingRecoveryPath = $WindowsMissingRecoveryPath
    }
    
    # Mark as initialized
    $script:Config.IsInitialized = $true
    
    Write-Verbose "Configuration updated: BackupRoot=$BackupRoot, MachineName=$MachineName, CloudProvider=$CloudProvider"
    
    return $script:Config
} 