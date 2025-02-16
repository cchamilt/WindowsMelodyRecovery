@{
    RootModule = 'WindowsConfig.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'new-guid' # Generate a new GUID
    Author = 'Your Name'
    Description = 'Windows Configuration Management and Backup Tools'
    PowerShellVersion = '5.1'
    RequiredModules = @()
    FunctionsToExport = @(
        'Install-WindowsConfig',
        'Update-WindowsConfig',
        'Backup-WindowsConfig',
        'Restore-WindowsConfig',
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