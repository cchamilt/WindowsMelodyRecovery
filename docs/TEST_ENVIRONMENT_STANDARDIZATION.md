# Test Environment Standardization Guide

This document describes the standardized test environment system for Windows Melody Recovery, implemented as part of Phase 4.1 of the testing plan.

## 🎯 Overview

The standardized test environment provides consistent, safe, and reliable test infrastructure across all test categories:

- **Unit Tests**: Logic-only testing with proper mocking
- **Integration Tests**: Component integration with real Windows APIs
- **File Operations Tests**: Safe file system operations in isolated directories
- **End-to-End Tests**: Complete user workflow scenarios

## 🔧 Core Components

### Test-Environment-Standard.ps1

The central standardized environment utility located at `tests/utilities/Test-Environment-Standard.ps1` provides:

#### Core Functions
- `Initialize-StandardTestEnvironment` - Creates clean, safe test environment
- `Remove-StandardTestEnvironment` - Comprehensive cleanup with safety checks
- `Reset-StandardTestEnvironment` - Full environment reset
- `Get-StandardTestPaths` - Consistent path structure for tests
- `Test-SafeTestPath` - Enhanced safety validation
- `Test-EnvironmentSafety` - Comprehensive safety checks

### Migration Script

The migration script `tests/scripts/migrate-to-standard-environment.ps1` automatically updates existing test runners to use the standardized environment.

## 📁 Directory Structure

The standardized environment creates a comprehensive directory structure:

```
WindowsMelodyRecovery/
├── test-restore/                    # Restore testing target
├── test-backups/                    # Backup testing source  
├── Temp/                            # Temporary files
├── test-results/
│   └── reports/                     # Test execution reports
├── logs/                            # Test logging
└── tests/
    ├── unit/                        # Unit test files
    ├── integration/                 # Integration test files
    ├── file-operations/             # File operation test files
    ├── end-to-end/                  # End-to-end test files
    ├── mock-data/                   # Mock data for testing
    ├── isolated-temp/               # Isolated temporary operations
    └── safe-workspace/              # Safe environment simulation
```

## 🚀 Usage Examples

### Basic Usage

```powershell
# Initialize for unit tests
. (Join-Path $PSScriptRoot "..\utilities\Test-Environment-Standard.ps1")
$testPaths = Initialize-StandardTestEnvironment -TestType "Unit"

# Initialize for integration tests with enhanced isolation
$testPaths = Initialize-StandardTestEnvironment -TestType "Integration" -IsolationLevel "Enhanced"

# Full reset
Reset-StandardTestEnvironment -TestType "All" -IsolationLevel "Basic"

# Cleanup
Remove-StandardTestEnvironment -Confirm:$false
```

### Advanced Configuration

```powershell
# Initialize with safety validation and force cleanup
$testPaths = Initialize-StandardTestEnvironment `
    -TestType "EndToEnd" `
    -IsolationLevel "Complete" `
    -Force `
    -ValidateSafety

# Get current environment status
$status = Get-TestEnvironmentStatus
Write-Host "Environment initialized: $($status.Initialized)"

# Validate path safety
if (Test-SafeTestPath $somePath) {
    # Safe to perform file operations
    Remove-Item $somePath -Recurse -Force
}
```

## 🔒 Safety Features

### Multi-Level Safety Validation

1. **Path Safety Checks**
   - Forbidden paths (C:\Windows, C:\Program Files, etc.)
   - Required path patterns (WindowsMelodyRecovery, tests, test-)
   - Allowed root validation

2. **Environment Safety**
   - Production environment detection
   - Disk space validation (minimum 1GB free)
   - System resource checks

3. **Isolation Levels**
   - **None**: Basic directory structure only
   - **Basic**: Standard isolation with environment variables
   - **Enhanced**: Resource monitoring and limits
   - **Complete**: Full isolation with network/service restrictions

### Resource Monitoring

For Enhanced and Complete isolation levels:

```powershell
# Automatic resource monitoring
- Memory limit: 1024MB per test process
- Process limit: 50 test-related processes
- Timeout: 30 minutes per test environment
```

## 📊 Test Type Configurations

### Unit Tests (`-TestType "Unit"`)
- **Purpose**: Logic-only testing with mocking
- **Directories**: Minimal structure (unit-mocks, reports)
- **Safety**: High (no file operations)
- **Isolation**: Basic (environment variables only)

### Integration Tests (`-TestType "Integration"`)
- **Purpose**: Component integration testing
- **Directories**: Full backup/restore structure
- **Safety**: Medium (controlled file operations)
- **Isolation**: Basic to Enhanced
- **Components**: applications, system-settings, gaming, wsl, cloud, registry, files

### File Operations Tests (`-TestType "FileOperations"`)
- **Purpose**: Safe file system operations
- **Directories**: Isolated workspace and temp directories
- **Safety**: High (strict path validation)
- **Isolation**: Enhanced (resource monitoring)

### End-to-End Tests (`-TestType "EndToEnd"`)
- **Purpose**: Complete user workflow scenarios
- **Directories**: Full environment simulation
- **Safety**: Medium (comprehensive cleanup)
- **Isolation**: Enhanced to Complete
- **Features**: User profiles, system simulation, environment isolation

## 🔄 Migration Process

### Automatic Migration

The migration script handles:

1. **Import Statement Updates**
   ```powershell
   # Old
   . (Join-Path $PSScriptRoot "..\utilities\Test-Environment.ps1")
   
   # New
   . (Join-Path $PSScriptRoot "..\utilities\Test-Environment-Standard.ps1")
   ```

2. **Function Call Updates**
   ```powershell
   # Old
   Initialize-TestEnvironment -Force
   
   # New  
   Initialize-StandardTestEnvironment -TestType "Integration" -Force
   ```

3. **Local Function Removal**
   - Removes duplicate `Initialize-TestEnvironment` functions
   - Replaces with standardized version calls

### Migration Execution

```powershell
# Dry run to see changes
.\tests\scripts\migrate-to-standard-environment.ps1 -DryRun

# Apply migration with backups
.\tests\scripts\migrate-to-standard-environment.ps1 -Backup

# Migration report
cat test-results\reports\environment-migration-*.json
```

## 📈 Benefits

### Consistency
- Single source of truth for test environment setup
- Standardized path structures across all test types
- Consistent safety validation and cleanup

### Safety
- Multi-level safety checks prevent accidental system damage
- Enhanced path validation with forbidden pattern detection
- Production environment protection

### Reliability
- Comprehensive resource monitoring and limits
- Automatic cleanup with recovery mechanisms
- Environment integrity validation

### Maintainability
- Centralized configuration reduces code duplication
- Easy updates to environment setup across all tests
- Comprehensive reporting and debugging capabilities

## 🛠️ Configuration

### Environment Variables

The system automatically sets:

```powershell
$env:WMR_TEST_MODE = $true
$env:WMR_SAFE_MODE = $true
$env:WMR_LOG_LEVEL = "Debug"
$env:WMR_TEST_ROOT = "path-to-tests"
$env:WMR_TEST_RESTORE = "path-to-test-restore"
$env:WMR_TEST_BACKUP = "path-to-test-backup"
```

### Customization

Modify `$script:TestConfiguration` in Test-Environment-Standard.ps1:

```powershell
$script:TestConfiguration = @{
    Directories = @{
        # Add custom directories
        CustomTestDir = "tests\custom"
    }
    SafetyPatterns = @{
        # Add safety patterns
        RequiredInPath = @("WindowsMelodyRecovery", "custom-pattern")
    }
    Environment = @{
        # Add environment settings
        Variables = @{
            "CUSTOM_VAR" = "value"
        }
    }
}
```

## 🔍 Troubleshooting

### Common Issues

1. **Permission Errors**
   ```
   Solution: Ensure PowerShell is running with appropriate permissions
   Check: Test-EnvironmentSafety -Strict
   ```

2. **Path Safety Violations**
   ```
   Solution: Verify working directory is within project
   Check: Test-SafeTestPath $PWD
   ```

3. **Resource Limits**
   ```
   Solution: Adjust isolation level or increase limits
   Config: $script:TestConfiguration.Environment.Isolation
   ```

### Debugging

```powershell
# Check environment status
Get-TestEnvironmentStatus

# Validate safety
Test-EnvironmentSafety -Strict

# Test path safety
Test-SafeTestPath "C:\some\path"

# Environment integrity
Test-EnvironmentIntegrity -Paths $testPaths
```

## 📝 Integration with Test Runners

All test runners have been automatically migrated:

- ✅ `run-unit-tests.ps1` - Uses Unit test type
- ✅ `run-integration-tests.ps1` - Uses Integration test type  
- ✅ `run-file-operation-tests.ps1` - Uses FileOperations test type
- ✅ `run-end-to-end-tests.ps1` - Uses EndToEnd test type
- ✅ `reset-test-environment.ps1` - Uses All test types

### Runner Implementation

Each runner automatically:

1. Sources the standardized environment
2. Initializes with appropriate test type
3. Runs tests with consistent infrastructure
4. Cleans up with comprehensive safety checks
