# Windows 11 Desktop Configuration

Inspired by the recent instability of Windows 11, we are trying to replicate a desktop for Windows based on One Drive and other backup tools.

The default One Drive location is "C:\Users\<username>\OneDrive\backup\shared" for common shared files.

Backup files are stored in "C:\Users\<username>\OneDrive\backup\<machine name>"

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
├── Backup-WindowsConfig.ps1      # Main backup script
├── Restore-WindowsConfig.ps1     # Main restore script
├── Update-WindowsConfig.ps1      # System update script
└── Install-WindowsConfig.ps1     # Installation script
```

## Install the Windows Configuration Scripts

In a PowerShell prompt with admin privileges, run the following command to install the Windows Configuration.

```powershell
Install-WindowsConfig.ps1 [-InstallPath <path>] [-NoScheduledTasks] [-NoPrompt]
```

Parameters:
- `-InstallPath`: Custom installation directory (default: `%USERPROFILE%\Scripts\WindowsConfig`)
- `-NoScheduledTasks`: Skip scheduled task registration
- `-NoPrompt`: Non-interactive installation

This will install the Windows Configuration and create a scheduled task to backup the Windows Configuration to One Drive.  It will install an update task to update win-get and chocolatey packages to the latest version.

## Features

- Automatic backup of Windows settings
- System updates management
- Browser profile backup
- KeePassXC configuration
- Network and printer settings
- And more...

## Post-Installation

1. Restart PowerShell
2. Configure backup email notifications (optional):

## Recover Windows 11

If the machine needs recovery, run the following command to restore the Windows Configuration from One Drive.  (We recommend verifying the user has set the Windows license and has setup one drive to sync the backup folder before running this script.)

With admin privileges, run the following command to restore the Windows Configuration from One Drive.

```powershell
Restore-WindowsConfig.ps1
```

This will restore the Windows Configuration from One Drive.  If the machine name directory is not found for individual restore scripts, it will use the shared folder.

## Update the Windows Configuration

With admin privileges, run the following command to update the Windows Configuration.

```powershell
Update-WindowsConfig.ps1
```

This will update the Windows Configuration to the latest version.

## Backup the Windows Configuration

With admin privileges, run the following command to backup the Windows Configuration to One Drive.

```powershell
Backup-WindowsConfig.ps1
```

This will backup the Windows Configuration to One Drive.

## Convert to Win-get

With admin privileges, run the following command to search for all the packages installed and convert them to win-get packages if possible.

```powershell
Convert-ToWinGet.ps1
```
