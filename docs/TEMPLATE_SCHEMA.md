# Template YAML Schema for WindowsMelodyRecovery

This document defines the schema for `template.yaml` files, which are used to define how system components (applications, registry settings, files) should be managed (backed up, restored, or synced). These templates act as blueprints or policies, specifying what to manage, how to discover dynamic state, where to store that state, and what prerequisites are required.

---

## Top-Level Structure

A `template.yaml` file has the following top-level keys:

```yaml
metadata:
  # Metadata about the template
prerequisites:
  # Checks required before backup or restore operations
files:
  # Definitions for managing files and directories
registry:
  # Definitions for managing registry keys and values
applications:
  # Definitions for managing applications and packages
stages:
  # Scripts or checks to run at specific points in the process
```

---

## `metadata`

Provides general information about the template.

| Key | Type | Description | Required |
|---|---|---|---|
| `name` | String | A human-readable name for the template (e.g., "Display Settings Template", "Winget Applications"). | Yes |
| `description` | String | A brief description of what this template manages. | Yes |
| `version` | String | The version of the template schema (e.g., "1.0"). | Yes |
| `author` | String | The author or maintainer of the template. | No |
| `created_date` | String (ISO 8601) | The date the template was created. | No |
| `last_modified_date` | String (ISO 8601) | The date the template was last modified. | No |

**Example:**

```yaml
metadata:
  name: Display Settings
  description: Template for backing up and restoring display configuration.
  version: "1.0"
  author: Your Name
```

---

## `prerequisites`

A list of checks that must pass before a backup or restore operation can proceed.

| Key | Type | Description | Required |
|---|---|---|---|
| `type` | String | The type of prerequisite: `application`, `registry`, or `script`. | Yes |
| `name` | String | A descriptive name for the prerequisite (e.g., "DisplayLink Driver", "PowerShell 7"). | Yes |
| `on_missing` | String | Action to take if the prerequisite is missing: `warn`, `fail_backup`, or `fail_restore`. | Yes |
| `check_command` | String | (For `application` type) The command to execute to check for the application (e.g., `winget list "DisplayLink Graphics Driver"`). | Conditional (if type is `application`) |
| `expected_output` | String (Regex) | (For `application` or `script` type) A regex pattern to match against the output of `check_command` or inline script. | Conditional (if type is `application` or `script`) |
| `path` | String | (For `registry` or `script` type) The path to the registry key/value or script file. | Conditional (if type is `registry` or `script`) |
| `key_name` | String | (For `registry` type) The name of the registry value to check (optional, if checking the default value). | Conditional (if type is `registry`) |
| `expected_value` | String | (For `registry` type) The expected value of the registry key/value. | Conditional (if type is `registry`) |
| `inline_script` | String | (For `script` type) PowerShell script content to execute directly. | Conditional (if type is `script`) |

**Example:**

```yaml
prerequisites:
  - type: application
    name: "Winget Package Manager"
    check_command: "winget --version"
    expected_output: "^\d+\.\d+\.\d+$" # Checks for any version number
    on_missing: fail_backup
  - type: registry
    name: "BitLocker Enabled"
    path: "HKLM:\SYSTEM\CurrentControlSet\Control\BitLocker"
    key_name: "Active"
    expected_value: "1"
    on_missing: warn
  - type: script
    name: "Custom PowerShell Module Loaded"
    inline_script: |
      try {
          Import-Module MyCustomModule -ErrorAction Stop
          Write-Output "Module Loaded"
      } catch {
          Write-Output "Module Not Loaded"
      }
    expected_output: "Module Loaded"
    on_missing: fail_restore
```

---

## `files`

Defines files and directories to be managed.

| Key | Type | Description | Required |
|---|---|---|---|
| `name` | String | A descriptive name for the file/directory set. | Yes |
| `path` | String | The path to the file or directory. Supports environment variables (e.g., `$env:APPDATA`, `$HOME`) and URI formats (`file://`, `wsl:///`). | Yes |
| `type` | String | `file` or `directory`. | Yes |
| `action` | String | `backup`, `restore`, or `sync`. `backup` captures state, `restore` applies it, `sync` does both. | Yes |
| `encrypt` | Boolean | Whether the file/directory contents should be encrypted in the state file. | No (default: false) |
| `dynamic_state_path` | String | Relative path within the backup where the file's content or directory's hash/list will be stored as state. E.g., `user_configs/my_app_settings.json`. | Conditional (if action is `backup` or `sync`) |
| `destination` | String | (For `restore` or `sync` action) The destination path during restore, if different from `path`. Supports environment variables and URI formats. | Conditional (if action is `restore` or `sync`) |
| `checksum_type` | String | The type of checksum to generate for verification (e.g., `SHA256`). | No |

**Example:**

```yaml
files:
  - name: SSH Configuration
    path: "$HOME\.ssh"
    type: directory
    action: sync
    encrypt: true
    dynamic_state_path: "home_configs/ssh_config_hash.json"
  - name: Notepad++ Settings
    path: "$env:APPDATA\Notepad++\config.xml"
    type: file
    action: backup
    dynamic_state_path: "app_configs/notepad_plus_plus_config.xml"
```

---

## `registry`

Defines registry keys and values to be managed.

| Key | Type | Description | Required |
|---|---|---|---|
| `name` | String | A descriptive name for the registry item. | Yes |
| `path` | String | The path to the registry key (e.g., `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion`). Supports `winreg://` URI format. | Yes |
| `type` | String | `key` or `value`. | Yes |
| `action` | String | `backup`, `restore`, or `sync`. | Yes |
| `key_name` | String | (For `value` type) The name of the specific registry value to manage. | Conditional (if type is `value`) |
| `value_data` | String / Integer / Boolean | (For `restore` or `sync` action, and `value` type) The default value to set during restore if not found in state. | Conditional (if type is `value` and action is `restore` or `sync`) |
| `encrypt` | Boolean | Whether the registry value should be encrypted in the state file. | No (default: false) |
| `dynamic_state_path` | String | Relative path within the backup where the registry key's values or a specific value will be stored as state. E.g., `system_settings/display_rotation.json`. | Conditional (if action is `backup` or `sync`) |

**Example:**

```yaml
registry:
  - name: Enable Remote Desktop
    path: "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server"
    key_name: "fDenyTSConnections"
    type: value
    action: sync
    value_data: "0" # 0 means enabled
    dynamic_state_path: "system_settings/remote_desktop.json"
  - name: Explorer Settings
    path: "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    type: key
    action: backup
    dynamic_state_path: "user_configs/explorer_advanced.json"
```

---

## `applications`

Defines policies for managing applications and packages. The actual lists of installed applications are dynamically generated and stored as state.

| Key | Type | Description | Required |
|---|---|---|---|
| `name` | String | A descriptive name for the application set (e.g., "Winget Applications", "WSL Apt Packages"). | Yes |
| `type` | String | The package manager or method: `winget`, `choco`, `apt`, `steam`, `npm`, `powershell_module`, `custom`. | Yes |
| `dynamic_state_path` | String | Relative path within the backup where the dynamically generated list of applications/packages will be stored (e.g., `applications/winget-installed.json`). | Yes |
| `discovery_command` | String | The command to list installed applications/packages (e.g., `winget list`, `apt list --installed`). | Yes |
| `parse_script` | String | Path to a PowerShell script or inline script content that parses the output of `discovery_command` into a standardized JSON array (e.g., `[{ "name": "App Name", "version": "1.0" }]`). | Yes |
| `install_script` | String | Path to a PowerShell script or inline script content that takes the standardized JSON array as input and installs the applications/packages. | Yes |
| `uninstall_script` | String | (Optional) Path to a PowerShell script or inline script content that uninstalls applications/packages based on a list. | No |
| `dependencies` | Array of Strings | (Optional) List of other template names or prerequisite names that must be satisfied before this application set is managed. | No |

**Example:**

```yaml
applications:
  - name: Winget Applications
    type: winget
    dynamic_state_path: "applications/winget-installed.json"
    discovery_command: "winget list"
    parse_script: |
      param([string]$WingetListOutput)
      # Example: Parse winget list output into JSON
      # (Actual parsing logic would be more robust)
      $apps = @()
      $WingetListOutput -split "`n" | ForEach-Object {
          if ($_ -match '^(?<Name>[^ ]+)\s+(?<Id>[^ ]+)\s+(?<Version>[^ ]+)') {
              $apps += @{ Name = $($Matches.Name); Id = $($Matches.Id); Version = $($Matches.Version) }
          }
      }
      $apps | ConvertTo-Json -Compress
    install_script: |
      param([string]$AppListJson)
      $apps = $AppListJson | ConvertFrom-Json
      foreach ($app in $apps) {
          Write-Host "Installing $($app.Name) with Winget..."
          # winget install --id $($app.Id) --version $($app.Version) --accept-source-agreements --silent
          # For demonstration, just echo:
          echo "Simulating install of $($app.Name) $($app.Version)"
      }
    dependencies: ["Winget Package Manager"]
  - name: WSL Apt Packages (Ubuntu)
    type: apt
    dynamic_state_path: "applications/wsl-ubuntu-apt-installed.json"
    discovery_command: "wsl -d Ubuntu apt list --installed | grep -E '^\S+/'"
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
          # For demonstration, just echo:
          echo "Simulating install of $($pkg.Name) in WSL Ubuntu"
      }
```

---

## `stages`

Defines scripts or checks to run at specific points during the backup or restore process.

| Key | Type | Description | Required |
|---|---|---|---|
| `prereqs` | Array of Stage Items | Scripts/checks to run before any main operations. | No |
| `pre_update` | Array of Stage Items | Scripts/checks to run before main file/registry/app operations (during restore/sync). | No |
| `post_update` | Array of Stage Items | Scripts/checks to run after main file/registry/app operations (during restore/sync). | No |
| `cleanup` | Array of Stage Items | Scripts/checks to run at the very end. | No |

**Stage Item Schema:**

| Key | Type | Description | Required |
|---|---|---|---|
| `name` | String | A descriptive name for the stage item. | Yes |
| `type` | String | `script` or `check`. | Yes |
| `path` | String | (For `script` type) Path to the script file. | Conditional (if type is `script` and `inline_script` is not used) |
| `inline_script` | String | (For `script` type) PowerShell script content to execute directly. | Conditional (if type is `script` and `path` is not used) |
| `parameters` | Object | (For `script` type) Key-value pairs of parameters to pass to the script. | No |
| `expected_output` | String (Regex) | (For `check` type) A regex pattern to match against the output of the script. | Conditional (if type is `check`) |

**Example:**

```yaml
stages:
  prereqs:
    - name: Ensure PowerShell Execution Policy
      type: script
      inline_script: "Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -Force"
  post_update:
    - name: Restart Display Driver Service
      type: script
      inline_script: "Restart-Service -Name 'DisplayLinkManagerService' -ErrorAction SilentlyContinue"
    - name: Verify Display Resolution
      type: check
      inline_script: |
        $resolution = (Get-DisplayResolution).ToString()
        Write-Output "Current Resolution: $resolution"
      expected_output: "Current Resolution: 1920x1080"
```
