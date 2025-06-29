# State Management Guide for Windows Melody Recovery

This guide provides a comprehensive overview of the template-based state management system in Windows Melody Recovery. It explains how to define and use templates (`.yaml` files) to manage system configurations, applications, and files, moving away from imperative PowerShell scripts towards a declarative approach.

---

## Table of Contents

1.  [Introduction](#introduction)
2.  [Core Concepts](#core-concepts)
3.  [Template Structure (`template.yaml`)](#template-structure-templateyaml)
    *   [Metadata](#metadata)
    *   [Prerequisites](#prerequisites)
    *   [Files](#files)
    *   [Registry](#registry)
    *   [Applications](#applications)
    *   [Stages](#stages)
4.  [Working with State Files](#working-with-state-files)
5.  [Usage Examples](#usage-examples)
    *   [Backing Up with a Template](#backing-up-with-a-template)
    *   [Restoring with a Template](#restoring-with-a-template)
    *   [Syncing State](#syncing-state)
    *   [Uninstalling Applications](#uninstalling-applications)
6.  [Best Practices](#best-practices)
7.  [Troubleshooting](#troubleshooting)

---

## 1. Introduction

Windows Melody Recovery (WMR) introduces a new template-based state management system designed to simplify the backup, restoration, and synchronization of your Windows system's configuration. Instead of writing custom PowerShell scripts for every backup or restore scenario, you define your desired system state in human-readable YAML template files.

This declarative approach offers several benefits:

*   **Idempotency:** Templates can be run multiple times, ensuring the system converges to the desired state without unintended side effects.
*   **Readability:** YAML files are easy to understand and maintain, describing *what* should be managed rather than *how*.
*   **Consistency:** Standardized templates ensure consistent application of settings across different systems.
*   **Modularity:** Break down complex configurations into smaller, manageable templates.

---

## 2. Core Concepts

Before diving into the template structure, it's important to understand two key concepts:

*   **Templates (`.yaml` files):** These are static configuration files that serve as blueprints for managing specific system components. They define policies, such as which applications to track, which registry keys to back up, and what prerequisites are necessary. Templates are version-controlled and shared.

*   **State Files (dynamically generated):** These are data snapshots created during a `Backup` operation. They contain the *actual* observed state of your system at a given time, such as a list of currently installed Winget applications, the current values of registry keys, or the contents of specific files. State files are typically stored in your designated backup location (e.g., cloud storage) and are used by `Restore` operations.

---

## 3. Template Structure (`template.yaml`)

A `template.yaml` file follows a well-defined schema, organized into top-level sections:

```yaml
metadata:
  # Information about the template
prerequisites:
  # Checks required before operations
files:
  # Definitions for files and directories
registry:
  # Definitions for registry keys and values
applications:
  # Policies for managing applications/packages
stages:
  # Scripts/checks at specific execution points
```

For a detailed definition of each field, refer to `docs/TEMPLATE_SCHEMA.md`.

### Metadata

Provides general information about the template.

```yaml
metadata:
  name: "My Custom Setup"
  description: "Personalized settings for development environment."
  version: "1.0.1"
  author: "John Doe"
  created_date: "2023-01-15"
  last_modified_date: "2024-06-28"
```

### Prerequisites

A list of checks that must pass before a backup or restore operation can proceed. If a prerequisite fails and its `on_missing` action is `fail_backup` or `fail_restore`, the operation will be aborted.

| Key | Description | Example Values |
|---|---|---|
| `type` | Type of prerequisite: `application`, `registry`, or `script`. | |
| `name` | A descriptive name for the prerequisite. | "PowerShell 7", "Visual Studio Code" |
| `on_missing` | Action if missing: `warn`, `fail_backup`, `fail_restore`. | `warn` |
| `check_command` | (For `application`) Command to check for the application. | `winget --version` |
| `expected_output` | (For `application`, `script`) Regex pattern to match command/script output. | `^v\d+\.\d+\.\d+$` |
| `path` | (For `registry`, `script`) Path to registry key/value or script file. | `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion` |
| `key_name` | (For `registry`) Name of the registry value to check. | `InstallLocation` |
| `expected_value` | (For `registry`) Expected value of the registry key/value. | `C:\Program Files\My App` |
| `inline_script` | (For `script`) PowerShell script content to execute directly. | `Write-Output (Get-Host).Version` |

**Example:**

```yaml
prerequisites:
  - type: application
    name: "Git for Windows"
    check_command: "git --version"
    expected_output: "^git version"
    on_missing: fail_backup
  - type: registry
    name: "Custom Font Installed Check"
    path: "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
    key_name: "Cascadia Code PL (TrueType)"
    expected_value: "Cascadia Code PL.ttf"
    on_missing: warn
```

### Files

Defines files and directories to be managed. `dynamic_state_path` is crucial here, as it specifies where the content or metadata of the file/directory will be stored in the state files during a `backup` operation.

| Key | Description | Example Values |
|---|---|---|
| `name` | Descriptive name for the file/directory set. | "VS Code Settings" |
| `path` | Path to the file or directory. Supports `$env:VAR`, `$HOME`, `file://`, `wsl:///`. | `"$env:APPDATA\Code\User\settings.json"` |
| `type` | `file` or `directory`. | `file` |
| `action` | `backup`, `restore`, or `sync`. | `sync` |
| `encrypt` | Whether contents should be encrypted in the state file. | `true` |
| `dynamic_state_path` | Relative path in backup for state. | `user_data/vscode_settings.json` |
| `destination` | (For `restore`, `sync`) Alternate destination path. | `"C:\Users\Public\SharedConfig\app.conf"` |
| `checksum_type` | Type of checksum (`SHA256`). | `SHA256` |

**Example:**

```yaml
files:
  - name: PowerShell Profile
    path: "$HOME\Documents\PowerShell\Microsoft.PowerShell_profile.ps1"
    type: file
    action: sync
    encrypt: false
    dynamic_state_path: "profiles/powershell_profile.ps1"
  - name: Desktop Backgrounds
    path: "C:\Users\Public\Pictures\Wallpapers"
    type: directory
    action: backup
    dynamic_state_path: "media/wallpapers_metadata.json"
```

### Registry

Defines registry keys and values to be managed. Similar to files, `dynamic_state_path` determines where the registry data will be stored as part of the state files.

| Key | Description | Example Values |
|---|---|---|
| `name` | Descriptive name for the registry item. | "Explorer Hidden Files" |
| `path` | Path to the registry key. Supports `HKLM:\...`, `winreg://`. | `HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced` |
| `type` | `key` or `value`. | `value` |
| `action` | `backup`, `restore`, or `sync`. | `sync` |
| `key_name` | (For `value`) Name of the specific registry value. | `Hidden` |
| `value_data` | (For `restore`, `sync`, `value`) Default value to set if not in state. | `0` |
| `encrypt` | Whether value should be encrypted in state file. | `true` |
| `dynamic_state_path` | Relative path in backup for state. | `system_settings/hidden_files.json` |

**Example:**

```yaml
registry:
  - name: Disable OneDrive AutoStart
    path: "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
    key_name: "OneDrive"
    type: value
    action: restore
    value_data: "" # Set to empty string to disable
  - name: Network Profile Settings
    path: "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\NetworkList\Profiles"
    type: key
    action: backup
    dynamic_state_path: "network/network_profiles.json"
```

### Applications

Defines policies for managing applications and packages. Crucially, the *actual lists* of installed applications are dynamically generated during `backup` operations and saved to the `dynamic_state_path`. During `restore`, these saved lists are used to reinstall applications.

| Key | Description | Example Values |
|---|---|---|
| `name` | Descriptive name for the application set. | "Chocolatey Packages" |
| `type` | Package manager/method: `winget`, `choco`, `apt`, `steam`, `npm`, `powershell_module`, `custom`. | `choco` |
| `dynamic_state_path` | Relative path in backup for generated list. | `applications/choco-installed.json` |
| `discovery_command` | Command to list installed items. | `choco list --local-only` |
| `parse_script` | Path/inline script to parse `discovery_command` output to JSON. | (inline script or `scripts/parse-choco-list.ps1`) |
| `install_script` | Path/inline script to install from JSON list. | (inline script or `scripts/install-choco-list.ps1`) |
| `uninstall_script` | (Optional) Path/inline script to uninstall from JSON list. | |
| `dependencies` | List of other template names or prerequisite names. | `["Chocolatey Package Manager"]` |

**Example:**

```yaml
applications:
  - name: NodeJS NPM Global Packages
    type: npm
    dynamic_state_path: "applications/npm-global-packages.json"
    discovery_command: "npm list -g --json"
    parse_script: |
      param([string]$NpmListOutput)
      # NPM list --json already outputs JSON, so just pass it through
      return $NpmListOutput
    install_script: |
      param([string]$PackageListJson)
      $packages = $PackageListJson | ConvertFrom-Json
      foreach ($pkg in $packages.dependencies.PSObject.Properties) {
          Write-Host "Installing NPM package $($pkg.Name)..."
          # npm install -g $($pkg.Name)
          Write-Host "Simulating install of $($pkg.Name)"
      }
  - name: WSL Ubuntu Apt Packages
    type: apt
    dynamic_state_path: "applications/wsl-ubuntu-apt-packages.json"
    discovery_command: "wsl -d Ubuntu apt list --installed | grep -E '^\\S+/'"
    parse_script: |
      param([string]$AptListOutput)
      $packages = @()
      $AptListOutput -split "`n" | ForEach-Object {
          if ($_ -match '^(?<Name>[^/]+)/') {
              $packages += @{ Name = $($Matches.Name) }
          }
      }
      $packages | ConvertTo-Json -Compress
    install_script: |
      param([string]$PackageListJson)
      $packages = $PackageListJson | ConvertFrom-Json
      foreach ($pkg in $packages) {
          Write-Host "Installing $($pkg.Name) in WSL Ubuntu..."
          # wsl -d Ubuntu sudo apt-get install -y $($pkg.Name)
          Write-Host "Simulating install of $($pkg.Name)"
      }
```

### Stages

Defines scripts or checks to run at specific points during the backup or restore process. This is useful for pre- and post-operation tasks that cannot be captured purely declaratively (e.g., restarting services, running custom validation scripts).

| Key | Description |
|---|---|
| `prereqs` | Scripts/checks to run before any main operations (files, registry, apps). |
| `pre_update` | Scripts/checks to run before main file/registry/app operations during `restore` or `sync`. |
| `post_update` | Scripts/checks to run after main file/registry/app operations during `restore` or `sync`. |
| `cleanup` | Scripts/checks to run at the very end, regardless of success. |

**Stage Item Schema:**

| Key | Description | Example Values |
|---|---|---|
| `name` | Descriptive name for the stage item. | "Run Custom Fixup Script" |
| `type` | `script` or `check`. | `script` |
| `path` | (For `script`) Path to the script file. | `scripts/post-restore-fix.ps1` |
| `inline_script` | (For `script`) PowerShell script content to execute directly. | `Restart-Service -Name MyService` |
| `parameters` | Key-value pairs of parameters to pass to the script. | `@{ LogLevel = "Verbose" }` |
| `expected_output` | (For `check`) Regex pattern to match script output. | `"Verification Passed"` |

**Example:**

```yaml
stages:
  prereqs:
    - name: "Ensure Required Service is Running"
      type: check
      inline_script: "(Get-Service -Name 'BITS').Status"
      expected_output: "Running"
  post_update:
    - name: "Flush DNS Cache"
      type: script
      inline_script: "ipconfig /flushdns"
```

---

## 4. Working with State Files

During a `backup` operation, WMR generates state files based on the `dynamic_state_path` definitions in your template. These files are JSON formatted and are stored in a timestamped directory within your configured `backups` directory (e.g., `backups/backup_20240628_143000/`).

*   **Organization:** State files mirror the `dynamic_state_path` structure within the backup directory.
*   **Content:** They contain the actual data (e.g., file contents, registry values, lists of installed applications).
*   **Encryption:** If `encrypt: true` is specified in the template, the content within the state file will be Base64 encoded (placeholder for actual encryption).

When performing a `restore` or `sync` operation, you specify the path to one of these timestamped backup directories as the `StateFilesDirectory`.

---

## 5. Usage Examples

### Backing Up with a Template

To back up your system state using a template:

```powershell
# Example: Backup display settings
.\Public\Backup-WindowsMelodyRecovery.ps1 -TemplatePath ".\Templates\System\display.yaml"

# Example: Backup installed Winget applications
.\Public\Backup-WindowsMelodyRecovery.ps1 -TemplatePath ".\Templates\System\winget-apps.yaml"
```

This will create a new timestamped directory in your `backups` folder (e.g., `backups/backup_YYYYMMDD_HHMMSS/`) containing the generated state files.

### Restoring with a Template

To restore your system state from a previous backup using a template:

```powershell
# Example: Restore display settings from a specific backup
.\Public\Restore-WindowsMelodyRecovery.ps1 -TemplatePath ".\Templates\System\display.yaml" -RestoreFromDirectory ".\backups\backup_20240628_143000"

# Example: Restore Winget applications from a specific backup
.\Public\Restore-WindowsMelodyRecovery.ps1 -TemplatePath ".\Templates\System\winget-apps.yaml" -RestoreFromDirectory ".\backups\backup_20240628_143000"
```

### Syncing State

The `sync` action performs both a `backup` and `restore` operation, ensuring the system's current state matches the template, and then captures the latest state. This is useful for maintaining idempotency.

```powershell
# Example: Sync a custom file configuration
# Assume you have a template named custom-files.yaml with action: sync
# .\Public\Invoke-WmrTemplate -TemplatePath ".\Templates\User\custom-files.yaml" -Operation "Sync" -StateFilesDirectory ".\current_state_sync"
```

### Uninstalling Applications

Templates can also define how to uninstall applications based on a previously captured state.

```powershell
# Example: Uninstall Winget applications based on a previously backed-up list
# .\Public\Invoke-WmrTemplate -TemplatePath ".\Templates\System\winget-apps.yaml" -Operation "Uninstall" -StateFilesDirectory ".\backups\backup_20240628_143000"
```

---

## 6. Best Practices

*   **Granular Templates:** Create small, focused templates for specific components (e.g., one for display settings, one for a particular application, one for WSL configurations). This improves reusability and maintainability.
*   **Version Control:** Store your `template.yaml` files in a version control system (like Git) to track changes and collaborate.
*   **Test Thoroughly:** Always test your templates in a non-production environment before applying them to critical systems.
*   **Prerequisites First:** Utilize the `prerequisites` section to ensure necessary dependencies (e.g., package managers, specific PowerShell modules) are present before an operation proceeds.
*   **Clear `dynamic_state_path`:** Use descriptive and organized paths for your state files within the backup directory to easily locate them later.
*   **Consider Encryption:** Use the `encrypt: true` option for sensitive data in your templates.

---

## 7. Troubleshooting

*   **"Template file not found"**: Double-check the `TemplatePath` provided. Ensure the file exists and the path is correct.
*   **"Posh-YAML module not found"**: The `WindowsMelodyRecovery.Template.psm1` module attempts to install `Posh-YAML` automatically. If it fails, install it manually: `Install-Module -Name Posh-YAML -Scope CurrentUser`.
*   **"Prerequisites not met"**: Review the output for warnings or errors related to prerequisite checks. Adjust your system or template accordingly.
*   **"Failed to get/set file/registry/application state"**: Check the detailed error message. This often indicates incorrect paths, insufficient permissions, or issues with external commands (e.g., `winget`, `apt`).
*   **Inline Scripts:** Ensure inline scripts are valid PowerShell syntax and handle their output as expected by the `expected_output` regex for checks.

For further assistance, refer to the `docs/TEMPLATE_SCHEMA.md` for detailed field definitions.