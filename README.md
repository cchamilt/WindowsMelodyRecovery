# WindowsMissingRecovery PowerShell Module

A comprehensive PowerShell module for managing Windows system recovery, backup, and restoration of critical system settings and applications.

## Overview

The WindowsMissingRecovery module provides a robust set of tools for:

- **System Configuration Management** - Backup and restore Windows settings, registry entries, and system configurations
- **Application Management** - Backup and restore application settings and data
- **Package Manager Integration** - Support for Winget, Chocolatey, Scoop, and other package managers
- **Gaming Platform Support** - Backup and restore settings for Steam, Epic Games, GOG, EA, etc.
- **Automated Scheduling** - Set up automated backup and maintenance tasks
- **Modular Setup System** - Optional component installation and configuration

```mermaid
graph TD
    A["🔍 BACKUP: Analyze-UnmanagedApplications"] --> B["Original 
    System State"]
    B --> C["📝 unmanaged-analysis.json<br/>List of unmanaged 
    apps"]
    
    D["💾 BACKUP PROCESS"] --> E["Package Manager Data<br/>(Store, 
    Scoop, Choco, Winget)"]
    D --> F["Game Manager Data<br/>(Steam, Epic, GOG, etc.)"]
    D --> C
    
    G["🔄 RESTORE PROCESS"] --> H["Install Package Managers"]
    G --> I["Install Game Managers"]
    G --> J["Install Applications"]
    
    K["🔍 POST-RESTORE: Compare-PostRestoreApplications"] --> L
    ["Load Original Analysis"]
    K --> M["Scan Current System"]
    K --> N["Compare Original vs Current"]
    
    L --> C
    M --> O["Current System State<br/>(after restore)"]
    
    N --> P["✅ Successfully Restored<br/>(were unmanaged, now 
    installed)"]
    N --> Q["❌ Still Unmanaged<br/>(need manual install)"]
    
    P --> R["📊 restored-apps.json"]
    Q --> S["📋 still-unmanaged-apps.json"]
    Q --> T["📈 still-unmanaged-apps.csv"]
    
    N --> U["📈 Post-Restore Analysis<br/>Success Rate: X%"]
    
    style A fill:#e3f2fd
    style K fill:#e8f5e8
    style P fill:#c8e6c9
    style Q fill:#ffcdd2
    style U fill:#fff3e0
```

## Installation Workflow

The module follows a clean separation of concerns with three distinct phases:

### 1. Install (Copy Files Only)
```powershell
.\Install-Module.ps1
```
- Copies module files to PowerShell modules directory
- No configuration or setup performed
- Use `-Force` to overwrite existing files
- Use `-CleanInstall` for fresh installation

### 2. Initialize (Configuration Only)
```powershell
Initialize-WindowsMissingRecovery
```
- Sets up module configuration
- Configures backup locations and cloud providers
- Creates configuration files
- No actual setup or installation of components

### 3. Setup (Optional Components)
```powershell
Setup-WindowsMissingRecovery
```
- **Requires Administrator privileges**
- Installs and configures optional components
- Prompts for each available setup script
- Installs scheduled tasks for automation

## Core Public Functions

### Module Management
- `Initialize-WindowsMissingRecovery` - Configure module settings and backup locations
- `Setup-WindowsMissingRecovery` - Install and configure optional system components
- `Get-WindowsMissingRecovery` - Get current module configuration
- `Set-WindowsMissingRecovery` - Update module configuration

### Backup and Restore Operations
- `Backup-WindowsMissingRecovery` - Create comprehensive system backup
- `Restore-WindowsMissingRecovery` - Restore system from backup
- `Update-WindowsMissingRecovery` - Update system packages and configurations

### Task Management
- `Install-WindowsMissingRecoveryTasks` - Install scheduled tasks for automated operations
- `Remove-WindowsMissingRecoveryTasks` - Remove scheduled tasks

### Script Configuration
- `Set-WindowsMissingRecoveryScripts` - Configure which backup/restore/setup scripts are enabled
- `Sync-WindowsMissingRecoveryScripts` - Synchronize script configurations

### Utilities
- `Convert-ToWinget` - Convert package installations to Winget format
- `Test-WindowsMissingRecovery` - Test module functionality and configuration

## Available Setup Components

When running `Setup-WindowsMissingRecovery`, you can choose from these optional components:

- **Custom Profiles (chezmoi)** - Configure chezmoi for dotfile management
- **Remove Bloat** - Remove unwanted pre-installed software and Lenovo bloatware
- **Windows Defender** - Configure Windows Defender settings and policies
- **System Restore Points** - Configure automatic restore point creation
- **WSL Fonts** - Install development fonts for WSL (Nerd Fonts, Ubuntu fonts)
- **KeePassXC** - Install and configure password manager
- **Steam Games** - Configure Steam game settings and library
- **Epic Games** - Configure Epic Games Launcher and Legendary CLI
- **GOG Games** - Configure GOG Galaxy settings
- **EA Games** - Configure EA App/Origin settings

## Configuration System

The module uses a flexible configuration system with:

### Configuration Files
- `Config/windows.env` - Main module configuration
- `Config/scripts-config.json` - Script enablement configuration
- `Templates/` - Template files for initial setup

### Key Configuration Areas
- **Backup Settings** - Retention, paths, exclusions
- **Cloud Integration** - OneDrive, Google Drive, Dropbox support
- **Email Notifications** - Success/failure notifications
- **Logging** - Configurable logging levels and paths
- **Script Management** - Enable/disable individual backup/restore/setup scripts

## Usage Examples

### Complete Setup Workflow
```powershell
# 1. Install the module files
.\Install-Module.ps1

# 2. Configure the module
Initialize-WindowsMissingRecovery

# 3. Set up optional components (as Administrator)
Setup-WindowsMissingRecovery
```

### Backup and Restore Operations
```powershell
# Create a comprehensive backup
Backup-WindowsMissingRecovery

# Restore from a specific backup
Restore-WindowsMissingRecovery -BackupDate "2024-03-20"

# Update system packages
Update-WindowsMissingRecovery
```

### Configuration Management
```powershell
# View current configuration
Get-WindowsMissingRecovery

# Update backup location
Set-WindowsMissingRecovery -BackupRoot "D:\Backups"

# Configure script enablement
Set-WindowsMissingRecoveryScripts
```

### Task Automation
```powershell
# Install scheduled tasks for automation
Install-WindowsMissingRecoveryTasks

# Remove scheduled tasks
Remove-WindowsMissingRecoveryTasks
```

## Module Architecture

```
WindowsMissingRecovery/
├── Public/                 # Public functions (exported)
│   ├── Backup-WindowsMissingRecovery.ps1
│   ├── Initialize-WindowsMissingRecovery.ps1
│   ├── Setup-WindowsMissingRecovery.ps1
│   └── ...
├── Private/                # Private functions (loaded on-demand)
│   ├── backup/            # Backup scripts
│   ├── restore/           # Restore scripts
│   ├── setup/             # Setup scripts
│   ├── tasks/             # Scheduled task scripts
│   └── Core/              # Core utilities
├── Config/                 # User configuration files
├── Templates/              # Template files
├── docs/                   # Documentation
├── WindowsMissingRecovery.psd1  # Module manifest
└── WindowsMissingRecovery.psm1  # Module script
```

## Key Features

### Modular Script System
- **On-demand loading** - Private scripts loaded only when needed
- **Configurable components** - Enable/disable individual scripts
- **Category-based organization** - Backup, restore, setup, and task scripts

### Clean Separation of Concerns
- **Install** - Only copies files, no configuration
- **Initialize** - Only handles configuration, no installation
- **Setup** - Only handles optional component setup
- **Private scripts** - Loaded on-demand when their functions are called

### Comprehensive Backup Coverage
- System settings and registry entries
- Application configurations and data
- Package manager installations
- Gaming platform settings
- Development environment configurations

## Prerequisites

- **Windows PowerShell 5.1** or later
- **Administrative privileges** (for Setup phase only)
- **Internet connection** (for package installations)

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For issues and feature requests, please use the GitHub issue tracker.
