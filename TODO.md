# TODO

## Testing

We need a new testing plan and strategy to pass CI/CD.

Should review the original plan and strategy in docs.  Make sure that our unit, fileop, integration, and e2e tests meet them.  Make sure that all destructive/write operations in windows are safe/blocked for local dev and optionally allowed in CI/CD.

Test Environment Fragility: Fixing tests in one suite breaks others
Cross-Suite Interference: Environment isolation problems, mock data conflicts, path resolution inconsistencies
Infrastructure Brittleness: Dependency chain failures, environment variable conflicts, mock system overlap - need more separation of testing code paths from Windows and mocking in Docker.

Squash more PSScriptAnalyzer warnings in CI pipeline.

📋 **See [Comprehensive Testing Plan](docs/TESTING_PLAN.md) for structured approach to all testing issues**

## User Interface

Add a curses based TUI for initialization and configuring.  Allow selection of what templates/Windows components/features (and their options) are backed up regularly or recovered (and recovery exists).  Have its layout and association parallel Windows setup/features lists.  Allow it to update/search for recovery directories and pick from shared/specific system configuration.  Show status and timing of tasks like backup and regular package updating.  Have it also check for updates for itself at startup and reload its module on installation.  Make a systray badge optional to launch the TUI.

- Add tabs or sub-menus for initialization (e.g., a wizard to set backup roots and cloud providers).
- Integrate status views (e.g., last backup time from logs).
- Add update checking (e.g., query GitHub for module updates).
- Implement an optional systray icon (using System.Windows.Forms.NotifyIcon for Windows-specific launching).
- Handle restore/setup categories similarly in the tree (currently focused on backup for simplicity).
- Test and refine UX (e.g., better error handling if config loading fails).

## Features

- Support for shared configurations and override logic for host vs default shared
- Discovering unmanaged packages, document them so that a user can manually store their installation files
- Determine to uninstall/keep apps not on restore list
- Refactor setup scripts and test for them in docker
- Create export/import or edit calls for a simplified user editable app/game lists
- Manage version pinning
- Implement restore procedure for the complex templates
- Add all packaging -winget,choco,npm,etc. and powershell module updates as scheduled tasks
- Clean up verb practices and naming for gallery release
- optional filtered/limited user directory rsync in windows and wsl to zip or at least a cloud home backup directory
- store windows key information - account attached and ideally actual key.
- Determine a recovery policy similar to Windows - 90 days of weekly backups, cloud store in git or in some form of deltas.
- Update documentation and workflow - install, initialize, capture state, remove bloat, optimize/recommendations, capture new state, install maintenance/backup tasks
- Procedural recovery - ie. make sure backup is recovered, remove bloatware, install critical apps, recover configuration, setup wsl, setup dev/env/languages, install remaining apps, games, etc.
- Certificate storage options like keyvault and local file encryption
- In addition to cloud file services - support network drive backup and Azure Blob storage
- server features - services, server features, iis configuration, files/directories
- document and support administrative privelege management with Windows' new sudo inline option https://learn.microsoft.com/en-us/windows/advanced-settings/sudo/
- Output system backup into packer build compatible HCL formatted files.
