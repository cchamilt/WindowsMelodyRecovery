# Windows Melody Recovery - Comprehensive Testing Plan

This document outlines a structured approach to resolving all testing issues, improving test infrastructure, and implementing comprehensive test coverage for the Windows Melody Recovery module.

## 🚨 UPDATED Critical Issues (Priority 1) - POST-AUDIT

### Test Suite Architecture Overhaul - IMMEDIATE ATTENTION REQUIRED

**Status**: ❌ BROKEN - Multiple architectural issues discovered in audit

#### Test Redundancy Crisis 
- **Issue**: 6 separate WSL test files with 80%+ overlapping functionality (2,446 total lines)
- **Impact**: Maintenance nightmare, conflicting test approaches, wasted resources
- **Root Cause**: Multiple "generations" of tests without consolidation
- **Priority**: CRITICAL

#### Legacy Script References
- **Issue**: Tests still reference deleted backup scripts (`backup-wsl.ps1`, `backup-system-settings.ps1`, etc.)
- **Impact**: 6+ test files failing with "file not found" errors
- **Root Cause**: Incomplete migration from script-based to template-based system
- **Priority**: CRITICAL

#### Unit Test Violations
- **Issue**: Unit tests performing file operations, violating testing hierarchy principles
- **Impact**: Unsafe tests, unclear test boundaries, potential system damage
- **Root Cause**: Lack of adherence to documented testing hierarchy
- **Priority**: HIGH

#### Module Import Chaos
- **Issue**: 4+ different module import patterns across test files
- **Impact**: Inconsistent test environment setup, hard to maintain
- **Root Cause**: No standardized test infrastructure
- **Priority**: HIGH

## 📋 CONSOLIDATED Structured Testing Plan

### Phase 1: EMERGENCY Test Architecture Consolidation (Week 1)

#### Task 1.1: Remove Legacy Script References
- **Objective**: Eliminate all references to deleted backup scripts
- **Actions**:
  - Scan all test files for `backup-wsl.ps1`, `backup-system-settings.ps1`, `backup-applications.ps1` references
  - Replace with template-based approaches using `Invoke-WmrTemplate`
  - Update `wsl-tests.Tests.ps1` (lines 241, 286, 431, 438, 450, 494) 
  - Remove function calls to `Backup-WSL`, `Backup-WSLSettings` that no longer exist

#### Task 1.2: WSL Test Consolidation 
- **Objective**: Reduce 6 overlapping WSL test files to 3 logical files
- **Current Files to Consolidate**:
  - `backup-wsl.Tests.ps1` (371 lines) 
  - `wsl-integration.Tests.ps1` (354 lines)
  - `wsl-tests.Tests.ps1` (593 lines)
  - `wsl-package-management.Tests.ps1` (520 lines)
  - `wsl-communication-validation.Tests.ps1` (195 lines)
  - `chezmoi-wsl-integration.Tests.ps1` (413 lines)
- **Target Structure**:
  - `WSL-Logic.Tests.ps1` - Pure logic tests (unit level)
  - `WSL-FileOperations.Tests.ps1` - Safe file operations
  - `WSL-Integration.Tests.ps1` - Docker/container integration

#### Task 1.3: Standardize Module Imports
- **Objective**: Single import pattern across all test files
- **Actions**:
  - Replace 4+ different import patterns with standardized approach
  - Implement: `Import-Module (Resolve-Path "$PSScriptRoot/../../WindowsMelodyRecovery.psd1") -Force`
  - Update all 29 test files with consistent import pattern
  - Add error handling for missing module files

#### Task 1.4: Unit Test Purification
- **Objective**: Move file operations out of unit tests
- **Actions**:
  - Audit `FileState-Logic.Tests.ps1` for file operations
  - Move file operations to `tests/file-operations/`
  - Ensure unit tests only test logic with proper mocking
  - Validate adherence to testing hierarchy [[memory:2421544]]

### Phase 2: Template System Integration Testing (Week 2)

#### Task 2.1: Backup Test Unification
- **Objective**: Consolidate 7 backup test files into coherent structure
- **Current Files**:
  - `backup-tests.Tests.ps1` (template-based) ✅
  - `backup-wsl.Tests.ps1` (template-based) ✅  
  - `backup-applications.Tests.ps1` (template-based) ✅
  - `backup-system-settings.Tests.ps1` (template-based) ✅
  - `backup-gaming.Tests.ps1` (template-based) ✅
  - `backup-cloud.Tests.ps1` (mixed approach) ⚠️
  - Legacy script references ❌
- **Actions**:
  - Merge template-based backup tests into unified suite
  - Remove redundant backup contexts across files
  - Standardize template testing approach

#### Task 2.2: Template Coverage Validation
- **Objective**: Ensure all 26 templates have proper test coverage
- **Actions**:
  - Audit template coverage in consolidated backup tests
  - Add missing template tests for gaps identified
  - Validate template parsing and JSON handling
  - Test template backup/restore round-trips

### Phase 3: Test Category Enforcement (Week 3)

#### Task 3.1: File Operations Migration
- **Objective**: Move all file operations to proper test category
- **Actions**:
  - Create additional files in `tests/file-operations/`
  - Move file operations from unit and integration tests
  - Implement safety checks for all file operations
  - Ensure operations only in test-restore, test-backup, Temp directories

#### Task 3.2: Integration Test Safety Assessment
- **Objective**: Identify and isolate dangerous Windows tests
- **Actions**:
  - Audit integration tests for Windows admin requirements
  - Move dangerous tests to CI-only execution [[memory:2261044]]
  - Implement proper Windows-only test tagging
  - Add safety checks to prevent execution on development systems

#### Task 3.3: Missing End-to-End Implementation
- **Objective**: Populate empty end-to-end test directory
- **Actions**:
  - Design end-to-end test scenarios
  - Implement full backup/restore workflow tests
  - Add multi-component integration scenarios
  - Test complete user journeys

### Phase 4: Infrastructure Modernization (Week 4)

#### Task 4.1: Test Environment Standardization
- **Objective**: Implement consistent test environment setup
- **Actions**:
  - Create standardized test environment utilities
  - Implement proper test cleanup mechanisms
  - Add safety validation for all test paths
  - Create test environment reset functionality

#### Task 4.2: Mock Infrastructure Enhancement
- **Objective**: Improve mock data quality and coverage
- **Actions**:
  - Enhance Windows environment simulation
  - Improve cloud storage provider mocking
  - Add realistic application and gaming platform mocks
  - Standardize mock data structures

### Phase 5: Registry and Restoration Testing (Week 5-6)

#### Task 5.1: Registry Testing Consistency
- **Objective**: Ensure registry operations work correctly
- **Actions**:
  - Validate registry calls match between templates and mocks
  - Test graceful handling of missing registry keys during backup
  - Test registry restoration to empty/missing paths
  - Implement registry prerequisite checking

#### Task 5.2: Shared Configuration Testing
- **Objective**: Test shared vs host-specific configurations  
- **Actions**:
  - Test shared configuration and override logic
  - Validate host vs default shared configuration blending
  - Test system restoration with shared configuration merging
  - Test configuration inheritance patterns

#### Task 5.3: Administrative Privileges Testing
- **Objective**: Test features requiring admin rights
- **Actions**:
  - Test windows-features backup/restore (requires admin)
  - Validate privilege escalation prompts
  - Test admin-required setup scripts
  - Mock administrative operations for testing

### Phase 6: Security and Encryption Testing (Week 6-7)

#### Task 6.1: Encryption Workflow Testing
- **Objective**: Test secure backup and restore operations
- **Actions**:
  - Test password prompts for encryption passkey
  - Validate secure key/file encryption workflows
  - Test encrypted backup task installation
  - Test secure file handling and storage

#### Task 6.2: Authentication and Security Testing
- **Objective**: Test security-related features
- **Actions**:
  - Test SSH key backup and restore
  - Test secure cloud storage authentication
  - Test Windows key information storage and retrieval
  - Test security policy backup and restoration

### Phase 7: Feature Development Testing (Week 7-8)

#### Task 7.1: BitLocker and Windows Backup Testing
- **Objective**: Test system backup and security features
- **Actions**:
  - Test BitLocker setup and configuration
  - Test Windows backup service configuration
  - Validate system backup and restore workflows
  - Test backup verification and integrity checking

#### Task 7.2: Application Discovery and Management
- **Objective**: Test application management workflows
- **Actions**:
  - Test unmanaged application discovery
  - Test application installation file documentation
  - Test app install/uninstall decision workflows
  - Test simplified user-editable app/game lists
  - Initialization testing
  - Setup scripting/configuration selection

#### Task 7.3: Version and Update Management
- **Objective**: Test package and module update workflows
- **Actions**:
  - Test version pinning functionality
  - Test packaging and module updates as scheduled tasks
  - Test update task installation and configuration
  - Test automated update workflows

### Phase 8: CI/CD Integration (Week 8-9)

#### Task 8.1: GitHub Actions Integration
- **Objective**: Set up automated testing pipeline
- **Actions**:
  - Configure GitHub Actions to match Docker testing framework
  - Set up automated test execution on PRs and pushes
  - Configure test result reporting and artifact collection
  - Set up automated deployment of test results

#### Task 8.2: Test Framework Consolidation
- **Objective**: Merge all testing approaches
- **Actions**:
  - Consolidate unit and integration testing in Docker
  - Review and optimize container/emulation logic
  - Determine what can be unmocked for full testing
  - Push consolidated testing to main branch

#### Task 8.3: PowerShell Gallery Preparation
- **Objective**: Prepare module for public release
- **Actions**:
  - Clean up PowerShell verb practices and naming conventions
  - Validate module manifest and dependencies
  - Test module installation from PowerShell Gallery
  - Validate gallery publishing workflow

## 🎯 UPDATED Success Metrics

### Phase 1 Success Criteria (CRITICAL)
- [x] All legacy script references removed from test files
- [x] WSL tests consolidated from 6 files to 3 logical files
- [x] Single standardized module import pattern across all 29 test files
- [x] Unit tests purified of file operations

### Phase 2 Success Criteria (HIGH)
- [x] Backup tests unified into coherent structure
- [ ] All 26 templates have validated test coverage
- [ ] Template parsing and JSON handling working
- [ ] Template backup/restore round-trips successful

### Phase 3 Success Criteria (MEDIUM)
- [ ] File operations properly categorized in file-operations directory
- [ ] Dangerous Windows tests isolated to CI-only execution
- [ ] End-to-end test directory populated with real tests
- [ ] Test safety mechanisms implemented

### Phase 4 Success Criteria (MEDIUM)
- [ ] Standardized test environment utilities implemented
- [ ] Enhanced mock infrastructure for realistic testing
- [ ] Consistent test cleanup and safety validation
- [ ] Mock data quality and coverage improved

### Phase 5 Success Criteria (LOW)
- [ ] Registry operations reliable across all templates
- [ ] Shared configuration logic working
- [ ] Administrative privilege handling working
- [ ] Registry prerequisite checking functional

### Phase 6 Success Criteria (LOW)
- [ ] Encryption workflows tested and secure
- [ ] Authentication mechanisms validated
- [ ] Security features fully tested
- [ ] Secure storage mechanisms working

### Phase 7 Success Criteria (LOW)
- [ ] BitLocker and Windows backup features working
- [ ] Application discovery and management working
- [ ] Version management and updates working
- [ ] All new features properly tested
- [ ] Initialization mock integration testing
- [ ] Setup script selection scripts
- [ ] Ability to select different bloat removal preferences and per hardware vendor removals

### Phase 8 Success Criteria (LOW)
- [ ] CI/CD pipeline fully operational
- [ ] All tests running automatically
- [ ] Module ready for PowerShell Gallery
- [ ] Documentation complete and accurate

## 📊 UPDATED Testing Dashboard - POST-AUDIT

| Test Area | Current Status | Root Issue | Target Status | Priority |
|-----------|---------------|------------|---------------|----------|
| WSL Tests | ❌ 6 Redundant Files | Multiple generations, 80% overlap | ✅ 3 Logical Files | CRITICAL |
| Legacy References | ❌ Script Not Found | Template migration incomplete | ✅ All References Updated | CRITICAL |
| Module Imports | ❌ 4+ Patterns | No standardization | ✅ Single Pattern | CRITICAL |
| Unit Test Purity | ❌ File Operations | Hierarchy violations | ✅ Logic Only | HIGH |
| Backup Tests | ⚠️ 7 Overlapping Files | Mixed approaches | ✅ Unified Structure | HIGH |
| Template Coverage | ❌ Gaps Identified | Incomplete validation | ✅ All 26 Templates | HIGH |
| File Operations | ⚠️ Scattered | Wrong categories | ✅ Proper Directory | MEDIUM |
| Integration Safety | ❌ Mixed Safe/Dangerous | No safety isolation | ✅ CI-Only Dangerous | MEDIUM |
| End-to-End | ❌ Empty Directory | Missing implementation | ✅ Full Workflows | MEDIUM |
| Mock Infrastructure | ⚠️ Basic | Needs enhancement | ✅ Comprehensive | LOW |

## 🚀 UPDATED Getting Started

**Based on audit findings, we are NOW in Phase 1 of a completely restructured plan:**

1. **CRITICAL: Remove Legacy Script References** - Fix immediate test failures
2. **CRITICAL: Consolidate WSL Tests** - Eliminate massive redundancy  
3. **CRITICAL: Standardize Module Imports** - Create consistent test infrastructure
4. **HIGH: Purify Unit Tests** - Enforce testing hierarchy
5. **Update TODO list** - Track progress on consolidated tasks

**Current Position**: We have successfully completed the audit phase and identified the architectural issues. We are now ready to execute the emergency consolidation plan.

This updated plan focuses on the **critical architectural issues** discovered in the audit rather than the original runtime failures, providing a foundation for sustainable test infrastructure. 