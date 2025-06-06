# TODO

## Update Private scripts

1. Review and update each backup script to follow the template while preserving its specific logic
2. Ensure consistent error handling and logging across all scripts
3. Add proper parameter validation and documentation
4. Implement proper testing hooks as shown in the template
5. Review backup scripts and improve some if missing configuration for a specific topic.
6. Review restore to ensure they match backup functionality.
7. ✅ Review setup scripts and make sure they are following templates and decoupled from all public scripts but the setup script.


- ✅ decouple initialization, setup, and common env/code from Load-Environment (removed Load-Environment dependency)
  - ✅ Install just installs (Install-Module.ps1 only copies files)
  - ✅ Initialize ONLY: a. tries to find config
                     b. reads config if available
                     c. ask if you want to reconfig or configs
                     d. asks about cloud, and multiple cloud paths
                     e. rest of config file fields optionally
                     f. ends with no errors, installs, script loading, etc. never happening
  - ✅ Setup script to try to orchestrate all setup (ask to run each script, etc.)
  - ✅ Private scripts are now loaded on-demand only when their respective public functions are called
  - ✅ Fixed OneDrive provider selection logic in Initialize function
  - ✅ Module now loads cleanly without admin requirements, errors, or unwanted script execution
  - ✅ Fixed Install-Module.ps1 to properly handle file overwriting with -Force and -CleanInstall parameters
  - ✅ Fixed BACKUP_ROOT configuration issue in Initialize-WindowsMissingRecovery function
  - ✅ Removed Load-Environment dependencies from setup-customprofiles.ps1 and fixed syntax errors


- Make all the backup/restore script lists optional config so not all the components need be backed up or restored.  Same with setup and breakout the remove tasks as scripts too
- Make a wsl diff system from a base to rsync user home

```bash
#Need something like rsync but as compressed deltas to preserve permisions
rsync -av --exclude 'work/*/repos' /home/<user>/ /mnt/c/Users/<YourUser>/OneDrive/WSL-Home/
```

- Update global packages merge and then dump merged updated package lists:

```bash
#!/bin/bash
# ~/OneDrive/WSL-Packages/sync-packages.sh

# Export package lists
mkdir -p /mnt/c/Users/<YourUser>/OneDrive/WSL-Packages
dpkg --get-selections > /mnt/c/Users/<YourUser>/OneDrive/WSL-Packages/apt-packages.txt
npm list -g --depth=0 > /mnt/c/Users/<YourUser>/OneDrive/WSL-Packages/npm-packages.txt
pip list --format=freeze > /mnt/c/Users/<YourUser>/OneDrive/WSL-Packages/pip-packages.txt

# Optional: Sync to other devices (run on target device)
# sudo dpkg --set-selections < /mnt/c/Users/<YourUser>/OneDrive/WSL-Packages/apt-packages.txt
# sudo apt-get dselect-upgrade
# xargs npm install -g < /mnt/c/Users/<YourUser>/OneDrive/WSL-Packages/npm-packages.txt
# pip install -r /mnt/c/Users/<YourUser>/OneDrive/WSL-Packages/pip-packages.txt
```

- Some /etc diff system too of at least wsl.conf
- go through ~/work/repos and push/pull and warn when files aren't checked in?
- Add chezmoi checks in root
