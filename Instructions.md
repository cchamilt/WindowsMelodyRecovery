# Instructions

The core idea is to shift from imperative PowerShell scripts for backup/restore to a more declarative, YAML-based configuration for managing system state, including files, registry settings, and applications. This will promote idempotency and simplify configuration.

### Detailed Plan for Template-based State Management

**Core Concepts:**

*   **Templates (`.yaml` files):** These are the static configuration files that define *how* to manage specific system components (applications, registry, files). They act as blueprints or policies, specifying *what* to back up/restore, *how* to find applications, *where* to store dynamic state data, and *what prerequisites* are needed. These replace the current imperative backup/restore PowerShell scripts.
*   **State Files (dynamically generated):** These are the actual data snapshots created during a backup operation based on the templates. They contain lists of installed applications, current registry values, file contents, etc., and are stored in the cloud for later recovery.

---

**Phase 1: Template Schema Definition & Core Utilities**

*   **Task 1.1: Design the `template.yaml` Schema.**
    *   Define the top-level structure including `metadata`, `prerequisites`, `files`, `registry`, `applications`, and `stages`.
    *   **`prerequisites` section:**
        *   Each prerequisite will have a `type` (`application`, `registry`, `script`).
        *   For `application` prerequisites: `name`, `check_command` (e.g., `Get-Package winget`, `apt list --installed | grep 'package-name'`), `expected_output` (regex or specific string).
        *   For `registry` prerequisites: `path`, `name` (for values), `expected_value`.
        *   For `script` prerequisites: `path` or `inline` script, `expected_output`.
        *   Add `on_missing` action (`warn`, `fail_backup`, `fail_restore`).
    *   For `files`, specify attributes like `path` (supporting various formats and environment variables), `type` (`file`, `directory`), `action` (`backup`, `restore`, `sync`), `encrypt`, `destination` (for restore), and `checksum`. Crucially, add a `dynamic_state_path` if the template should generate a list of files or hash of a directory that gets stored as state (e.g., for user-defined file lists).
    *   For `registry`, define `path` (supporting `HKLM:\...` and `winreg://...`), `type` (`key`, `value`), `action`, `name` (for values), `value` (for default restore), and `encrypt`. Add `dynamic_state_path` for keys whose values are to be captured as state.
    *   For `applications`, define *management policies* and *where to store the generated lists*:
        *   `name` (e.g., "Winget Applications", "WSL Apt Packages").
        *   `type` (`winget`, `choco`, `apt`, `steam`, `custom`).
        *   `discovery_command` (e.g., `winget list`, `apt list --installed`).
        *   `parse_script` (path to a script or inline script to parse `discovery_command` output into a standardized list).
        *   `dynamic_state_path`: Path within the backup where the generated list of applications will be stored (e.g., `applications/winget-installed.json`).
        *   `install_script` (path to a script or inline script to install applications from the generated list during restore).
        *   `uninstall_script` (optional, for cleanup).
    *   For `stages` (`Prereqs`, `Preupdate`, `Postupdate`, `Cleanup`), specify `type` (`script`, `check`), `path` or `inline` script content, `parameters`, and `expected_output` for checks.
    *   **Deliverable:** Create `docs/TEMPLATE_SCHEMA.md` detailing this schema.

*   **Task 1.2: Implement Path Normalization and Environment Variable Substitution.**
    *   Create a PowerShell function, e.g., `Convert-WmrPath`, within `Private/Core/PathUtilities.ps1`.
    *   This function will:
        *   Handle Windows local paths, URI paths (`file://`, `wsl://`, `winreg://`).
        *   Perform environment variable substitutions for `$env:VAR`, `$HOME`, and `$user`.
        *   Normalize paths to a consistent internal format suitable for PowerShell operations.
    *   **Deliverable:** `Private/Core/PathUtilities.ps1` with the `Convert-WmrPath` function.

*   **Task 1.3: Develop YAML Parsing Module.**
    *   Create a PowerShell module, `WindowsMelodyRecovery.Template.psm1`, in `Private/Core/`.
    *   This module will contain functions such as:
        *   `Read-WmrTemplateConfig`: Reads and parses a YAML file into a PowerShell object.
        *   `Test-WmrTemplateSchema`: Validates the parsed YAML against the defined schema, including checks for required fields and valid types.
    *   **Deliverable:** `Private/Core/WindowsMelodyRecovery.Template.psm1` with `Read-WmrTemplateConfig` and `Test-WmrTemplateSchema`.

---

**Phase 2: Core State Management Logic (Get/Set & Prerequisites)**

*   **Task 2.1: Implement Prerequisite Checker.**
    *   In `Private/Core/Prerequisites.ps1`, create `Test-WmrPrerequisites` function.
    *   This function will take a `template.yaml` object and the operation type (`Backup` or `Restore`).
    *   It will iterate through the `prerequisites` section:
        *   Execute `check_command` for applications and compare output with `expected_output`.
        *   Read registry values and compare with `expected_value`.
        *   Execute prerequisite scripts and check `expected_output`.
        *   Based on `on_missing` policy, `warn` or throw an error (which `Manage-WmrState` will catch to `fail_backup`/`fail_restore`).
    *   **Deliverable:** `Private/Core/Prerequisites.ps1` with `Test-WmrPrerequisites`.

*   **Task 2.2: Implement File State Management Functions.**
    *   In `Private/Core/FileState.ps1`, create PowerShell functions:
        *   `Get-WmrFileState`: Reads content and metadata (e.g., checksum, last modified date) of a file/directory based on the template definition. If `dynamic_state_path` is specified, it will save the relevant state to that path within the designated "state files" directory.
        *   `Set-WmrFileState`: Writes/copies a file/directory to the specified path during restore, handling encryption/decryption as needed, reading content from the designated "state files" directory.
    *   These functions will utilize `Convert-WmrPath`.
    *   **Deliverable:** `Private/Core/FileState.ps1` with `Get-WmrFileState` and `Set-WmrFileState`.

*   **Task 2.3: Implement Registry State Management Functions.**
    *   In `Private/Core/RegistryState.ps1`, create PowerShell functions:
        *   `Get-WmrRegistryState`: Reads a registry key or value. If `dynamic_state_path` is specified, it will save the value to that path within the designated "state files" directory.
        *   `Set-WmrRegistryState`: Sets a registry key or value during restore, reading the value from the designated "state files" directory.
    *   These functions will utilize `Convert-WmrPath`.
    *   **Deliverable:** `Private/Core/RegistryState.ps1` with `Get-WmrRegistryState` and `Set-WmrRegistryState`.

*   **Task 2.4: Implement Application State Management Functions.**
    *   In `Private/Core/ApplicationState.ps1`, create PowerShell functions:
        *   `Get-WmrApplicationState`:
            *   Takes an application definition from the template.
            *   Executes `discovery_command`.
            *   Pipes the output through `parse_script` to generate a standardized list of installed applications (e.g., JSON array of objects with `name`, `version`, `source`).
            *   Saves this generated list to the `dynamic_state_path` within the "state files" directory.
        *   `Set-WmrApplicationState`:
            *   Reads the generated application list from `dynamic_state_path` within the "state files" directory.
            *   Uses the `install_script` from the template to re-install applications based on the list.
    *   **Deliverable:** `Private/Core/ApplicationState.ps1` with `Get-WmrApplicationState` and `Set-WmrApplicationState`.

*   **Task 2.5: Implement Encryption/Decryption Utilities.**
    *   In `Private/Core/EncryptionUtilities.ps1`, create PowerShell functions:
        *   `Protect-WmrData`: Encrypts data (string or file content) using a symmetric passphrase.
        *   `Unprotect-WmrData`: Decrypts data using the passphrase.
    *   Ensure secure handling of the passphrase (e.g., prompt user, or integrate with a secure key management system).
    *   **Deliverable:** `Private/Core/EncryptionUtilities.ps1` with `Protect-WmrData` and `Unprotect-WmrData`.

---

**Phase 3: Integration and Refactoring**

*   **Task 3.1: Create a Central `Invoke-WmrTemplate` Function.**
    *   Develop a core PowerShell function, `Invoke-WmrTemplate`, in `Private/Core/InvokeWmrTemplate.ps1`.
    *   This function will take a `template.yaml` path and an `operation` (`Backup` or `Restore`).
    *   It will:
        *   Call `Read-WmrTemplateConfig` and `Test-WmrTemplateSchema`.
        *   Call `Test-WmrPrerequisites` to check prerequisites for the given operation.
        *   Manage the creation/reading of the "state files" directory.
        *   Iterate through `files`, `registry`, and `applications` sections, calling `Get-Wmr*State` during backup and `Set-Wmr*State` during restore.
        *   Execute scripts within the defined `stages` (`Prereqs`, `Preupdate`, `Postupdate`, `Cleanup`).
        *   Integrate encryption/decryption where specified.
    *   **Deliverable:** `Private/Core/InvokeWmrTemplate.ps1` with the `Invoke-WmrTemplate` function.

*   **Task 3.2: Create Example Templates.**
    *   Identify a few simple existing `Private/backup/*.ps1` and `Private/restore/*.ps1` scripts (e.g., `backup-display.ps1`, `restore-display.ps1`).
    *   Create corresponding `template.yaml` files for these configurations in a new directory like `Templates/System/` (or `Config/templates/`). These templates will define how to manage display settings, possibly including a prerequisite check for a specific display driver utility.
    *   Create an example template for managing Winget applications, specifying the discovery and installation commands, and where to store the dynamic list.
    *   **Deliverable:** Example `Templates/System/*.yaml` files and an `applications/winget-template.yaml`.

*   **Task 3.3: Refactor Existing Public Scripts to Use Templates.**
    *   Modify `Public/Backup-WindowsMelodyRecovery.ps1` and `Public/Restore-WindowsMelodyRecovery.ps1` to:
        *   Accept template paths as input (e.g., `Backup-WindowsMelodyRecovery -TemplatePath 'Templates/System/display.yaml'`).
        *   Call `Invoke-WmrTemplate` with the appropriate operation (`Backup` or `Restore`) and the provided template path.
        *   Handle the management of the generated "state files" (e.g., create a timestamped directory for each backup in `backups/`).
    *   **Deliverable:** Updated `Public/Backup-WindowsMelodyRecovery.ps1` and `Public/Restore-WindowsMelodyRecovery.ps1`.

---

**Phase 4: Testing and Documentation**

*   **Task 4.1: Develop Unit Tests.**
    *   Write Pester unit tests for all new PowerShell functions created in Phases 1 and 2 (e.g., `Convert-WmrPath`, `Read-WmrTemplateConfig`, `Test-WmrPrerequisites`, `Get-WmrFileState`, `Set-WmrFileState`, `Get-WmrApplicationState`, `Protect-WmrData`).
    *   **Deliverable:** New `.Tests.ps1` files in `tests/unit/` for the new modules.

*   **Task 4.2: Develop Integration Tests.**
    *   Create integration tests in `tests/integration/` that use example `template.yaml` files to simulate backup and restore operations, verify system state changes, and test prerequisite checks (both warning and failing scenarios).
    *   **Deliverable:** New `.Tests.ps1` files in `tests/integration/` for the template-based management.

*   **Task 4.3: Update Documentation.**
    *   Update `README.md` with instructions on how to use the new template-based state management, including examples of creating and using templates.
    *   Create a new document, `docs/STATE_MANAGEMENT_GUIDE.md`, detailing the `template.yaml` schema, usage examples, best practices for defining templates, and how state files are managed.
    *   **Deliverable:** Updated `README.md` and new `docs/STATE_MANAGEMENT_GUIDE.md`.

---
