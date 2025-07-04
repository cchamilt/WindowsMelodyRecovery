# Windows Melody Recovery - Test Strategy

## Overview

This document outlines the testing strategy for Windows Melody Recovery, which properly separates Windows-specific functionality from cross-platform functionality to ensure reliable testing across different environments.

## Test Categories

### 1. Cross-Platform Tests (Docker/Linux Compatible)

These tests run in the Linux Docker container and test functionality that works across platforms:

- **Integration Tests**: Module loading, configuration management, file operations
- **Unit Tests**: Core logic, template processing, path utilities
- **Mock-Based Tests**: Windows-specific features mocked for Linux environment

**Location**: `tests/integration/` and `tests/unit/` (excluding Windows-Only.Tests.ps1)

**Execution**: 
```bash
# In Docker container
docker exec wmr-test-runner pwsh -Command "/workspace/run-pester-tests.ps1 -TestSuite Installation"
```

### 2. Windows-Only Tests (Windows Systems Only)

These tests require actual Windows functionality and cannot run in Linux containers:

- **Windows Principal Checks**: Real administrator privilege validation
- **Scheduled Tasks**: Actual Windows Task Scheduler operations
- **Registry Operations**: Real Windows registry access
- **Windows-Specific File Operations**: Windows path handling and file system operations
- **Windows Installation Tests**: System directory access, Windows path validation, Windows-specific error handling

**Location**: `tests/unit/Windows-Only.Tests.ps1`

**Execution**:
```powershell
# On Windows systems only
.\run-windows-tests.ps1 -TestSuite WindowsOnly
```

## Test Execution Strategy

### Docker Environment (Linux)

The Docker test environment runs cross-platform tests with proper mocking:

```bash
# Run specific test suites
docker exec wmr-test-runner pwsh -Command "/workspace/run-pester-tests.ps1 -TestSuite Installation"
docker exec wmr-test-runner pwsh -Command "/workspace/run-pester-tests.ps1 -TestSuite Backup"
docker exec wmr-test-runner pwsh -Command "/workspace/run-pester-tests.ps1 -TestSuite All"

# Available test suites:
# - Installation: Module installation and initialization
# - Backup: Backup functionality tests
# - WSL: WSL integration tests
# - Gaming: Gaming platform tests
# - Cloud: Cloud storage tests
# - Restore: Restore functionality tests
# - Pester: Unit tests (excluding Windows-only)
# - All: All cross-platform tests
```

### Windows Environment

Windows-specific tests run on actual Windows systems:

```powershell
# Run Windows-only tests
.\run-windows-tests.ps1 -TestSuite WindowsOnly

# Run all tests (including Windows-only)
.\run-windows-tests.ps1 -TestSuite All
```

## Mocking Strategy

### Cross-Platform Mocking

For tests that run in Linux containers, Windows-specific functionality is properly mocked:

1. **Windows Principal**: Mocked to return configurable results
2. **Scheduled Tasks**: Mocked to simulate task existence/absence
3. **Registry Operations**: Mocked using file-based registry simulation
4. **Windows Paths**: Converted to Linux-compatible paths

### Mock Implementation

```powershell
# Example: Mocking Windows Principal check
Mock Test-WmrAdminPrivilege { return $true }  # Simulate admin
Mock Test-WmrAdminPrivilege { return $false } # Simulate non-admin
```

## CI/CD Integration

### Linux CI/CD Pipeline

```yaml
# Example GitHub Actions for Linux
- name: Run Cross-Platform Tests
  run: |
    docker-compose -f docker-compose.test.yml up -d
    docker exec wmr-test-runner pwsh -Command "/workspace/run-pester-tests.ps1 -TestSuite All"
```

### Windows CI/CD Pipeline

```yaml
# Example GitHub Actions for Windows
- name: Run Windows-Only Tests
  run: |
    .\run-windows-tests.ps1 -TestSuite WindowsOnly
```

## Test Development Guidelines

### Adding Cross-Platform Tests

1. Place tests in appropriate `tests/integration/` or `tests/unit/` files
2. Ensure all Windows-specific functionality is properly mocked
3. Test should pass in Linux Docker container
4. Use platform-agnostic paths and operations

### Adding Windows-Only Tests

1. Place tests in `tests/unit/Windows-Only.Tests.ps1`
2. Tag tests with `WindowsOnly` tag
3. Test should use real Windows functionality
4. Include proper platform checks

### Example Test Structure

```powershell
# Cross-platform test
Describe "Cross-Platform Functionality" {
    It "Should work on any platform" {
        # Test logic that works everywhere
        $result = Test-CrossPlatformFunction
        $result | Should -Be $true
    }
}

# Windows-only test
Describe "Windows-Only Functionality" -Tag "WindowsOnly" {
    BeforeAll {
        if (-not $IsWindows) {
            Write-Warning "Skipping Windows-only tests on non-Windows platform"
            return
        }
    }
    
    It "Should work on Windows only" {
        # Test real Windows functionality
        $result = Test-WindowsSpecificFunction
        $result | Should -Be $true
    }
}
```

## Troubleshooting

### Common Issues

1. **Windows Tests Running in Linux**: Ensure Windows-only tests are properly tagged and excluded
2. **Mock Not Working**: Check mock scope and ensure mocks are set up before function calls
3. **Path Issues**: Use platform-agnostic paths or proper path conversion
4. **Missing Dependencies**: Ensure all required modules are imported

### Debug Commands

```powershell
# Check platform
$IsWindows

# Check available functions
Get-Command -Module WindowsMelodyRecovery

# Run tests with verbose output
Invoke-Pester -Path ./tests/unit/Windows-Only.Tests.ps1 -Verbose

# Check mock status
Get-Mock -All
```

## Best Practices

1. **Always test cross-platform functionality in Docker first**
2. **Use proper mocking for Windows-specific features in Linux tests**
3. **Keep Windows-only tests minimal and focused**
4. **Document any platform-specific behavior**
5. **Use descriptive test names and proper error messages**
6. **Maintain separate test runners for different platforms**

## Future Enhancements

1. **Automated Platform Detection**: Enhanced platform-specific test selection
2. **Parallel Test Execution**: Run Windows and Linux tests in parallel
3. **Enhanced Mocking**: More sophisticated mock implementations
4. **Test Coverage Reporting**: Separate coverage reports for each platform 