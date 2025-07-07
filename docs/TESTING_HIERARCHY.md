# Testing Hierarchy for Windows Melody Recovery

This document outlines the structured testing approach that separates different types of tests based on their scope and safety requirements.

## 🏗️ **Testing Structure**

```
tests/
├── unit/                    # Pure logic tests - NO file operations
├── file-operations/         # File tests in SAFE test directories only  
├── integration/            # Windows admin/destructive (CI/CD ONLY)
├── docker/                 # Dockerable mocked system tests
└── end-to-end/             # Full system tests (dockerized)
```

## 🧪 **Test Categories**

### 1. **Unit Tests** (`tests/unit/`)
**Purpose**: Test function logic only
**Safety**: Completely safe - no file operations
**Scope**: Individual functions and decision logic

**Characteristics**:
- ✅ Mock all file system operations
- ✅ Test decision-making logic
- ✅ Test parameter validation
- ✅ Test error handling paths
- ❌ NO actual file creation/deletion
- ❌ NO directory operations
- ❌ NO external system calls

**Examples**:
- `SharedConfiguration.Tests.ps1` - Tests backup path priority logic
- `FileState-Logic.Tests.ps1` - Tests file state decision logic
- `ApplicationState.Tests.ps1` - Tests application discovery logic

### 2. **File Operation Tests** (`tests/file-operations/`)
**Purpose**: Test actual file operations in safe directories
**Safety**: Operates ONLY in test-restore, test-backup, Temp
**Scope**: File system interactions

**Characteristics**:
- ✅ Real file operations in safe directories
- ✅ Automatic cleanup before/after tests
- ✅ Safety validation of all paths
- ✅ Tests backup/restore file workflows
- ❌ NEVER operates outside test directories
- ❌ NO system-wide changes

**Examples**:
- `FileState-FileOperations.Tests.ps1` - Tests actual file backup/restore
- Future: `RegistryState-FileOperations.Tests.ps1` - Tests registry export/import

### 3. **Integration Tests** (`tests/integration/`)
**Purpose**: Test Windows admin/destructive operations
**Safety**: DANGEROUS - CI/CD pipeline ONLY
**Scope**: Real Windows system integration

**Characteristics**:
- ⚠️ Requires administrative privileges
- ⚠️ Makes real system changes
- ⚠️ NEVER run on development machines
- ⚠️ NEVER run on QA machines
- ✅ CI/CD pipeline only
- ✅ Isolated test environments

**Examples**:
- Windows Features enable/disable
- Registry modifications outside test keys
- Service installations
- System restore points

### 4. **Docker Tests** (`tests/docker/`)
**Purpose**: Mocked system integration testing
**Safety**: Safe - containerized
**Scope**: Cross-platform compatibility

**Characteristics**:
- ✅ Dockerized environments
- ✅ Mock Windows/Linux systems
- ✅ Safe for all environments
- ✅ Repeatable and isolated

### 5. **End-to-End Tests** (`tests/end-to-end/`)
**Purpose**: Full system workflow testing
**Safety**: Safe - containerized
**Scope**: Complete user scenarios

**Characteristics**:
- ✅ Full backup/restore workflows
- ✅ Multi-component integration
- ✅ User scenario validation

## 🛡️ **Safety Mechanisms**

### Test Environment Management
- **Centralized utilities**: `tests/utilities/Test-Environment.ps1`
- **Path validation**: `Test-SafeTestPath` function
- **Automatic cleanup**: Before and after test execution
- **Directory isolation**: Only test-restore, test-backup, Temp

### Safety Checks
```powershell
# All file operations must pass safety validation
if (-not (Test-SafeTestPath $path)) {
    Write-Error "SAFETY VIOLATION: Path not safe for testing"
    return
}
```

### Test Scripts
- **Unit Tests**: `tests/scripts/run-clean-unit-tests.ps1`
- **File Operations**: `tests/scripts/run-file-operation-tests.ps1` 
- **Environment Reset**: `tests/scripts/reset-test-environment.ps1`

## 📊 **Current Status**

### ✅ **Completed**
- **Unit Tests**: SharedConfiguration (8/8 passing), ApplicationState (7/7 passing), FileState-Logic (10/14 passing)
- **Test Environment**: Centralized utilities with safety checks
- **File Operations**: Structure created, FileState-FileOperations moved
- **Safety**: Dangerous deletion bug fixed in SharedConfiguration

### 🚧 **In Progress** 
- **Unit Tests**: FileState-Logic mock refinements
- **File Operations**: Testing and validation
- **Integration**: Separation of admin/destructive tests

### 📋 **Planned**
- **Docker Tests**: Organization and enhancement
- **End-to-End**: Full workflow testing
- **CI/CD**: Integration test pipeline

## 🎯 **Testing Best Practices**

### Unit Tests
```powershell
# GOOD - Test logic only
It "Should prioritize machine-specific backup when both exist" {
    Mock Test-Path { $true } -ParameterFilter { $Path -like "*machine*" }
    Mock Test-Path { $true } -ParameterFilter { $Path -like "*shared*" }
    
    $result = Test-BackupPath -Path "test.json" -BackupType "Test"
    $result | Should -Be $machineBackupPath
}

# BAD - File operations in unit tests
BeforeEach {
    Remove-Item -Path $testDir -Recurse -Force  # ❌ NO!
}
```

### File Operation Tests
```powershell
# GOOD - Safe file operations
BeforeAll {
    $testPaths = Initialize-TestEnvironment -Force
    # Operates only in safe test directories
}

# BAD - Unsafe paths
$unsafePath = "C:\Windows\System32\test.txt"  # ❌ NO!
```

## 🔄 **Test Execution Workflow**

1. **Development**: Run unit tests only (`run-clean-unit-tests.ps1`)
2. **QA**: Run unit + file operation tests
3. **CI/CD**: Run all test categories including integration
4. **Docker**: Cross-platform validation

This hierarchy ensures safety while providing comprehensive test coverage across all components and scenarios. 