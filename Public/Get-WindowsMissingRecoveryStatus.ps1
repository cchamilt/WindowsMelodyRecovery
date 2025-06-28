function Get-WindowsMissingRecoveryStatus {
    <#
    .SYNOPSIS
        Get comprehensive status information about the Windows Missing Recovery module.
    
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
        Get-WindowsMissingRecoveryStatus
    
    .EXAMPLE
        Get-WindowsMissingRecoveryStatus -Detailed
    
    .EXAMPLE
        Get-WindowsMissingRecoveryStatus -ShowErrors
    
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
    $moduleInfo = Get-Module WindowsMissingRecovery -ErrorAction SilentlyContinue
    
    # Get initialization status if available
    $initStatus = $null
    if (Get-Command Get-ModuleInitializationStatus -ErrorAction SilentlyContinue) {
        $initStatus = Get-ModuleInitializationStatus
    }
    
    # Get configuration
    $config = Get-WindowsMissingRecovery
    
    # Build status object
    $status = @{
        ModuleInfo = @{
            Name = $moduleInfo.Name
            Version = $moduleInfo.Version
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
            ModuleVersion = $config.ModuleVersion
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
        'Get-WindowsMissingRecovery',
        'Set-WindowsMissingRecovery',
        'Initialize-WindowsMissingRecovery',
        'Backup-WindowsMissingRecovery',
        'Restore-WindowsMissingRecovery',
        'Setup-WindowsMissingRecovery',
        'Test-WindowsMissingRecovery'
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
    
    return $status
}

function Show-WindowsMissingRecoveryStatus {
    <#
    .SYNOPSIS
        Display a formatted status report for the Windows Missing Recovery module.
    
    .DESCRIPTION
        Shows a user-friendly status report with color-coded information about
        the module's state, configuration, and any issues.
    
    .PARAMETER Detailed
        Show detailed configuration information.
    
    .EXAMPLE
        Show-WindowsMissingRecoveryStatus
    
    .EXAMPLE
        Show-WindowsMissingRecoveryStatus -Detailed
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [switch]$Detailed
    )
    
    $status = Get-WindowsMissingRecoveryStatus -Detailed:$Detailed
    
    Write-Host "`n" + "=" * 60 -ForegroundColor Cyan
    Write-Host "Windows Missing Recovery - Module Status Report" -ForegroundColor Cyan
    Write-Host "=" * 60 -ForegroundColor Cyan
    
    # Module Information
    Write-Host "`n📦 Module Information:" -ForegroundColor Yellow
    if ($status.ModuleInfo.Loaded) {
        Write-Host "  ✓ Module loaded successfully" -ForegroundColor Green
        Write-Host "  Name: $($status.ModuleInfo.Name)" -ForegroundColor White
        Write-Host "  Version: $($status.ModuleInfo.Version)" -ForegroundColor White
        Write-Host "  Path: $($status.ModuleInfo.Path)" -ForegroundColor Gray
    } else {
        Write-Host "  ✗ Module not loaded" -ForegroundColor Red
    }
    
    # Initialization Status
    Write-Host "`n🚀 Initialization Status:" -ForegroundColor Yellow
    if ($status.Initialization.Initialized) {
        Write-Host "  ✓ Module initialized successfully" -ForegroundColor Green
        Write-Host "  Loaded Components: $($status.Initialization.LoadedComponents.Count)" -ForegroundColor White
        if ($status.Initialization.LoadedComponents.Count -gt 0) {
            Write-Host "  Components: $($status.Initialization.LoadedComponents -join ', ')" -ForegroundColor Gray
        }
    } else {
        Write-Host "  ✗ Module not initialized" -ForegroundColor Red
    }
    
    # Configuration
    Write-Host "`n⚙️  Configuration:" -ForegroundColor Yellow
    if ($status.Configuration.IsInitialized) {
        Write-Host "  ✓ Configuration loaded" -ForegroundColor Green
        Write-Host "  Backup Root: $($status.Configuration.BackupRoot)" -ForegroundColor White
        Write-Host "  Machine Name: $($status.Configuration.MachineName)" -ForegroundColor White
        Write-Host "  Cloud Provider: $($status.Configuration.CloudProvider)" -ForegroundColor White
        Write-Host "  Last Configured: $($status.Configuration.LastConfigured)" -ForegroundColor Gray
    } else {
        Write-Host "  ⚠ Configuration not initialized" -ForegroundColor Yellow
    }
    
    # Functions
    Write-Host "`n🔧 Functions:" -ForegroundColor Yellow
    Write-Host "  Available: $($status.Functions.Available.Count)/$($status.Functions.Available.Count + $status.Functions.Missing.Count)" -ForegroundColor White
    if ($status.Functions.Available.Count -gt 0) {
        Write-Host "  Loaded: $($status.Functions.Available -join ', ')" -ForegroundColor Green
    }
    if ($status.Functions.Missing.Count -gt 0) {
        Write-Host "  Missing: $($status.Functions.Missing -join ', ')" -ForegroundColor Red
    }
    
    # Dependencies
    Write-Host "`n📋 Dependencies:" -ForegroundColor Yellow
    if ($status.Dependencies.Pester) {
        Write-Host "  ✓ Pester module available" -ForegroundColor Green
    } else {
        Write-Host "  ✗ Pester module not found" -ForegroundColor Red
    }
    if ($status.Dependencies.PowerShellVersion) {
        Write-Host "  ✓ PowerShell version compatible" -ForegroundColor Green
    } else {
        Write-Host "  ⚠ PowerShell 5.1+ recommended" -ForegroundColor Yellow
    }
    
    # Environment
    Write-Host "`n💻 Environment:" -ForegroundColor Yellow
    Write-Host "  PowerShell: $($status.Environment.PowerShellVersion)" -ForegroundColor White
    Write-Host "  OS: $($status.Environment.OS)" -ForegroundColor White
    Write-Host "  Platform: $($status.Environment.Platform)" -ForegroundColor White
    Write-Host "  User: $($status.Environment.CurrentUser)" -ForegroundColor White
    Write-Host "  Computer: $($status.Environment.ComputerName)" -ForegroundColor White
    
    # Detailed Configuration
    if ($Detailed -and $status.Configuration.Detailed) {
        Write-Host "`n📊 Detailed Configuration:" -ForegroundColor Yellow
        
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
        Write-Host "`n❌ Errors:" -ForegroundColor Red
        foreach ($error in $status.Initialization.Errors) {
            Write-Host "  • $error" -ForegroundColor Red
        }
    }
    
    # Summary
    Write-Host "`n" + "=" * 60 -ForegroundColor Cyan
    if ($status.Initialization.Initialized -and $status.Functions.Missing.Count -eq 0) {
        Write-Host "✅ Module is ready for use!" -ForegroundColor Green
    } elseif ($status.Initialization.Initialized) {
        Write-Host "⚠️  Module is initialized but some functions are missing" -ForegroundColor Yellow
    } else {
        Write-Host "❌ Module needs initialization" -ForegroundColor Red
    }
    Write-Host "=" * 60 -ForegroundColor Cyan
    Write-Host ""
} 