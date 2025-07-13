@{
    RootModule = 'WindowsMelodyRecovery.TUI.psm1'
    ModuleVersion = '0.1.0'
    GUID = 'a9f5d0a6-16e7-4402-9a37-523c1f2b9d5b'
    Author = 'Windows Melody Recovery Team'
    CompanyName = 'WMR'
    Copyright = '(c) WMR. All rights reserved.'
    Description = 'Provides a Text User Interface for the Windows Melody Recovery module.'
    PowerShellVersion = '7.2'
    RequiredModules = @(
        @{
            ModuleName = 'Microsoft.PowerShell.ConsoleGuiTools'
            ModuleVersion = '0.7.7' # Pinning to a known version
        }
    )
    FunctionsToExport = @(
        'Show-WmrTui'
    )
    CmdletsToExport = @()
    VariablesToExport = '*'
    AliasesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('TUI', 'Console', 'Gui')
        }
    }
}
