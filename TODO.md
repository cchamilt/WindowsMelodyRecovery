# Windows Melody Recovery - Implementation Plan

## Phase 0: Critical Code Quality & Testing Infrastructure (URGENT - Must Complete First)

### Test Function Cleanup & Separation
- **[URGENT]** Remove all Test- files and functions from Public and Private directories
  - Move `Public/Test-WindowsMelodyRecovery.ps1` to test utilities with proper imports
  - Move `Private/Core/Test-WmrAdminPrivilege.ps1` to test utilities
  - Remove all Test- functions from production code in Private/ directories:
    - `Test-WmrAdministrativePrivilege`, `Test-WmrElevationCapability`, `Test-WmrAdminRequiredOperation` (AdministrativePrivileges.ps1)
    - `Test-WmrInheritanceRuleCondition`, `Test-WmrConditionalSectionCondition`, `Test-WmrRuleItemMatch` (ConditionalProcessing.ps1)
    - `Test-ConfigurationConsistency`, `Test-SharedConfigurationMerging`, `Test-ConfigurationInheritance` and 8 other Test- functions (ConfigurationValidation.ps1)
    - `Test-WmrFileConfig` (FileState.ps1)
    - `Test-WmrMachineSelector`, `Test-WmrStringComparison` (MachineContext.ps1)
    - `Test-WmrPrerequisite` (Prerequisites.ps1)
    - `Test-ModuleInitialized`, `Test-WSLRepository` (WindowsMelodyRecovery.Core.ps1)
    - `Test-ModuleStructure`, `Test-ModuleDependency` (WindowsMelodyRecovery.Initialization.ps1)
    - All Test- functions from setup scripts (setup-*.ps1 files)
  - Refactor test suites to use proper module imports instead of accessing internal Test- functions
  - Status: Critical for proper module design and PowerShell Gallery compliance

### Dot Sourcing Elimination
- **[URGENT]** Remove all dot sourcing from test suites and replace with proper module imports
  - Eliminate dot sourcing from all unit tests (PathUtilities.Tests.ps1, EncryptionUtilities.Tests.ps1, EncryptionWorkflow.Tests.ps1)
  - Remove dot sourcing from integration tests (cloud-failover.Tests.ps1, installation-integration.Tests.ps1, etc.)
  - Replace dot sourcing in file-operations tests with proper module imports
  - Update test runner scripts to use module imports instead of dot sourcing
  - Fix code coverage tracking broken by dot sourcing [[memory:3249270]]
  - Status: Critical for code coverage accuracy and proper module design

### Production Code Dot Sourcing Review
- **[HIGH PRIORITY]** Audit and potentially refactor dot sourcing in production code
  - Review dot sourcing in Private/Core/ files (TemplateResolution.ps1, TemplateInheritance.ps1)
  - Evaluate dot sourcing in setup scripts and determine if module imports are more appropriate
  - Ensure production dot sourcing doesn't violate module design principles
  - Status: Important for consistent module architecture

## Phase 1: Foundation & Testing (High Priority - In Progress)

### Testing Infrastructure
- **[IN PROGRESS]** Test test suites in their proper environments and pass in CI/CD
  - Fix Docker test environment stability issues
  - Enhance Windows-only test coverage for CI/CD execution
  - Improve integration test reliability
  - Status: Docker tests need stability improvements, Windows CI/CD tests functional

### User Experience Improvements
- **[PENDING]** Test and refine UX (better error handling if config loading fails)
  - Implement graceful config loading failure handling in TUI
  - Add user-friendly error messages and recovery options
  - Enhance TUI navigation and feedback systems
  - Status: TUI framework exists, needs error handling improvements

## Phase 2: User Experience Enhancements (High Priority)

### Application Management
- **[PENDING]** Create export/import or edit calls for simplified user editable app/game lists
  - Implement CSV/JSON export functionality for app/game lists
  - Add bulk selection UI in TUI for app management
  - Create user-friendly editing interface
  - Status: Basic app discovery exists, needs user management interface

- **[PENDING]** Determine to uninstall/keep apps not on restore list
  - Implement app decision workflow in TUI
  - Add bloatware detection and removal recommendations
  - Create whitelist/blacklist management system
  - Status: App discovery implemented, decision logic needed

### Package Management
- **[PENDING]** Manage version pinning
  - Implement version constraints for winget, chocolatey, scoop
  - Add version conflict resolution
  - Create version rollback capabilities
  - Status: Package managers integrated, version pinning needed

## Phase 3: Advanced Features (Medium Priority)

### Configuration Management
- **[PARTIALLY IMPLEMENTED]** Support for shared configurations and override logic for host vs default shared
  - Enhance template inheritance system
  - Add machine-specific vs shared configuration logic
  - Implement configuration merging and conflict resolution
  - Status: Template inheritance exists, needs enhanced override logic

### Setup & Deployment
- **[PENDING]** Refactor setup scripts and test for them in docker
  - Modularize setup scripts for better testability
  - Create Docker-compatible setup procedures
  - Add comprehensive setup script testing
  - Status: Setup scripts exist, need refactoring and Docker testing

### Restore Procedures
- **[PENDING]** Implement restore procedure for the complex templates
  - Create restore workflows for registry, system settings, applications
  - Add validation and rollback capabilities
  - Implement incremental restore options
  - Status: Basic restore exists, complex template restore needed

### Scheduled Maintenance
- **[PARTIALLY IMPLEMENTED]** Add all packaging updates as scheduled tasks (winget, choco, npm, etc.)
  - Extend existing task system for package manager updates
  - Add PowerShell module update scheduling
  - Implement update conflict resolution
  - Status: Task framework exists, needs package manager integration

## Phase 4: Discovery & Documentation (Medium Priority)

### Application Discovery
- **[IMPLEMENTED]** Discovering unmanaged packages, document them for manual storage
  - Status: Fully implemented in Find-UnmanagedApplication.ps1
  - Enhancement: Add user documentation generation

### Documentation & Workflow
- **[PENDING]** Update documentation and workflow
  - Document: install → initialize → capture state → remove bloat → optimize → capture new state → install maintenance tasks
  - Create procedural recovery documentation
  - Add troubleshooting guides
  - Status: Basic docs exist, comprehensive workflow docs needed

### Gallery Preparation
- **[PENDING]** Clean up verb practices and naming for gallery release
  - Audit all functions for PowerShell approved verbs
  - Standardize naming conventions
  - Prepare for PowerShell Gallery publication
  - Status: Core functions exist, need verb compliance audit

## Phase 5: Advanced Storage & Backup (Lower Priority)

### Data Protection
- **[PARTIALLY IMPLEMENTED]** Certificate storage options (keyvault, local file encryption)
  - Status: AES-256 encryption utilities implemented
  - Enhancement: Add Azure Key Vault integration

- **[PENDING]** Store Windows key information (account attached, actual key)
  - Implement secure Windows license key storage
  - Add account association tracking
  - Create key recovery procedures
  - Status: Not implemented, needs security design

### Backup Strategies
- **[PENDING]** User directory sync (filtered/limited rsync to zip/cloud)
  - Implement selective user directory backup
  - Add cloud storage integration beyond current providers
  - Create incremental sync capabilities
  - Status: Cloud providers integrated, user directory sync needed

- **[PENDING]** Recovery policy (90 days weekly backups, cloud/git storage with deltas)
  - Implement retention policy management
  - Add delta backup capabilities
  - Create automated cleanup procedures
  - Status: Basic backup exists, retention policy needed

- **[PENDING]** Network drive backup and Azure Blob storage support
  - Extend beyond current cloud file services
  - Add network drive integration
  - Implement Azure Blob storage provider
  - Status: File-based cloud providers exist, network/blob storage needed

## Phase 6: Enterprise & Advanced Features (Future)

### Server Features
- **[PENDING]** Server features (services, server features, IIS configuration, files/directories)
  - Add Windows Server role and feature backup/restore
  - Implement IIS configuration management
  - Create service configuration backup
  - Status: Client-focused currently, server features needed

### Administrative Management
- **[PENDING]** Document and support Windows' new sudo inline option
  - Reference: https://learn.microsoft.com/en-us/windows/advanced-settings/sudo/
  - Integrate with existing administrative privilege management
  - Update documentation for sudo usage
  - Status: Admin privilege system exists, sudo integration needed

### Infrastructure Integration
- **[PENDING]** Output system backup into packer build compatible HCL files
  - Create Packer template generation from system state
  - Add HCL formatting for infrastructure as code
  - Wrap module installation, initialization, restoration in HCL
  - Implement automated build pipeline integration
  - Status: System state capture exists, Packer output needed

## Future Considerations

### Branding
- **[UNDER CONSIDERATION]** Rename as "retune"?
  - Evaluate branding implications
  - Consider trademark and naming conflicts
  - Assess community feedback
  - Status: Current name functional, rename optional

---

## Implementation Notes

- **Confidence Levels**: High (90%+), Medium (70-89%), Lower (50-69%)
- **Dependencies**: Many features build on existing template inheritance and encryption systems
- **Testing Strategy**: Each phase includes comprehensive testing requirements
- **Documentation**: All features require user documentation and inline help

## Current Status Summary
- ✅ **Implemented**: Unmanaged app discovery, scheduled tasks framework, encryption utilities, TUI interface
- 🔄 **In Progress**: Testing infrastructure improvements
- 📋 **Next Priority**: User experience enhancements and application management workflows
