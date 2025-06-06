# WindowsMissingRecovery PowerShell Module

A comprehensive PowerShell module for managing Windows system recovery, backup, and restoration of critical system settings and applications.

## Overview

The WindowsMissingRecovery module provides a robust set of tools for:

- Managing Windows system recovery points
- Backing up and restoring critical system settings
- Managing application settings (Excel, Visio, etc.)
- Automated backup scheduling and maintenance
- System configuration management

graph TD
    A["🔍 BACKUP: Analyze-UnmanagedApplications"] --> B["Original System State"]
    B --> C["📝 unmanaged-analysis.json<br/>List of unmanaged apps"]
    
    D["💾 BACKUP PROCESS"] --> E["Package Manager Data<br/>(Store, Scoop, Choco, Winget)"]
    D --> F["Game Manager Data<br/>(Steam, Epic, GOG, etc.)"]
    D --> C
    
    G["🔄 RESTORE PROCESS"] --> H["Install Package Managers"]
    G --> I["Install Game Managers"]
    G --> J["Install Applications"]
    
    K["🔍 POST-RESTORE: Compare-PostRestoreApplications"] --> L["Load Original Analysis"]
    K --> M["Scan Current System"]
    K --> N["Compare Original vs Current"]
    
    L --> C
    M --> O["Current System State<br/>(after restore)"]
    
    N --> P["✅ Successfully Restored<br/>(were unmanaged, now installed)"]
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

## Installation

### Prerequisites

- Windows PowerShell 5.1 or later
- Administrative privileges

### Installation Methods

1. **Using the Install Script**

```powershell
.\Install-Module.ps1
```

2. **Manual Installation**

```powershell
# Copy the module to your PowerShell modules directory
Copy-Item -Path "WindowsMissingRecovery" -Destination "$env:USERPROFILE\Documents\WindowsPowerShell\Modules\" -Recurse
```

## Core Functions

### Initialization and Setup

- `Initialize-WindowsMissingRecovery` - Initializes the module configuration
- `Setup-WindowsMissingRecovery` - Sets up the module with custom configuration
- `Install-WindowsMissingRecoveryTasks` - Installs scheduled tasks for automated operations

### Backup and Recovery

- `Backup-WindowsMissingRecovery` - Creates system backups
- `Restore-WindowsMissingRecovery` - Restores from backup
- `Update-WindowsMissingRecovery` - Updates module components and configurations

### Application-Specific Functions

- `Backup-ExcelSettings` / `Restore-ExcelSettings` - Manages Excel application settings
- `Backup-VisioSettings` / `Restore-VisioSettings` - Manages Visio application settings

### Utility Functions

- `Convert-ToWinget` - Converts package installations to Winget format
- `Test-WindowsMissingRecovery` - Tests module functionality
- `Remove-WindowsMissingRecoveryTasks` - Removes scheduled tasks

## Configuration

The module uses a configuration system that can be managed through:

- Environment variables
- Configuration files
- PowerShell commands

Key configuration areas include:

- Backup settings
- Email notifications
- Scheduling
- Recovery options
- Logging preferences

## Usage Examples

### Basic Setup

```powershell
# Initialize the module
Initialize-WindowsMissingRecovery

# Configure backup location
Set-WindowsMissingRecovery -BackupRoot "D:\Backups"

# Install scheduled tasks
Install-WindowsMissingRecoveryTasks
```

### Backup Operations

```powershell
# Create a backup
Backup-WindowsMissingRecovery

# Restore from backup
Restore-WindowsMissingRecovery -BackupDate "2024-03-20"
```

### Application Settings

```powershell
# Backup Excel settings
Backup-ExcelSettings

# Restore Visio settings
Restore-VisioSettings
```

## Module Structure

```
WindowsMissingRecovery/
├── Public/           # Public functions
├── Private/          # Private functions
├── Config/           # Configuration files
├── Templates/        # Template files
└── docs/            # Documentation
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For issues and feature requests, please use the GitHub issue tracker.
