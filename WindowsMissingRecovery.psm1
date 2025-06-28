# WindowsMissingRecovery PowerShell Module
# Comprehensive Windows system recovery, backup, and configuration management tool

# Module metadata
$ModuleName = "WindowsMissingRecovery"
$ModuleVersion = "1.0.0"

# Module configuration (in-memory state)
$script:Config = @{
    BackupRoot = $null
    MachineName = $env:COMPUTERNAME
    WindowsMissingRecoveryPath = Join-Path $PSScriptRoot "Config"
    CloudProvider = $null
    ModuleVersion = $ModuleVersion
    LastConfigured = $null
    IsInitialized = $false
    EmailSettings = @{
        FromAddress = $null
        ToAddress = $null
        Password = $null
        SmtpServer = $null
        SmtpPort = 587
        EnableSsl = $true
    }
    BackupSettings = @{
        RetentionDays = 30
        ExcludePaths = @()
        IncludePaths = @()
    }
    ScheduleSettings = @{
        BackupSchedule = $null
        UpdateSchedule = $null
    }
    NotificationSettings = @{
        EnableEmail = $false
        NotifyOnSuccess = $false
        NotifyOnFailure = $true
    }
    RecoverySettings = @{
        Mode = "Selective"
        ForceOverwrite = $false
    }
    LoggingSettings = @{
        Path = $null
        Level = "Information"
    }
    UpdateSettings = @{
        AutoUpdate = $true
        ExcludePackages = @()
    }
}

# Module initialization state
$script:ModuleInitialized = $false
$script:InitializationErrors = @()
$script:LoadedComponents = @()

# Define core functions first
function Get-WindowsMissingRecovery {
    <#
    .SYNOPSIS
        Get the current Windows Missing Recovery configuration.
    
    .DESCRIPTION
        Returns the current module configuration including backup settings, 
        cloud provider settings, and initialization status.
    
    .EXAMPLE
        Get-WindowsMissingRecovery
    
    .OUTPUTS
        Hashtable containing the module configuration.
    #>
    [CmdletBinding()]
    param()
    
    return $script:Config
}

function Set-WindowsMissingRecovery {
    <#
    .SYNOPSIS
        Set Windows Missing Recovery configuration.
    
    .DESCRIPTION
        Updates the module configuration with new settings.
    
    .PARAMETER Config
        Complete configuration hashtable to replace current config.
    
    .PARAMETER BackupRoot
        Path to the backup root directory.
    
    .PARAMETER MachineName
        Name of the machine for backup identification.
    
    .PARAMETER WindowsMissingRecoveryPath
        Path to the Windows Missing Recovery installation.
    
    .PARAMETER CloudProvider
        Cloud storage provider (OneDrive, GoogleDrive, Dropbox, Box, Custom).
    
    .EXAMPLE
        Set-WindowsMissingRecovery -BackupRoot "C:\Backups" -CloudProvider "OneDrive"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [hashtable]$Config,
        
        [Parameter(Mandatory=$false)]
        [string]$BackupRoot,
        
        [Parameter(Mandatory=$false)]
        [string]$MachineName,
        
        [Parameter(Mandatory=$false)]
        [string]$WindowsMissingRecoveryPath,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('OneDrive', 'GoogleDrive', 'Dropbox', 'Box', 'Custom')]
        [string]$CloudProvider
    )
    
    if ($Config) {
        $script:Config = $Config
    } else {
        if ($BackupRoot) { $script:Config.BackupRoot = $BackupRoot }
        if ($MachineName) { $script:Config.MachineName = $MachineName }
        if ($WindowsMissingRecoveryPath) { $script:Config.WindowsMissingRecoveryPath = $WindowsMissingRecoveryPath }
        if ($CloudProvider) { $script:Config.CloudProvider = $CloudProvider }
    }
    
    $script:Config.LastConfigured = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
}

# Helper function to load private scripts on demand
function Import-PrivateScripts {
    <#
    .SYNOPSIS
        Import private scripts by category.
    
    .DESCRIPTION
        Loads private scripts from the specified category (backup, restore, setup, tasks, scripts).
    
    .PARAMETER Category
        The category of scripts to load.
    
    .EXAMPLE
        Import-PrivateScripts -Category "backup"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet('backup', 'restore', 'setup', 'tasks', 'scripts')]
        [string]$Category
    )
    
    $categoryPath = Join-Path $PSScriptRoot "Private\$Category"
    Write-Verbose "Looking for $Category scripts in: $categoryPath"
    
    if (Test-Path $categoryPath) {
        $scripts = Get-ChildItem -Path "$categoryPath\*.ps1" -ErrorAction SilentlyContinue
        Write-Verbose "Found $($scripts.Count) $Category scripts"
        
        foreach ($script in $scripts) {
            try {
                Write-Verbose "Loading script: $($script.FullName)"
                . $script.FullName
                Write-Host "Successfully loaded $Category script: $($script.Name)" -ForegroundColor Green
            } catch {
                Write-Warning "Failed to load $Category script $($script.Name): $_"
            }
        }
    } else {
        Write-Warning "$Category scripts directory not found at: $categoryPath"
    }
}

# Load initialization system
$InitializationPath = Join-Path $PSScriptRoot "Private\Core\WindowsMissingRecovery.Initialization.ps1"
if (Test-Path $InitializationPath) {
    try {
        . $InitializationPath
        Write-Verbose "Successfully loaded initialization system from: $InitializationPath"
    } catch {
        Write-Warning "Failed to load initialization system from: $InitializationPath"
        Write-Warning $_.Exception.Message
    }
} else {
    Write-Warning "Initialization system not found at: $InitializationPath"
}

# Load core utilities
$CorePath = Join-Path $PSScriptRoot "Private\Core\WindowsMissingRecovery.Core.ps1"
if (Test-Path $CorePath) {
    try {
        . $CorePath
        Write-Verbose "Successfully loaded core utilities from: $CorePath"
    } catch {
        Write-Warning "Failed to load core utilities from: $CorePath"
        Write-Warning $_.Exception.Message
    }
} else {
    Write-Warning "Core utilities not found at: $CorePath"
}

# Initialize module using the new initialization system
if (Get-Command Initialize-WindowsMissingRecoveryModule -ErrorAction SilentlyContinue) {
    try {
        $initResult = Initialize-WindowsMissingRecoveryModule -SkipValidation
        if ($initResult.Success) {
            Write-Verbose "Module initialized successfully: $($initResult.Message)"
            if ($initResult.Warnings) {
                Write-Warning "Initialization warnings: $($initResult.Warnings -join '; ')"
            }
        } else {
            Write-Warning "Module initialization failed: $($initResult.Message)"
            $script:InitializationErrors += $initResult.Message
        }
    } catch {
        Write-Warning "Module initialization error: $($_.Exception.Message)"
        $script:InitializationErrors += $_.Exception.Message
    }
} else {
    Write-Warning "Initialization system not available, using fallback initialization"
    
    # Fallback initialization
    try {
        # Try to initialize module configuration from config file
        if (Get-Command Initialize-ModuleFromConfig -ErrorAction SilentlyContinue) {
            Initialize-ModuleFromConfig
        }
        
        # Load public functions
        $PublicPath = Join-Path $PSScriptRoot "Public"
        if (Test-Path $PublicPath) {
            $Public = @(Get-ChildItem -Path "$PublicPath\*.ps1" -ErrorAction SilentlyContinue)
            
            foreach ($import in $Public) {
                $functionName = $import.BaseName
                Write-Verbose "Attempting to load: $functionName from $($import.FullName)"
                
                try {
                    . $import.FullName
                    
                    # Small delay to ensure function is registered
                    Start-Sleep -Milliseconds 10
                    
                    # Verify the function was actually loaded
                    if (Get-Command $functionName -ErrorAction SilentlyContinue) {
                        Write-Verbose "Successfully loaded public function: $functionName"
                    } else {
                        Write-Warning "Function $functionName not found after loading $($import.FullName)"
                    }
                } catch {
                    Write-Warning "Failed to import public function $($import.FullName): $($_.Exception.Message)"
                }
            }
        } else {
            Write-Warning "Public functions directory not found at: $PublicPath"
        }
        
        $script:ModuleInitialized = $true
        
    } catch {
        Write-Warning "Fallback initialization failed: $($_.Exception.Message)"
        $script:InitializationErrors += $_.Exception.Message
    }
}

# Export all functions
$ModuleFunctions = @('Import-PrivateScripts', 'Get-WindowsMissingRecovery', 'Set-WindowsMissingRecovery')

# Get all loaded functions
$AllFunctions = @()
$AllFunctions += $ModuleFunctions

# Add initialization functions if available
if (Get-Command Initialize-WindowsMissingRecoveryModule -ErrorAction SilentlyContinue) {
    $AllFunctions += 'Initialize-WindowsMissingRecoveryModule'
}
if (Get-Command Get-ModuleInitializationStatus -ErrorAction SilentlyContinue) {
    $AllFunctions += 'Get-ModuleInitializationStatus'
}

# Add public functions
$PublicPath = Join-Path $PSScriptRoot "Public"
if (Test-Path $PublicPath) {
    $PublicScripts = Get-ChildItem -Path "$PublicPath\*.ps1" -ErrorAction SilentlyContinue
    foreach ($script in $PublicScripts) {
        $AllFunctions += $script.BaseName
    }
}

# Only export functions that actually exist
$ExistingFunctions = @()
foreach ($funcName in $AllFunctions) {
    if (Get-Command $funcName -ErrorAction SilentlyContinue) {
        $ExistingFunctions += $funcName
    } else {
        Write-Warning "Function $funcName not found, skipping export"
    }
}

if ($ExistingFunctions.Count -gt 0) {
    Export-ModuleMember -Function $ExistingFunctions
    Write-Verbose "Exported $($ExistingFunctions.Count) functions: $($ExistingFunctions -join ', ')"
} else {
    Write-Warning "No functions were successfully loaded to export"
}

# Export configuration variable
Set-Variable -Name "WindowsMissingRecoveryConfig" -Value $script:Config -Scope Global -Force

# Module initialization complete message
if ($script:ModuleInitialized) {
    Write-Verbose "WindowsMissingRecovery module loaded successfully"
    if ($script:InitializationErrors.Count -gt 0) {
        Write-Warning "Module loaded with errors: $($script:InitializationErrors -join '; ')"
    }
} else {
    Write-Warning "Module loaded but initialization may be incomplete"
} 