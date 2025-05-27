# Module metadata
$ModuleName = "WindowsMissingRecovery"
$ModuleVersion = "1.0.0"

# Define public and private functions
$Public = @(Get-ChildItem -Path "$PSScriptRoot\Public\*.ps1" -ErrorAction SilentlyContinue)
$Private = @(Get-ChildItem -Path "$PSScriptRoot\Private\*.ps1" -ErrorAction SilentlyContinue)

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

# Initialize module configuration
function Initialize-ModuleConfig {
    param(
        [switch]$Force
    )

    if ($script:Config.IsInitialized -and !$Force) {
        return $true
    }

    # Try local config first
    $configFile = Join-Path $PSScriptRoot "config.env"
    
    # If local config doesn't exist, try backup location if we know it
    if (!(Test-Path $configFile) -and $script:Config.BackupRoot) {
        $backupConfig = Join-Path $script:Config.BackupRoot "config.env"
        if (Test-Path $backupConfig) {
            $configFile = $backupConfig
        }
    }

    if (Test-Path $configFile) {
        Get-Content $configFile | ForEach-Object {
            if ($_ -match '^([^=]+)=(.*)$') {
                $script:Config[$matches[1]] = $matches[2]
            }
        }
        $script:Config.IsInitialized = $true
        return $true
    }

    return $false
}

# Check if configuration is ready for use
function Test-ConfigurationReady {
    if (-not $script:Config.IsInitialized) {
        Write-Warning "Configuration not initialized. Please run Initialize-WindowsMissingRecovery."
        return $false
    }
    
    if (-not $script:Config.BackupRoot) {
        Write-Warning "Backup location not configured. Please run Install-WindowsMissingRecovery."
        return $false
    }
    
    return $true
}

# Save module configuration
function Save-ModuleConfig {
    if (!$script:Config.BackupRoot) {
        throw "BackupRoot not configured. Please run Initialize-WindowsMissingRecovery first."
    }

    $configContent = @()
    foreach ($key in $script:Config.Keys) {
        if ($key -ne 'IsInitialized') {  # Don't persist internal state
            $configContent += "$key=$($script:Config[$key])"
        }
    }

    # Save to local installation directory - ensure directory exists
    $localConfigDir = $script:Config.WindowsMissingRecoveryPath
    if (!(Test-Path -Path $localConfigDir)) {
        try {
            New-Item -ItemType Directory -Path $localConfigDir -Force | Out-Null
            Write-Host "Created scripts directory: $localConfigDir" -ForegroundColor Green
        } catch {
            Write-Warning "Could not create directory: $localConfigDir - $_"
        }
    }
    
    $localConfigPath = Join-Path $localConfigDir "config.env"
    try {
        Set-Content -Path $localConfigPath -Value $configContent -ErrorAction Stop
    } catch {
        Write-Warning "Could not write to local config path: $localConfigPath - $_"
    }

    # Save to backup directory
    $backupConfigPath = Join-Path $script:Config.BackupRoot "config.env"
    if (!(Test-Path (Split-Path $backupConfigPath -Parent))) {
        New-Item -ItemType Directory -Path (Split-Path $backupConfigPath -Parent) -Force | Out-Null
    }
    
    try {
        Set-Content -Path $backupConfigPath -Value $configContent -ErrorAction Stop
    } catch {
        Write-Warning "Could not write to backup config path: $backupConfigPath - $_"
    }
}

# Get current configuration
function Get-WindowsMissingRecovery {
    if (!(Initialize-ModuleConfig)) {
        Write-Warning "Configuration not initialized. Please run Initialize-WindowsMissingRecovery."
    }
    return $script:Config
}

# Set configuration values
function Set-WindowsMissingRecovery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$BackupRoot,
        
        [Parameter(Mandatory=$false)]
        [string]$MachineName,
        
        [Parameter(Mandatory=$false)]
        [string]$WindowsMissingRecoveryPath,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('OneDrive', 'GoogleDrive', 'Dropbox', 'Box', 'Custom')]
        [string]$CloudProvider,
        
        # Email Settings
        [Parameter(Mandatory=$false)]
        [string]$EmailFromAddress,
        [Parameter(Mandatory=$false)]
        [string]$EmailToAddress,
        [Parameter(Mandatory=$false)]
        [SecureString]$EmailPassword,
        [Parameter(Mandatory=$false)]
        [string]$EmailSmtpServer,
        [Parameter(Mandatory=$false)]
        [int]$EmailSmtpPort,
        [Parameter(Mandatory=$false)]
        [bool]$EmailEnableSsl,
        
        # Backup Settings
        [Parameter(Mandatory=$false)]
        [int]$BackupRetentionDays,
        [Parameter(Mandatory=$false)]
        [string[]]$BackupExcludePaths,
        [Parameter(Mandatory=$false)]
        [string[]]$BackupIncludePaths,
        
        # Schedule Settings
        [Parameter(Mandatory=$false)]
        [string]$BackupSchedule,
        [Parameter(Mandatory=$false)]
        [string]$UpdateSchedule,
        
        # Notification Settings
        [Parameter(Mandatory=$false)]
        [bool]$EnableEmailNotifications,
        [Parameter(Mandatory=$false)]
        [bool]$NotifyOnSuccess,
        [Parameter(Mandatory=$false)]
        [bool]$NotifyOnFailure,
        
        # Recovery Settings
        [Parameter(Mandatory=$false)]
        [string]$RecoveryMode,
        [Parameter(Mandatory=$false)]
        [bool]$ForceOverwrite,
        
        # Logging Settings
        [Parameter(Mandatory=$false)]
        [string]$LogPath,
        [Parameter(Mandatory=$false)]
        [string]$LogLevel,
        
        # Update Settings
        [Parameter(Mandatory=$false)]
        [bool]$AutoUpdateEnabled,
        [Parameter(Mandatory=$false)]
        [string[]]$UpdateExcludePackages
    )
    
    # Update configuration if parameters provided
    if ($BackupRoot) { 
        $script:Config.BackupRoot = $BackupRoot
        if (!(Test-Path $BackupRoot)) {
            New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
        }
    }
    if ($MachineName) { $script:Config.MachineName = $MachineName }
    if ($WindowsMissingRecoveryPath) { $script:Config.WindowsMissingRecoveryPath = $WindowsMissingRecoveryPath }
    if ($CloudProvider) { $script:Config.CloudProvider = $CloudProvider }
    
    # Email Settings
    if ($EmailFromAddress) { $script:Config.EmailSettings.FromAddress = $EmailFromAddress }
    if ($EmailToAddress) { $script:Config.EmailSettings.ToAddress = $EmailToAddress }
    if ($EmailPassword) { $script:Config.EmailSettings.Password = ConvertFrom-SecureString $EmailPassword }
    if ($EmailSmtpServer) { $script:Config.EmailSettings.SmtpServer = $EmailSmtpServer }
    if ($EmailSmtpPort) { $script:Config.EmailSettings.SmtpPort = $EmailSmtpPort }
    if ($PSBoundParameters.ContainsKey('EmailEnableSsl')) { $script:Config.EmailSettings.EnableSsl = $EmailEnableSsl }
    
    # Backup Settings
    if ($BackupRetentionDays) { $script:Config.BackupSettings.RetentionDays = $BackupRetentionDays }
    if ($BackupExcludePaths) { $script:Config.BackupSettings.ExcludePaths = $BackupExcludePaths }
    if ($BackupIncludePaths) { $script:Config.BackupSettings.IncludePaths = $BackupIncludePaths }
    
    # Schedule Settings
    if ($BackupSchedule) { $script:Config.ScheduleSettings.BackupSchedule = $BackupSchedule }
    if ($UpdateSchedule) { $script:Config.ScheduleSettings.UpdateSchedule = $UpdateSchedule }
    
    # Notification Settings
    if ($PSBoundParameters.ContainsKey('EnableEmailNotifications')) { $script:Config.NotificationSettings.EnableEmail = $EnableEmailNotifications }
    if ($PSBoundParameters.ContainsKey('NotifyOnSuccess')) { $script:Config.NotificationSettings.NotifyOnSuccess = $NotifyOnSuccess }
    if ($PSBoundParameters.ContainsKey('NotifyOnFailure')) { $script:Config.NotificationSettings.NotifyOnFailure = $NotifyOnFailure }
    
    # Recovery Settings
    if ($RecoveryMode) { $script:Config.RecoverySettings.Mode = $RecoveryMode }
    if ($PSBoundParameters.ContainsKey('ForceOverwrite')) { $script:Config.RecoverySettings.ForceOverwrite = $ForceOverwrite }
    
    # Logging Settings
    if ($LogPath) { $script:Config.LoggingSettings.Path = $LogPath }
    if ($LogLevel) { $script:Config.LoggingSettings.Level = $LogLevel }
    
    # Update Settings
    if ($PSBoundParameters.ContainsKey('AutoUpdateEnabled')) { $script:Config.UpdateSettings.AutoUpdate = $AutoUpdateEnabled }
    if ($UpdateExcludePackages) { $script:Config.UpdateSettings.ExcludePackages = $UpdateExcludePackages }
    
    # Update last configured timestamp
    $script:Config.LastConfigured = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    # Save the updated configuration
    Save-ModuleConfig
}

# Initialize module configuration
Initialize-ModuleConfig

# Only load specific scripts to avoid errors
# First load core scripts
$CoreScripts = @(
    "Initialize-WindowsMissingRecovery.ps1",
    "Install-WindowsMissingRecoveryTasks.ps1",
    "Remove-WindowsMissingRecoveryTasks.ps1",
    "Test-WindowsMissingRecovery.ps1",
    "Setup-WindowsMissingRecovery.ps1"
)

# Dot source core files
foreach ($import in $Public) {
    if ($CoreScripts -contains $import.Name) {
        try {
            . $import.FullName
        } catch {
            Write-Error "Failed to import core function $($import.FullName): $_"
        }
    }
}

# Dot source other files only if configuration is ready
if (Test-ConfigurationReady) {
    # Dot source the rest of the files
    foreach ($import in @($Public + $Private)) {
        if ($CoreScripts -notcontains $import.Name) {
            try {
                . $import.FullName
            } catch {
                Write-Error "Failed to import function $($import.FullName): $_"
            }
        }
    }
}

# Export public functions
Export-ModuleMember -Function ($Public.BaseName + @(
    'Get-WindowsMissingRecovery',
    'Set-WindowsMissingRecovery',
    'Initialize-ModuleConfig',
    'Test-ConfigurationReady'
)) 