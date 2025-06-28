# Windows Missing Recovery - Module Initialization

## Overview

The Windows Missing Recovery module uses a comprehensive initialization system that ensures proper loading of all components, validation of dependencies, and setup of the module environment. This document describes how the initialization system works and how to use it.

## Initialization Process

### 1. Module Loading Sequence

When the module is imported, the following sequence occurs:

1. **Module Manifest Processing** - PowerShell loads the module manifest (`WindowsMissingRecovery.psd1`)
2. **ScriptsToProcess Loading** - Core utilities are loaded via `ScriptsToProcess`
3. **Root Module Loading** - The main module file (`WindowsMissingRecovery.psm1`) is executed
4. **Initialization System Loading** - The initialization system is loaded
5. **Component Loading** - Public functions and other components are loaded
6. **Environment Setup** - Module environment is configured
7. **Validation** - Dependencies and structure are validated

### 2. Initialization Components

The initialization system consists of several key components:

#### Core Initialization Functions

- `Initialize-WindowsMissingRecoveryModule` - Main initialization function
- `Get-ModuleInitializationStatus` - Get initialization status
- `Test-ModuleStructure` - Validate module structure
- `Load-CoreUtilities` - Load core utility functions
- `Load-PublicFunctions` - Load public functions
- `Setup-ModuleEnvironment` - Setup module environment
- `Test-ModuleDependencies` - Validate dependencies
- `Setup-ModuleAliases` - Setup module aliases

#### Configuration Management

- `Load-ConfigurationFromFile` - Load configuration from file
- `Load-ConfigurationFromTemplate` - Load configuration from template
- `Get-DefaultConfiguration` - Get default configuration
- `Merge-Configurations` - Merge configuration objects

## Configuration Sources

The module can load configuration from multiple sources in order of priority:

### 1. External Configuration File
```powershell
Initialize-WindowsMissingRecoveryModule -ConfigPath "C:\Custom\config.env"
```

### 2. Module Configuration Directory
```
ModuleRoot/
├── Config/
│   └── windows.env
```

### 3. Template Configuration
```
ModuleRoot/
├── Templates/
│   └── windows.env.template
```

### 4. Default Configuration
If no configuration files are found, default values are used.

## Configuration File Format

Configuration files use a simple key-value format:

```env
# Windows Missing Recovery Configuration
BACKUP_ROOT=C:\Users\Username\Backups\WindowsMissingRecovery
MACHINE_NAME=DESKTOP-ABC123
CLOUD_PROVIDER=OneDrive
WINDOWS_MISSING_RECOVERY_PATH=C:\Scripts\WindowsMissingRecovery
```

## Module Status and Diagnostics

### Get Module Status

```powershell
# Get basic status
Get-WindowsMissingRecoveryStatus

# Get detailed status
Get-WindowsMissingRecoveryStatus -Detailed

# Show only errors
Get-WindowsMissingRecoveryStatus -ShowErrors

# Show only warnings
Get-WindowsMissingRecoveryStatus -ShowWarnings
```

### Display Formatted Status

```powershell
# Show formatted status report
Show-WindowsMissingRecoveryStatus

# Show detailed formatted report
Show-WindowsMissingRecoveryStatus -Detailed
```

## Manual Initialization

### Force Re-initialization

```powershell
# Force re-initialization
Initialize-WindowsMissingRecoveryModule -Force

# Skip structure validation
Initialize-WindowsMissingRecoveryModule -SkipValidation

# Use custom configuration
$customConfig = @{
    BackupRoot = "D:\CustomBackups"
    CloudProvider = "GoogleDrive"
}
Initialize-WindowsMissingRecoveryModule -OverrideConfig $customConfig
```

### Check Initialization Status

```powershell
# Get initialization status
$status = Get-ModuleInitializationStatus

# Check if module is initialized
if ($status.Initialized) {
    Write-Host "Module is ready for use"
} else {
    Write-Host "Module needs initialization"
}
```

## Module Structure Validation

The initialization system validates the following module structure:

```
WindowsMissingRecovery/
├── WindowsMissingRecovery.psd1
├── WindowsMissingRecovery.psm1
├── Private/
│   ├── Core/
│   │   ├── WindowsMissingRecovery.Core.ps1
│   │   └── WindowsMissingRecovery.Initialization.ps1
│   ├── backup/
│   ├── restore/
│   ├── setup/
│   ├── tasks/
│   └── scripts/
├── Public/
├── Config/
└── Templates/
```

## Dependencies

### Required Dependencies

- **PowerShell 5.1+** - Required for module functionality
- **Pester 5.0.0+** - Required for testing functionality

### Optional Dependencies

- **WSL** - For WSL integration features
- **Docker** - For integration testing
- **Cloud Storage Clients** - For cloud backup features

## Error Handling

### Common Initialization Errors

1. **Missing Dependencies**
   ```
   Error: Missing dependencies: Pester
   Solution: Install-Module Pester -Force
   ```

2. **Invalid Module Structure**
   ```
   Error: Missing required directories: Private\Core
   Solution: Ensure module is properly installed
   ```

3. **Configuration File Issues**
   ```
   Error: Failed to load configuration from config.env
   Solution: Check file format and permissions
   ```

### Error Recovery

```powershell
# Check for errors
$status = Get-WindowsMissingRecoveryStatus -ShowErrors

# Re-initialize with force
Initialize-WindowsMissingRecoveryModule -Force

# Use fallback configuration
Initialize-WindowsMissingRecoveryModule -SkipValidation
```

## Module Aliases

The initialization system creates the following aliases:

- `wmr-init` → `Initialize-WindowsMissingRecovery`
- `wmr-backup` → `Backup-WindowsMissingRecovery`
- `wmr-restore` → `Restore-WindowsMissingRecovery`
- `wmr-setup` → `Setup-WindowsMissingRecovery`
- `wmr-test` → `Test-WindowsMissingRecovery`
- `wmr-status` → `Show-WindowsMissingRecoveryStatus`

## Environment Variables

The module sets up the following environment:

- **Backup Directories** - Creates backup root and subdirectories
- **Logging** - Sets up logging directory and file
- **Configuration** - Exports `$WindowsMissingRecoveryConfig` variable
- **Module Paths** - Sets up module-specific directories

## Best Practices

### 1. Always Check Status After Import

```powershell
Import-Module WindowsMissingRecovery
Show-WindowsMissingRecoveryStatus
```

### 2. Use Configuration Files for Production

```powershell
# Create configuration file
$config = @{
    BACKUP_ROOT = "D:\Backups\WindowsMissingRecovery"
    MACHINE_NAME = $env:COMPUTERNAME
    CLOUD_PROVIDER = "OneDrive"
}
$config.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" } | 
    Set-Content "Config\windows.env"
```

### 3. Handle Initialization Errors

```powershell
try {
    Initialize-WindowsMissingRecoveryModule
} catch {
    Write-Error "Initialization failed: $($_.Exception.Message)"
    Get-WindowsMissingRecoveryStatus -ShowErrors
}
```

### 4. Use Detailed Status for Troubleshooting

```powershell
# For troubleshooting
Show-WindowsMissingRecoveryStatus -Detailed

# For automation
$status = Get-WindowsMissingRecoveryStatus
if (-not $status.Initialization.Initialized) {
    throw "Module not properly initialized"
}
```

## Troubleshooting

### Module Won't Load

1. Check PowerShell version: `$PSVersionTable.PSVersion`
2. Verify module path: `Get-Module WindowsMissingRecovery -ListAvailable`
3. Check for errors: `Get-WindowsMissingRecoveryStatus -ShowErrors`

### Functions Not Available

1. Check loaded functions: `Get-Command -Module WindowsMissingRecovery`
2. Re-initialize module: `Initialize-WindowsMissingRecoveryModule -Force`
3. Check initialization status: `Get-ModuleInitializationStatus`

### Configuration Issues

1. Verify configuration file format
2. Check file permissions
3. Use template as reference: `Templates\windows.env.template`

### Dependency Issues

1. Install missing modules: `Install-Module Pester -Force`
2. Check PowerShell version compatibility
3. Verify WSL installation (if using WSL features)

## Integration with CI/CD

### Automated Testing

```powershell
# In CI/CD pipeline
Import-Module WindowsMissingRecovery
$status = Get-WindowsMissingRecoveryStatus

if (-not $status.Initialization.Initialized) {
    throw "Module initialization failed"
}

if ($status.Functions.Missing.Count -gt 0) {
    throw "Missing functions: $($status.Functions.Missing -join ', ')"
}
```

### Configuration Management

```powershell
# Deploy configuration
$configPath = "Config\windows.env"
if (Test-Path $configPath) {
    Initialize-WindowsMissingRecoveryModule -ConfigPath $configPath
} else {
    Initialize-WindowsMissingRecoveryModule -SkipValidation
}
```

## Advanced Configuration

### Custom Initialization

```powershell
# Custom initialization with override
$overrideConfig = @{
    BackupSettings = @{
        RetentionDays = 60
        ExcludePaths = @("C:\Temp", "C:\Logs")
    }
    LoggingSettings = @{
        Level = "Debug"
        Path = "C:\CustomLogs"
    }
}

Initialize-WindowsMissingRecoveryModule -OverrideConfig $overrideConfig
```

### Environment-Specific Configuration

```powershell
# Development environment
if ($env:ENVIRONMENT -eq "Development") {
    Initialize-WindowsMissingRecoveryModule -ConfigPath "Config\dev.env"
} elseif ($env:ENVIRONMENT -eq "Production") {
    Initialize-WindowsMissingRecoveryModule -ConfigPath "Config\prod.env"
} else {
    Initialize-WindowsMissingRecoveryModule -SkipValidation
}
```

This initialization system ensures that the Windows Missing Recovery module is properly configured and ready for use in any environment. 