# Windows 11 Desktop Setup

Try to replicate a desktop for Windows based on One Drive and other backup tools since Windows 11 appears to trash boot drives.

The default One Drive location is "C:\Users\<username>\OneDrive - Fyber Labs\PCbackup\shared" for common shared files.

Backup files are stored in "C:\Users\<username>\OneDrive - Fyber Labs\PCbackup\<machine name>"

If during the recovery process the machine name directory is not found, it will use the shared folder.

## Recover Windows 11

### One Drive install and setup its recovery system

### Login to office 365

### Set the Windows license

### Run the restore.ps1 script

This script will restore any backed up settings for Windows for the specific machine as well as any saved user preferences if no backup exists.

## Install the other software

Run install.ps1

```powershell
install.ps1
```

## Run the setup.ps1 script

This script will setup RDP, VPN, ssh keys, etc.

## Run the user.ps1 script

```powershell
user.ps1
```

This will copy any user files from the backup to the new machine.  Including packages and home settings in WSL.

## Need to install some stuff manually

- Webull
- Interactive Brokers TWS
- Fritzing
- DipTrace

## Remove bloatware

### Remove Asus/Lenovo fake drivers, tools, etc.

### Remove mcafee, etc. AV

```powershell
remove.ps1
```

## Task schedule backup

Add backup.ps1 to task schedule to backup the registry and other stuff to One Drive.

```powershell
register-backup-task.ps1
```



# Windows Configuration Scripts

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

## Installation

### Quick Install

1. Open PowerShell as Administrator
2. Navigate to the script directory
3. Run: `.\install.ps1`

### Advanced Installation

```powershell
.\install.ps1 [-InstallPath <path>] [-NoScheduledTasks] [-NoPrompt]
```

Parameters:
- `-InstallPath`: Custom installation directory (default: `%USERPROFILE%\Scripts\WindowsConfig`)
- `-NoScheduledTasks`: Skip scheduled task registration
- `-NoPrompt`: Non-interactive installation

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

```powershell
$env:BACKUP_EMAIL_FROM = "your-email@domain.com"
$env:BACKUP_EMAIL_TO = "your-email@domain.com"
$env:BACKUP_EMAIL_PASSWORD = "your-app-password"
```

## Usage

- Manual backup: `Backup-WindowsConfig`
- Manual restore: `Restore-WindowsConfig`
- System update: `Update-WindowsConfig`
- Installation: `Install-WindowsConfig`
