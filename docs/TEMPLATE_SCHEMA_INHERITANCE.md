# Extended Template Schema with Configuration Inheritance

This document extends the base template schema to support configuration inheritance patterns, allowing templates to define both shared and machine-specific configuration sections with proper inheritance rules.

## Overview

The extended template schema supports:
- **Shared Configuration**: Settings that apply across all machines
- **Machine-Specific Configuration**: Settings that override shared settings for specific machines
- **Inheritance Rules**: Rules that govern how configurations are merged and applied
- **Conditional Sections**: Template sections that are conditionally applied based on machine characteristics

---

## Extended Top-Level Structure

The extended template schema adds new top-level sections:

```yaml
metadata:
  # Standard metadata (unchanged)
configuration:
  # NEW: Configuration inheritance settings
shared:
  # NEW: Shared configuration sections
machine_specific:
  # NEW: Machine-specific configuration overrides
inheritance_rules:
  # NEW: Rules for configuration inheritance
conditional_sections:
  # NEW: Conditionally applied sections
prerequisites:
  # Standard prerequisites (unchanged)
files:
  # Standard files (unchanged)
registry:
  # Standard registry (unchanged)
applications:
  # Standard applications (unchanged)
stages:
  # Standard stages (unchanged)
```

---

## `configuration` Section

Defines global configuration inheritance settings for the template.

| Key | Type | Description | Required |
|---|---|---|---|
| `inheritance_mode` | String | How inheritance should be applied: `merge`, `override`, or `selective`. | No (default: `merge`) |
| `machine_precedence` | Boolean | Whether machine-specific settings always take precedence over shared settings. | No (default: `true`) |
| `validation_level` | String | Level of validation to apply: `strict`, `moderate`, or `relaxed`. | No (default: `moderate`) |
| `fallback_strategy` | String | What to do when machine-specific config is missing: `use_shared`, `fail`, or `warn`. | No (default: `use_shared`) |

**Example:**

```yaml
configuration:
  inheritance_mode: merge
  machine_precedence: true
  validation_level: moderate
  fallback_strategy: use_shared
```

---

## `shared` Section

Defines configuration sections that apply to all machines unless overridden.

The `shared` section can contain any of the standard template sections (`files`, `registry`, `applications`, `prerequisites`, `stages`) with additional inheritance metadata.

| Key | Type | Description | Required |
|---|---|---|---|
| `name` | String | Descriptive name for the shared configuration section. | No |
| `description` | String | Description of what this shared configuration manages. | No |
| `priority` | Integer | Priority level for this shared configuration (1-100, higher = more important). | No (default: 50) |
| `override_policy` | String | How machine-specific overrides should be handled: `merge`, `replace`, or `extend`. | No (default: `merge`) |
| `files` | Array | Shared file configurations. | No |
| `registry` | Array | Shared registry configurations. | No |
| `applications` | Array | Shared application configurations. | No |
| `prerequisites` | Array | Shared prerequisites. | No |
| `stages` | Array | Shared stages. | No |

**Example:**

```yaml
shared:
  name: "Common Display Settings"
  description: "Display settings that apply to all machines"
  priority: 60
  override_policy: merge
  
  registry:
    - name: Default Theme Settings
      path: 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ThemeManager'
      type: key
      action: sync
      dynamic_state_path: "shared/registry/theme_manager.json"
      inheritance_tags:
        - "theme"
        - "appearance"
  
  files:
    - name: Shared Color Profiles
      path: '%SystemRoot%\System32\spool\drivers\color'
      type: directory
      action: sync
      dynamic_state_path: "shared/files/color_profiles"
      inheritance_tags:
        - "color"
        - "display"
```

---

## `machine_specific` Section

Defines configuration overrides for specific machines or machine types.

| Key | Type | Description | Required |
|---|---|---|---|
| `machine_selectors` | Array | Criteria for selecting which machines this configuration applies to. | Yes |
| `name` | String | Descriptive name for the machine-specific configuration. | No |
| `description` | String | Description of what this machine-specific configuration manages. | No |
| `priority` | Integer | Priority level for this machine-specific configuration (1-100). | No (default: 80) |
| `merge_strategy` | String | How to merge with shared configuration: `deep_merge`, `shallow_merge`, or `replace`. | No (default: `deep_merge`) |
| `files` | Array | Machine-specific file configurations. | No |
| `registry` | Array | Machine-specific registry configurations. | No |
| `applications` | Array | Machine-specific application configurations. | No |
| `prerequisites` | Array | Machine-specific prerequisites. | No |
| `stages` | Array | Machine-specific stages. | No |

### Machine Selectors

Machine selectors determine which machines a configuration applies to:

| Key | Type | Description | Required |
|---|---|---|---|
| `type` | String | Selector type: `machine_name`, `hostname_pattern`, `environment_variable`, `registry_value`, or `script`. | Yes |
| `value` | String | The value to match against (pattern for `hostname_pattern`, variable name for `environment_variable`, etc.). | Yes |
| `operator` | String | Comparison operator: `equals`, `contains`, `matches`, `not_equals`, `greater_than`, `less_than`. | No (default: `equals`) |
| `case_sensitive` | Boolean | Whether the comparison should be case-sensitive. | No (default: `false`) |

**Example:**

```yaml
machine_specific:
  - machine_selectors:
      - type: machine_name
        value: "GAMING-RIG"
        operator: equals
      - type: hostname_pattern
        value: "GAMING-.*"
        operator: matches
    
    name: "Gaming Machine Display Settings"
    description: "High-performance display settings for gaming machines"
    priority: 90
    merge_strategy: deep_merge
    
    registry:
      - name: Gaming Display Performance
        path: 'HKCU:\Software\Microsoft\Windows\CurrentVersion\VideoSettings'
        type: key
        action: sync
        dynamic_state_path: "machine_specific/gaming/registry/video_settings.json"
        inheritance_tags:
          - "gaming"
          - "performance"
        
        # Override specific values
        override_values:
          - key_name: "EnableHDR"
            value: "1"
          - key_name: "RefreshRate"
            value: "144"
```

---

## `inheritance_rules` Section

Defines custom rules for how configuration inheritance should be applied.

| Key | Type | Description | Required |
|---|---|---|---|
| `name` | String | Descriptive name for the inheritance rule. | Yes |
| `description` | String | Description of what this rule does. | No |
| `applies_to` | Array | Which template sections this rule applies to (e.g., `["files", "registry"]`). | Yes |
| `condition` | Object | Conditions under which this rule should be applied. | No |
| `action` | String | Action to take: `merge`, `replace`, `skip`, `validate`, or `transform`. | Yes |
| `parameters` | Object | Parameters for the rule action. | No |
| `script` | String | Custom PowerShell script for complex inheritance logic. | No |

**Example:**

```yaml
inheritance_rules:
  - name: "Registry Value Merge Rule"
    description: "Merge registry values instead of replacing entire keys"
    applies_to: ["registry"]
    condition:
      inheritance_tags:
        contains: ["user_preference"]
    action: merge
    parameters:
      merge_level: "value"
      conflict_resolution: "machine_wins"
  
  - name: "File Path Transformation"
    description: "Transform file paths based on machine environment"
    applies_to: ["files"]
    condition:
      machine_selectors:
        - type: environment_variable
          value: "USERPROFILE"
          operator: contains
    action: transform
    script: |
      param($SharedPath, $MachineContext)
      
      # Transform shared paths to machine-specific paths
      if ($SharedPath -like "*%USERPROFILE%*") {
          $machinePath = $SharedPath -replace "%USERPROFILE%", $MachineContext.UserProfile
          return $machinePath
      }
      return $SharedPath
```

---

## `conditional_sections` Section

Defines template sections that are conditionally applied based on machine characteristics.

| Key | Type | Description | Required |
|---|---|---|---|
| `name` | String | Descriptive name for the conditional section. | Yes |
| `description` | String | Description of what this conditional section does. | No |
| `conditions` | Array | Array of conditions that must be met for this section to be applied. | Yes |
| `logic` | String | Logic for combining conditions: `and`, `or`, or `not`. | No (default: `and`) |
| `files` | Array | Conditional file configurations. | No |
| `registry` | Array | Conditional registry configurations. | No |
| `applications` | Array | Conditional application configurations. | No |
| `prerequisites` | Array | Conditional prerequisites. | No |
| `stages` | Array | Conditional stages. | No |

### Conditions

Conditions determine when a section should be applied:

| Key | Type | Description | Required |
|---|---|---|---|
| `type` | String | Condition type: `machine_name`, `os_version`, `hardware_check`, `software_check`, or `custom_script`. | Yes |
| `check` | String | The specific check to perform. | Yes |
| `expected_result` | String | Expected result for the condition to be true. | Yes |
| `on_failure` | String | Action to take if condition fails: `skip`, `warn`, or `fail`. | No (default: `skip`) |

**Example:**

```yaml
conditional_sections:
  - name: "Multi-Monitor Setup"
    description: "Additional settings for machines with multiple monitors"
    conditions:
      - type: hardware_check
        check: "Get-WmiObject -Class Win32_DesktopMonitor | Measure-Object | Select-Object -ExpandProperty Count"
        expected_result: "^[2-9]$|^[1-9][0-9]+$"  # 2 or more monitors
        on_failure: skip
    logic: and
    
    registry:
      - name: Multi-Monitor Display Settings
        path: 'HKCU:\Control Panel\Desktop'
        type: key
        action: sync
        dynamic_state_path: "conditional/multi_monitor/registry/desktop.json"
        
        # Additional multi-monitor specific settings
        additional_values:
          - key_name: "MultiMonitorMode"
            value: "Extended"
          - key_name: "PrimaryMonitorIndex"
            value: "0"
```

---

## Inheritance Tags

Inheritance tags provide a way to categorize and manage configuration inheritance at a granular level.

| Key | Type | Description | Required |
|---|---|---|---|
| `inheritance_tags` | Array | Tags that categorize this configuration item for inheritance purposes. | No |
| `inheritance_priority` | Integer | Priority for this specific item within its category (1-100). | No (default: 50) |
| `inheritance_policy` | String | How this item should be inherited: `merge`, `replace`, `extend`, or `skip`. | No (default: `merge`) |
| `conflict_resolution` | String | How to resolve conflicts: `machine_wins`, `shared_wins`, `prompt`, or `merge_both`. | No (default: `machine_wins`) |

**Example:**

```yaml
registry:
  - name: Display Resolution
    path: 'HKCU:\Control Panel\Desktop'
    key_name: "DesktopResolution"
    type: value
    action: sync
    dynamic_state_path: "registry/desktop_resolution.json"
    
    # Inheritance configuration
    inheritance_tags:
      - "display"
      - "resolution"
      - "user_preference"
    inheritance_priority: 80
    inheritance_policy: replace
    conflict_resolution: machine_wins
```

---

## Template Processing with Inheritance

When processing templates with inheritance, the system follows this order:

1. **Load Base Template**: Parse the template file and extract all sections
2. **Apply Shared Configuration**: Process shared sections as base configuration
3. **Evaluate Machine Selectors**: Determine which machine-specific sections apply
4. **Apply Inheritance Rules**: Execute custom inheritance rules
5. **Merge Configurations**: Combine shared and machine-specific configurations
6. **Process Conditional Sections**: Evaluate conditions and apply matching sections
7. **Validate Final Configuration**: Ensure the final configuration is valid
8. **Execute Template Operations**: Perform backup/restore operations with merged configuration

### Configuration Merge Process

The merge process follows these rules:

1. **Priority-Based Merging**: Higher priority configurations override lower priority ones
2. **Tag-Based Grouping**: Items with the same inheritance tags are grouped and merged together
3. **Conflict Resolution**: Conflicts are resolved based on the specified conflict resolution strategy
4. **Validation**: The final merged configuration is validated for consistency and completeness

---

## Example: Complete Template with Inheritance

```yaml
metadata:
  name: "Enhanced Display Settings with Inheritance"
  description: "Display settings template with shared and machine-specific configurations"
  version: "2.0"
  author: "Windows Melody Recovery"

configuration:
  inheritance_mode: merge
  machine_precedence: true
  validation_level: moderate
  fallback_strategy: use_shared

shared:
  name: "Common Display Settings"
  description: "Display settings that apply to all machines"
  priority: 60
  override_policy: merge
  
  registry:
    - name: Basic Theme Settings
      path: 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ThemeManager'
      type: key
      action: sync
      dynamic_state_path: "shared/registry/theme_manager.json"
      inheritance_tags: ["theme", "appearance"]
      inheritance_priority: 50

machine_specific:
  - machine_selectors:
      - type: machine_name
        value: "WORKSTATION-01"
        operator: equals
    
    name: "Workstation Display Settings"
    priority: 90
    merge_strategy: deep_merge
    
    registry:
      - name: Workstation Theme Override
        path: 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ThemeManager'
        type: key
        action: sync
        dynamic_state_path: "machine_specific/workstation/registry/theme_manager.json"
        inheritance_tags: ["theme", "appearance"]
        inheritance_priority: 90
        inheritance_policy: merge
        conflict_resolution: machine_wins

inheritance_rules:
  - name: "Theme Merge Rule"
    description: "Merge theme settings instead of replacing"
    applies_to: ["registry"]
    condition:
      inheritance_tags:
        contains: ["theme"]
    action: merge
    parameters:
      merge_level: "value"
      conflict_resolution: "machine_wins"

conditional_sections:
  - name: "High DPI Settings"
    description: "Settings for high DPI displays"
    conditions:
      - type: hardware_check
        check: "Get-WmiObject -Class Win32_VideoController | Where-Object { $_.CurrentHorizontalResolution -gt 1920 } | Measure-Object | Select-Object -ExpandProperty Count"
        expected_result: "^[1-9][0-9]*$"  # At least 1 high-res display
        on_failure: skip
    
    registry:
      - name: High DPI Settings
        path: 'HKCU:\Control Panel\Desktop'
        type: key
        action: sync
        dynamic_state_path: "conditional/high_dpi/registry/desktop.json"
        inheritance_tags: ["display", "dpi"]

prerequisites:
  - type: script
    name: "Windows Display System Available"
    inline_script: |
      try {
          Get-Command Get-CimInstance -ErrorAction Stop | Out-Null
          Write-Output "Display system available"
      } catch {
          Write-Output "Display system not available"
      }
    expected_output: "Display system available"
    on_missing: warn

files:
  - name: Color Profiles Directory
    path: '%SystemRoot%\System32\spool\drivers\color'
    type: directory
    action: sync
    dynamic_state_path: "files/color_profiles"
    inheritance_tags: ["color", "display"]
```

This extended schema provides comprehensive support for configuration inheritance while maintaining backward compatibility with existing templates. 