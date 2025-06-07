# Backup Details

This document describes what each backup script captures and restores in the Windows Missing Recovery module.

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

## Gaming Platforms

### Steam Settings

`backup-steam-games.ps1`

- Steam client configuration and preferences
- Game library information and metadata
- User profiles and achievements data
- Workshop subscriptions and content
- Friends list and community settings
- Custom game categories and collections
- Steam overlay and in-game settings
- Controller configurations
- Screenshot and video settings
- Download and bandwidth preferences
- Game installation paths and library folders
- Custom skin and theme settings
- Auto-launch and startup preferences

### Epic Games Settings

`backup-epic-games.ps1`

- Epic Games Launcher configuration
- Game library and installation information
- User account preferences
- Download and installation settings
- Legendary CLI configuration (if installed)
- Game metadata and playtime tracking
- Friends and social features settings
- Store preferences and wishlist
- Parental controls and restrictions
- Cloud save synchronization settings
- Custom installation directories
- Launcher appearance and behavior settings

### GOG Galaxy Settings

`backup-gog-games.ps1`

- GOG Galaxy client configuration
- Game library and installation data
- User profile and achievements
- Integration settings for other platforms
- Download and update preferences
- Game metadata and playtime statistics
- Friends and community features
- Store and wishlist preferences
- Cloud save synchronization
- Custom game categories and tags
- Installation directories and paths
- Client appearance and behavior settings

### EA Games Settings

`backup-ea-games.ps1`

- EA App (formerly Origin) configuration
- Game library and installation information
- User account and profile settings
- Download and installation preferences
- Game metadata and playtime tracking
- Friends and social features
- Store and purchase history preferences
- Cloud save synchronization settings
- Custom installation directories
- Client appearance and behavior
- Auto-update and background download settings
- In-game overlay and screenshot settings

## Security and Access

### KeePassXC Settings

`backup-keepassxc.ps1`

- Application settings and preferences
- Custom themes and appearance
- Window layouts and interface customization
- Database locations and recent files
- Security settings and encryption preferences
- Custom icons and database styling
- Auto-type configurations and shortcuts
- Browser integration settings
- Backup and export preferences
- Plugin and extension configurations

### SSH Settings

`backup-ssh.ps1`

- SSH keys (public and private)
- Known hosts file
- SSH config files and connection settings
- Custom SSH settings and preferences
- Key permissions and security settings
- SSH agent configurations
- Port forwarding and tunnel settings
- Authentication methods and preferences

### WSL SSH Settings

`backup-wsl-ssh.ps1`

- WSL-specific SSH configurations
- SSH keys and known hosts within WSL environment
- Permissions and access controls for WSL SSH
- Cross-platform SSH key sharing settings
- WSL-specific SSH agent configurations
- Integration settings between Windows and WSL SSH

## Windows Subsystem for Linux (WSL)

### WSL Environment Backup

`backup-wsl.ps1`

- **Distribution Information**:
  - WSL version (WSL 1 or WSL 2)
  - Installed distributions list
  - Default distribution settings
  - Distribution-specific configurations

- **Package Management**:
  - APT package lists (installed, manually installed, held packages)
  - NPM global packages and configurations
  - PIP packages (user and system-wide)
  - Snap packages and configurations
  - Flatpak packages and repositories
  - Package manager configurations and sources

- **System Configuration Files**:
  - `/etc/wsl.conf` - WSL distribution configuration
  - `/etc/fstab` - File system mount configurations
  - `/etc/hosts` - Host name resolution
  - `/etc/environment` - System-wide environment variables
  - Network and DNS configurations
  - Systemd and service configurations

- **User Environment**:
  - Shell configurations (`.bashrc`, `.profile`, `.zshrc`, `.bash_profile`)
  - Custom aliases and functions
  - Environment variables and PATH modifications
  - Shell history and preferences
  - Terminal multiplexer configurations (`.tmux.conf`)
  - Editor configurations (`.vimrc`, `.nanorc`)

- **Development Tools**:
  - Git configuration (`.gitconfig`, `.gitignore_global`)
  - SSH keys and configurations (WSL-specific)
  - Development tool configurations
  - Programming language version managers (nvm, pyenv, rbenv)
  - Docker and container configurations
  - Database client configurations

- **Home Directory Selective Backup**:
  - Important dotfiles and configurations
  - Custom scripts and utilities
  - Development project metadata (excluding large repositories)
  - Personal configurations and preferences
  - Application-specific settings

### WSL Restore Features

`restore-wsl.ps1`

- Automated package installation across all package managers
- Configuration file restoration with proper Linux permissions
- Shell environment restoration and customization
- Development tool reconfiguration and setup
- Home directory restoration with selective file recovery
- Git repository validation and setup assistance
- SSH key restoration with proper permissions
- Service and daemon reconfiguration

## Dotfile Management (chezmoi)

### chezmoi Configuration Backup

`backup-chezmoi.ps1`

- **chezmoi Source Directory**:
  - Complete chezmoi source directory structure
  - Managed dotfiles and configurations
  - Template files and data
  - Encrypted secrets and sensitive configurations
  - Custom scripts and hooks
  - chezmoi configuration files

- **Git Repository Integration**:
  - Git repository information and remote URLs
  - Commit history and branch information
  - Git configuration specific to chezmoi
  - Repository access credentials (if configured)
  - Merge and conflict resolution settings

- **chezmoi Configuration**:
  - `~/.config/chezmoi/chezmoi.toml` - Main configuration
  - Template data and variables
  - Encryption settings and key management
  - Source and destination path configurations
  - Hook and script configurations
  - Platform-specific settings and conditions

### chezmoi Restore Features

`restore-chezmoi.ps1`

- chezmoi installation and setup
- Git repository cloning and configuration
- Dotfile application and synchronization
- Template processing and variable substitution
- Encrypted secret restoration
- Cross-machine configuration synchronization
- Conflict resolution and merge handling
- Custom script execution and hooks

## Windows Features

### Explorer Settings

`backup-explorer.ps1`

- File Explorer preferences and view settings
- View settings and display options
- Folder options and behavior
- Navigation pane settings and shortcuts
- Quick access locations and pinned folders
- Search settings and indexing preferences
- File operations preferences and confirmations
- Privacy settings and recent files tracking
- Thumbnail cache settings and preview options
- Context menu customizations

### Keyboard Settings

`backup-keyboard.ps1`

- Keyboard layouts and input methods
- Input methods and language settings
- Keyboard repeat delay and rate settings
- Special key assignments and shortcuts
- System-wide keyboard shortcuts
- Input language settings and switching
- Touch keyboard preferences and layouts
- Hardware keyboard settings and drivers
- Accessibility keyboard features
- Custom key mappings and macros

### Start Menu Settings

`backup-startmenu.ps1`

- Start menu layout and organization
- Pinned applications and tiles
- Folder options and grouping
- Live tile configurations and updates
- Start menu size and behavior settings
- Recently added apps list and tracking
- Most used apps list and frequency
- Jump lists and recent items
- Start menu search settings
- Taskbar integration and behavior

### Remote Desktop Settings

`backup-rdp.ps1`

- RDP connection profiles and saved connections
- Display configurations and resolution settings
- Local resource settings and redirection
- Network settings and connection options
- Authentication settings and security
- Remote audio settings and redirection
- Printer redirection and local printing
- Clipboard sharing options and security
- Drive redirection and file sharing
- Performance and bandwidth optimization

### Terminal Settings

`backup-terminal.ps1`

- Windows Terminal profiles and configurations
- Color schemes and themes
- Key bindings and shortcuts
- Font settings and typography
- Custom actions and commands
- Split pane configurations and layouts
- Tab settings and behavior
- Shell integration and startup
- Startup configurations and default profiles
- Command line arguments and parameters
- Background images and transparency
- Scrollback and history settings

### PowerShell Settings

`backup-powershell.ps1`

- PowerShell profiles (AllUsers, CurrentUser, ISE)
- Module configurations and settings
- PSReadLine settings and key bindings
- Custom functions and aliases
- Console preferences and appearance
- Execution policy settings
- Module installation paths and repositories
- Custom prompt configurations
- History settings and persistence
- Tab completion and IntelliSense settings

### WSL Global Settings

`backup-wsl-config.ps1`

- Global WSL configuration (`.wslconfig`)
- WSL 2 kernel and memory settings
- Network and DNS configurations
- File system and mount options
- Interoperability settings
- Default distribution settings
- Resource allocation and limits
- Security and isolation settings

## Cloud Storage Integration

### Multi-Cloud Backup Support

`backup-cloud-config.ps1`

- **OneDrive Integration**:
  - OneDrive Personal path detection and configuration
  - OneDrive for Business path detection and configuration
  - Sync status and health monitoring
  - Backup retention and cleanup policies
  - Selective sync and folder exclusions

- **Google Drive Integration**:
  - Google Drive path configuration
  - Sync folder monitoring and validation
  - Backup organization and folder structure
  - File versioning and conflict resolution

- **Dropbox Integration**:
  - Dropbox path configuration and validation
  - Sync status monitoring
  - Backup folder organization
  - File sharing and collaboration settings

- **Custom Cloud Storage**:
  - Generic cloud storage folder support
  - Custom path configuration and validation
  - Sync monitoring and health checks
  - Backup retention and management

## Additional Settings

### Display Settings

`backup-display.ps1`

- Monitor configurations and arrangements
- Display scaling and DPI settings
- Color profiles and calibration
- Night light settings and scheduling
- HDR settings and capabilities
- Multiple monitor configurations
- Display orientation and rotation
- Refresh rate and resolution settings

### Network Settings

`backup-network.ps1`

- Network adapter configurations and settings
- Wi-Fi profiles and saved networks
- VPN connections and configurations
- Proxy settings and authentication
- Network drive mappings and credentials
- Network discovery and sharing settings
- Firewall rules and exceptions
- Network location profiles

### Power Settings

`backup-power.ps1`

- Power plans and schemes
- Sleep settings and timers
- Battery configurations and thresholds
- Advanced power options and policies
- Display and sleep timers
- USB selective suspend settings
- Processor power management
- Hard disk power settings

### Sound Settings

`backup-sound.ps1`

- Audio device configurations and preferences
- Default playback and recording devices
- Sound schemes and system sounds
- Application volume and device preferences
- Communication settings and ducking
- Spatial audio and enhancements
- Microphone settings and levels
- Audio driver configurations

### Touchpad Settings

`backup-touchpad.ps1`

- Touchpad sensitivity and responsiveness
- Gesture configurations and customizations
- Multi-finger gestures and actions
- Scrolling preferences and behavior
- Tap settings and click behavior
- Palm rejection settings and sensitivity
- Edge swipe settings and actions
- Button configurations and assignments
- Driver-specific settings and features
- Custom gesture mappings and shortcuts

### Touchscreen Settings

`backup-touchscreen.ps1`

- Touch sensitivity and calibration
- Palm rejection settings and algorithms
- Multi-touch gestures and recognition
- Pen settings and pressure sensitivity
- Touch keyboard preferences and layouts
- Screen orientation settings and rotation
- Touch feedback options and haptics
- Edge swipe configurations and actions
- Driver-specific settings and calibration
- Custom gesture assignments and shortcuts

### VPN Settings

`backup-vpn.ps1`

- VPN profiles and connection settings
- Connection settings and protocols
- Authentication configurations and methods
- Split tunneling settings and rules
- Custom routes and network configurations
- Network protocols and encryption
- Security settings and certificates
- Auto-connect rules and triggers
- Credential storage and management
- Traffic routing rules and policies

## Windows Features Settings

`backup-windows-features.ps1`

- Installed Windows features and components
- Optional components and capabilities
- Windows capabilities and language packs
- Feature dependencies and requirements
- Installation states and configurations
- Windows subsystems (WSL, Hyper-V, etc.)
- Legacy components and compatibility
- Development features and tools
- Enterprise features and policies
- Feature update settings and preferences

## Package Managers

### Chocolatey Settings

`backup-chocolatey.ps1`

- Installed packages and versions
- Package sources and repositories
- Configuration settings and preferences
- Custom installation directories
- Package upgrade and update policies
- Security settings and verification
- Proxy and network configurations
- Feature settings and behaviors

### Scoop Settings

`backup-scoop.ps1`

- Installed packages and manifests
- Bucket configurations and sources
- Global and user-specific installations
- Custom installation directories
- Package update and cleanup policies
- Scoop configuration and preferences
- Custom buckets and repositories
- Shim and alias configurations

### Winget Settings

`backup-winget.ps1`

- Installed packages and sources
- Package source configurations
- Installation preferences and settings
- Upgrade and update policies
- Custom installation directories
- Package manifest and metadata
- Source priority and authentication
- Configuration file settings

## Notes

- **Exclusions**: All backup scripts exclude temporary files, cache data, and large binary files
- **Personal Data**: Personal data files (documents, downloads, media) are not included in backups
- **Application Dependencies**: Some settings may require applications to be installed before restoration
- **Version Compatibility**: Certain settings may be version-specific (e.g., Office 365 vs Office 2019)
- **Installation vs Configuration**: Application backups store installation information and settings, not the applications themselves
- **Permissions**: Some operations may require elevated permissions or specific user contexts
- **WSL Requirements**: WSL-related backups require WSL to be installed and configured
- **Cloud Storage**: Cloud storage integration requires respective cloud clients to be installed and configured
- **Gaming Platforms**: Game files and installations are managed by respective platforms, only settings are backed up
- **chezmoi Integration**: Requires Git and chezmoi to be installed for full functionality
- **Cross-Platform**: WSL backups are designed to work across different Linux distributions within WSL

---

*This document reflects the backup capabilities of Windows Missing Recovery v1.0.0 as of June 2025.*
