function Get-WindowsMelodyRecoveryStatus {
    <#
    .SYNOPSIS
        Get comprehensive status information about the Windows Melody Recovery module.

    .DESCRIPTION
        Returns detailed information about the module's initialization status,
        loaded components, configuration, and any errors or warnings.

    .PARAMETER Detailed
        Show detailed information including all configuration settings.

    .PARAMETER ShowErrors
        Show only error information.

    .PARAMETER ShowWarnings
        Show only warning information.

    .EXAMPLE
        Get-WindowsMelodyRecoveryStatus

    .EXAMPLE
        Get-WindowsMelodyRecoveryStatus -Detailed

    .EXAMPLE
        Get-WindowsMelodyRecoveryStatus -ShowErrors

    .OUTPUTS
        Hashtable containing the module status information.
    #>
    [OutputType([System.Collections.Hashtable])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [switch]$Detailed,

        [Parameter(Mandatory = $false)]
        [switch]$ShowErrors,

        [Parameter(Mandatory = $false)]
        [switch]$ShowWarnings
    )

    # Get module information
    $moduleInfo = Get-Module WindowsMelodyRecovery -ErrorAction SilentlyContinue

    # Get module version from manifest if module info is not available
    $moduleVersion = $null
    if ($moduleInfo) {
        $moduleVersion = $moduleInfo.Version
    }
    else {
        # Try to get version from manifest file using an absolute path in the container
        $manifestPath = "/workspace/WindowsMelodyRecovery.psd1"
        Write-Verbose "Could not find module, trying absolute manifest path: $manifestPath"
        if (Test-Path $manifestPath) {
            try {
                $manifestContent = Get-Content $manifestPath -Raw -ErrorAction Stop
                if ($manifestContent -match "ModuleVersion\s*=\s*['`"]([^'`"]+)['`"]") {
                    $moduleVersion = $matches[1]
                    Write-Verbose "Found version $moduleVersion in manifest"
                }
            }
            catch {
                Write-Warning "Could not read manifest file at ${manifestPath}: $($_.Exception.Message)"
            }
        }
    }

    # Get initialization status if available
    $initStatus = $null
    if (Get-Command Get-ModuleInitializationStatus -ErrorAction SilentlyContinue) {
        $initStatus = Get-ModuleInitializationStatus
    }

    # Get configuration
    $config = Get-WindowsMelodyRecovery

    # Build status object
    $status = @{
        ModuleInfo     = @{
            Name    = $moduleInfo.Name
            Version = $moduleVersion
            Path    = $moduleInfo.Path
            Loaded  = $null -ne $moduleInfo
        }
        Initialization = @{
            Initialized      = $initStatus.Initialized
            LoadedComponents = $initStatus.LoadedComponents
            Errors           = $initStatus.Errors
        }
        Configuration  = @{
            IsInitialized  = $config.IsInitialized
            BackupRoot     = $config.BackupRoot
            MachineName    = $config.MachineName
            CloudProvider  = $config.CloudProvider
            ModuleVersion  = $moduleVersion  # Use module version from loaded module or manifest
            LastConfigured = $config.LastConfigured
        }
        Environment    = @{
            PowerShellVersion = $PSVersionTable.PSVersion.ToString()
            OS                = $PSVersionTable.OS
            Platform          = $PSVersionTable.Platform
            CurrentUser       = $env:USERNAME
            ComputerName      = $env:COMPUTERNAME
        }
        Functions      = @{
            Available = @()
            Missing   = @()
        }
        Dependencies   = @{
            Pester            = $null -ne (Get-Module Pester -ListAvailable -ErrorAction SilentlyContinue)
            PowerShellVersion = $PSVersionTable.PSVersion.Major -ge 5
        }
    }

    # Check for available functions
    $expectedFunctions = @(
        'Get-WindowsMelodyRecovery',
        'Set-WindowsMelodyRecovery',
        'Initialize-WindowsMelodyRecovery',
        'Backup-WindowsMelodyRecovery',
        'Restore-WindowsMelodyRecovery',
        'Setup-WindowsMelodyRecovery'
    )

    foreach ($function in $expectedFunctions) {
        if (Get-Command $function -ErrorAction SilentlyContinue) {
            $status.Functions.Available += $function
        }
        else {
            $status.Functions.Missing += $function
        }
    }

    # Add detailed configuration if requested
    if ($Detailed) {
        $status.Configuration.Detailed = @{
            EmailSettings        = $config.EmailSettings
            BackupSettings       = $config.BackupSettings
            ScheduleSettings     = $config.ScheduleSettings
            NotificationSettings = $config.NotificationSettings
            RecoverySettings     = $config.RecoverySettings
            LoggingSettings      = $config.LoggingSettings
            UpdateSettings       = $config.UpdateSettings
        }
    }

    # Filter based on parameters
    if ($ShowErrors) {
        $status = @{
            Errors           = $status.Initialization.Errors
            MissingFunctions = $status.Functions.Missing
            DependencyIssues = @()
        }

        if (-not $status.Dependencies.Pester) {
            $status.DependencyIssues += "Pester module not found"
        }
        if (-not $status.Dependencies.PowerShellVersion) {
            $status.DependencyIssues += "PowerShell 5.1+ recommended"
        }

        return $status
    }

    if ($ShowWarnings) {
        $warnings = @()

        if ($status.Functions.Missing.Count -gt 0) {
            $warnings += "Missing functions: $($status.Functions.Missing -join ', ')"
        }

        if (-not $status.Dependencies.Pester) {
            $warnings += "Pester module not found (required for testing)"
        }

        if (-not $status.Configuration.IsInitialized) {
            $warnings += "Module not fully initialized"
        }

        return @{
            Warnings = $warnings
        }
    }

    # Add compatibility properties for tests
    Write-Verbose "ModuleInfo.Version: $($status.ModuleInfo.Version)"
    Write-Verbose "moduleVersion: $moduleVersion"

    $status.ModuleVersion = if ($status.ModuleInfo.Version) {
        Write-Verbose "Using ModuleInfo.Version: $($status.ModuleInfo.Version)"
        $status.ModuleInfo.Version
    }
    elseif ($moduleVersion) {
        Write-Verbose "Using moduleVersion: $moduleVersion"
        $moduleVersion
    }
    else {
        Write-Verbose "Using fallback version: 1.0.0"
        "1.0.0"  # Fallback version
    }
    $status.InitializationStatus = if ($status.Initialization.Initialized) { "Initialized" } else { "Not Initialized" }
    $status.ConfigurationPath = $status.Configuration.BackupRoot
    $status.PowerShellVersion = $status.Environment.PowerShellVersion
    $status.OperatingSystem = $status.Environment.OS

    return $status
}

function Show-WindowsMelodyRecoveryStatus {
    <#
    .SYNOPSIS
        Display a formatted status report for the Windows Melody Recovery module.

    .DESCRIPTION
        Shows a user-friendly status report with color-coded information about
        the module's state, configuration, and any issues.

    .PARAMETER Detailed
        Show detailed configuration information.

    .EXAMPLE
        Show-WindowsMelodyRecoveryStatus

    .EXAMPLE
        Show-WindowsMelodyRecoveryStatus -Detailed
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [switch]$Detailed
    )

    $status = Get-WindowsMelodyRecoveryStatus -Detailed:$Detailed

    $separator = "=" * 60
    Write-Information -MessageData "" -InformationAction Continue
    Write-Information -MessageData $separator  -InformationAction Continue-ForegroundColor Cyan
    Write-Information -MessageData "Windows Melody Recovery - Module Status Report" -InformationAction Continue
    Write-Information -MessageData $separator  -InformationAction Continue-ForegroundColor Cyan

    # Module Information
    Write-Information -MessageData "" -InformationAction Continue
    Write-Warning -Message "Module Information:"
    if ($status.ModuleInfo.Loaded) {
        Write-Information -MessageData "  Module loaded successfully" -InformationAction Continue
        Write-Information -MessageData "  Name: $($status.ModuleInfo.Name)"  -InformationAction Continue-ForegroundColor White
        Write-Information -MessageData "  Version: $($status.ModuleInfo.Version)"  -InformationAction Continue-ForegroundColor White
        Write-Verbose -Message "  Path: $($status.ModuleInfo.Path)"
    }
    else {
        Write-Error -Message "  Module not loaded"
    }

    # Initialization Status
    Write-Information -MessageData "" -InformationAction Continue
    Write-Warning -Message "Initialization Status:"
    if ($status.Initialization.Initialized) {
        Write-Information -MessageData "  Module initialized successfully" -InformationAction Continue
        Write-Information -MessageData "  Loaded Components: $($status.Initialization.LoadedComponents.Count)"  -InformationAction Continue-ForegroundColor White
        if ($status.Initialization.LoadedComponents.Count -gt 0) {
            Write-Verbose -Message "  Components: $($status.Initialization.LoadedComponents -join ', ')"
        }
    }
    else {
        Write-Error -Message "  Module not initialized"
    }

    # Configuration
    Write-Information -MessageData "" -InformationAction Continue
    Write-Warning -Message "Configuration:"
    if ($status.Configuration.IsInitialized) {
        Write-Information -MessageData "  Configuration loaded" -InformationAction Continue
        Write-Information -MessageData "  Backup Root: $($status.Configuration.BackupRoot)"  -InformationAction Continue-ForegroundColor White
        Write-Information -MessageData "  Machine Name: $($status.Configuration.MachineName)"  -InformationAction Continue-ForegroundColor White
        Write-Information -MessageData "  Cloud Provider: $($status.Configuration.CloudProvider)"  -InformationAction Continue-ForegroundColor White
        Write-Verbose -Message "  Last Configured: $($status.Configuration.LastConfigured)"
    }
    else {
        Write-Warning -Message "  Configuration not initialized"
    }

    # Functions
    Write-Information -MessageData "" -InformationAction Continue
    Write-Warning -Message "Functions:"
    Write-Information -MessageData "  Available: $($status.Functions.Available.Count)/$($status.Functions.Available.Count + $status.Functions.Missing.Count)"  -InformationAction Continue-ForegroundColor White
    if ($status.Functions.Available.Count -gt 0) {
        Write-Information -MessageData "  Loaded: $($status.Functions.Available -join ', ')" -InformationAction Continue
    }
    if ($status.Functions.Missing.Count -gt 0) {
        Write-Error -Message "  Missing: $($status.Functions.Missing -join ', ')"
    }

    # Dependencies
    Write-Information -MessageData "" -InformationAction Continue
    Write-Warning -Message "Dependencies:"
    if ($status.Dependencies.Pester) {
        Write-Information -MessageData "  Pester module available" -InformationAction Continue
    }
    else {
        Write-Error -Message "  Pester module not found"
    }
    if ($status.Dependencies.PowerShellVersion) {
        Write-Information -MessageData "  PowerShell version compatible" -InformationAction Continue
    }
    else {
        Write-Warning -Message "  PowerShell 5.1+ recommended"
    }

    # Environment
    Write-Information -MessageData "" -InformationAction Continue
    Write-Warning -Message "Environment:"
    Write-Information -MessageData "  PowerShell: $($status.Environment.PowerShellVersion)"  -InformationAction Continue-ForegroundColor White
    Write-Information -MessageData "  OS: $($status.Environment.OS)"  -InformationAction Continue-ForegroundColor White
    Write-Information -MessageData "  Platform: $($status.Environment.Platform)"  -InformationAction Continue-ForegroundColor White
    Write-Information -MessageData "  User: $($status.Environment.CurrentUser)"  -InformationAction Continue-ForegroundColor White
    Write-Information -MessageData "  Computer: $($status.Environment.ComputerName)"  -InformationAction Continue-ForegroundColor White

    # Detailed Configuration
    if ($Detailed -and $status.Configuration.Detailed) {
        Write-Information -MessageData "" -InformationAction Continue
        Write-Warning -Message "Detailed Configuration:"

        # Email Settings
        Write-Information -MessageData "  Email Settings:" -InformationAction Continue
        $email = $status.Configuration.Detailed.EmailSettings
        Write-Verbose -Message "    From: $($email.FromAddress)"
        Write-Verbose -Message "    To: $($email.ToAddress)"
        Write-Verbose -Message "    SMTP: $($email.SmtpServer):$($email.SmtpPort)"

        # Backup Settings
        Write-Information -MessageData "  Backup Settings:" -InformationAction Continue
        $backup = $status.Configuration.Detailed.BackupSettings
        Write-Verbose -Message "    Retention: $($backup.RetentionDays) days"
        Write-Verbose -Message "    Exclude Paths: $($backup.ExcludePaths.Count)"
        Write-Verbose -Message "    Include Paths: $($backup.IncludePaths.Count)"

        # Logging Settings
        Write-Information -MessageData "  Logging Settings:" -InformationAction Continue
        $logging = $status.Configuration.Detailed.LoggingSettings
        Write-Verbose -Message "    Path: $($logging.Path)"
        Write-Verbose -Message "    Level: $($logging.Level)"
    }

    # Errors and Warnings
    if ($status.Initialization.Errors.Count -gt 0) {
        Write-Information -MessageData "" -InformationAction Continue
        Write-Error -Message "Errors:"
        foreach ($errorMessage in $status.Initialization.Errors) {
            Write-Error -Message "  $errorMessage"
        }
    }

    # Summary
    $separator = "=" * 60
    Write-Information -MessageData "" -InformationAction Continue
    Write-Information -MessageData $separator  -InformationAction Continue-ForegroundColor Cyan
    if ($status.Initialization.Initialized -and $status.Functions.Missing.Count -eq 0) {
        Write-Information -MessageData "Module is ready for use!" -InformationAction Continue
    }
    elseif ($status.Initialization.Initialized) {
        Write-Warning -Message "Module is initialized but some functions are missing"
    }
    else {
        Write-Error -Message "Module needs initialization"
    }
    Write-Information -MessageData $separator  -InformationAction Continue-ForegroundColor Cyan
    Write-Information -MessageData "" -InformationAction Continue
}







