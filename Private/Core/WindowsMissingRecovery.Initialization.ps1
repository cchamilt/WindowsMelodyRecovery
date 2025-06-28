# WindowsMissingRecovery Module Initialization System
# This file handles all module initialization, configuration loading, and setup

# Module initialization state
$script:ModuleInitialized = $false
$script:InitializationErrors = @()
$script:LoadedComponents = @()

function Initialize-WindowsMissingRecoveryModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [switch]$Force,
        
        [Parameter(Mandatory=$false)]
        [switch]$SkipValidation,
        
        [Parameter(Mandatory=$false)]
        [string]$ConfigPath,
        
        [Parameter(Mandatory=$false)]
        [hashtable]$OverrideConfig
    )
    
    Write-Verbose "Starting WindowsMissingRecovery module initialization..."
    
    try {
        # Step 1: Validate module structure
        if (-not $SkipValidation) {
            $validationResult = Test-ModuleStructure
            if (-not $validationResult.Success) {
                throw "Module structure validation failed: $($validationResult.Message)"
            }
        }
        
        # Step 2: Load core configuration
        $configResult = Initialize-ModuleConfiguration -ConfigPath $ConfigPath -OverrideConfig $OverrideConfig
        if (-not $configResult.Success) {
            throw "Configuration initialization failed: $($configResult.Message)"
        }
        
        # Step 3: Load core utilities
        $coreResult = Load-CoreUtilities
        if (-not $coreResult.Success) {
            throw "Core utilities loading failed: $($coreResult.Message)"
        }
        
        # Step 4: Load public functions
        $publicResult = Load-PublicFunctions
        if (-not $publicResult.Success) {
            throw "Public functions loading failed: $($publicResult.Message)"
        }
        
        # Step 5: Setup module environment
        $envResult = Setup-ModuleEnvironment
        if (-not $envResult.Success) {
            throw "Environment setup failed: $($envResult.Message)"
        }
        
        # Step 6: Validate dependencies
        $depResult = Test-ModuleDependencies
        if (-not $depResult.Success) {
            Write-Warning "Dependency validation failed: $($depResult.Message)"
            $script:InitializationErrors += $depResult.Message
        }
        
        # Step 7: Setup aliases
        $aliasResult = Setup-ModuleAliases
        if (-not $aliasResult.Success) {
            Write-Warning "Alias setup failed: $($aliasResult.Message)"
            $script:InitializationErrors += $aliasResult.Message
        }
        
        # Mark module as initialized
        $script:ModuleInitialized = $true
        $script:Config.IsInitialized = $true
        $script:Config.LastInitialized = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
        
        Write-Verbose "Module initialization completed successfully"
        Write-Verbose "Loaded components: $($script:LoadedComponents -join ', ')"
        
        if ($script:InitializationErrors.Count -gt 0) {
            Write-Warning "Module initialized with warnings: $($script:InitializationErrors -join '; ')"
        }
        
        return @{
            Success = $true
            Message = "Module initialized successfully"
            LoadedComponents = $script:LoadedComponents
            Warnings = $script:InitializationErrors
        }
        
    } catch {
        $script:ModuleInitialized = $false
        $script:InitializationErrors += $_.Exception.Message
        
        Write-Error "Module initialization failed: $($_.Exception.Message)"
        return @{
            Success = $false
            Message = $_.Exception.Message
            LoadedComponents = $script:LoadedComponents
            Errors = $script:InitializationErrors
        }
    }
}

function Test-ModuleStructure {
    [CmdletBinding()]
    param()
    
    Write-Verbose "Validating module structure..."
    
    $requiredPaths = @(
        "Private",
        "Private\Core",
        "Private\backup",
        "Private\restore",
        "Private\setup",
        "Private\tasks",
        "Private\scripts",
        "Public",
        "Config",
        "Templates"
    )
    
    $missingPaths = @()
    foreach ($path in $requiredPaths) {
        $fullPath = Join-Path $PSScriptRoot ".." $path
        if (-not (Test-Path $fullPath)) {
            $missingPaths += $path
        }
    }
    
    if ($missingPaths.Count -gt 0) {
        return @{
            Success = $false
            Message = "Missing required directories: $($missingPaths -join ', ')"
        }
    }
    
    $requiredFiles = @(
        "Private\Core\WindowsMissingRecovery.Core.ps1",
        "WindowsMissingRecovery.psm1",
        "WindowsMissingRecovery.psd1"
    )
    
    $missingFiles = @()
    foreach ($file in $requiredFiles) {
        $fullPath = Join-Path $PSScriptRoot ".." $file
        if (-not (Test-Path $fullPath)) {
            $missingFiles += $file
        }
    }
    
    if ($missingFiles.Count -gt 0) {
        return @{
            Success = $false
            Message = "Missing required files: $($missingFiles -join ', ')"
        }
    }
    
    return @{
        Success = $true
        Message = "Module structure validation passed"
    }
}

function Initialize-ModuleConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$ConfigPath,
        
        [Parameter(Mandatory=$false)]
        [hashtable]$OverrideConfig
    )
    
    Write-Verbose "Initializing module configuration..."
    
    try {
        # Try to load from provided config path first
        if ($ConfigPath -and (Test-Path $ConfigPath)) {
            $configResult = Load-ConfigurationFromFile -ConfigPath $ConfigPath
            if ($configResult.Success) {
                $script:LoadedComponents += "ExternalConfig"
                return $configResult
            }
        }
        
        # Try to load from module config directory
        $moduleConfigPath = Join-Path (Split-Path $PSScriptRoot -Parent) "Config\windows.env"
        if (Test-Path $moduleConfigPath) {
            $configResult = Load-ConfigurationFromFile -ConfigPath $moduleConfigPath
            if ($configResult.Success) {
                $script:LoadedComponents += "ModuleConfig"
                return $configResult
            }
        }
        
        # Try to load from template
        $templateConfigPath = Join-Path (Split-Path $PSScriptRoot -Parent) "Templates\windows.env.template"
        if (Test-Path $templateConfigPath) {
            $configResult = Load-ConfigurationFromTemplate -TemplatePath $templateConfigPath
            if ($configResult.Success) {
                $script:LoadedComponents += "TemplateConfig"
                return $configResult
            }
        }
        
        # Use default configuration
        $defaultConfig = Get-DefaultConfiguration
        if ($OverrideConfig) {
            $defaultConfig = Merge-Configurations -Base $defaultConfig -Override $OverrideConfig
        }
        
        $script:Config = $defaultConfig
        $script:LoadedComponents += "DefaultConfig"
        
        return @{
            Success = $true
            Message = "Default configuration loaded"
        }
        
    } catch {
        return @{
            Success = $false
            Message = "Configuration initialization failed: $($_.Exception.Message)"
        }
    }
}

function Load-ConfigurationFromFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ConfigPath
    )
    
    try {
        if (-not (Test-Path $ConfigPath)) {
            return @{
                Success = $false
                Message = "Configuration file not found: $ConfigPath"
            }
        }
        
        $configContent = Get-Content $ConfigPath -Raw
        $config = @{}
        
        # Parse key-value pairs
        $lines = $configContent -split "`n" | Where-Object { $_ -match '^([^#][^=]+)=(.*)$' }
        foreach ($line in $lines) {
            if ($line -match '^([^=]+)=(.*)$') {
                $key = $matches[1].Trim()
                $value = $matches[2].Trim()
                $config[$key] = $value
            }
        }
        
        # Update module configuration
        if ($config.BACKUP_ROOT) { $script:Config.BackupRoot = $config.BACKUP_ROOT }
        if ($config.MACHINE_NAME) { $script:Config.MachineName = $config.MACHINE_NAME }
        if ($config.WINDOWS_MISSING_RECOVERY_PATH) { $script:Config.WindowsMissingRecoveryPath = $config.WINDOWS_MISSING_RECOVERY_PATH }
        if ($config.CLOUD_PROVIDER) { $script:Config.CloudProvider = $config.CLOUD_PROVIDER }
        
        return @{
            Success = $true
            Message = "Configuration loaded from: $ConfigPath"
        }
        
    } catch {
        return @{
            Success = $false
            Message = "Failed to load configuration from $ConfigPath : $($_.Exception.Message)"
        }
    }
}

function Load-ConfigurationFromTemplate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$TemplatePath
    )
    
    try {
        if (-not (Test-Path $TemplatePath)) {
            return @{
                Success = $false
                Message = "Template file not found: $TemplatePath"
            }
        }
        
        $templateContent = Get-Content $TemplatePath -Raw
        $config = @{}
        
        # Parse template and substitute environment variables
        $lines = $templateContent -split "`n" | Where-Object { $_ -match '^([^#][^=]+)=(.*)$' }
        foreach ($line in $lines) {
            if ($line -match '^([^=]+)=(.*)$') {
                $key = $matches[1].Trim()
                $value = $matches[2].Trim()
                
                # Substitute environment variables
                $value = [System.Environment]::ExpandEnvironmentVariables($value)
                $config[$key] = $value
            }
        }
        
        # Update module configuration
        if ($config.BACKUP_ROOT) { $script:Config.BackupRoot = $config.BACKUP_ROOT }
        if ($config.MACHINE_NAME) { $script:Config.MachineName = $config.MACHINE_NAME }
        if ($config.WINDOWS_MISSING_RECOVERY_PATH) { $script:Config.WindowsMissingRecoveryPath = $config.WINDOWS_MISSING_RECOVERY_PATH }
        if ($config.CLOUD_PROVIDER) { $script:Config.CloudProvider = $config.CLOUD_PROVIDER }
        
        return @{
            Success = $true
            Message = "Configuration loaded from template: $TemplatePath"
        }
        
    } catch {
        return @{
            Success = $false
            Message = "Failed to load configuration from template $TemplatePath : $($_.Exception.Message)"
        }
    }
}

function Get-DefaultConfiguration {
    [CmdletBinding()]
    param()
    
    return @{
        BackupRoot = if ($env:TEMP) { Join-Path $env:TEMP "WindowsMissingRecovery\Backups" } else { "/tmp/WindowsMissingRecovery/Backups" }
        MachineName = $env:COMPUTERNAME
        WindowsMissingRecoveryPath = Split-Path $PSScriptRoot -Parent
        CloudProvider = "OneDrive"
        ModuleVersion = "1.0.0"
        LastConfigured = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
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
            Path = if ($env:TEMP) { Join-Path $env:TEMP "WindowsMissingRecovery\Logs" } else { "/tmp/WindowsMissingRecovery/Logs" }
            Level = "Information"
        }
        UpdateSettings = @{
            AutoUpdate = $true
            ExcludePackages = @()
        }
    }
}

function Merge-Configurations {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Base,
        
        [Parameter(Mandatory=$true)]
        [hashtable]$Override
    )
    
    $merged = $Base.Clone()
    
    foreach ($key in $Override.Keys) {
        if ($Override[$key] -is [hashtable] -and $merged[$key] -is [hashtable]) {
            $merged[$key] = Merge-Configurations -Base $merged[$key] -Override $Override[$key]
        } else {
            $merged[$key] = $Override[$key]
        }
    }
    
    return $merged
}

function Load-CoreUtilities {
    [CmdletBinding()]
    param()
    
    Write-Verbose "Loading core utilities..."
    
    try {
        # Core utilities are already loaded via ScriptsToProcess in the manifest
        # Just verify they're available
        $coreFunctions = @(
            'Load-Environment',
            'Get-ConfigValue',
            'Set-ConfigValue',
            'Test-ModuleInitialized',
            'Get-BackupRoot',
            'Get-MachineName',
            'Get-CloudProvider',
            'Get-ModulePath',
            'Get-ScriptsConfig',
            'Set-ScriptsConfig',
            'Initialize-ModuleFromConfig'
        )
        
        $missingFunctions = @()
        foreach ($function in $coreFunctions) {
            if (-not (Get-Command $function -ErrorAction SilentlyContinue)) {
                $missingFunctions += $function
            }
        }
        
        if ($missingFunctions.Count -gt 0) {
            return @{
                Success = $false
                Message = "Missing core functions: $($missingFunctions -join ', ')"
            }
        }
        
        $script:LoadedComponents += "CoreUtilities"
        
        return @{
            Success = $true
            Message = "Core utilities loaded successfully"
        }
        
    } catch {
        return @{
            Success = $false
            Message = "Failed to load core utilities: $($_.Exception.Message)"
        }
    }
}

function Load-PublicFunctions {
    [CmdletBinding()]
    param()
    
    Write-Verbose "Loading public functions..."
    
    try {
        $publicPath = Join-Path (Split-Path $PSScriptRoot -Parent) "Public"
        if (-not (Test-Path $publicPath)) {
            return @{
                Success = $false
                Message = "Public functions directory not found: $publicPath"
            }
        }
        
        $publicScripts = Get-ChildItem -Path "$publicPath\*.ps1" -ErrorAction SilentlyContinue
        $loadedFunctions = @()
        $failedFunctions = @()
        
        foreach ($script in $publicScripts) {
            try {
                $functionName = $script.BaseName
                Write-Verbose "Loading function: $functionName from $($script.FullName)"
                
                . $script.FullName
                
                # Verify function was loaded
                if (Get-Command $functionName -ErrorAction SilentlyContinue) {
                    $loadedFunctions += $functionName
                } else {
                    $failedFunctions += $functionName
                }
            } catch {
                $failedFunctions += $script.BaseName
                Write-Warning "Failed to load function $($script.BaseName): $($_.Exception.Message)"
            }
        }
        
        if ($failedFunctions.Count -gt 0) {
            Write-Warning "Failed to load functions: $($failedFunctions -join ', ')"
        }
        
        $script:LoadedComponents += "PublicFunctions"
        
        return @{
            Success = $loadedFunctions.Count -gt 0
            Message = "Loaded $($loadedFunctions.Count) public functions"
            LoadedFunctions = $loadedFunctions
            FailedFunctions = $failedFunctions
        }
        
    } catch {
        return @{
            Success = $false
            Message = "Failed to load public functions: $($_.Exception.Message)"
        }
    }
}

function Setup-ModuleEnvironment {
    [CmdletBinding()]
    param()
    
    Write-Verbose "Setting up module environment..."
    
    try {
        # Create necessary directories
        $directories = @(
            $script:Config.BackupRoot,
            $script:Config.LoggingSettings.Path,
            (Join-Path $script:Config.WindowsMissingRecoveryPath "Config"),
            (Join-Path $script:Config.WindowsMissingRecoveryPath "Logs"),
            (Join-Path $script:Config.WindowsMissingRecoveryPath "Temp")
        )
        
        foreach ($dir in $directories) {
            if (-not (Test-Path $dir)) {
                New-Item -Path $dir -ItemType Directory -Force | Out-Null
                Write-Verbose "Created directory: $dir"
            }
        }
        
        # Set up logging
        $logFile = Join-Path $script:Config.LoggingSettings.Path "WindowsMissingRecovery.log"
        $script:Config.LoggingSettings.LogFile = $logFile
        
        # Export configuration variable
        Set-Variable -Name "WindowsMissingRecoveryConfig" -Value $script:Config -Scope Global -Force
        
        $script:LoadedComponents += "ModuleEnvironment"
        
        return @{
            Success = $true
            Message = "Module environment setup completed"
        }
        
    } catch {
        return @{
            Success = $false
            Message = "Failed to setup module environment: $($_.Exception.Message)"
        }
    }
}

function Test-ModuleDependencies {
    [CmdletBinding()]
    param()
    
    Write-Verbose "Testing module dependencies..."
    
    try {
        $dependencies = @(
            @{ Name = "Pester"; ModuleName = "Pester" },
            @{ Name = "PowerShell"; Version = "5.1" }
        )
        
        $missingDeps = @()
        $warnings = @()
        
        foreach ($dep in $dependencies) {
            if ($dep.ModuleName) {
                $module = Get-Module -Name $dep.ModuleName -ListAvailable -ErrorAction SilentlyContinue
                if (-not $module) {
                    $missingDeps += $dep.Name
                }
            }
        }
        
        # Test PowerShell version
        if ($PSVersionTable.PSVersion.Major -lt 5) {
            $warnings += "PowerShell 5.1 or higher recommended"
        }
        
        if ($missingDeps.Count -gt 0) {
            return @{
                Success = $false
                Message = "Missing dependencies: $($missingDeps -join ', ')"
            }
        }
        
        if ($warnings.Count -gt 0) {
            return @{
                Success = $true
                Message = "Dependencies validated with warnings: $($warnings -join '; ')"
                Warnings = $warnings
            }
        }
        
        return @{
            Success = $true
            Message = "All dependencies validated successfully"
        }
        
    } catch {
        return @{
            Success = $false
            Message = "Dependency validation failed: $($_.Exception.Message)"
        }
    }
}

function Setup-ModuleAliases {
    [CmdletBinding()]
    param()
    
    Write-Verbose "Setting up module aliases..."
    
    try {
        $aliases = @{
            "wmr-init" = "Initialize-WindowsMissingRecovery"
            "wmr-backup" = "Backup-WindowsMissingRecovery"
            "wmr-restore" = "Restore-WindowsMissingRecovery"
            "wmr-setup" = "Setup-WindowsMissingRecovery"
            "wmr-test" = "Test-WindowsMissingRecovery"
        }
        
        $createdAliases = @()
        $failedAliases = @()
        
        foreach ($alias in $aliases.Keys) {
            try {
                if (-not (Get-Alias -Name $alias -ErrorAction SilentlyContinue)) {
                    Set-Alias -Name $alias -Value $aliases[$alias] -Scope Global
                    $createdAliases += $alias
                }
            } catch {
                $failedAliases += $alias
            }
        }
        
        if ($failedAliases.Count -gt 0) {
            return @{
                Success = $false
                Message = "Failed to create aliases: $($failedAliases -join ', ')"
            }
        }
        
        $script:LoadedComponents += "ModuleAliases"
        
        return @{
            Success = $true
            Message = "Created $($createdAliases.Count) module aliases"
            CreatedAliases = $createdAliases
        }
        
    } catch {
        return @{
            Success = $false
            Message = "Failed to setup module aliases: $($_.Exception.Message)"
        }
    }
}

function Get-ModuleInitializationStatus {
    [CmdletBinding()]
    param()
    
    return @{
        Initialized = $script:ModuleInitialized
        LoadedComponents = $script:LoadedComponents
        Errors = $script:InitializationErrors
        Config = $script:Config
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Initialize-WindowsMissingRecoveryModule',
    'Get-ModuleInitializationStatus',
    'Test-ModuleStructure',
    'Load-ConfigurationFromFile',
    'Load-ConfigurationFromTemplate',
    'Get-DefaultConfiguration',
    'Merge-Configurations',
    'Load-CoreUtilities',
    'Load-PublicFunctions',
    'Setup-ModuleEnvironment',
    'Test-ModuleDependencies',
    'Setup-ModuleAliases'
) 