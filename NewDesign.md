
# Melody Windows Configuration Manager

Recovers a desktop or laptop Windows system from the user perspective.  Compliments Windows Backup.  Not a full endpoint manager, but to provide abilities to backup/recover/share device configuration for SMEs per user utilizing simple cloud storage.  May eventually support integration with OCS, GLPi, OPSI, or even ansible.

## Features

- Automating background app/game reinstallation via package managers (e.g., winget, choco) or custom scripts.
- Backing up/restoring specific home directory files (e.g., .ssh, .bashrc) with encryption.
- Targeting %APPDATA% and %LOCALAPPDATA% for app-specific states.
- Supporting WSL dotfiles and package lists.
- Focus on cursor/AI configuration files for MCPs, etc.
- Focus on cloud deployment keys and settings
- Custom driver bundling/setting
- Eventual consistency/idempotency, manager may be run multiple times to check and set all requested settings and files.
- Check/set common (group policy emulation) to registry settings
- Tailor the bloatware removal
- Make sure Bitlocker is enabled and cloud stored
- Yaml supports wide format for paths: Windows local and then forward slash more universal URI paths all with environment substitution, ie.
  - "$env:LOCALAPPDATA\GameX\saves"
  - "file://C:/Users/$env:USER/.ssh/id_rsa"
  - "$HOME\.ssh\id_rsa"
  - "HKLM:\Software\Policies\Microsoft\Windows\System"
  - "winreg://HKLM/Software/Microsoft/..."
  - "wsl:///home/$user/.bashrc" - default wsl with wsl environment substitution
  - "wsl://WSLVM/home/$user/.bashrc" - specific wsl VM

## Applications/Games/npm/Powershell modules/etc

- Support Windows and WSL/VM environments
- Handled by custom/specific package installer automation scripting/wrapping that we call

## Configuration Engine Architecture

- Still store in cloud whatever files and configuration is requested.  Configuration in json with files in the same directory specified by the name of the bstate config.
- State configs are specified in YAML
- Backup/restore scripts convert to just a list of files or registry or other internal windows path URI settings to save.
- Yaml of 'state' structured by restore state, ie. how to get the system to the eventual state.
- Stages available for checks or scripts (both inline and referenced by path (bash,pwsh,com)) - Prereqs, Preupdate, Postupdate, Cleanup
- Files or Windows internal path URI keys outside stages will be considered what needs backed up and restored, ie. get/set by the system.
- Any files or settings may be requested stored/recovered encrypted with a manager-wide key

## Home directory design

- have a home directory specific yaml configuration, chezmoi support/url
- have a set of common home and dotfiles files to backup
- support encrypting - key,certificate,ssh files
- files should be listed under chezmoi, copy, rsync depending on how the user wants to store them
- Custom saved games and other app states by app or directory/file list
- Use symmetric passphrase encryption to decouple from TPM
