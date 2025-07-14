# Windows Melody Recovery - Module Initialization

## Overview

The Windows Melody Recovery module uses a comprehensive initialization system that ensures proper loading of all components, validation of dependencies, and setup of the module environment. **As of version 1.0.0, the module now features an interactive Text User Interface (TUI) wizard as the default initialization method**, making configuration more intuitive and user-friendly.

## Initialization Methods

### 1. Interactive TUI Wizard (Default)

The TUI wizard is the new default initialization method, providing a modern, interactive interface for configuration:

```powershell
Initialize-WindowsMelodyRecovery
```

**Features:**
- **Tabbed Interface**: Components, Initialization Wizard, and Status tabs
- **Visual Component Selection**: TreeView with categorized templates and checkboxes
- **Smart Auto-Detection**: Automatically detects cloud storage paths
- **Real-time Validation**: Tests configuration before saving
- **Comprehensive Configuration**: Backup root, cloud provider, email settings, retention policies
- **Action Integration**: Direct backup/restore operations from the interface

![TUI Wizard Interface](images/tui-wizard.png)

### 2. Parameter-Based Configuration (Automation)

For scripting and automation scenarios, use parameter-based configuration:

```powershell
# Complete configuration
Initialize-WindowsMelodyRecovery -BackupRoot "C:\Backups\WMR" -CloudProvider "OneDrive" -MachineName "MyPC" -EmailAddress "user@example.com" -RetentionDays 60 -EnableEmailNotifications

# Partial updates (only specified parameters are changed)
Initialize-WindowsMelodyRecovery -BackupRoot "D:\NewBackups"
Initialize-WindowsMelodyRecovery -EmailAddress "newemail@company.com" -EnableEmailNotifications
```

**Available Parameters:**
- `BackupRoot` - Primary backup directory path
- `CloudProvider` - OneDrive, GoogleDrive, Dropbox, Box, or Custom
- `MachineName` - Unique machine identifier
- `EmailAddress` - Email for notifications
- `RetentionDays` - Backup retention period (default: 30)
- `EnableEmailNotifications` - Enable email notifications switch

### 3. Traditional Command-Line Prompts

For backward compatibility and CI/CD scenarios:

```powershell
Initialize-WindowsMelodyRecovery -NoPrompt
```

## Initialization Process

When the module is imported, the following sequence occurs:

1. **Module Manifest Processing** - PowerShell loads the module manifest (`WindowsMelodyRecovery.psd1`)
2. **ScriptsToProcess Loading** - Core utilities are loaded via `ScriptsToProcess`
3. **Root Module Loading** - The main module file (`WindowsMelodyRecovery.psm1`) is executed
4. **Initialization System Loading** - The initialization system is loaded
5. **Component Loading** - Public functions and other components are loaded
6. **Environment Setup** - Module environment is configured
7. **Validation** - Dependencies and structure are validated

### 2. Initialization Components

The initialization system consists of several key components:

#### Core Initialization Functions

- `Initialize-WindowsMelodyRecoveryModule` - Main initialization function
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
Initialize-WindowsMelodyRecoveryModule -ConfigPath "C:\Custom\config.env"
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
# Windows Melody Recovery Configuration
BACKUP_ROOT=C:\Users\Username\Backups\WindowsMelodyRecovery
MACHINE_NAME=DESKTOP-ABC123
CLOUD_PROVIDER=OneDrive
WINDOWS_MELODY_RECOVERY_PATH=C:\Scripts\WindowsMelodyRecovery
```

## Module Status and Diagnostics

### Get Module Status

```powershell
# Get basic status
Get-WindowsMelodyRecoveryStatus

# Get detailed status
Get-WindowsMelodyRecoveryStatus -Detailed

# Show only errors
Get-WindowsMelodyRecoveryStatus -ShowErrors

# Show only warnings
Get-WindowsMelodyRecoveryStatus -ShowWarnings
```

### Display Formatted Status

```powershell
# Show formatted status report
Show-WindowsMelodyRecoveryStatus

# Show detailed formatted report
Show-WindowsMelodyRecoveryStatus -Detailed
```

## Manual Initialization

### Force Re-initialization

```powershell
# Force re-initialization
Initialize-WindowsMelodyRecoveryModule -Force

# Skip structure validation
Initialize-WindowsMelodyRecoveryModule -SkipValidation

# Use custom configuration
$customConfig = @{
    BackupRoot = "D:\CustomBackups"
    CloudProvider = "GoogleDrive"
}
Initialize-WindowsMelodyRecoveryModule -OverrideConfig $customConfig
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
WindowsMelodyRecovery/
├── WindowsMelodyRecovery.psd1
├── WindowsMelodyRecovery.psm1
├── Private/
│   ├── Core/
│   │   ├── WindowsMelodyRecovery.Core.ps1
│   │   └── WindowsMelodyRecovery.Initialization.ps1
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
$status = Get-WindowsMelodyRecoveryStatus -ShowErrors

# Re-initialize with force
Initialize-WindowsMelodyRecoveryModule -Force

# Use fallback configuration
Initialize-WindowsMelodyRecoveryModule -SkipValidation
```

## Module Aliases

The initialization system creates the following aliases:

- `wmr-init` → `Initialize-WindowsMelodyRecovery`
- `wmr-backup` → `Backup-WindowsMelodyRecovery`
- `wmr-restore` → `Restore-WindowsMelodyRecovery`
- `wmr-setup` → `Setup-WindowsMelodyRecovery`
- `wmr-status` → `Show-WindowsMelodyRecoveryStatus`

These aliases are automatically exported and available when the module is imported.
This allows for quick and easy access to the core functions of the module from the command line.

## Environment Variables

The module sets up the following environment:

- **Backup Directories** - Creates backup root and subdirectories
- **Logging** - Sets up logging directory and file
- **Configuration** - Exports `$WindowsMelodyRecoveryConfig` variable
- **Module Paths** - Sets up module-specific directories

## Best Practices

### 1. Always Check Status After Import

```powershell
Import-Module WindowsMelodyRecovery
Show-WindowsMelodyRecoveryStatus
```

### 2. Use Configuration Files for Production

```powershell
# Create configuration file
$config = @{
    BACKUP_ROOT = "D:\Backups\WindowsMelodyRecovery"
    MACHINE_NAME = $env:COMPUTERNAME
    CLOUD_PROVIDER = "OneDrive"
}
$config.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" } |
    Set-Content "Config\windows.env"
```

### 3. Handle Initialization Errors

```powershell
try {
    Initialize-WindowsMelodyRecoveryModule
} catch {
    Write-Error "Initialization failed: $($_.Exception.Message)"
    Get-WindowsMelodyRecoveryStatus -ShowErrors
}
```

### 4. Use Detailed Status for Troubleshooting

```powershell
# For troubleshooting
Show-WindowsMelodyRecoveryStatus -Detailed

# For automation
$status = Get-WindowsMelodyRecoveryStatus
if (-not $status.Initialization.Initialized) {
    throw "Module not properly initialized"
}
```

## Troubleshooting

### Module Won't Load

1. Check PowerShell version: `$PSVersionTable.PSVersion`
2. Verify module path: `Get-Module WindowsMelodyRecovery -ListAvailable`
3. Check for errors: `Get-WindowsMelodyRecoveryStatus -ShowErrors`

### Functions Not Available

1. Check loaded functions: `Get-Command -Module WindowsMelodyRecovery`
2. Re-initialize module: `Initialize-WindowsMelodyRecoveryModule -Force`
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
Import-Module WindowsMelodyRecovery
$status = Get-WindowsMelodyRecoveryStatus

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
    Initialize-WindowsMelodyRecoveryModule -ConfigPath $configPath
} else {
    Initialize-WindowsMelodyRecoveryModule -SkipValidation
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

Initialize-WindowsMelodyRecoveryModule -OverrideConfig $overrideConfig
```

### Environment-Specific Configuration

```powershell
# Development environment
if ($env:ENVIRONMENT -eq "Development") {
    Initialize-WindowsMelodyRecoveryModule -ConfigPath "Config\dev.env"
} elseif ($env:ENVIRONMENT -eq "Production") {
    Initialize-WindowsMelodyRecoveryModule -ConfigPath "Config\prod.env"
} else {
    Initialize-WindowsMelodyRecoveryModule -SkipValidation
}
```

This initialization system ensures that the Windows Melody Recovery module is properly configured and ready for use in any environment.
