# Windows Missing Recovery - Integration Testing System

This directory contains a comprehensive Docker-based integration testing system that simulates Windows, WSL, and cloud storage environments to test the Windows Missing Recovery module functionality.

## Overview

The testing system creates a complete mock environment that includes:

- **Mock Windows Environment**: PowerShell Core on Linux with simulated Windows commands and file structures
- **Mock WSL Environment**: Real Ubuntu container with development tools and package managers
- **Mock Cloud Storage**: HTTP/HTTPS server simulating OneDrive, Google Drive, and Dropbox APIs
- **Gaming Platform Mocks**: Simulated Steam, Epic Games, GOG Galaxy, and EA App environments
- **Package Manager Mocks**: Simulated Chocolatey, Scoop, and Winget functionality

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Test Runner   │    │  Windows Mock   │    │   WSL Mock      │
│   (Orchestrator)│◄──►│  (PowerShell)   │◄──►│   (Ubuntu)      │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         │              ┌─────────────────┐              │
         └─────────────►│  Cloud Mock     │◄─────────────┘
                        │  (Node.js API)  │
                        └─────────────────┘
                                 │
                        ┌─────────────────┐
                        │  Gaming Mocks   │
                        │  Package Mocks  │
                        └─────────────────┘
```

## Prerequisites

- **Docker Desktop** (Windows, macOS, or Linux)
- **Docker Compose** (included with Docker Desktop)
- **PowerShell 7+** (for running the test script)
- **8GB+ RAM** (recommended for running all containers)
- **10GB+ free disk space** (for container images and test data)

## Quick Start

1. **Clone the repository and navigate to the root directory**:
   ```powershell
   git clone <repository-url>
   cd WindowsMissingRecovery
   ```

2. **Run all integration tests**:
   ```powershell
   ./run-integration-tests.ps1 -TestSuite All -GenerateReport
   ```

3. **Run specific test suites**:
   ```powershell
   # Test module installation and setup
   ./run-integration-tests.ps1 -TestSuite Installation
   
   # Test module initialization and configuration
   ./run-integration-tests.ps1 -TestSuite Initialization
   
   # Run Pester unit and integration tests
   ./run-integration-tests.ps1 -TestSuite Pester
   
   # Test chezmoi dotfile management
   ./run-integration-tests.ps1 -TestSuite Chezmoi
   
   # Test only WSL functionality
   ./run-integration-tests.ps1 -TestSuite WSL
   
   # Test only backup functionality
   ./run-integration-tests.ps1 -TestSuite Backup
   
   # Test only cloud integration
   ./run-integration-tests.ps1 -TestSuite Cloud
   ```

4. **Clean environment and run tests**:
   ```powershell
   ./run-integration-tests.ps1 -TestSuite All -Clean -GenerateReport
   ```

## Test Suites

### Available Test Suites

- **All**: Runs all test suites (default)
- **Installation**: Tests module installation and setup functionality
- **Initialization**: Tests module initialization and configuration management
- **Pester**: Runs Pester unit and integration tests
- **Backup**: Tests all backup functionality
- **Restore**: Tests all restore functionality  
- **WSL**: Tests WSL integration and chezmoi functionality
- **Gaming**: Tests gaming platform integrations
- **Cloud**: Tests cloud storage provider integrations
- **Chezmoi**: Tests chezmoi dotfile management functionality
- **Setup**: Tests setup and configuration functionality

### Test Coverage

#### Installation Tests
- Module manifest validation
- PowerShell script syntax validation
- Module import and export verification
- Installation script functionality
- Required file presence and structure
- Module dependencies and prerequisites

#### Initialization Tests
- Module initialization workflow
- Configuration directory creation
- Template file copying and validation
- Environment variable setup
- Status and health check functions
- Error handling and recovery
- Configuration validation and integrity

#### Pester Tests
- Unit test execution and validation
- Integration test execution
- Test infrastructure verification
- Code coverage analysis
- Test result reporting
- Pester configuration validation
- Test file syntax validation

#### Chezmoi Tests
- Chezmoi availability and installation verification
- Chezmoi initialization and configuration
- Source directory management and validation
- File management and template processing
- Backup and restore functionality
- Integration with Windows Missing Recovery module
- Error handling and edge cases
- Performance and scalability testing

#### Backup Tests
- System settings backup
- Application and package manager backup
- Gaming platform configuration backup
- WSL environment backup (packages, configs, dotfiles)
- Cloud storage integration
- Registry export functionality
- File and folder backup operations

#### Restore Tests
- System settings restoration
- Application and package manager restoration
- Gaming platform configuration restoration
- WSL environment restoration
- Cloud storage synchronization
- Registry import functionality
- File and folder restoration operations

#### WSL Integration Tests
- Package manager synchronization (APT, NPM, PIP, Snap, Flatpak)
- Configuration file backup and restore
- Shell environment restoration
- chezmoi dotfile management
- SSH key management
- Development tool configurations
- Cross-container communication

#### Cloud Integration Tests
- OneDrive path detection and sync
- Google Drive integration
- Dropbox integration
- Multi-cloud backup strategies
- Sync status monitoring
- File upload/download operations
- Backup retention policies

#### Gaming Platform Tests
- Steam configuration and library management
- Epic Games Launcher and Legendary CLI
- GOG Galaxy settings and library
- EA App/Origin configurations
- Game metadata and save data handling

## Container Details

### Windows Mock Container (`wmr-windows-mock`)
- **Base**: PowerShell 7.4 on Ubuntu 22.04
- **Purpose**: Simulates Windows PowerShell environment
- **Features**:
  - Mock Windows commands (`reg`, `winget`, `choco`, `scoop`)
  - Simulated Windows directory structure
  - Mock registry operations
  - PowerShell module testing environment

### WSL Mock Container (`wmr-wsl-mock`)
- **Base**: Ubuntu 22.04
- **Purpose**: Real WSL environment for testing
- **Features**:
  - Complete development environment
  - Package managers (APT, NPM, PIP, Snap, Flatpak)
  - Version managers (nvm, pyenv, rbenv)
  - chezmoi for dotfile management
  - SSH and Git configurations

### Cloud Mock Container (`wmr-cloud-mock`)
- **Base**: Node.js 18 Alpine
- **Purpose**: Simulates cloud storage APIs
- **Features**:
  - REST API endpoints for file operations
  - Multi-provider support (OneDrive, Google Drive, Dropbox)
  - File upload/download simulation
  - Sync status simulation
  - HTTPS support with self-signed certificates

### Test Runner Container (`wmr-test-runner`)
- **Base**: PowerShell 7.4 on Ubuntu 22.04
- **Purpose**: Orchestrates and executes tests
- **Features**:
  - Pester testing framework
  - Test result aggregation
  - Report generation (HTML, JSON)
  - Container health monitoring
  - Cross-container test coordination

## Mock Data and Scripts

### Mock Windows Commands
Located in `tests/mock-scripts/windows/`:
- `reg.sh`: Mock Windows registry operations
- `winget.sh`: Mock Windows Package Manager
- `choco.sh`: Mock Chocolatey operations
- `scoop.sh`: Mock Scoop operations

### Mock Data
Located in `tests/mock-data/`:
- `registry/`: Mock Windows registry exports
- `appdata/`: Mock application data
- `wsl/`: Mock WSL configurations and dotfiles
- `cloud/`: Mock cloud storage data

### Test Scripts
Located in `tests/`:
- `integration/`: Integration test scripts
- `unit/`: Unit test scripts
- `utilities/`: Test utility functions
- `scripts/`: Test orchestration scripts

## Configuration

### Environment Variables

The testing system uses environment variables for configuration:

```bash
# Container hostnames
MOCK_WINDOWS_HOST=windows-mock
MOCK_WSL_HOST=wsl-mock
MOCK_CLOUD_HOST=mock-cloud-server

# Paths
BACKUP_ROOT=/workspace/test-backups
CLOUD_PATH=/mock-cloud
USER_PROFILE=/mock-appdata/Users/TestUser

# Cloud server configuration
ONEDRIVE_PATH=/cloud-storage/OneDrive
GOOGLEDRIVE_PATH=/cloud-storage/GoogleDrive
DROPBOX_PATH=/cloud-storage/Dropbox
```

### Test Configuration

Test behavior can be configured through parameters:

```powershell
# Run with cleanup
./run-integration-tests.ps1 -Clean

# Keep containers for debugging
./run-integration-tests.ps1 -KeepContainers

# Generate detailed reports
./run-integration-tests.ps1 -GenerateReport

# Run tests in parallel
./run-integration-tests.ps1 -Parallel
```

## Debugging

### Container Logs
```bash
# View all container logs
docker compose -f docker-compose.test.yml logs -f

# View specific container logs
docker logs wmr-windows-mock
docker logs wmr-wsl-mock
docker logs wmr-cloud-mock
docker logs wmr-test-runner
```

### Interactive Debugging
```bash
# Connect to Windows mock environment
docker exec -it wmr-windows-mock pwsh

# Connect to WSL mock environment
docker exec -it wmr-wsl-mock bash

# Connect to test runner
docker exec -it wmr-test-runner pwsh
```

### Cloud Server Testing
```bash
# Test cloud server health
curl http://localhost:8080/health

# Test OneDrive API
curl http://localhost:8080/api/onedrive/status

# Test file upload
curl -X POST -F "file=@test.txt" http://localhost:8080/api/onedrive/upload
```

## Test Results

### Output Locations
- **Local Results**: `./test-results/`
- **Container Results**: `/test-results/` (in test-runner container)

### Report Types
- **JSON Report**: `test-results/reports/integration-test-report.json`
- **HTML Report**: `test-results/reports/integration-test-report.html`
- **Unit Test Results**: `test-results/unit/`
- **Integration Test Results**: `test-results/integration/`
- **Coverage Reports**: `test-results/coverage/`

### Report Contents
- Test execution summary
- Individual test results
- Performance metrics
- Error details and stack traces
- Container health information
- Environment configuration

## Extending the Tests

### Adding New Test Cases

1. **Create test script** in `tests/integration/`:
   ```powershell
   # tests/integration/my-feature.Tests.ps1
   Describe "My Feature Tests" {
       It "Should perform expected operation" {
           # Test implementation
       }
   }
   ```

2. **Add to test orchestrator** in `tests/scripts/test-orchestrator.ps1`:
   ```powershell
   $myTests = @(
       @{ Name = "My Feature"; Script = "my-feature.Tests.ps1" }
   )
   ```

### Adding Mock Services

1. **Create Dockerfile** in `tests/docker/`:
   ```dockerfile
   FROM appropriate-base-image
   # Service setup
   ```

2. **Add to docker-compose.test.yml**:
   ```yaml
   my-service:
     build:
       dockerfile: tests/docker/Dockerfile.my-service
     # Service configuration
   ```

3. **Update test orchestrator** to include new service

### Adding Mock Data

1. **Create mock data** in `tests/mock-data/`:
   ```
   tests/mock-data/
   ├── my-service/
   │   ├── config.json
   │   └── sample-data.xml
   ```

2. **Copy to container** in Dockerfile:
   ```dockerfile
   COPY tests/mock-data/my-service/ /mock-service/
   ```

## Troubleshooting

### Common Issues

1. **Docker not running**:
   ```
   Error: Cannot connect to Docker daemon
   Solution: Start Docker Desktop
   ```

2. **Port conflicts**:
   ```
   Error: Port 8080 already in use
   Solution: Stop conflicting services or change ports in docker-compose.test.yml
   ```

3. **Insufficient memory**:
   ```
   Error: Container killed (OOMKilled)
   Solution: Increase Docker memory limit or reduce parallel containers
   ```

4. **Container build failures**:
   ```
   Error: Failed to build image
   Solution: Check Dockerfile syntax and network connectivity
   ```

### Performance Optimization

1. **Use Docker BuildKit**:
   ```bash
   export DOCKER_BUILDKIT=1
   ```

2. **Increase Docker resources**:
   - Memory: 8GB+
   - CPU: 4+ cores
   - Disk: 10GB+

3. **Use parallel testing**:
   ```powershell
   ./run-integration-tests.ps1 -Parallel
   ```

## Contributing

### Test Development Guidelines

1. **Follow naming conventions**:
   - Test files: `*.Tests.ps1`
   - Mock scripts: `*.sh` or `*.ps1`
   - Mock data: Organized by service/component

2. **Use proper mocking**:
   - Mock external dependencies
   - Use consistent mock data
   - Provide realistic responses

3. **Include error scenarios**:
   - Test failure conditions
   - Test edge cases
   - Test recovery mechanisms

4. **Document test cases**:
   - Clear test descriptions
   - Expected outcomes
   - Prerequisites and setup

### Submitting Changes

1. **Test locally**:
   ```powershell
   ./run-integration-tests.ps1 -TestSuite All -Clean
   ```

2. **Update documentation** if needed

3. **Submit pull request** with:
   - Description of changes
   - Test results
   - Any new dependencies

## License

This testing system is part of the Windows Missing Recovery project and follows the same license terms.

---

*For more information about the Windows Missing Recovery module, see the main [README.md](../README.md).* 
