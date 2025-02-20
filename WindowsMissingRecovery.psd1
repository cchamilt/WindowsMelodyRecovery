@{
    RootModule = 'WindowsMissingRecovery.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'new-guid' # Generate a new GUID
    Author = 'Chris Hamilton'
    Description = 'Windows Recovery Management and Backup Tools'
    PowerShellVersion = '5.1'
    RequiredModules = @()
    FunctionsToExport = @(
        'Install-WindowsRecovery',
        'Update-WindowsRecovery',
        'Backup-WindowsRecovery',
        'Restore-WindowsRecovery',
        'Backup-ExcelSettings',
        'Restore-ExcelSettings',
        'Backup-VisioSettings',
        'Restore-VisioSettings'
        # Add other functions to export
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