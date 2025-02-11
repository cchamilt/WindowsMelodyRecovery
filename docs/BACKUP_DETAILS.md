# Backup Details

This document describes what each backup script captures and restores.

## System Settings
`backup-system-settings.ps1`
- System-wide Windows settings
- Performance and memory settings
- Environment variables
- Power schemes and settings
- Time and region settings
- System restore points
- Page file configuration
- Remote settings
- System security settings
- Printer configurations
- Network profiles and adapters
- Scheduled tasks
- Mapped network drives

## Applications
`backup-applications.ps1`
- Installed applications list (winget, chocolatey, scoop)
- Package manager configurations
- Application-specific settings
- Installation sources and versions
- Custom installation paths

## Default Applications
`backup-defaultapps.ps1`
- Default browser settings
- Default email client
- Default media players
- File type associations
- Protocol handlers
- App defaults by file type
- Default apps by file extension
- System-wide default applications

## Browser Settings
`backup-browsers.ps1`
- Browser profiles for Chrome, Edge, Firefox, Brave, and Vivaldi
- Bookmarks and favorites
- Browser preferences and settings
- Extensions list
- Custom search engines
- Saved form data (excluding passwords)
- Browser themes and customizations

## Office Applications

### OneNote Settings
`backup-onenote.ps1`
- Application settings and preferences
- Custom templates
- Quick access locations
- Recent files list
- Notebook list and locations
- Custom dictionaries
- User interface customizations

### Outlook Settings
`backup-outlook.ps1`
- Account settings and profiles (excluding PST files)
- View preferences and customizations
- Signatures
- Templates
- AutoCorrect settings
- Rules and alerts
- Custom dictionaries
- Security settings

### Word Settings
`backup-word.ps1`
- Custom templates
- AutoCorrect settings
- Custom dictionaries
- Building blocks (reusable content)
- Custom styles
- Ribbon customizations
- Recent files and locations
- User preferences and settings

### Excel Settings
`backup-excel.ps1`
- Custom templates and workbooks
- Add-ins
- AutoCorrect settings
- Custom ribbons and toolbars
- Personal macro workbook (PERSONAL.XLSB)
- Custom views and workspaces
- Recent files and locations
- User preferences and settings

### Visio Settings
`backup-visio.ps1`
- Custom templates and stencils
- Add-ins
- Custom themes
- Workspace settings
- Custom macros
- Drawing settings
- Recent files and locations
- User preferences and settings

## Security and Access

### KeePassXC Settings
`backup-keepassxc.ps1`
- Application settings
- Custom themes
- Window layouts
- Database locations
- Security settings
- Custom icons
- Recent databases list

### SSH Settings
`backup-ssh.ps1`
- SSH keys
- Known hosts
- SSH config files
- Custom SSH settings

### WSL SSH Settings
`backup-wsl-ssh.ps1`
- WSL-specific SSH configurations
- Keys and known hosts within WSL
- Permissions and access controls

## Windows Features

### Explorer Settings
`backup-explorer.ps1`
- File Explorer preferences
- View settings and options
- Folder options
- Navigation pane settings
- Quick access locations
- Search settings
- File operations preferences
- Privacy settings
- Thumbnail cache settings

### Keyboard Settings
`backup-keyboard.ps1`
- Keyboard layouts
- Input methods
- Keyboard repeat delay and rate
- Special key assignments
- Keyboard shortcuts
- Input language settings
- Touch keyboard preferences
- Hardware keyboard settings

### Start Menu Settings
`backup-startmenu.ps1`
- Start menu layout
- Pinned applications
- Folder options
- Live tile configurations
- Start menu size and behavior
- Recently added apps list
- Most used apps list
- Jump lists

### Remote Desktop Settings
`backup-rdp.ps1`
- RDP connection profiles
- Display configurations
- Local resource settings
- Network settings
- Authentication settings
- Remote audio settings
- Printer redirection
- Clipboard sharing options

### Terminal Settings
`backup-terminal.ps1`
- Windows Terminal profiles
- Color schemes
- Key bindings
- Font settings
- Custom actions
- Split pane configurations
- Tab settings
- Shell integration
- Startup configurations
- Command line arguments

### PowerShell Settings
`backup-powershell.ps1`
- PowerShell profiles
- Module configurations
- PSReadLine settings
- Custom scripts
- Console preferences

### WSL Settings
`backup-wsl.ps1`
- WSL distribution configurations
- Network settings
- Mount points
- Default user settings
- Global WSL configurations

## Additional Settings

### Display Settings
`backup-display.ps1`
- Monitor configurations
- Display scaling
- Color profiles
- Night light settings
- HDR settings

### Network Settings
`backup-network.ps1`
- Network adapter configurations
- Wi-Fi profiles
- VPN connections
- Proxy settings
- Network drive mappings

### Power Settings
`backup-power.ps1`
- Power plans
- Sleep settings
- Battery configurations
- Advanced power options
- Display and sleep timers

### Sound Settings
`backup-sound.ps1`
- Audio device configurations
- Default devices
- Sound schemes
- App volume settings
- Communication settings

### Touchpad Settings
`backup-touchpad.ps1`
- Touchpad sensitivity
- Gesture configurations
- Multi-finger gestures
- Scrolling preferences
- Tap settings
- Palm rejection settings
- Edge swipe settings
- Button configurations
- Driver-specific settings
- Custom gesture mappings

### Touchscreen Settings
`backup-touchscreen.ps1`
- Touch sensitivity
- Palm rejection settings
- Multi-touch gestures
- Pen settings and calibration
- Touch keyboard preferences
- Screen orientation settings
- Touch feedback options
- Edge swipe configurations
- Driver-specific settings
- Custom gesture assignments

### VPN Settings
`backup-vpn.ps1`
- VPN profiles
- Connection settings
- Authentication configurations
- Split tunneling settings
- Custom routes
- Network protocols
- Security settings
- Auto-connect rules
- Credential storage
- Traffic routing rules

## Windows Features Settings
`backup-windows-features.ps1`
- Installed Windows features
- Optional components
- Windows capabilities
- Feature dependencies
- Installation states
- Windows subsystems
- Legacy components
- Development features

## Notes
- All backup scripts exclude temporary files and cache data
- Personal data files (documents, downloads, etc.) are not included
- Some settings may require application restart to take effect after restore
- Certain settings may be version-specific (e.g., Office 365 vs Office 2019)
- Application backups only store installation information, not the applications themselves
- Some applications may need to be installed before their settings can be restored