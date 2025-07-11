# Enhanced Mock Infrastructure for Windows Melody Recovery

## Overview

The Enhanced Mock Infrastructure provides comprehensive, realistic mock data generation and management for all test categories in the Windows Melody Recovery project. This system replaces basic mock utilities with sophisticated data generation that scales across unit, integration, and end-to-end tests.

## Architecture

### Core Components

1. **Enhanced-Mock-Infrastructure.ps1** - Core mock data generation engine
2. **Mock-Integration.ps1** - Integration layer for seamless test compatibility
3. **Mock-Utilities.ps1** (Enhanced) - Backwards-compatible wrapper functions
4. **Test-Environment-Standard.ps1** - Standardized test environment integration

### Key Features

- **Realistic Data Generation**: Comprehensive mock data based on real-world applications and configurations
- **Scalable Scope**: Minimal, Standard, Comprehensive, and Enterprise data scopes
- **Test Type Optimization**: Tailored mock data for Unit, Integration, FileOperations, and EndToEnd tests
- **Context-Aware Generation**: Specialized mock data for specific test scenarios
- **Backwards Compatibility**: Seamless integration with existing tests
- **Data Validation**: Built-in integrity checking and validation capabilities

## Mock Data Types

### Application Data
- **Winget Packages**: Real application IDs, versions, and metadata
- **Chocolatey Packages**: Authentic package structures and versions
- **Scoop Applications**: Bucket-aware app installations with realistic paths
- **Configuration Files**: Browser settings, IDE configurations, application preferences

### Gaming Platform Data
- **Steam**: Library configurations, game metadata, user settings
- **Epic Games**: Game installations, launcher configurations
- **GOG Galaxy**: Game library and platform settings
- **EA Desktop**: Game installations and platform configurations

### System Settings
- **Display Configuration**: Multi-monitor setups, resolution, color profiles
- **Power Management**: Power schemes, sleep settings, battery configurations
- **Network Settings**: Adapter configurations, DNS, proxy settings
- **Audio/Video**: Device configurations, codec settings
- **Input Devices**: Mouse, keyboard, touchpad configurations

### Cloud Storage
- **OneDrive**: Sync status, account information, folder configurations
- **Google Drive**: Streaming settings, backup configurations
- **Dropbox**: Smart Sync, selective sync configurations
- **Box**: Enterprise settings, sync configurations

### WSL Data
- **Distributions**: Ubuntu, Debian, custom distributions
- **Package Lists**: APT, PIP, NPM package installations
- **Configurations**: WSL settings, dotfiles, environment configurations
- **Development Tools**: Compilers, interpreters, build tools

### Registry Data
- **System Keys**: Windows version, installation paths
- **User Settings**: Explorer preferences, desktop configurations
- **Application Settings**: Installed application registry entries

## Usage Guide

### Basic Initialization

```powershell
# Import the enhanced mock infrastructure
. "tests/utilities/Enhanced-Mock-Infrastructure.ps1"

# Initialize for integration tests with standard scope
Initialize-EnhancedMockInfrastructure -TestType "Integration" -Scope "Standard"

# Initialize for specific test context
Initialize-MockForTestType -TestType "Integration" -TestContext "ApplicationBackup" -Scope "Comprehensive"
```

### Data Retrieval

```powershell
# Get winget application data
$wingetData = Get-EnhancedMockData -Component "applications" -DataType "winget"

# Get all cloud provider data
$cloudData = Get-EnhancedMockData -Component "cloud"

# Get test-specific data
$appBackupData = Get-MockDataForTest -TestName "ApplicationBackup" -Component "winget" -DataFormat "json"
```

### Legacy Compatibility

```powershell
# Existing tests continue to work with enhanced data
Initialize-MockEnvironment -Environment "Enhanced" -TestType "Integration"
$mockPath = Get-MockDataPath -DataType "applications"
$dataExists = Test-MockDataExists -DataType "applications" -Path "winget.json"
```

## Test Integration Examples

### Unit Tests
```powershell
BeforeAll {
    . "tests/utilities/Enhanced-Mock-Infrastructure.ps1"
    Initialize-EnhancedMockInfrastructure -TestType "Unit" -Scope "Minimal"
}

Describe "Application Logic Tests" {
    It "Should parse winget package data correctly" {
        $mockData = Get-EnhancedMockData -Component "unit" -DataType "configurations"
        # Test logic only, no file operations
    }
}
```

### Integration Tests
```powershell
BeforeAll {
    . "tests/utilities/Enhanced-Mock-Infrastructure.ps1"
    Initialize-MockForTestType -TestType "Integration" -TestContext "ApplicationBackup" -Scope "Standard"
}

Describe "Application Backup Integration" {
    It "Should backup winget packages with realistic data" {
        $wingetData = Get-MockDataForTest -TestName "ApplicationBackup" -Component "winget" -DataFormat "json"
        # Test with realistic package data including VSCode, Chrome, etc.
    }
}
```

### End-to-End Tests
```powershell
BeforeAll {
    . "tests/utilities/Enhanced-Mock-Infrastructure.ps1"
    Initialize-MockForTestType -TestType "EndToEnd" -TestContext "CompleteWorkflow" -Scope "Comprehensive"
}

Describe "Complete Backup Restore Workflow" {
    It "Should perform full system backup and restore" {
        # All components available with comprehensive data
    }
}
```

## Data Scopes

### Minimal
- Essential data for basic testing
- 3-5 applications per package manager
- Basic system configurations
- Single cloud provider

### Standard
- Comprehensive data for regular testing
- 10+ applications per package manager
- Complete system settings coverage
- Multiple cloud providers

### Comprehensive
- Extensive data for thorough testing
- 20+ applications per package manager
- Advanced configurations and edge cases
- All supported platforms and services

### Enterprise
- Maximum data for stress testing
- 50+ applications per package manager
- Complex multi-user configurations
- Enterprise-specific features

## Validation and Quality Assurance

### Built-in Validation
```powershell
# Validate mock data integrity
$validation = Test-MockDataIntegrity -TestType "Integration"

if ($validation.Valid) {
    Write-Host "✅ Mock data validation passed"
} else {
    Write-Host "❌ Issues found: $($validation.Summary.IssuesFound)"
}
```

### Quality Metrics
- **Data Realism**: Based on real-world application data
- **Completeness**: All required fields populated
- **Consistency**: Consistent data formats and structures
- **Accuracy**: Realistic versions, IDs, and configurations

## Performance Characteristics

### Generation Speed
- **Unit Data**: < 1 second
- **Integration Data**: 2-5 seconds
- **End-to-End Data**: 5-10 seconds
- **Enterprise Scope**: 10-15 seconds

### Memory Usage
- **Minimal Scope**: < 10 MB
- **Standard Scope**: 20-50 MB
- **Comprehensive Scope**: 50-100 MB
- **Enterprise Scope**: 100-200 MB

### Storage Requirements
- **Minimal Scope**: < 5 MB disk space
- **Standard Scope**: 10-25 MB disk space
- **Comprehensive Scope**: 25-50 MB disk space
- **Enterprise Scope**: 50-100 MB disk space

## Advanced Features

### Context-Specific Enhancement
```powershell
# Enhance data for specific test contexts
Initialize-MockForTestType -TestType "Integration" -TestContext "GamingIntegration" -Scope "Standard"

# This automatically:
# - Generates enhanced Steam library data
# - Creates realistic game configurations
# - Adds gaming-specific system settings
```

### Data Reset and Regeneration
```powershell
# Reset specific component data
Reset-EnhancedMockData -Component "applications" -Scope "Standard"

# Reset all mock data
Reset-EnhancedMockData -Scope "Comprehensive"
```

### Custom Data Integration
```powershell
# Add custom data to existing mock infrastructure
$customApps = @(
    @{ Id = "Company.InternalTool"; Name = "Internal Tool"; Version = "1.0.0" }
)

# Integrate with existing data
$existingData = Get-EnhancedMockData -Component "applications" -DataType "winget"
$existingData.Packages += $customApps
```

## Migration from Legacy Mock System

### Automatic Migration
The enhanced system provides automatic backwards compatibility:

```powershell
# Legacy code continues to work
Initialize-MockEnvironment -Environment "Docker"
$mockPath = Get-MockDataPath -DataType "registry"

# But now gets enhanced data automatically
```

### Upgrading Tests
To take advantage of enhanced features:

1. **Replace imports**:
   ```powershell
   # Old
   . "$PSScriptRoot\..\utilities\Mock-Utilities.ps1"

   # New
   . "$PSScriptRoot\..\utilities\Enhanced-Mock-Infrastructure.ps1"
   ```

2. **Use context-specific initialization**:
   ```powershell
   # Old
   Initialize-MockEnvironment -Environment "Docker"

   # New
   Initialize-MockForTestType -TestType "Integration" -TestContext "ApplicationBackup"
   ```

3. **Leverage enhanced data retrieval**:
   ```powershell
   # Old
   $data = Get-Content "$TestDataPath\app.json" | ConvertFrom-Json

   # New
   $data = Get-MockDataForTest -TestName "ApplicationBackup" -Component "winget"
   ```

## Best Practices

### Test Design
1. **Use appropriate scope**: Match data scope to test requirements
2. **Leverage context enhancement**: Use test context for specialized data
3. **Validate data integrity**: Run validation checks in CI/CD
4. **Clean up properly**: Use standardized cleanup mechanisms

### Performance Optimization
1. **Initialize once per test suite**: Avoid repeated initialization
2. **Use minimal scope for unit tests**: Reduce memory usage
3. **Cache data retrieval**: Store frequently accessed data
4. **Reset selectively**: Only reset changed components

### Maintenance
1. **Keep data current**: Update mock data versions periodically
2. **Add new applications**: Expand coverage as needed
3. **Validate regularly**: Run integrity checks on data updates
4. **Document customizations**: Record any custom data additions

## Troubleshooting

### Common Issues

#### Mock Data Not Found
```powershell
# Check if infrastructure is initialized
$validation = Test-MockDataIntegrity -TestType "Integration"
if (-not $validation.Valid) {
    Initialize-EnhancedMockInfrastructure -TestType "Integration" -Force
}
```

#### Performance Issues
```powershell
# Use smaller scope for faster initialization
Initialize-EnhancedMockInfrastructure -TestType "Unit" -Scope "Minimal"

# Reset data to clean state
Reset-EnhancedMockData -Scope "Minimal"
```

#### Data Inconsistencies
```powershell
# Force regeneration of problematic component
Reset-EnhancedMockData -Component "applications" -Scope "Standard"

# Validate after regeneration
$validation = Test-MockDataIntegrity -TestType "Integration"
```

### Diagnostic Commands
```powershell
# Check data integrity
Test-MockDataIntegrity -TestType "All"

# List available components
Get-ChildItem (Get-StandardTestPaths).TestMockData

# Check specific component data
Get-EnhancedMockData -Component "applications" | ConvertTo-Json -Depth 2
```

## Future Enhancements

### Planned Features
- **Dynamic Data Generation**: Real-time data generation based on test requirements
- **AI-Enhanced Realism**: Machine learning for more realistic data patterns
- **Cloud Integration**: Sync mock data across test environments
- **Version Management**: Track and manage mock data versions
- **Performance Monitoring**: Built-in performance metrics and optimization

### Extension Points
- **Custom Generators**: Plugin system for custom data generators
- **External Data Sources**: Integration with external data sources
- **Template System**: Configurable data templates
- **API Integration**: REST API for mock data management

## Support and Resources

### Documentation
- [Test Environment Standardization](TEST_ENVIRONMENT_STANDARDIZATION.md)
- [Testing Hierarchy](TESTING_HIERARCHY.md)
- [Test Strategy](TEST_STRATEGY.md)

### Test Runners
- `test-enhanced-mock-infrastructure.ps1` - Validation and demonstration
- `run-integration-tests.ps1` - Integration test execution
- `run-end-to-end-tests.ps1` - End-to-end test execution

### Utilities
- `Enhanced-Mock-Infrastructure.ps1` - Core infrastructure
- `Mock-Integration.ps1` - Integration layer
- `Test-Environment-Standard.ps1` - Standardized environments
