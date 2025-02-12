function Load-Environment {
    param(
        [Parameter(Mandatory=$false)]
        [string]$EnvFile
    )

    $envVars = @{}

    # First load windows.env for base configuration
    if (!$EnvFile) {
        $EnvFile = Join-Path $env:WINDOWS_CONFIG_PATH "windows.env"
    }

    if (Test-Path $EnvFile) {
        Get-Content $EnvFile | Where-Object { $_ -match '^[^#]' } | ForEach-Object {
            $name, $value = $_.split('=')
            $value = $value.Trim('"')
            $envVars[$name.Trim()] = $ExecutionContext.InvokeCommand.ExpandString($value)
            [Environment]::SetEnvironmentVariable($name.Trim(), $ExecutionContext.InvokeCommand.ExpandString($value), 'Process')
        }
    } else {
        Write-Host "Base configuration file not found: $EnvFile" -ForegroundColor Red
        return $false
    }

    # Now look for config.env in machine-specific or shared backup locations
    $configLocations = @(
        (Join-Path (Join-Path $envVars.BACKUP_ROOT $envVars.MACHINE_NAME) "config.env"),
        (Join-Path (Join-Path $envVars.BACKUP_ROOT "shared") "config.env")
    )

    $configFound = $false
    foreach ($configFile in $configLocations) {
        if (Test-Path $configFile) {
            Write-Host "Loading configuration from: $configFile" -ForegroundColor Green
            Get-Content $configFile | Where-Object { $_ -match '^[^#]' } | ForEach-Object {
                $name, $value = $_.split('=')
                $value = $value.Trim('"')
                $envVars[$name.Trim()] = $ExecutionContext.InvokeCommand.ExpandString($value)
                [Environment]::SetEnvironmentVariable($name.Trim(), $ExecutionContext.InvokeCommand.ExpandString($value), 'Process')
            }
            $configFound = $true
            break
        }
    }

    if (!$configFound) {
        Write-Host "No config.env found in backup locations. Some features may be limited." -ForegroundColor Yellow
    }

    # Verify required environment variables
    $requiredVars = @(
        'BACKUP_ROOT',
        'WINDOWS_CONFIG_PATH',
        'MACHINE_NAME'
    )

    $missingVars = $requiredVars | Where-Object { !$envVars.ContainsKey($_) }
    if ($missingVars) {
        Write-Host "Missing required environment variables: $($missingVars -join ', ')" -ForegroundColor Red
        return $false
    }

    return $true
} 