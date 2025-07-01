# Testing Quick Reference

Quick reference for common Docker testing framework commands and workflows.

## Quick Start

```bash
# 1. Start test environment
docker-compose -f docker-compose.test.yml up -d

# 2. Run tests
pwsh .\run-integration-tests.ps1 -TestSuite All -GenerateReport

# 3. Check results
Get-ChildItem test-results -Recurse

# 4. Clean up
docker-compose -f docker-compose.test.yml down
```

## Common Commands

### Environment Management
```bash
# Start all containers
docker-compose -f docker-compose.test.yml up -d

# Stop all containers
docker-compose -f docker-compose.test.yml down

# Restart containers
docker-compose -f docker-compose.test.yml restart

# Check container status
docker-compose -f docker-compose.test.yml ps

# View logs
docker-compose -f docker-compose.test.yml logs
```

### Running Tests

#### Host Scripts
```powershell
# Full test suite with reporting
pwsh .\run-integration-tests.ps1 -TestSuite All -GenerateReport

# Specific test suites
pwsh .\run-integration-tests.ps1 -TestSuite Backup
pwsh .\run-integration-tests.ps1 -TestSuite WSL
pwsh .\run-integration-tests.ps1 -TestSuite Gaming

# Skip Docker build (faster)
pwsh .\run-integration-tests.ps1 -TestSuite Backup -SkipBuild

# With cleanup
pwsh .\run-integration-tests.ps1 -TestSuite All -Cleanup
```

#### Direct Container Execution
```bash
# Test orchestrator
docker exec wmr-test-runner pwsh /tests/scripts/test-orchestrator.ps1 -TestSuite Backup

# Specific test file
docker exec wmr-test-runner pwsh -Command "Invoke-Pester /tests/integration/backup-applications.Tests.ps1"

# Interactive PowerShell
docker exec -it wmr-test-runner pwsh
```

### Mock Commands
```bash
# WSL commands
docker exec wmr-test-runner wsl --version
docker exec wmr-test-runner wsl --list --quiet
docker exec wmr-test-runner wsl --exec bash -c "whoami"

# Windows Registry
docker exec wmr-test-runner reg query "HKLM\SOFTWARE\Microsoft"

# Package managers
docker exec wmr-test-runner winget list
docker exec wmr-test-runner choco list
```

## Test Results

### Viewing Results
```powershell
# List all results
Get-ChildItem test-results -Recurse

# View latest JSON report
$latest = Get-ChildItem test-results/reports -Filter "*.json" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
Get-Content $latest.FullName | ConvertFrom-Json | Format-Table

# From container
docker exec wmr-test-runner ls -la /test-results/reports/
```

### Copying Results
```bash
# Manual copy from container
docker cp wmr-test-runner:/test-results/. ./test-results/

# Copy specific report
docker cp wmr-test-runner:/test-results/reports/test-summary-latest.json ./
```

## Debugging

### Container Inspection
```bash
# Interactive debugging
docker exec -it wmr-test-runner pwsh
docker exec -it wmr-wsl-mock bash

# Check container health
docker exec wmr-test-runner pwsh -Command "Test-Environment"
docker exec wmr-wsl-mock bash -c "whoami && pwd"
docker exec wmr-cloud-mock curl http://localhost:8080/health
```

### Log Analysis
```bash
# Container logs
docker logs wmr-test-runner
docker logs wmr-wsl-mock --tail 50

# Test execution logs
docker exec wmr-test-runner cat /test-results/logs/test-orchestrator.log
```

### Network Testing
```bash
# Container connectivity
docker exec wmr-test-runner ping wmr-wsl-mock
docker exec wmr-test-runner ping wmr-cloud-mock

# Port testing
docker exec wmr-test-runner curl http://wmr-cloud-mock:8080/health
```

## Test Suites

| Suite | Description |
|-------|-------------|
| `All` | Complete test suite |
| `Backup` | Backup functionality |
| `WSL` | WSL integration |
| `Gaming` | Gaming platforms |
| `Cloud` | Cloud storage |

## Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| Container won't start | `docker-compose down && docker-compose up -d` |
| Tests not found | Verify volume mounts: `docker exec wmr-test-runner ls /workspace` |
| No test results | Check: `docker exec wmr-test-runner ls /test-results` |
| WSL commands fail | Test: `docker exec wmr-test-runner which wsl` |
| Network issues | Restart: `docker-compose restart` |

### Reset Environment
```bash
# Complete reset
docker-compose -f docker-compose.test.yml down
docker system prune -f
docker-compose -f docker-compose.test.yml build --no-cache
docker-compose -f docker-compose.test.yml up -d
```

## Test Suites

| Suite | Description | Key Tests |
|-------|-------------|-----------|
| `All` | Complete test suite | Everything |
| `Backup` | Backup functionality | Applications, Gaming, Cloud, System |
| `Restore` | Restore operations | System settings restore |
| `WSL` | WSL integration | Distribution management, file access |
| `Gaming` | Gaming platforms | Steam, Epic, GOG, EA |
| `Cloud` | Cloud storage | OneDrive, Google Drive, Dropbox |
| `Installation` | Module installation | Template integration |

## Performance Tips

```bash
# Faster iteration
pwsh .\run-integration-tests.ps1 -TestSuite Backup -SkipBuild

# Parallel execution (when supported)
docker exec wmr-test-runner pwsh /tests/scripts/test-orchestrator.ps1 -TestSuite All -Parallel

# Resource monitoring
docker stats

# Cleanup between runs
docker system prune -f
```

## CI/CD Integration

```yaml
# GitHub Actions example
- name: Setup Test Environment
  run: docker-compose -f docker-compose.test.yml up -d

- name: Run Tests
  run: pwsh .\run-integration-tests.ps1 -TestSuite All -GenerateReport

- name: Upload Results
  uses: actions/upload-artifact@v4
  with:
    name: test-results
    path: test-results/
```
