# TODO

📋 **See [Comprehensive Testing Plan](docs/TESTING_PLAN.md) for structured approach to all testing issues**

❌ Broken Test Suites:
Installation - ❌ Infinite loop (hangs indefinitely)
WSL - ❌ Fails tests and shows repetitive script loading messages (0% success rate)
Restore - ❌ Completes but fails tests (0% success rate)
All - ❌ Infinite loop (because it includes Installation)

🎯 **Current Focus**: Phase 1 - Emergency Stabilization (Critical test fixes)

## Features

- Support for shared configurations and override logic for host vs default shared
- Test/fix as most backup templates are failing
- Restore logic complete for templates?
- Split some larger templates into optional subfeatures or split scripts out to keep file sizes under ~500 lines
- Identify and prune some of the excessive backup states that are transient, obvious, or too hardware configuration specific
- Discovering unmanaged packages, document them so that a user can manually store their installation files
- Determine to uninstall/keep apps not on restore list
- Refactor setup scripts and test for them in docker
- Add setup for bitlocker and windows backup to make sure they are up and working
- Create export/import or edit calls for a simplified user editable app/game lists
- Manage version pinning
- Implement restore procedure for the complex templates
- Add all packaging and module updates as tasks
- Clean up verb practices and naming for gallery release
- test password prompts for encryption passkey
- workflow for installing backup tasks with encryption
- optional filtered/limited user directory rsync in windows and wsl to zip or at least a cloud home backup directory
- Fix printer, touchpad, touchscreen, and visio application discovery json parsing
- windows-features need admin privs
- store windows key information - account attached and ideally actual key.

## Testing

- Mocks
  - Make sure that various cloud drives are mocked and we test their code paths in configuration and use
  - More windows like mock app and home directory trees
  - Tests for games and winget/chocolatey backup mocks and restore from json
- WSL backup/restore
  - Emulate both ssh and wsl cli calls into Linux
  - Make sure that chezmoi works in wsl
  - Test system, npm, python, etc. packaging backup/restore
- Registry calls
  - Make sure registry calls in scripts are same as mocks
  - Make sure we gracefully handle missing registry to backup
  - Make sure we gracefully handle restoration in empty paths
- General restoration
  - Make sure we handle system restoration and shared configuration blended
  - Make sure the local or remote chezmoi repo works
  - Secure key/file encryption test
- Review mocks and container/emulation exception logic to see what can be unmocked and fully tested in test framework
- Merge all testing - setup ci in github to match new unit and integration in docker, push to main
