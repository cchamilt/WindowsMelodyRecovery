# Changelog

All notable changes to the Windows Missing Recovery module will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-06-29

### Added

#### Comprehensive Testing Framework
- **Docker Containerization**: Complete Docker-based testing environment with `docker-compose.test.yml`
- **Test Runner Container**: Dedicated PowerShell 7.4 Ubuntu container for consistent testing
- **Installation Simulation**: Realistic module installation simulation in test environment
- **Automated Test Orchestration**: `Start-TestRun` function for automated test execution
- **Test Environment Validation**: `Test-Environment` function for test environment health checks
- **Mock Data Support**: Comprehensive mock data for testing various scenarios
- **Integration Test Suite**: Full integration tests for backup, restore, and WSL functionality
- **Unit Test Coverage**: Complete unit test coverage for all module functions

#### Testing Infrastructure
- **Dockerfile.test-runner**: Optimized test runner container with all required dependencies
- **Test Utilities**: Comprehensive test utilities for mocking, Docker operations, and test orchestration
- **Health Check Scripts**: Automated health checks for test environment validation
- **Test Reporting**: Automated test result generation and reporting
- **Mock Scripts**: Realistic mock scripts for testing various scenarios
- **Test Configuration**: Flexible test configuration system

### Fixed

#### Syntax and Parsing Issues
- **Colon Escaping Bugs**: Fixed all colon escaping issues in restore scripts (`$manager: $_` → `$manager`: `$_`)
- **Variable Reference Errors**: Resolved invalid variable reference errors in multiple restore scripts
- **PowerShell Syntax Errors**: Fixed syntax errors across all backup and restore scripts
- **String Interpolation Issues**: Corrected string interpolation problems in error handling

#### Module Export and Function Issues
- **DefaultCommandPrefix Removal**: Removed `DefaultCommandPrefix = 'WMR'` causing function name conflicts
- **Function Name Conflicts**: Resolved WMR prefix issues on exported function names
- **Module Import Problems**: Fixed module import issues in test environments
- **Function Discovery**: Corrected function discovery and export mechanisms

#### Test Environment Issues
- **Module Path Detection**: Fixed module root path detection in Docker test environments
- **Installation Path Issues**: Corrected PowerShell 7+ module path detection on Linux
- **Configuration Template Issues**: Fixed missing configuration template detection
- **OneDrive Detection**: Improved OneDrive path detection for test environments

#### Initialization and Prompt Issues
- **User Prompt Handling**: Fixed initialization prompts appearing during automated tests
- **NoPrompt Parameter**: Properly implemented `-NoPrompt` parameter handling
- **Configuration Persistence**: Fixed configuration persistence issues in test environments
- **Multiple Initialization**: Resolved issues with multiple initialization calls

### Changed

#### Testing Architecture
- **Realistic Test Environment**: Tests now simulate actual production installation process
- **Module Installation Simulation**: Tests use proper module installation instead of direct imports
- **Error Handling Expectations**: Updated test expectations to match actual graceful error handling
- **Permission Error Handling**: Tests now expect graceful handling instead of exceptions

#### Docker Test Environment
- **PowerShell Module Path**: Corrected module installation to `/root/.local/share/powershell/Modules/` for Linux
- **Test Environment Isolation**: Improved test environment isolation and cleanup
- **Module Discovery**: Enhanced module discovery and import mechanisms
- **Configuration Management**: Improved configuration management in test environments

#### Error Handling Philosophy
- **Graceful Error Handling**: Module now handles permission errors gracefully with warnings
- **User Experience Focus**: Prioritizes user experience over strict error enforcement
- **Partial Success Support**: Supports partial initialization when some operations fail
- **Recovery Mechanisms**: Provides recovery mechanisms for failed operations

### Removed

#### Test Inconsistencies
- **Conflicting Test Expectations**: Removed conflicting test expectations for error handling
- **Hardcoded Test Assumptions**: Removed hardcoded assumptions about module behavior
- **Inconsistent Error Handling**: Standardized error handling expectations across all tests

### Security

#### Testing Security
- **Isolated Test Environment**: Complete isolation of test environment from production
- **Mock Data Security**: Secure handling of mock data and test configurations
- **Permission Testing**: Comprehensive permission testing without affecting system security

### Performance

#### Testing Performance
- **Optimized Test Execution**: Improved test execution performance with Docker caching
- **Parallel Test Support**: Support for parallel test execution where applicable
- **Efficient Test Environment**: Optimized test environment setup and teardown

---

## [-.-.-] - 2025-06-07

### Added

#### Core Module Architecture
- **Modular Design**: Complete separation of concerns with Install → Initialize → Setup workflow
- **Configurable Script System**: JSON-based configuration for backup, restore, and setup scripts
- **Load-Environment Function**: Optional environment loading with fallback to module configuration
- **Private Script Loading**: On-demand loading of private scripts only when their public functions are called
- **Clean Module Loading**: Module loads without admin requirements, errors, or unwanted script execution

#### Installation & Configuration System
- **Install-Module.ps1**: Proper file overwriting with `-Force` and `-CleanInstall` parameters
- **Initialize-WindowsMissingRecovery**: Configuration-only initialization with cloud provider selection
- **OneDrive Provider Selection**: Intelligent OneDrive path detection and configuration
- **BACKUP_ROOT Configuration**: Proper backup root path configuration and validation
- **Module Directory Structure**: Uses module directory instead of separate Scripts folder

#### Backup & Restore System
- **Configurable Scripts**: Templates/scripts-config.json for managing enabled backup/restore components
- **Backup-WindowsMissingRecovery**: Uses configuration instead of hardcoded script lists
- **Restore-WindowsMissingRecovery**: Uses configuration instead of hardcoded script lists
- **Set-WindowsMissingRecoveryScripts**: Interactive script management function
- **Get-ScriptsConfig & Set-ScriptsConfig**: Core utilities for configuration management

#### Setup System
- **Setup-WindowsMissingRecovery**: Orchestrates all setup scripts with user prompts
- **Template-Based Setup Scripts**: Consistent structure across all setup components
- **Load-Environment Integration**: All setup scripts use optional Load-Environment with fallback

#### WSL Integration
- **Invoke-WSLScript**: Robust function for executing bash scripts inside WSL from PowerShell
- **WSL Backup System**: Complete backup of packages (APT, NPM, PIP, Snap, Flatpak), configuration files, and home directory
- **WSL Restore System**: Automated restoration of packages, configurations, and dotfiles
- **WSL Package Sync**: Sync-WSLPackages function for package list management
- **WSL Home Sync**: Sync-WSLHome function with rsync and intelligent exclusions
- **Repository Checking**: Test-WSLRepositories function for git repository status monitoring
- **WSL Setup**: Complete WSL installation, configuration, and development environment setup

#### Chezmoi Dotfile Management
- **Setup-WSLChezmoi**: Install and configure chezmoi in WSL with git repository support
- **Backup-WSLChezmoi**: Backup chezmoi source directory and configuration
- **Restore-WSLChezmoi**: Restore chezmoi dotfiles and apply configurations
- **Setup-Chezmoi**: Interactive chezmoi setup with repository initialization
- **Chezmoi Aliases**: Convenient aliases (cm, cma, cme, cms, cmd, cmu, cmcd) for dotfile management
- **Git Repository Support**: Both empty repositories and existing git repositories for dotfiles

#### Setup Script Improvements
- **Template Fixes**: Applied consistent template structure to all setup scripts
- **Function Structure**: All setup scripts converted to proper function format with CmdletBinding
- **Error Handling**: Consistent error handling using `$($_.Exception.Message)` pattern
- **Return Values**: Proper `$true`/`$false` return values for success/failure
- **Admin Privilege Checking**: Warnings instead of hard failures where appropriate

#### Gaming Platform Setup
- **setup-ea-games.ps1**: Complete EA App installation and game management workflow
- **setup-epic-games.ps1**: Epic Games Launcher setup with Legendary CLI integration
- **setup-gog-games.ps1**: GOG Galaxy installation and game management
- **setup-steam-games.ps1**: Steam configuration and game management

#### System Setup Scripts
- **setup-defender.ps1**: Windows Defender configuration with proper structure
- **setup-packagemanagers.ps1**: Chocolatey and Scoop installation and setup
- **setup-restorepoints.ps1**: System restore point configuration
- **setup-removebloat.ps1**: Comprehensive Windows bloatware removal including Lenovo-specific cleanup
- **setup-wsl-fonts.ps1**: Development font installation for WSL with full Nerd Fonts support
- **setup-customprofiles.ps1**: Chezmoi dotfile management setup replacing AI-based generation

### Fixed

#### Core Issues
- **Load-Environment Parameter Prompting**: Fixed ConfigPath parameter prompting by setting default value to `$null`
- **Module Export Problems**: Corrected multiple `Export-ModuleMember` calls and added missing functions to manifest
- **Setup Function Loading**: Fixed function loading issues in Administrator sessions
- **PowerShell Syntax Errors**: Resolved syntax issues in multiple setup scripts

#### Script Structure Issues
- **setup-defender.ps1**: Fixed improper indentation and code structure within function blocks
- **setup-ea-games.ps1**: Restored missing game management logic and fixed function structure
- **setup-epic-games.ps1**: Fixed script-to-function conversion with complete functionality restoration
- **setup-customprofiles.ps1**: Fixed PowerShell syntax errors and string termination issues
- **setup-restorepoints.ps1**: Removed duplicate script code after function conversion

#### Template and Documentation
- **Private/setup/template.ps1**: Updated to reflect correct structure patterns and Load-Environment usage
- **README.md**: Comprehensive update with corrected installation workflow and function documentation

### Changed

#### Architecture Improvements
- **Decoupled Components**: Complete separation of installation, initialization, setup, and environment loading
- **Optional Dependencies**: Load-Environment made optional with graceful fallback to module configuration
- **On-Demand Loading**: Private scripts loaded only when their respective public functions are called
- **Configuration-Driven**: All backup, restore, and setup operations now use configurable script lists

#### Script Standardization
- **Consistent Structure**: All setup scripts follow the same template pattern
- **Error Handling**: Standardized error handling and return value patterns
- **Load-Environment Usage**: Consistent optional usage across all scripts
- **Parameter Validation**: Improved parameter validation and documentation

#### WSL Enhancements
- **Advanced Script Execution**: Robust WSL script execution with proper UTF-8 encoding and error handling
- **Comprehensive Backup**: Complete WSL environment backup including packages, configs, and dotfiles
- **Repository Management**: Advanced git repository status checking and management tools
- **Development Environment**: Complete WSL development environment setup with tools and configurations

### Removed

#### Deprecated Features
- **Hardcoded Script Lists**: Replaced with configurable JSON-based system
- **AI-Based Profile Generation**: Replaced with practical chezmoi dotfile management
- **Load-Environment Dependencies**: Removed mandatory Load-Environment requirements from setup scripts
- **Separate Scripts Folder**: Consolidated to use module directory structure

#### Cleanup
- **Duplicate Code**: Removed duplicate script code in various setup files
- **Unused Dependencies**: Removed unnecessary dependencies and imports
- **Legacy Patterns**: Removed outdated script patterns and structures

### Security

#### Improvements
- **Admin Privilege Handling**: Improved admin privilege checking with warnings instead of hard failures
- **SSH Key Management**: Proper SSH key backup and restore with correct permissions
- **Secure Script Execution**: Enhanced WSL script execution with proper error handling and cleanup

### Performance

#### Optimizations
- **On-Demand Loading**: Scripts loaded only when needed, improving module startup time
- **Parallel Operations**: Support for parallel tool calls where applicable
- **Efficient Backup**: Optimized backup operations with intelligent exclusions and compression

---

## Release Notes

Version 1.0.0 represents a complete overhaul of the Windows Missing Recovery module, transforming it from a collection of scripts into a professional, modular system for Windows environment management. This release introduces comprehensive WSL support, dotfile management with chezmoi, and a fully configurable backup/restore system.

### Key Highlights

- **Complete WSL Integration**: Full support for WSL backup, restore, and management
- **Dotfile Management**: Professional dotfile management with chezmoi integration
- **Modular Architecture**: Clean separation of concerns with configurable components
- **Enhanced Gaming Support**: Complete setup for all major gaming platforms
- **Professional Structure**: Consistent patterns and error handling across all components

### Migration Guide

Users upgrading from previous versions should:
1. Run `Install-WindowsMissingRecovery` to install the new module structure
2. Run `Initialize-WindowsMissingRecovery` to configure the new system
3. Use `Setup-WindowsMissingRecovery` to set up individual components as needed

### Compatibility

- **Windows 10/11**: Full support
- **PowerShell 5.1+**: Required
- **WSL 1/2**: Full support with automatic detection
- **Administrator Privileges**: Required for setup operations, optional for backup/restore

---

*This changelog documents the transformation of Windows Missing Recovery into a comprehensive, professional system for Windows environment management and recovery.* 