# Core utility functions for WindowsMissingRecovery module

function Load-Environment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ConfigPath
    )
    
    if (-not (Test-Path $ConfigPath)) {
        Write-Warning "Configuration file not found at: $ConfigPath"
        return $false
    }
    
    try {
        $config = Get-Content $ConfigPath | ConvertFrom-StringData
        foreach ($key in $config.Keys) {
            Set-Variable -Name $key -Value $config[$key] -Scope Script
        }
        return $true
    } catch {
        Write-Warning "Failed to load environment from ${ConfigPath}: $($_.Exception.Message)"
        return $false
    }
}

function Get-ConfigValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Key
    )
    
    return $script:Config[$Key]
}

function Set-ConfigValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Key,
        
        [Parameter(Mandatory=$true)]
        $Value
    )
    
    $script:Config[$Key] = $Value
}

function Test-ModuleInitialized {
    return $script:Config.IsInitialized
}

function Get-BackupRoot {
    return $script:Config.BackupRoot
}

function Get-MachineName {
    return $script:Config.MachineName
}

function Get-CloudProvider {
    return $script:Config.CloudProvider
}

function Get-ModulePath {
    return $PSScriptRoot
}

function Get-ScriptsConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [ValidateSet('backup', 'restore', 'setup')]
        [string]$Category
    )
    
    # Try to load from user's config directory first, then fall back to module template
    $moduleRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $userConfigPath = Join-Path $moduleRoot "Config\scripts-config.json"
    $templateConfigPath = Join-Path $moduleRoot "Templates\scripts-config.json"
    
    $configPath = if (Test-Path $userConfigPath) { $userConfigPath } else { $templateConfigPath }
    
    if (-not (Test-Path $configPath)) {
        Write-Warning "Scripts configuration not found at: $configPath"
        return $null
    }
    
    try {
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
        
        if ($Category) {
            return $config.$Category.enabled | Where-Object { $_.enabled -eq $true }
        } else {
            return $config
        }
    } catch {
        Write-Warning "Failed to load scripts configuration: $($_.Exception.Message)"
        return $null
    }
}

function Set-ScriptsConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Category,
        
        [Parameter(Mandatory=$true)]
        [string]$ScriptName,
        
        [Parameter(Mandatory=$true)]
        [bool]$Enabled
    )
    
    $moduleRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $userConfigPath = Join-Path $moduleRoot "Config\scripts-config.json"
    $templateConfigPath = Join-Path $moduleRoot "Templates\scripts-config.json"
    
    # Copy template to user config if it doesn't exist
    if (-not (Test-Path $userConfigPath) -and (Test-Path $templateConfigPath)) {
        $configDir = Split-Path $userConfigPath -Parent
        if (-not (Test-Path $configDir)) {
            New-Item -ItemType Directory -Path $configDir -Force | Out-Null
        }
        Copy-Item -Path $templateConfigPath -Destination $userConfigPath -Force
    }
    
    if (-not (Test-Path $userConfigPath)) {
        Write-Error "Cannot create or find scripts configuration file"
        return $false
    }
    
    try {
        $config = Get-Content $userConfigPath -Raw | ConvertFrom-Json
        
        # Find and update the script
        $scriptConfig = $config.$Category.enabled | Where-Object { $_.name -eq $ScriptName -or $_.function -eq $ScriptName }
        if ($scriptConfig) {
            $scriptConfig.enabled = $Enabled
            
            # Save the updated configuration
            $config | ConvertTo-Json -Depth 10 | Set-Content -Path $userConfigPath -Force
            Write-Verbose "Updated $ScriptName in $Category to enabled=$Enabled"
            return $true
        } else {
            Write-Warning "Script '$ScriptName' not found in category '$Category'"
            return $false
        }
    } catch {
        Write-Error "Failed to update scripts configuration: $($_.Exception.Message)"
        return $false
    }
}

function Initialize-ModuleFromConfig {
    # Try to load configuration from the module's config directory
    $moduleRoot = Split-Path $PSScriptRoot -Parent
    $configFile = Join-Path $moduleRoot "Config\windows.env"
    
    if (Test-Path $configFile) {
        try {
            $config = Get-Content $configFile | ConvertFrom-StringData
            
            # Update module configuration from file
            if ($config.BACKUP_ROOT) { $script:Config.BackupRoot = $config.BACKUP_ROOT }
            if ($config.MACHINE_NAME) { $script:Config.MachineName = $config.MACHINE_NAME }
            if ($config.WINDOWS_MISSING_RECOVERY_PATH) { $script:Config.WindowsMissingRecoveryPath = $config.WINDOWS_MISSING_RECOVERY_PATH }
            if ($config.CLOUD_PROVIDER) { $script:Config.CloudProvider = $config.CLOUD_PROVIDER }
            
            $script:Config.IsInitialized = $true
            Write-Verbose "Module configuration loaded from: $configFile"
            return $true
        } catch {
            Write-Warning "Failed to load configuration from: $configFile - $($_.Exception.Message)"
            return $false
        }
    }
    
    return $false
}

# Export functions
Export-ModuleMember -Function @(
    'Load-Environment',
    'Get-ConfigValue',
    'Set-ConfigValue',
    'Test-ModuleInitialized',
    'Get-BackupRoot',
    'Get-MachineName',
    'Get-CloudProvider',
    'Get-ModulePath',
    'Initialize-ModuleFromConfig',
    'Get-ScriptsConfig',
    'Set-ScriptsConfig'
) 