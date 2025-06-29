
# Melody Windows Configuration Manager

Recovers a desktop or laptop Windows system from the user perspective.  Compliments Windows Backup.  Not a full endpoint manager, but to provide abilities to backup/recover/share device configuration for SMEs per user utilizing simple cloud storage.  May eventually support integration with OCS, GLPi, OPSI, or even ansible.

## Applications/Games/Powershell modules/etc.

- Support Windows and WSL/VM environments
- Handled by custom/specific installer automation scripting/wrapping that we call

## Configuration Engine Architecture

- Still store in cloud whatever files and configuration is requested.  Configuration in json with files in the same directory specified by the name of the bstate config.
- State configs are specified in YAML
- Backup/restore scripts convert to just a list of files or registry or other internal windows path URI settings to save.
- Yaml of 'state' structured by restore state, ie. how to get the system to the eventual state.
- Stages available for checks or scripts (both inline and referenced by path) - Prereqs, Preupdate, Postupdate, Cleanup
- Files or Windows internal path URI outside stages will be considered what needs backed up and restored, ie. get/set by the system.
- Any files or settings may be requested stored/recovered encrypted with a manager-wide key

## Extended Features

- Special handling of home (Windows and WSL) directory files - chezmoi or rsync bundles and key,certificate,ssh file encryption
- Custom saved games and other app states by app or directory/file list
- Passkey/U2F encryption support?
- Eventual consistency/iampotency, manager may be run multiple times to check and set all requested settings and files.
- Common group policy to registry settings
- Group policy emulation