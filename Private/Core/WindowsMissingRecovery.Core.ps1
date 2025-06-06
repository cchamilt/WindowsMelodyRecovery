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

# Export functions
Export-ModuleMember -Function @(
    'Load-Environment',
    'Get-ConfigValue',
    'Set-ConfigValue',
    'Test-ModuleInitialized',
    'Get-BackupRoot',
    'Get-MachineName',
    'Get-CloudProvider',
    'Get-ModulePath'
) 