# Windows Melody Recovery - Consolidated Testing Strategy

## 1. Overview & Core Principles

This document outlines the unified testing strategy for the Windows Melody Recovery project. It serves as the single source of truth, superseding all previous testing plans and strategy documents.

Our core principle is a **strict separation of concerns** between two primary test environments:
1.  **Cross-Platform (Docker/Linux):** The default environment for all tests that can be run on a non-Windows system. All Windows-specific functionality (Registry, WMI, File Paths) is **aggressively mocked**. This environment is fast, consistent, and safe.
2.  **Windows-Only (Native CI/CD):** A specialized, protected environment for tests that *absolutely require* real Windows APIs. These tests are isolated and run with safety checks, primarily within our CI/CD pipeline, to prevent accidental execution on developer machines.

The recent project milestone of achieving a 100% test pass rate was a tactical success, but it came at the cost of strategic stability by blurring the lines between these environments. The purpose of this consolidated strategy is to **re-establish and enforce this critical separation**, creating a robust and stable foundation for future development.

## 2. Test Runner Architecture

We will use a suite of specialized Pester test runners, each designed for a specific category of tests. This ensures that each test suite runs with only the context and mocks it requires.

| Script | Environment | Purpose | Windows-Only Tests |
|---|---|---|---|
| `run-unit-tests.ps1` | Cross-platform | Validates pure logic (no file or registry I/O) | Skipped in Docker |
| `run-file-operation-tests.ps1` | Cross-platform | Validates safe file I/O within temporary paths | Skipped in Docker |
| `run-integration-tests.ps1` | Auto-detect | Tests component interaction with mocked dependencies | Skipped in Docker |
| `run-end-to-end-tests.ps1` | Auto-detect | Validates complete user workflows (backup/restore) | Skipped in Docker |
| `run-windows-tests.ps1` | Windows CI/CD only | Executes tests requiring real Windows APIs | Required |

## 3. Test Environment Architecture: Enforcing Isolation

To eliminate the fragility of the current system, we will enforce strict isolation between test suites.

*   **Isolated Helper & Mocking Scripts:**
    *   Each test suite will have its own environment setup script (e.g., `Test-Environment.Unit.ps1`, `Test-Environment.E2E.ps1`).
    *   This ensures a test suite *only* loads the mocks and helper functions it needs. For example, Unit tests will never load file-system mocks, and End-to-End tests will have a completely separate mock registry from Integration tests.

*   **Isolated File System Paths:**
    *   Each test run will generate a unique, temporary root directory (e.g., `/tmp/wmr-tests/unit-run-XYZ`).
    *   All file I/O, logging, and mock data for that run *must* exist within this temporary directory. This makes it impossible for tests from different suites to conflict with each other.

*   **Strict Windows-Only Test Segregation:**
    *   Any test that makes a call to a real, un-mocked Windows API (e.g., `Get-Item 'HKLM:\...'`, `Get-CimInstance`, `Register-ScheduledTask`) must reside in the `tests/windows-only/` directory and be executed *only* by the `run-windows-tests.ps1` runner within the Windows CI/CD pipeline.

## 4. Strategic Roadmap: From Stabilization to Features

This roadmap is our active plan. It is managed via the project's `TODO.md` file.

### **Phase 1: Stabilize the Foundation - Isolate Test Environments (Immediate Priority)**

*   **Objective**: Eradicate test fragility by enforcing strict environment isolation.
*   **Tasks**:
    1.  **Refactor Test Helpers & Mocking**: Create distinct setup scripts for each test suite (Unit, FileOps, Integration, E2E) to ensure strict mock/environment isolation.
    2.  **Enforce Strict Pathing Isolation**: Modify test runners to use unique, temporary root paths for each test run to prevent cross-suite file conflicts.
    3.  **Refactor Windows-Only Tests**: Audit and move all tests requiring real Windows APIs to the dedicated `tests/windows-only/` directory, ensuring Docker-based suites are pure cross-platform.

### **Phase 2: Consolidate and Simplify**

*   **Objective**: With a stable foundation, streamline the test suite for maintainability.
*   **Tasks**:
    1.  **Consolidate Redundant Test Files**: Re-evaluate and merge overlapping test files (e.g., for WSL) into single, logical files within their correct categories.
    2.  **Streamline Test Logic**: Simplify tests by removing now-unnecessary environment checks and complex setup, relying on the new isolated test runners.

### **Phase 3: Feature Development and CI/CD Hardening**

*   **Objective**: Resume feature development with confidence, backed by a stable testing platform.
*   **Tasks**:
    1.  **Re-enable Parallel CI/CD Execution**: Update GitHub Actions to run the newly isolated test suites in parallel to accelerate feedback.
    2.  **Implement TUI for Configuration**: Begin development of the curses-based Text User Interface for module initialization and configuration.
    3.  **Squash PSScriptAnalyzer Warnings**: Address and fix outstanding PSScriptAnalyzer warnings in the CI pipeline.

## 5. CI/CD Implementation

Our CI/CD pipeline will consist of two distinct, parallel workflows.

### Docker-Based Workflow (`docker-tests.yml`)

This workflow will run on an Ubuntu host and execute all cross-platform tests inside Docker. After Phase 1 stabilization, the jobs can be run in parallel.

```yaml
name: Docker Cross-Platform Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        test-category: [unit, file-operations, integration, end-to-end]
    steps:
    - uses: actions/checkout@v4
    - name: Run ${{ matrix.test-category }} Tests
      run: ./tests/scripts/run-${{ matrix.test-category }}-tests.ps1
```

### Windows-Native Workflow (`windows-tests.yml`)

This workflow runs on a Windows host and executes only the tests that require a real Windows environment.

```yaml
name: Windows Native Tests
on: [push, pull_request]
jobs:
  windows-tests:
    runs-on: windows-latest
    steps:
    - uses: actions/checkout@v4
    - name: Run Windows-Only Tests
      run: ./tests/scripts/run-windows-tests.ps1 -Category all -CreateRestorePoint
```
