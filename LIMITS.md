# Limits of our Windows 11 Setup scripts

## This might conflict with intune policies

## This assumes OneDrive is already setup with Windows Backup

## Windows elements that are NOT being backed up to OneDrive:

1. System Files:
   - Windows system files
   - Program Files
   - Installed program binaries
   - System32 directory
2. User Data:
   - Documents, Pictures, Downloads folders (assuming these are already synced by OneDrive)
   - Saved passwords
   - Email files/PST files
   - App data and most application settings
3. System State:
   - Registry hives
   - System state backup
   - Shadow copies
   - System restore points
4. Security:
   - Windows credentials
   - Certificates
   - BitLocker keys
   - EFS certificates
5. Hardware:
   - Device drivers
   - Printer settings
   - Hardware configurations
