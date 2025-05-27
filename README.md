# Windows 11 Desktop Configuration

Inspired by the recent instability of Windows 11, we are trying to replicate a desktop for Windows based on One Drive and other backup tools.

The default One Drive location is `C:\Users\<username>\OneDrive\backup\shared` for common shared files.

Backup files are stored in `C:\Users\<username>\OneDrive\backup\<machine name>`

If during the recovery process the machine name directory is not found, it will use the shared folder.  Please see the LIMITS.md file for a better idea of what can be restored.

## Directory Structure

```text
.
├── backup/         # Backup operation scripts
├── restore/        # Restore operation scripts
├── setup/          # Setup scripts for applications
├── tasks/          # Scheduled task registration scripts
├── templates/      # Configuration templates
├── scripts/        # Helper scripts
├── Backup-WindowsMissingRecovery.ps1      # Main backup script
├── Restore-WindowsMissingRecovery.ps1     # Main restore script
├── Update-WindowsMissingRecovery.ps1      # Package update script
└── Install-WindowsMissingRecovery.ps1     # Installation script
```

## Install the Windows Configuration Scripts

In a PowerShell prompt with admin privileges, run the following command to install the Windows Configuration.

```powershell
Install-WindowsMissingRecovery.ps1 [-InstallPath <path>] [-NoScheduledTasks] [-NoPrompt]
```

Parameters:

- `-InstallPath`: Custom installation directory (default: `%USERPROFILE%\Scripts\WindowsMissingRecovery`)
- `-NoScheduledTasks`: Skip scheduled task registration
- `-NoPrompt`: Non-interactive installation

This will install the Windows Configuration and create a scheduled task to backup the Windows Configuration to One Drive.  It will install an update task to update win-get and chocolatey packages to the latest version.

## Features

- Automatic backup of Windows settings
- Detailed list of backed up settings can be found in [BACKUP_DETAILS.md](docs/BACKUP_DETAILS.md)
- System updates management
- Browser profile backup
- KeePassXC configuration
- OneNote settings and templates
- Outlook configuration (excluding PST files)
- Word settings and templates
- Excel settings and macros
- Visio settings and stencils
- Network and printer settings
- And more...

## Post-Installation

1. Restart PowerShell
2. Configure backup email notifications (optional):

## Recover Windows 11

If the machine needs recovery, run the following command to restore the Windows Configuration from One Drive.  (We recommend verifying the user has set the Windows license and has setup one drive to sync the backup folder before running this script.)

With admin privileges, run the following command to restore the Windows Configuration from One Drive.

```powershell
Restore-WindowsMissingRecovery.ps1
```

This will restore the Windows Configuration from One Drive.  If the machine name directory is not found for individual restore scripts, it will use the shared folder.

## Package Updates through Windows Configuration

With admin privileges, run the following command to update the Windows Configuration.

```powershell
Update-WindowsMissingRecovery.ps1
```

This will update applications and powershell packages through the package managers supported including inside WSL distributions.

## Backup the Windows Configuration

With admin privileges, run the following command to backup the Windows Configuration to One Drive.

```powershell
Backup-WindowsMissingRecovery.ps1
```

This will backup the Windows Configuration to One Drive.

## Convert to Win-get

With admin privileges, run the following command to search for all the packages installed and convert them to win-get packages if possible.

```powershell
Convert-ToWinGet.ps1
```

## Example backup directory structure on One Drive

```text
C:\Users\<username>\OneDrive\backup\
├── LAPTOP-XYZ123\              # Machine-specific backup directory
│   ├── Applications\           # Installed apps and package manager configs
│   ├── Browsers\              # Browser profiles and settings
│   │   ├── Chrome\
│   │   ├── Edge\
│   │   └── Firefox\
│   ├── Excel\                 # Excel settings and templates
│   ├── KeePassXC\             # KeePassXC configurations
│   ├── Network\               # Network and VPN settings
│   ├── OneNote\               # OneNote settings
│   ├── Outlook\               # Outlook settings (no PST files)
│   ├── PowerShell\            # PowerShell profiles and modules
│   ├── SSH\                   # SSH keys and configs
│   ├── System\                # Windows system settings
│   ├── Terminal\              # Windows Terminal settings
│   ├── Visio\                 # Visio settings and stencils
│   ├── Word\                  # Word settings and templates
│   └── WSL\                   # WSL configurations
│
└── shared\                    # Shared settings across machines
    ├── Applications\          # Common application settings
    ├── Browsers\              # Shared browser bookmarks/settings
    ├── SSH\                   # Shared SSH configurations
    ├── Templates\             # Common document templates
    └── WSL\                   # Common WSL configurations
```
