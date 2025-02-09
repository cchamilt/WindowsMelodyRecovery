# Windows 11 Desktop Setup

Try to replicate a desktop for Windows based on One Drive and other backup tools since Windows 11 appears to trash boot drives.

## Recover Windows 11

### One Drive install and setup its recovery system

### Login to office 365

### Set the Windows license

### Run the recovery.ps1 script

This script will restore any backed up settings for Windows for the specific machine as well as any saved user preferences if no backup exists.

## Install the other software

Run install.ps1

## Run the setup.ps1 script

This script will setup RDP, VPN, ssh keys, etc.

## Run the user.ps1 script

This will copy any user files from the backup to the new machine.  Including packages and home settings in WSL.

## Need to install some stuff manually

- Webull
- Interactive Brokers TWS
- Fritzing
- DipTrace

## Remove bloatware

### Remove Asus/Lenovo fake drivers, tools, etc.

### Remove mcafee, etc. AV

Run remove.ps1

## Task schedule backup

Add backup.ps1 to task schedule to backup the registry and other stuff to One Drive.

