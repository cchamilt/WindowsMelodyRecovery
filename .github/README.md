# GitHub Actions CI/CD

This directory contains GitHub Actions workflows for automated testing and validation of the Windows Missing Recovery module.

## Workflows

### 1. CI Workflow (`.github/workflows/ci.yml`)

**Purpose**: Fast validation for every push and pull request
**Runtime**: ~5-10 minutes
**Triggers**: Push to main/develop, Pull Requests

**Jobs**:
- **Code Validation**: PSScriptAnalyzer, module structure validation
- **Documentation Check**: README, CHANGELOG, and docs validation  
- **Security Scan**: Basic secret detection and file permission checks

**Use Cases**:
- Quick feedback on code quality
- Validate module can be imported
- Check documentation completeness
- Basic security scanning

### 2. Integration Tests Workflow (`.github/workflows/integration-tests.yml`)

**Purpose**: Comprehensive testing on real Windows environments
**Runtime**: ~60-90 minutes
**Triggers**: Push to main/develop, Pull Requests, Daily schedule, Manual dispatch

**Jobs**:
- **Unit Tests**: Fast Pester tests for core functionality
- **Integration Tests**: Real Windows environment with WSL, package managers
- **End-to-End Tests**: Complete backup/restore cycles
- **Report Generation**: Comprehensive HTML and JSON reports

**Features**:
- **Real WSL 2**: Ubuntu 22.04 installation and testing
- **Real Package Managers**: Chocolatey, Scoop, Winget
- **Gaming Platform Simulation**: Mock Steam, Epic, GOG, EA configurations
- **Cloud Storage Simulation**: OneDrive, Google Drive, Dropbox paths
- **Matrix Testing**: Parallel execution across different test suites
- **Comprehensive Reporting**: HTML reports with test results and system info

## Test Environment

### GitHub Actions Windows Runners

The integration tests run on `windows-latest` runners which provide:

- **OS**: Windows Server 2022
- **PowerShell**: 5.1 and 7.x
- **WSL**: Installable with Ubuntu distributions
- **Package Managers**: Winget pre-installed, Chocolatey/Scoop installable
- **Development Tools**: Git, .NET, Node.js, Python

### Real vs Mock Testing

| Component | CI Workflow | Integration Tests |
|-----------|-------------|-------------------|
| Windows Environment | ✅ Real | ✅ Real |
| PowerShell | ✅ Real | ✅ Real |
| WSL | ❌ Not tested | ✅ Real Ubuntu 22.04 |
| Package Managers | ❌ Not tested | ✅ Real (Choco, Scoop, Winget) |
| Gaming Platforms | ❌ Not tested | 🔶 Simulated directories |
| Cloud Storage | ❌ Not tested | 🔶 Simulated directories |
| Registry Operations | ❌ Not tested | ✅ Real (read-only) |

## Usage

### Automatic Triggers

Both workflows run automatically on:
- Push to `main` or `develop` branches
- Pull requests to `main` or `develop` branches
- Daily schedule (integration tests only, 2 AM UTC)

### Manual Triggers

You can manually trigger the integration tests with custom parameters:

1. Go to **Actions** tab in GitHub
2. Select **Integration Tests** workflow
3. Click **Run workflow**
4. Choose options:
   - **Test Suite**: All, Backup, Restore, WSL, Gaming, Cloud, Setup
   - **Debug Mode**: Enable for verbose logging

### Viewing Results

#### CI Results
- **Status**: Green checkmark or red X on commits/PRs
- **Logs**: Click on workflow run to see detailed logs
- **Artifacts**: Test results XML files

#### Integration Test Results
- **Status**: Detailed status for each test suite
- **Artifacts**: 
  - `unit-test-results`: Pester test results and coverage
  - `integration-test-results-*`: Results for each test suite
  - `e2e-test-results`: End-to-end test results
  - `comprehensive-test-report`: HTML and JSON reports
- **PR Comments**: Automatic summary comments on pull requests

## Test Structure

### Unit Tests (`tests/unit/`)
- Fast tests for core functionality
- Module loading and configuration
- Utility functions
- Error handling

### Integration Tests (`tests/integration/`)
- Real environment testing
- WSL operations
- Package manager integration
- Gaming platform backup/restore
- Cloud storage simulation

### Test Tags

Tests are organized with Pester tags:
- `Unit`: Fast unit tests
- `Backup`: Backup functionality tests
- `Restore`: Restore functionality tests  
- `WSL`: WSL-specific tests
- `Gaming`: Gaming platform tests
- `Cloud`: Cloud storage tests
- `Setup`: Setup script tests

## Development Workflow

### Before Committing
1. Run PSScriptAnalyzer locally: `Invoke-ScriptAnalyzer -Path . -Recurse`
2. Test module import: `Import-Module .\WindowsMissingRecovery.psm1`
3. Run unit tests: `Invoke-Pester tests/unit/`

### Pull Request Process
1. Create feature branch
2. Make changes
3. Push to GitHub
4. CI workflow runs automatically
5. Review results and fix any issues
6. Integration tests run on PR
7. Review comprehensive test report
8. Merge after all checks pass

### Release Process
1. Update version in `WindowsMissingRecovery.psd1`
2. Update `CHANGELOG.md`
3. Create release branch
4. Full integration test suite runs
5. Manual testing if needed
6. Merge to main
7. Create GitHub release

## Troubleshooting

### Common Issues

**PSScriptAnalyzer Failures**:
- Fix code style issues
- Use approved verbs for functions
- Add proper comment-based help

**Module Import Failures**:
- Check syntax errors
- Verify all required files exist
- Test locally first

**WSL Test Failures**:
- WSL installation can be slow (~5-10 minutes)
- Network timeouts may occur
- Some tests are skipped if WSL unavailable

**Integration Test Timeouts**:
- Tests have 90-minute timeout
- WSL setup takes significant time
- Package installations may be slow

### Debugging

**Enable Debug Mode**:
- Use manual workflow dispatch
- Enable debug mode option
- Check detailed logs in Actions

**Local Testing**:
- Use Docker setup for local testing
- Run `run-integration-tests.ps1` locally
- Test individual components

**Log Analysis**:
- Check system information artifacts
- Review error messages in logs
- Compare with previous successful runs

## Configuration

### Workflow Customization

Edit `.github/workflows/*.yml` to:
- Change trigger conditions
- Modify timeout values
- Add/remove test suites
- Adjust matrix configurations

### Test Environment Variables

Available in integration tests:
- `WMR_TEST_MODE`: Set to "true"
- `WMR_BACKUP_ROOT`: Test backup directory
- `WMR_WSL_DISTRO`: WSL distribution name
- `WMR_CLOUD_PATH`: Simulated cloud path

### Secrets and Variables

No secrets required for current setup. All tests use:
- Public package repositories
- Simulated cloud storage
- Mock gaming platform data
- Test-only configurations

## Future Enhancements

### Planned Improvements
- **Performance Testing**: Benchmark backup/restore operations
- **Cross-Platform**: Test PowerShell Core on Linux
- **Real Cloud Testing**: Integration with actual cloud APIs
- **Gaming Platform APIs**: Real Steam/Epic API testing
- **Security Testing**: Advanced vulnerability scanning
- **Load Testing**: Multiple concurrent operations

### Monitoring
- **Test Reliability**: Track flaky tests
- **Performance Metrics**: Monitor test execution times
- **Coverage Reports**: Code coverage tracking
- **Trend Analysis**: Test success rates over time 