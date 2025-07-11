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
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [switch]$Detailed,

        [Parameter(Mandatory=$false)]
        [switch]$ShowErrors,

        [Parameter(Mandatory=$false)]
        [switch]$ShowWarnings
    )

    # Get module information
    $moduleInfo = Get-Module WindowsMelodyRecovery -ErrorAction SilentlyContinue

    # Get module version from manifest if module info is not available
    $moduleVersion = $null
    if ($moduleInfo) {
        $moduleVersion = $moduleInfo.Version
    } else {
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
            } catch {
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
        ModuleInfo = @{
            Name = $moduleInfo.Name
            Version = $moduleVersion
            Path = $moduleInfo.Path
            Loaded = $null -ne $moduleInfo
        }
        Initialization = @{
            Initialized = $initStatus.Initialized
            LoadedComponents = $initStatus.LoadedComponents
            Errors = $initStatus.Errors
        }
        Configuration = @{
            IsInitialized = $config.IsInitialized
            BackupRoot = $config.BackupRoot
            MachineName = $config.MachineName
            CloudProvider = $config.CloudProvider
            ModuleVersion = $moduleVersion  # Use module version from loaded module or manifest
            LastConfigured = $config.LastConfigured
        }
        Environment = @{
            PowerShellVersion = $PSVersionTable.PSVersion.ToString()
            OS = $PSVersionTable.OS
            Platform = $PSVersionTable.Platform
            CurrentUser = $env:USERNAME
            ComputerName = $env:COMPUTERNAME
        }
        Functions = @{
            Available = @()
            Missing = @()
        }
        Dependencies = @{
            Pester = $null -ne (Get-Module Pester -ListAvailable -ErrorAction SilentlyContinue)
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
        'Setup-WindowsMelodyRecovery',
        'Test-WindowsMelodyRecovery'
    )

    foreach ($function in $expectedFunctions) {
        if (Get-Command $function -ErrorAction SilentlyContinue) {
            $status.Functions.Available += $function
        } else {
            $status.Functions.Missing += $function
        }
    }

    # Add detailed configuration if requested
    if ($Detailed) {
        $status.Configuration.Detailed = @{
            EmailSettings = $config.EmailSettings
            BackupSettings = $config.BackupSettings
            ScheduleSettings = $config.ScheduleSettings
            NotificationSettings = $config.NotificationSettings
            RecoverySettings = $config.RecoverySettings
            LoggingSettings = $config.LoggingSettings
            UpdateSettings = $config.UpdateSettings
        }
    }

    # Filter based on parameters
    if ($ShowErrors) {
        $status = @{
            Errors = $status.Initialization.Errors
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
    } elseif ($moduleVersion) {
        Write-Verbose "Using moduleVersion: $moduleVersion"
        $moduleVersion
    } else {
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
        [Parameter(Mandatory=$false)]
        [switch]$Detailed
    )

    $status = Get-WindowsMelodyRecoveryStatus -Detailed:$Detailed

    $separator = "=" * 60
    Write-Host ""
    Write-Host $separator -ForegroundColor Cyan
    Write-Host "Windows Melody Recovery - Module Status Report" -ForegroundColor Cyan
    Write-Host $separator -ForegroundColor Cyan

    # Module Information
    Write-Host ""
    Write-Host "Module Information:" -ForegroundColor Yellow
    if ($status.ModuleInfo.Loaded) {
        Write-Host "  Module loaded successfully" -ForegroundColor Green
        Write-Host "  Name: $($status.ModuleInfo.Name)" -ForegroundColor White
        Write-Host "  Version: $($status.ModuleInfo.Version)" -ForegroundColor White
        Write-Host "  Path: $($status.ModuleInfo.Path)" -ForegroundColor Gray
    } else {
        Write-Host "  Module not loaded" -ForegroundColor Red
    }

    # Initialization Status
    Write-Host ""
    Write-Host "Initialization Status:" -ForegroundColor Yellow
    if ($status.Initialization.Initialized) {
        Write-Host "  Module initialized successfully" -ForegroundColor Green
        Write-Host "  Loaded Components: $($status.Initialization.LoadedComponents.Count)" -ForegroundColor White
        if ($status.Initialization.LoadedComponents.Count -gt 0) {
            Write-Host "  Components: $($status.Initialization.LoadedComponents -join ', ')" -ForegroundColor Gray
        }
    } else {
        Write-Host "  Module not initialized" -ForegroundColor Red
    }

    # Configuration
    Write-Host ""
    Write-Host "Configuration:" -ForegroundColor Yellow
    if ($status.Configuration.IsInitialized) {
        Write-Host "  Configuration loaded" -ForegroundColor Green
        Write-Host "  Backup Root: $($status.Configuration.BackupRoot)" -ForegroundColor White
        Write-Host "  Machine Name: $($status.Configuration.MachineName)" -ForegroundColor White
        Write-Host "  Cloud Provider: $($status.Configuration.CloudProvider)" -ForegroundColor White
        Write-Host "  Last Configured: $($status.Configuration.LastConfigured)" -ForegroundColor Gray
    } else {
        Write-Host "  Configuration not initialized" -ForegroundColor Yellow
    }

    # Functions
    Write-Host ""
    Write-Host "Functions:" -ForegroundColor Yellow
    Write-Host "  Available: $($status.Functions.Available.Count)/$($status.Functions.Available.Count + $status.Functions.Missing.Count)" -ForegroundColor White
    if ($status.Functions.Available.Count -gt 0) {
        Write-Host "  Loaded: $($status.Functions.Available -join ', ')" -ForegroundColor Green
    }
    if ($status.Functions.Missing.Count -gt 0) {
        Write-Host "  Missing: $($status.Functions.Missing -join ', ')" -ForegroundColor Red
    }

    # Dependencies
    Write-Host ""
    Write-Host "Dependencies:" -ForegroundColor Yellow
    if ($status.Dependencies.Pester) {
        Write-Host "  Pester module available" -ForegroundColor Green
    } else {
        Write-Host "  Pester module not found" -ForegroundColor Red
    }
    if ($status.Dependencies.PowerShellVersion) {
        Write-Host "  PowerShell version compatible" -ForegroundColor Green
    } else {
        Write-Host "  PowerShell 5.1+ recommended" -ForegroundColor Yellow
    }

    # Environment
    Write-Host ""
    Write-Host "Environment:" -ForegroundColor Yellow
    Write-Host "  PowerShell: $($status.Environment.PowerShellVersion)" -ForegroundColor White
    Write-Host "  OS: $($status.Environment.OS)" -ForegroundColor White
    Write-Host "  Platform: $($status.Environment.Platform)" -ForegroundColor White
    Write-Host "  User: $($status.Environment.CurrentUser)" -ForegroundColor White
    Write-Host "  Computer: $($status.Environment.ComputerName)" -ForegroundColor White

    # Detailed Configuration
    if ($Detailed -and $status.Configuration.Detailed) {
        Write-Host ""
        Write-Host "Detailed Configuration:" -ForegroundColor Yellow

        # Email Settings
        Write-Host "  Email Settings:" -ForegroundColor Cyan
        $email = $status.Configuration.Detailed.EmailSettings
        Write-Host "    From: $($email.FromAddress)" -ForegroundColor Gray
        Write-Host "    To: $($email.ToAddress)" -ForegroundColor Gray
        Write-Host "    SMTP: $($email.SmtpServer):$($email.SmtpPort)" -ForegroundColor Gray

        # Backup Settings
        Write-Host "  Backup Settings:" -ForegroundColor Cyan
        $backup = $status.Configuration.Detailed.BackupSettings
        Write-Host "    Retention: $($backup.RetentionDays) days" -ForegroundColor Gray
        Write-Host "    Exclude Paths: $($backup.ExcludePaths.Count)" -ForegroundColor Gray
        Write-Host "    Include Paths: $($backup.IncludePaths.Count)" -ForegroundColor Gray

        # Logging Settings
        Write-Host "  Logging Settings:" -ForegroundColor Cyan
        $logging = $status.Configuration.Detailed.LoggingSettings
        Write-Host "    Path: $($logging.Path)" -ForegroundColor Gray
        Write-Host "    Level: $($logging.Level)" -ForegroundColor Gray
    }

    # Errors and Warnings
    if ($status.Initialization.Errors.Count -gt 0) {
        Write-Host ""
        Write-Host "Errors:" -ForegroundColor Red
        foreach ($errorMessage in $status.Initialization.Errors) {
            Write-Host "  $errorMessage" -ForegroundColor Red
        }
    }

    # Summary
    $separator = "=" * 60
    Write-Host ""
    Write-Host $separator -ForegroundColor Cyan
    if ($status.Initialization.Initialized -and $status.Functions.Missing.Count -eq 0) {
        Write-Host "Module is ready for use!" -ForegroundColor Green
    } elseif ($status.Initialization.Initialized) {
        Write-Host "Module is initialized but some functions are missing" -ForegroundColor Yellow
    } else {
        Write-Host "Module needs initialization" -ForegroundColor Red
    }
    Write-Host $separator -ForegroundColor Cyan
    Write-Host ""
}