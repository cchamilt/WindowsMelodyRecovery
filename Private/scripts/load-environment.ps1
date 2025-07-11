# Load environment variables and settings for WindowsMelodyRecovery
# This script should be sourced using dot-sourcing, not executed directly

# Check if environment is already loaded
if ($script:EnvironmentLoaded) {
    return $true
}

# Default locations - all based on environment variables, nothing hardcoded
$DEFAULT_USER_PROFILE = if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME }
if (-not $DEFAULT_USER_PROFILE) {
    $DEFAULT_USER_PROFILE = "/tmp"
    Write-Warning "Could not determine user profile directory, using /tmp"
}

$DEFAULT_WINDOWS_CONFIG_PATH = Join-Path $DEFAULT_USER_PROFILE "Scripts\WindowsConfig"
$DEFAULT_CONFIG_FILE = Join-Path $DEFAULT_WINDOWS_CONFIG_PATH "windows.env"

# Check for OneDrive presence generically
$DEFAULT_ONEDRIVE_PATHS = @(
    # Check standard OneDrive paths without specific organization names
    (Join-Path $DEFAULT_USER_PROFILE "OneDrive")
)

# Look for any OneDrive folders (personal or business) without hardcoding org names
$oneDriveFolder = Get-ChildItem -Path $DEFAULT_USER_PROFILE -Directory -Filter "OneDrive*" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
if ($oneDriveFolder) {
    $DEFAULT_ONEDRIVE_PATHS += $oneDriveFolder
}

# Machine name handling
$MACHINE_NAME = $env:COMPUTERNAME
if (!$MACHINE_NAME) {
    $MACHINE_NAME = "UNKNOWN"
    Write-Warning "Could not determine machine name, using 'UNKNOWN'"
}

# Try to load configuration from file
function Import-EnvFile {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )

    if (Test-Path $Path) {
        Get-Content $Path | ForEach-Object {
            if (-not [string]::IsNullOrWhiteSpace($_) -and -not $_.StartsWith("#")) {
                $key, $value = $_.Split('=', 2)
                if ($key -and $value) {
                    Set-Item -Path "env:$key" -Value $value.Trim() -Force
                    Write-Verbose "Loaded environment variable: $key"
                }
            }
        }
        return $true
    } else {
        Write-Host "Base configuration file not found: $Path" -ForegroundColor Yellow
        return $false
    }
}

# Attempt to load from configuration file
$configLoaded = Import-EnvFile -Path $DEFAULT_CONFIG_FILE

# If config loaded, verify required variables
if ($configLoaded) {
    # Check required variables
    $requiredVars = @("BACKUP_ROOT", "CLOUD_PROVIDER")
    $missingVars = @()

    foreach ($var in $requiredVars) {
        if (-not (Get-Item "env:$var" -ErrorAction SilentlyContinue)) {
            $missingVars += $var
        }
    }

    if ($missingVars.Count -gt 0) {
        Write-Warning "Missing required variables in configuration: $($missingVars -join ', ')"
        Write-Host "Please update your configuration file: $DEFAULT_CONFIG_FILE" -ForegroundColor Yellow
        $configLoaded = $false
    }
} else {
    Write-Host "Failed to load environment configuration" -ForegroundColor Yellow
}

# Set backup paths
if ($configLoaded -and $env:BACKUP_ROOT) {
    $BACKUP_ROOT = $env:BACKUP_ROOT
} else {
    # Try generic OneDrive paths without hardcoding organization names
    $foundOneDrive = $false

    foreach ($path in $DEFAULT_ONEDRIVE_PATHS) {
        if ($path -and (Test-Path $path)) {
            $BACKUP_ROOT = $path
            Write-Host "Using default backup path: $BACKUP_ROOT\WindowsMelodyRecovery\$MACHINE_NAME" -ForegroundColor Yellow
            $foundOneDrive = $true
            break
        }
    }

    if (-not $foundOneDrive) {
        $BACKUP_ROOT = $DEFAULT_USER_PROFILE
        Write-Warning "OneDrive not found, using profile directory for backup: $BACKUP_ROOT\WindowsMelodyRecovery\$MACHINE_NAME"
    }
}

# Export variables to be used by other scripts
$WINDOWS_MELODY_RECOVERY_PATH = if ($env:WINDOWS_MELODY_RECOVERY_PATH) {
    $env:WINDOWS_MELODY_RECOVERY_PATH
} else {
    Join-Path $DEFAULT_WINDOWS_CONFIG_PATH "WindowsMelodyRecovery"
}

$CLOUD_PROVIDER = if ($env:CLOUD_PROVIDER) { $env:CLOUD_PROVIDER } else { $null }

# Export these variables
$env:BACKUP_ROOT = $BACKUP_ROOT
$env:MACHINE_NAME = $MACHINE_NAME
$env:WINDOWS_MELODY_RECOVERY_PATH = $WINDOWS_MELODY_RECOVERY_PATH
$env:CLOUD_PROVIDER = $CLOUD_PROVIDER

# Mark environment as loaded
$script:EnvironmentLoaded = $true

# Return success/failure
return $configLoaded