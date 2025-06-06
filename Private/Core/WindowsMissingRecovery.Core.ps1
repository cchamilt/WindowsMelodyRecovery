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
    'Initialize-ModuleFromConfig'
) 