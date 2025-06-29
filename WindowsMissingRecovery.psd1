@{
    RootModule = 'WindowsMissingRecovery.psm1'
    ModuleVersion = '1.0.0'
    GUID = '8a7f6674-c759-45f3-b26d-9a8e54d2eb14'
    Author = 'Chris Hamilton'
    CompanyName = 'Fyber Labs'
    Copyright = '(c) 2024 Chris Hamilton. All rights reserved.'
    Description = 'Comprehensive Windows system recovery, backup, and configuration management tool with WSL integration and cloud storage support.'
    PowerShellVersion = '5.1'
    DotNetFrameworkVersion = '4.7.2'
    CLRVersion = '4.0.30319'
    ProcessorArchitecture = 'Amd64'
    
    # Module dependencies
    RequiredModules = @(
        @{ModuleName='Pester'; ModuleVersion='5.0.0'}
    )
    
    # Required assemblies
    RequiredAssemblies = @()
    
    # Script files to process as modules
    ScriptsToProcess = @(
        'Private\Core\WindowsMissingRecovery.Core.ps1'
    )
    
    # Types to process
    TypesToProcess = @()
    
    # Format files
    FormatsToProcess = @()
    
    # Functions to export
    FunctionsToExport = @(
        # Core functions
        'Get-WindowsMissingRecovery',
        'Set-WindowsMissingRecovery',
        'Initialize-WindowsMissingRecovery',
        'Test-WindowsMissingRecovery',
        
        # Status and initialization functions
        'Get-WindowsMissingRecoveryStatus',
        'Show-WindowsMissingRecoveryStatus',
        'Initialize-WindowsMissingRecoveryModule',
        'Get-ModuleInitializationStatus',
        
        # Backup functions
        'Backup-WindowsMissingRecovery',
        'Backup-SystemSettings',
        'Backup-Applications',
        'Backup-GamingPlatforms',
        'Backup-WSL',
        'Backup-CloudIntegration',
        
        # Restore functions
        'Restore-WindowsMissingRecovery',
        'Restore-SystemSettings',
        'Restore-Applications',
        'Restore-GamingPlatforms',
        'Restore-WSL',
        'Restore-CloudIntegration',
        
        # Setup functions
        'Setup-WindowsMissingRecovery',
        'Setup-WSL',
        'Setup-GamingPlatforms',
        'Setup-CloudIntegration',
        
        # Management functions
        'Update-WindowsMissingRecovery',
        'Convert-ToWinget',
        'Set-WindowsMissingRecoveryScripts',
        'Sync-WindowsMissingRecoveryScripts',
        
        # Task management
        'Install-WindowsMissingRecoveryTasks',
        'Remove-WindowsMissingRecoveryTasks',
        
        # Utility functions
        'Import-PrivateScripts'
    )
    
    # Cmdlets to export
    CmdletsToExport = @()
    
    # Variables to export
    VariablesToExport = @(
        'WindowsMissingRecoveryConfig'
    )
    
    # Aliases to export
    AliasesToExport = @(
        'wmr-init',
        'wmr-backup',
        'wmr-restore',
        'wmr-setup',
        'wmr-test',
        'wmr-status'
    )
    
    # Module-specific data
    PrivateData = @{
        PSData = @{
            Tags = @(
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
            ProjectUri = 'https://github.com/fyberlabs/WindowsMissingRecovery'
            LicenseUri = 'https://github.com/fyberlabs/WindowsMissingRecovery/blob/main/LICENSE'
            ReleaseNotes = @'
## Version 1.0.0
- Initial release of Windows Missing Recovery
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
            Prerelease = $false
            RequireLicenseAcceptance = $false
            ExternalModuleDependencies = @(
                'Pester'
            )
        }
    }
    
    # Help info URI
    HelpInfoUri = 'https://github.com/fyberlabs/WindowsMissingRecovery/wiki'
} 