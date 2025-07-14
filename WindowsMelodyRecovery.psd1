@{
    RootModule         = 'WindowsMelodyRecovery.psm1'
    ModuleVersion      = '1.0.0'
    GUID               = 'a60338bd-2b57-4c2d-8c3a-025019cf317b'
    Author             = 'Chris Hamilton'
    CompanyName        = 'Fyber Labs'
    Copyright          = '(c) 2025 Chris Hamilton. All rights reserved.'
    Description        = 'Comprehensive Windows system recovery, backup, and configuration management tool with WSL integration and cloud storage support.'
    PowerShellVersion  = '7.4.2'

    # Module dependencies
    RequiredModules    = @(
        'Yayaml'
    )

    # Required assemblies
    RequiredAssemblies = @()

    # Script files to process as modules
    ScriptsToProcess   = @(
        'Private\Core\WindowsMelodyRecovery.Core.ps1'
    )

    # Types to process
    TypesToProcess     = @()

    # Format files
    FormatsToProcess   = @()

    # Modules to import as nested modules of the module specified in RootModule/ModuleToProcess
    NestedModules      = @(
        'Private/Core/WindowsMelodyRecovery.Core.ps1',
        'Private/Core/WindowsMelodyRecovery.Template.psm1'
    )

    # Functions to export from this module
    FunctionsToExport  = @(
        # Core functions
        'Get-WindowsMelodyRecovery',
        'Set-WindowsMelodyRecovery',
        'Initialize-WindowsMelodyRecovery',
        'Test-WindowsMelodyRecovery',

        # Status and initialization functions
        'Get-WindowsMelodyRecoveryStatus',
        'Show-WindowsMelodyRecoveryStatus',
        'Initialize-WindowsMelodyRecoveryModule',
        'Get-ModuleInitializationStatus',

        # Backup functions
        'Backup-WindowsMelodyRecovery',
        'Backup-SystemSettings',
        'Backup-Applications',
        'Backup-GamingPlatforms',
        'Backup-WSL',
        'Backup-CloudIntegration',

        # Restore functions
        'Restore-WindowsMelodyRecovery',
        'Restore-SystemSettings',
        'Restore-Applications',
        'Restore-GamingPlatforms',
        'Restore-WSL',
        'Restore-CloudIntegration',

        # Setup functions
        'Start-WindowsMelodyRecovery',
        'Setup-WSL',
        'Setup-GamingPlatforms',
        'Setup-CloudIntegration',

        # Management functions
        'Update-WindowsMelodyRecovery',
        'Convert-ToWinget',
        'Set-WindowsMelodyRecoveryScript',
        'Sync-WindowsMelodyRecoveryScript',

        # Task management
        'Install-WindowsMelodyRecoveryTask',
        'Remove-WindowsMelodyRecoveryTask',

        # Utility functions
        'Import-PrivateScript',
        'Convert-WmrPath',
        'Test-WmrAdministrativePrivilege',

        # Encryption functions
        'Protect-WmrData',
        'Unprotect-WmrData',
        'Get-WmrEncryptionKey',
        'Clear-WmrEncryptionCache',

        # Core state management functions
        'Get-WmrRegistryState',
        'Set-WmrRegistryState',
        'Get-WmrFileState',
        'Set-WmrFileState',
        'Get-WmrApplicationState',
        'Set-WmrApplicationState',
        'Uninstall-WmrApplicationState',
        'Invoke-WmrTemplate',

        # Template functions
        'Read-WmrTemplateConfig',
        'Test-WmrTemplateSchema',
        'Show-WmrTui'
    )

    # Cmdlets to export
    CmdletsToExport    = @()

    # Variables to export
    VariablesToExport  = @(
        'WindowsMelodyRecoveryConfig'
    )

    # Aliases to export
    AliasesToExport    = @(
        'wmr-init',
        'wmr-backup',
        'wmr-restore',
        'wmr-setup',
        'wmr-test',
        'wmr-status'
    )

    # Module-specific data
    PrivateData        = @{
        PSData = @{
            Tags                       = @(
                'Windows',
                'Backup',
                'Restore',
                'Recovery',
                'Configuration',
                'Settings',
                'WSL',
                'Gaming',
                'Cloud',
                'OneDrive',
                'GoogleDrive',
                'Dropbox',
                'Steam',
                'Epic',
                'GOG',
                'EA',
                'SystemAdministration',
                'DevOps'
            )
            ProjectUri                 = 'https://github.com/fyberlabs/WindowsMelodyRecovery'
            LicenseUri                 = 'https://github.com/fyberlabs/WindowsMelodyRecovery/blob/main/LICENSE'
            ReleaseNotes               = @'
## Version 1.0.0
- Initial release of Windows Melody Recovery
- Comprehensive backup and restore functionality
- WSL integration and management
- Gaming platform support (Steam, Epic, GOG, EA)
- Cloud storage integration (OneDrive, Google Drive, Dropbox)
- System settings backup and restore
- Application configuration management
- Automated task scheduling
- Cross-platform compatibility
- Enhanced module initialization system
- Comprehensive status reporting
'@
            Prerelease                 = $false
            RequireLicenseAcceptance   = $false
            ExternalModuleDependencies = @()
        }
    }

    # Help info URI
    HelpInfoUri        = 'https://github.com/fyberlabs/WindowsMelodyRecovery/wiki'
}
