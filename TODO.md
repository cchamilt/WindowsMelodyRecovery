# TODO

📋 **See [Comprehensive Testing Plan](docs/TESTING_PLAN.md) for structured approach to all testing issues**

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
