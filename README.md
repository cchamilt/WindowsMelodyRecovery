# Windows Melody Recovery PowerShell Module

It might not be in tune, but it keeps your Windows clients humming on keys, installed packages, and home files.

[![CI](https://github.com/cchamilt/WindowsMelodyRecovery/actions/workflows/ci.yml/badge.svg?branch=testing)](https://github.com/cchamilt/WindowsMelodyRecovery/actions/workflows/ci.yml)
[![Integration Tests](https://github.com/cchamilt/WindowsMelodyRecovery/actions/workflows/integration-tests.yml/badge.svg?branch=testing)](https://github.com/cchamilt/WindowsMelodyRecovery/actions/workflows/integration-tests.yml)
[![PowerShell Gallery](https://img.shields.io/powershellgallery/v/WindowsMelodyRecovery?label=PowerShell%20Gallery)](https://www.powershellgallery.com/packages/WindowsMelodyRecovery)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Documentation](https://img.shields.io/badge/docs-latest-blue.svg)](docs/)

A comprehensive PowerShell module for managing Windows system recovery, backup, and restoration of critical system settings, applications, and development environments.

## 📚 Documentation

| Document | Description |
|----------|-------------|
| **[Installation Guide](docs/INSTALLATION.md)** | Step-by-step installation and setup instructions |
| **[Configuration Guide](docs/CONFIGURATION.md)** | Detailed configuration options and examples |
| **[Backup Details](docs/BACKUP_DETAILS.md)** | Comprehensive backup coverage and technical details |
| **[WSL Integration](docs/WSL_INTEGRATION.md)** | Windows Subsystem for Linux features and setup |
| **[Gaming Platforms](docs/GAMING_PLATFORMS.md)** | Gaming platform support and configuration |
| **[Cloud Storage](docs/CLOUD_STORAGE.md)** | Multi-cloud provider setup and configuration |
| **[API Reference](docs/API_REFERENCE.md)** | Complete function reference and examples |
| **[Troubleshooting](docs/TROUBLESHOOTING.md)** | Common issues and solutions |
| **[Contributing](docs/CONTRIBUTING.md)** | Development setup and contribution guidelines |
| **[Changelog](CHANGELOG.md)** | Version history and release notes |
| **[Limits & Scope](docs/LIMITS.md)** | Module limitations and scope definition |
| **[State Management Guide](docs/STATE_MANAGEMENT_GUIDE.md)** | Declarative state management system |

## 🧪 Testing & Quality

| Test Suite | Status | Coverage |
|------------|--------|----------|
| **Docker Cross-Platform** | [![Docker Tests](https://github.com/cchamilt/WindowsMelodyRecovery/actions/workflows/docker-tests.yml/badge.svg)](https://github.com/cchamilt/WindowsMelodyRecovery/actions/workflows/docker-tests.yml) | Unit, file-ops, integration, e2e |
| **Windows Native** | [![Windows Tests](https://github.com/cchamilt/WindowsMelodyRecovery/actions/workflows/windows-tests.yml/badge.svg)](https://github.com/cchamilt/WindowsMelodyRecovery/actions/workflows/windows-tests.yml) | Windows-only functionality |
| **Code Quality** | [![PSScriptAnalyzer](https://github.com/cchamilt/WindowsMelodyRecovery/actions/workflows/ci.yml/badge.svg?branch=testing)](https://github.com/cchamilt/WindowsMelodyRecovery/actions/workflows/ci.yml) | Static analysis, style checks |

### 🔍 **Dual CI/CD Testing Architecture**

#### 🐳 **Docker Cross-Platform Tests** 
- **Environment**: Ubuntu containers with PowerShell
- **Coverage**: Unit tests, file operations, integration tests, end-to-end workflows
- **Windows-only handling**: Automatically skipped with `$IsWindows` detection
- **Execution**: `run-unit-tests.ps1`, `run-file-operation-tests.ps1`, `run-integration-tests.ps1`, `run-end-to-end-tests.ps1`

#### 🪟 **Windows Native Tests**
- **Environment**: Windows Server 2022 (GitHub Actions runners)
- **Coverage**: Windows-only functionality, admin privileges, registry operations
- **Safety**: CI/CD environment detection, restore points, admin checks
- **Execution**: `run-windows-tests.ps1` with safety mechanisms

### 🎯 **Test Execution Modes**

#### **Local Development (Cross-Platform)**
```powershell
# Run cross-platform tests (Windows-only tests skipped in Docker)
./tests/scripts/run-unit-tests.ps1
./tests/scripts/run-file-operation-tests.ps1
./tests/scripts/run-integration-tests.ps1
./tests/scripts/run-end-to-end-tests.ps1 -Timeout 30

# Run specific tests
./tests/scripts/run-unit-tests.ps1 -TestName "ConfigurationValidation"
./tests/scripts/run-integration-tests.ps1 -TestName "cloud-provider-detection"
```

#### **Windows CI/CD (Windows-Only)**
```powershell
# Run Windows-only tests (CI/CD environment required)
./tests/scripts/run-windows-tests.ps1 -Category unit
./tests/scripts/run-windows-tests.ps1 -Category integration -RequireAdmin
./tests/scripts/run-windows-tests.ps1 -Category all -CreateRestorePoint

# Force execution in development (use with caution)
./tests/scripts/run-windows-tests.ps1 -Category unit -Force
```

#### **Docker Environment**
```powershell
# Force Docker execution
./tests/scripts/run-integration-tests.ps1 -UseDocker
./tests/scripts/run-end-to-end-tests.ps1 -UseDocker -Timeout 30
```

### 🛡️ **Safety Features**

- **Environment Detection**: Automatic Windows vs non-Windows detection
- **CI/CD Protection**: Windows-only tests protected from development execution
- **Admin Privilege Checks**: Ensures proper permissions for destructive tests
- **Restore Point Creation**: System safety before destructive operations
- **Test Isolation**: Safe test directories and comprehensive cleanup

> 📊 **[View Detailed Test Results](https://github.com/cchamilt/WindowsMelodyRecovery/actions)** | **[Testing Documentation](docs/CI_CD_TESTING_STRATEGY.md)**

## 🚀 Quick Start

## Overview

The WindowsMelodyRecovery module provides a robust set of tools for:

- **System Configuration Management** - Backup and restore Windows settings, registry entries, and system configurations
- **Application Management** - Backup and restore application settings and data
- **Package Manager Integration** - Support for Winget, Chocolatey, Scoop, and other package managers
- **Gaming Platform Support** - Comprehensive backup and restore for Steam, Epic Games, GOG, EA, and more
- **WSL Development Environment** - Complete WSL backup, restore, and management with package synchronization
- **Dotfile Management** - chezmoi integration for cross-machine dotfile synchronization
- **Multi-Cloud Support** - OneDrive, Google Drive, Dropbox, and custom cloud storage integration
- **Automated Scheduling** - Set up automated backup and maintenance tasks
- **Modular Setup System** - Optional component installation and configuration

```mermaid
graph TD
    A["🔍 BACKUP: Analyze-UnmanagedApplications"] --> B["Original System State"]
    B --> C["📝 unmanaged-analysis.json<br/>List of unmanaged apps"]
    
    D["💾 BACKUP PROCESS"] --> E["Package Manager Data<br/>(Store, Scoop, Choco, Winget)"]
    D --> F["Game Manager Data<br/>(Steam, Epic, GOG, EA)"]
    D --> G["WSL Environment<br/>(Packages, Config, Dotfiles)"]
    D --> H["Cloud Storage<br/>(OneDrive, Google Drive, Dropbox)"]
    D --> C
    
    I["🔄 RESTORE PROCESS"] --> J["Install Package Managers"]
    I --> K["Install Game Managers"]
    I --> L["Restore WSL Environment"]
    I --> M["Setup chezmoi Dotfiles"]
    I --> N["Install Applications"]
    
    O["🔍 POST-RESTORE: Compare-PostRestoreApplications"] --> P["Load Original Analysis"]
    O --> Q["Scan Current System"]
    O --> R["Compare Original vs Current"]
    
    P --> C
    Q --> S["Current System State<br/>(after restore)"]
    
    R --> T["✅ Successfully Restored<br/>(were unmanaged, now installed)"]
    R --> U["❌ Still Unmanaged<br/>(need manual install)"]
    
    T --> V["📊 restored-apps.json"]
    U --> W["📋 still-unmanaged-apps.json"]
    U --> X["📈 still-unmanaged-apps.csv"]
    
    R --> Y["📈 Post-Restore Analysis<br/>Success Rate: X%"]
    
    style A fill:#e3f2fd
    style O fill:#e8f5e8
    style T fill:#c8e6c9
    style U fill:#ffcdd2
    style Y fill:#fff3e0
    style G fill:#f3e5f5
    style H fill:#e0f2f1
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
Initialize-WindowsMelodyRecovery
```
- Sets up module configuration
- Configures backup locations and cloud providers
- Creates configuration files
- Detects and configures cloud storage paths automatically
- No actual setup or installation of components

### 3. Setup (Optional Components)
```powershell
Setup-WindowsMelodyRecovery
```
- **Requires Administrator privileges**
- Installs and configures optional components
- Prompts for each available setup script
- Installs scheduled tasks for automation

## Core Public Functions

### Module Management
- `Initialize-WindowsMelodyRecovery` - Configure module settings and backup locations
- `Setup-WindowsMelodyRecovery` - Install and configure optional system components
- `Get-WindowsMelodyRecovery` - Get current module configuration
- `Set-WindowsMelodyRecovery` - Update module configuration

### Backup and Restore Operations
- `Backup-WindowsMelodyRecovery` - Create comprehensive system backup
- `Restore-WindowsMelodyRecovery` - Restore system from backup
- `Update-WindowsMelodyRecovery` - Update system packages and configurations

### Task Management
- `Install-WindowsMelodyRecoveryTasks` - Install scheduled tasks for automated operations
- `Remove-WindowsMelodyRecoveryTasks` - Remove scheduled tasks

### Script Configuration
- `Set-WindowsMelodyRecoveryScripts` - Configure which backup/restore/setup scripts are enabled
- `Sync-WindowsMelodyRecoveryScripts` - Synchronize script configurations

### Utilities
- `Convert-ToWinget` - Convert package installations to Winget format
- `Test-WindowsMelodyRecovery` - Test module functionality and configuration

## Available Setup Components

When running `Setup-WindowsMelodyRecovery`, you can choose from these optional components:

### Development Environment
- **WSL (Windows Subsystem for Linux)** - Complete WSL setup with Ubuntu, package management, and configuration
- **chezmoi Dotfiles** - Configure chezmoi for cross-machine dotfile management with git repository support
- **WSL Fonts** - Install development fonts for WSL (Nerd Fonts, Ubuntu fonts, programming fonts)
- **Package Managers** - Install and configure Chocolatey, Scoop, and other package managers

### Gaming Platforms

- **Steam Games** - Configure Steam game settings, library management, and game installations
- **Epic Games** - Configure Epic Games Launcher and Legendary CLI for game management
- **GOG Games** - Configure GOG Galaxy settings and game library management
- **EA Games** - Configure EA App/Origin settings and game installations

### Productivity and Security

- **KeePassXC** - Install and configure password manager with database setup
- **Custom Profiles** - Configure PowerShell profiles and terminal customizations
- **Windows Defender** - Configure Windows Defender settings and security policies
- **System Restore Points** - Configure automatic restore point creation and management

### System Optimization

- **Remove Bloat** - Remove unwanted pre-installed software and manufacturer bloatware
- **Windows Features** - Configure optional Windows features and capabilities

## Cloud Provider Support

The module automatically detects and supports multiple cloud storage providers:

### Fully Supported (Automatic Detection)

- **OneDrive Personal** - Automatic path detection and configuration
- **OneDrive for Business** - Automatic path detection and configuration

### Supported (Manual Configuration)

- **Google Drive** - Manual path configuration required
- **Dropbox** - Manual path configuration required
- **Custom Cloud Storage** - Any cloud storage with local sync folder

### Cloud Integration Features

- Automatic backup path detection
- Multi-cloud backup support
- Cloud storage health checking
- Configurable backup retention policies
- Cross-machine synchronization

## WSL Integration

Comprehensive Windows Subsystem for Linux support:

### WSL Backup Features

- **Package Management**: APT, NPM, PIP, Snap, Flatpak package lists
- **Configuration Files**: wsl.conf, fstab, hosts, environment variables
- **Shell Configurations**: .bashrc, .profile, .zshrc, custom shell settings
- **Development Tools**: Git configuration, SSH keys, development tool configs
- **Home Directory**: Selective backup of important dotfiles and configurations
- **Distribution Info**: WSL version, distribution details, kernel information

### WSL Restore Features
- Automated package installation across all package managers
- Configuration file restoration with proper permissions
- Shell environment restoration
- Development tool reconfiguration
- Home directory restoration
- Git repository checking and validation

### chezmoi Integration
- **Dotfile Management**: Complete chezmoi setup and configuration
- **Git Repository Support**: Automatic repository cloning and setup
- **Template Support**: chezmoi templates and encrypted secrets
- **Cross-Machine Sync**: Consistent dotfiles across multiple machines
- **Backup and Restore**: chezmoi source directory and configuration backup

## Configuration System

The module uses a flexible configuration system with:

### Configuration Files
- `Config/windows.env` - Main module configuration
- `Config/scripts-config.json` - Script enablement configuration
- `Templates/` - Template files for initial setup

### Key Configuration Areas
- **Backup Settings** - Retention, paths, exclusions, cloud integration
- **Cloud Integration** - Multi-provider support with automatic detection
- **Email Notifications** - Success/failure notifications with detailed reporting
- **Logging** - Configurable logging levels and paths
- **Script Management** - Enable/disable individual backup/restore/setup scripts
- **WSL Configuration** - WSL-specific backup and restore settings
- **Gaming Platforms** - Game library and settings management

## Usage Examples

### Complete Setup Workflow
```powershell
# 1. Install the module files
.\Install-Module.ps1

# 2. Configure the module (detects cloud storage automatically)
Initialize-WindowsMelodyRecovery

# 3. Set up optional components (as Administrator)
Setup-WindowsMelodyRecovery
```

### Backup and Restore Operations
```powershell
# Create a comprehensive backup (includes WSL and dotfiles)
Backup-WindowsMelodyRecovery

# Restore from a specific backup
Restore-WindowsMelodyRecovery -BackupDate "2024-03-20"

# Update system packages (includes WSL packages)
Update-WindowsMelodyRecovery
```

### WSL and Development Environment
```powershell
# Setup WSL with complete development environment
Setup-WindowsMelodyRecovery -Component "WSL"

# Setup chezmoi for dotfile management
Setup-WindowsMelodyRecovery -Component "chezmoi"

# Backup WSL environment
Backup-WindowsMelodyRecovery -Component "WSL"
```

### Gaming Platform Management
```powershell
# Setup all gaming platforms
Setup-WindowsMelodyRecovery -Component "Steam","Epic","GOG","EA"

# Backup gaming configurations
Backup-WindowsMelodyRecovery -Component "Gaming"
```

### Configuration Management
```powershell
# View current configuration
Get-WindowsMelodyRecovery

# Update backup location
Set-WindowsMelodyRecovery -BackupRoot "D:\Backups"

# Configure cloud storage manually
Set-WindowsMelodyRecovery -CloudProvider "GoogleDrive" -CloudPath "G:\My Drive\Backups"

# Configure script enablement
Set-WindowsMelodyRecoveryScripts
```

### Task Automation
```powershell
# Install scheduled tasks for automation
Install-WindowsMelodyRecoveryTasks

# Remove scheduled tasks
Remove-WindowsMelodyRecoveryTasks
```

## Module Architecture

```
WindowsMelodyRecovery/
├── Public/                 # Public functions (exported)
│   ├── Backup-WindowsMelodyRecovery.ps1
│   ├── Initialize-WindowsMelodyRecovery.ps1
│   ├── Setup-WindowsMelodyRecovery.ps1
│   └── ...
├── Private/                # Private functions (loaded on-demand)
│   ├── backup/            # Backup scripts (Windows, WSL, Gaming)
│   ├── restore/           # Restore scripts (Windows, WSL, Gaming)
│   ├── setup/             # Setup scripts (WSL, chezmoi, Gaming)
│   ├── tasks/             # Scheduled task scripts
│   └── Core/              # Core utilities and cloud integration
├── Config/                 # User configuration files
├── Templates/              # Template files
├── docs/                   # Documentation
├── WindowsMelodyRecovery.psd1  # Module manifest
└── WindowsMelodyRecovery.psm1  # Module script
```

## Key Features

### Modular Script System
- **On-demand loading** - Private scripts loaded only when needed
- **Configurable components** - Enable/disable individual scripts
- **Category-based organization** - Backup, restore, setup, and task scripts
- **Cross-platform support** - Windows and WSL integration

### Clean Separation of Concerns
- **Install** - Only copies files, no configuration
- **Initialize** - Only handles configuration, no installation
- **Setup** - Only handles optional component setup
- **Private scripts** - Loaded on-demand when their functions are called

### Comprehensive Backup Coverage
- **System Settings**: Windows configurations, registry entries, system preferences
- **Applications**: Package managers, gaming platforms, productivity software
- **Development Environment**: WSL, dotfiles, development tools, shell configurations
- **Cloud Integration**: Multi-provider support with automatic detection
- **Gaming Platforms**: Complete game library and settings management

### Advanced WSL Support
- **Complete Environment Backup**: Packages, configurations, dotfiles, development tools
- **Cross-Distribution Support**: Ubuntu, Debian, and other WSL distributions
- **Package Manager Integration**: APT, NPM, PIP, Snap, Flatpak synchronization
- **Development Tool Management**: Git, SSH, development environment restoration
- **chezmoi Integration**: Professional dotfile management with version control

### Multi-Cloud Architecture
- **Automatic Detection**: OneDrive personal and business automatic path detection
- **Manual Configuration**: Google Drive, Dropbox, and custom cloud storage support
- **Health Monitoring**: Cloud storage availability and sync status checking
- **Flexible Backup Paths**: Support for multiple backup locations and retention policies

## Prerequisites

- **Windows 10/11** (version 1903 or later for WSL 2 support)
- **Windows PowerShell 5.1** or **PowerShell 7+**
- **Administrative privileges** (for Setup phase only)
- **Internet connection** (for package installations and cloud synchronization)
- **WSL 2** (optional, for WSL-related features)
- **Git** (optional, for chezmoi dotfile management)

## 📁 Repository Structure

```
WindowsMelodyRecovery/
├── 📄 WindowsMelodyRecovery.psm1     # Main module file
├── 📄 WindowsMelodyRecovery.psd1     # Module manifest
├── 📄 Install-Module.ps1              # Installation script
├── 📁 Public/                         # Public functions (exported)
├── 📁 Private/                        # Private functions (internal)
│   ├── 📁 backup/                     # Backup scripts
│   ├── 📁 restore/                    # Restore scripts
│   ├── 📁 setup/                      # Setup scripts
│   ├── 📁 wsl/                        # WSL integration
│   └── 📁 Core/                       # Core utilities
├── 📁 Config/                         # Configuration files
├── 📁 docs/                           # Documentation
├── 📁 tests/                          # Test suites
│   ├── 📁 unit/                       # Unit tests
│   ├── 📁 integration/                # Integration tests
│   └── 📁 docker/                     # Docker test environment
├── 📁 .github/                        # GitHub Actions workflows
│   ├── 📁 workflows/                  # CI/CD workflows
│   └── 📄 README.md                   # Testing documentation
├── 📁 scripts/                        # Utility scripts
│   ├── 📄 Update-GitHubUsername.ps1   # Update GitHub references
│   └── 📄 README.md                   # Scripts documentation
└── 📄 CHANGELOG.md                    # Version history
```

## 🤝 Contributing

We welcome contributions! Here's how to get started:

1. **Read the Guidelines**: Check out **[Contributing Guide](docs/CONTRIBUTING.md)**
2. **Development Setup**: Follow the **[Development Setup](docs/CONTRIBUTING.md#development-setup)** instructions
3. **Testing**: Run tests locally with **[Testing Guide](.github/README.md)**
4. **Submit PR**: Create a pull request with your changes

### 🧪 **Testing Your Changes**
```powershell
# Run quick validation locally
Invoke-ScriptAnalyzer -Path . -Recurse

# Run unit tests locally
Invoke-Pester tests/unit/

# Run comprehensive Docker-based tests
.\run-integration-tests.ps1 -TestSuite All -GenerateReport
```

For detailed testing information, see:
- **[Docker Testing Framework Guide](docs/DOCKER_TESTING_FRAMEWORK.md)** - Comprehensive testing documentation
- **[Testing Quick Reference](docs/TESTING_QUICK_REFERENCE.md)** - Common commands and workflows

## 📋 Project Status

| Component | Status | Notes |
|-----------|--------|-------|
| **Core Module** | 🔄 Ongoing | Production ready |
| **WSL Integration** | 🔄 Ongoing | Full Ubuntu support |
| **Gaming Platforms** | 🔄 Ongoing | Steam, Epic, GOG, EA |
| **Cloud Storage** | ✅ Stable | OneDrive, Google Drive, Dropbox |
| **Package Managers** | ✅ Stable | Chocolatey, Scoop, Winget |
| **chezmoi Integration** | ✅ Stable | Dotfile management |
| **CI/CD Pipeline** | ✅ Active | GitHub Actions |
| **Documentation** | 🔄 Ongoing | Continuous improvement |

## 📄 License

This project is licensed under the **MIT License** - see the [LICENSE](LICENSE) file for details.

## 🆘 Support & Community

- **🐛 Bug Reports**: [GitHub Issues](https://github.com/cchamilt/WindowsMelodyRecovery/issues)
- **💡 Feature Requests**: [GitHub Discussions](https://github.com/cchamilt/WindowsMelodyRecovery/discussions)
- **📖 Documentation**: [docs/](docs/) directory
- **🧪 Test Results**: [GitHub Actions](https://github.com/cchamilt/WindowsMelodyRecovery/actions)
- **📊 Project Board**: [GitHub Projects](https://github.com/cchamilt/WindowsMelodyRecovery/projects)

### 🔗 **Quick Links**
- **[Latest Release](https://github.com/cchamilt/WindowsMelodyRecovery/releases/latest)**
- **[Backup Details](docs/BACKUP_DETAILS.md)**
- **[API Reference](docs/API_REFERENCE.md)**
- **[Scripts README](scripts/README.md)**
- **[Tests README](tests/README.md)**
- **[TODO](TODO.md)**
- **[Changelog](CHANGELOG.md)**

---

<div align="center">

**🏆 Windows Melody Recovery v1.0.0**  

[![Made with PowerShell](https://img.shields.io/badge/Made%20with-PowerShell-blue.svg)](https://microsoft.com/powershell)
[![Tested on Windows](https://img.shields.io/badge/Tested%20on-Windows%2010%2F11-blue.svg)](https://www.microsoft.com/windows)
[![WSL Compatible](https://img.shields.io/badge/WSL-Compatible-green.svg)](https://docs.microsoft.com/windows/wsl/)

</div>

## Template-Based State Management (New!)

Windows Melody Recovery now supports a declarative, template-based approach to managing your system's configuration, applications, and files. This allows you to define your desired system state using human-readable YAML files, making backups, restores, and synchronizations more robust, readable, and idempotent.

### Key Benefits:
*   **Declarative Configuration:** Define *what* your system state should be, not just *how* to achieve it.
*   **Idempotency:** Run templates multiple times to ensure your system converges to the desired state reliably.
*   **Modular & Reusable:** Break down complex configurations into smaller, reusable YAML templates.
*   **Prerequisite Checks:** Templates can define necessary conditions (e.g., specific software versions, registry settings) that must be met before operations proceed.

For a comprehensive guide on creating and using templates, including detailed schema, usage examples, and best practices, please refer to: [State Management Guide](docs/STATE_MANAGEMENT_GUIDE.md)

### Using the New System

To use the new template-based system, you will primarily interact with `Backup-WindowsMelodyRecovery.ps1` and `Restore-WindowsMelodyRecovery.ps1` by providing a template path.

**Example: Backing up your display settings using a template:**
```powershell
.\Public\Backup-WindowsMelodyRecovery.ps1 -TemplatePath ".\Templates\System\display.yaml"
```

**Example: Restoring Winget applications from a previous backup:**
```powershell
.\Public\Restore-WindowsMelodyRecovery.ps1 -TemplatePath ".\Templates\System\winget-apps.yaml" -RestoreFromDirectory ".\backups\backup_20240628_143000" # Replace with your actual backup directory
```

We encourage you to explore the `Templates/System/` directory for example templates to get started.

## 🧪 Testing Framework

The project includes comprehensive testing scripts for safe template development and validation:

### Safe Testing Scripts

- **`test-template-backup.ps1`** - Tests backup operations (always safe, read-only)
- **`test-template-restore.ps1`** - Tests restore operations with WhatIf simulation
- **`test-template-workflow.ps1`** - Tests complete backup→restore workflows

**Note**: These template testing scripts are designed for manual testing and development. For automated testing, use the Docker-based test runners: `run-integration-tests.ps1` and `run-end-to-end-tests.ps1`.

### WhatIf Safety Mechanism

**⚠️ IMPORTANT SAFETY FEATURE**: All restore testing operations run in **WhatIf mode by default** to prevent accidental system changes during development.

```powershell
# Safe simulation (default) - NO system changes
.\test-template-restore.ps1 -TemplatePath word.yaml -BackupName word

# Actual restore (dangerous) - requires explicit Force flag
.\test-template-restore.ps1 -TemplatePath word.yaml -BackupName word -Force
```

**Benefits:**
- ✅ **Safe by default** - No accidental system modifications during testing
- ✅ **Detailed simulation** - Shows exactly what would be restored
- ✅ **Graceful handling** - Missing files/registry keys are handled appropriately
- ✅ **Force flag protection** - Actual changes require explicit intent

### Testing Operations

```powershell
# Test a single template backup
.\test-template-workflow.ps1 -Operation backup -TemplatePath word.yaml

# Test restore simulation (safe)
.\test-template-workflow.ps1 -Operation restore -TemplatePath word.yaml -BackupName word

# Test complete workflow (safe restore)
.\test-template-workflow.ps1 -Operation workflow -TemplatePath word.yaml

# Clean test directories
.\test-template-workflow.ps1 -Operation clean

# List available test backups
.\test-template-workflow.ps1 -Operation list
```

**Note**: Integration and end-to-end tests require Docker for safe execution. See [Docker Testing Framework Guide](docs/DOCKER_TESTING_FRAMEWORK.md) for setup instructions.


