@{
    RootModule = 'WindowsMissingRecovery.psm1'
    ModuleVersion = '1.0.0'
    GUID = '8a7f6674-c759-45f3-b26d-9a8e54d2eb14'
    Author = 'Chris Hamilton'
    Description = 'Windows Recovery Management and Backup Tools'
    PowerShellVersion = '5.1'
    RequiredModules = @()
    FunctionsToExport = @(
        'Backup-WindowsMissingRecovery',
        'Convert-ToWinget',
        'Initialize-WindowsMissingRecovery',
        'Install-WindowsMissingRecoveryTasks',
        'Remove-WindowsMissingRecoveryTasks',
        'Restore-WindowsMissingRecovery',
        'Setup-WindowsMissingRecovery',
        'Test-WindowsMissingRecovery',
        'Update-WindowsMissingRecovery',
        'Set-WindowsMissingRecoveryScripts',
        'Sync-WindowsMissingRecoveryScripts'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('Windows', 'Backup', 'Configuration', 'Settings')
            ProjectUri = 'Your project URL'
        }
    }
} 