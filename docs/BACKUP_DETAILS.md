# Backup Details

This document describes what each backup template captures and restores in the Windows Melody Recovery module.

## Template-Based System

Windows Melody Recovery uses a modern template-based backup and restore system. Each component has a corresponding YAML template in `Templates/System/` that defines:

- **Registry Components**: Windows registry keys and values
- **File Components**: Configuration files and user data directories  
- **Application Components**: Installed software and application-specific configurations

Templates are executed through the `Invoke-WmrTemplate` function with automatic prerequisite checking, error handling, and state management.

## System Configuration Templates

### System Settings Template
**Template**: `system-settings.yaml`

- System-wide Windows registry settings
- Performance and memory management
- Environment variables and system paths
- Control Panel configurations
- UAC and security policies
- Windows Update settings
- System file associations
- System-level user interface settings

### Power Settings Template
**Template**: `power.yaml`

- Power plans and schemes (High Performance, Balanced, Power Saver)
- Advanced power settings per plan
- Battery optimization settings
- Display and sleep timeouts
- USB power management
- Processor power management
- Hard disk power settings
- Wireless adapter power policies

### Display Settings Template
**Template**: `display.yaml`

- Monitor configuration and arrangements
- Display scaling and DPI settings
- Color profiles and calibration
- Night light and blue light settings
- Multiple monitor setups
- Graphics driver settings
- Custom display modes and refresh rates
- HDR and advanced display features

### Windows Features Template
**Template**: `windows-features.yaml`

- Windows optional features state
- System capabilities and packages
- Windows Update installed features
- DISM feature information
- AppX package inventory
- System components status

## Hardware and Input Templates

### Sound Settings Template
**Template**: `sound.yaml`

- Audio devices and endpoints configuration
- Volume mixer settings per application
- Sound schemes and system sounds
- Audio driver settings
- Spatial audio and enhancements
- Recording device preferences
- Communication device settings
- Audio format and quality preferences

### Keyboard Settings Template
**Template**: `keyboard.yaml`

- Keyboard layout and input languages
- Key repeat rates and delays
- Accessibility features (Sticky Keys, Filter Keys)
- Input method preferences
- Custom key mappings
- Multilingual typing settings
- Text input and IME settings

### Mouse Settings Template
**Template**: `mouse.yaml`

- Mouse pointer speed and acceleration
- Button configuration and assignments
- Wheel scrolling behavior
- Pointer appearance and themes
- Double-click timing
- Mouse trails and visibility
- Left/right handed configuration
- Gaming mouse specific settings

### Touchpad Settings Template
**Template**: `touchpad.yaml`

- Precision touchpad configuration
- Gesture settings and customizations
- Palm rejection settings
- Two-finger scrolling preferences
- Tap to click and pressure sensitivity
- Multi-finger gesture assignments
- Edge swipe actions
- Vendor-specific touchpad features

### Touchscreen Settings Template
**Template**: `touchscreen.yaml`

- Touch input calibration and sensitivity
- Pen and ink settings for stylus input
- Touch keyboard and handwriting options
- Gesture recognition settings
- Palm rejection for touch input
- Tablet mode configurations
- Touch feedback and visual cues

### Printer Settings Template
**Template**: `printer.yaml`

- Installed printers and print queues
- Default printer settings
- Print server configurations
- Driver settings and preferences
- Paper sizes and print quality settings
- Network printer discovery and connections
- Print spooler configuration

## Network and Remote Access Templates

### Network Settings Template
**Template**: `network.yaml`

- Network adapter configurations
- WiFi profiles and saved networks
- Ethernet settings and protocols
- Network location profiles (Private/Public)
- Proxy settings and configurations
- VPN client settings
- Network discovery and sharing settings
- Advanced TCP/IP settings

### VPN Settings Template
**Template**: `vpn.yaml`

- Built-in Windows VPN connections
- Network credentials and authentication
- VPN client configurations
- IPSec and L2TP settings
- OpenVPN configurations
- Azure VPN and Cisco VPN settings
- VPN adapter settings
- Connection profiles and certificates

### SSH Settings Template
**Template**: `ssh.yaml`

- OpenSSH client and server configuration
- SSH key pairs and authentication
- SSH Agent service settings
- Known hosts and authorized keys
- SSH configuration files
- Custom SSH client settings
- Port forwarding configurations

### Remote Desktop Settings Template
**Template**: `rdp.yaml`

- Remote Desktop Protocol settings
- RDP user permissions and access
- Network Level Authentication settings
- Session configuration and timeouts
- Display and performance settings
- Audio and clipboard redirection
- Drive and printer redirection
- Security and encryption settings

## User Interface Templates

### Terminal Settings Template
**Template**: `terminal.yaml`

- Windows Terminal configuration and profiles
- PowerShell console settings
- Command Prompt customizations
- Console font and color schemes
- Keyboard shortcuts and key bindings
- Startup and default terminal settings
- Tab and pane configurations
- Background images and transparency

### Explorer Settings Template
**Template**: `explorer.yaml`

- File Explorer view preferences
- Folder options and display settings
- Navigation pane customizations
- Search settings and indexing
- File type associations
- Context menu customizations
- Taskbar and system tray settings

### Start Menu Settings Template
**Template**: `startmenu.yaml`

- Start menu layout and organization
- Pinned applications and tiles
- Start menu size and behavior
- Taskbar settings and grouping
- System tray icon preferences
- Jump lists and recent items
- Search settings and results
- Notification and action center settings

### Default Apps Settings Template
**Template**: `defaultapps.yaml`

- Default application associations by file type
- Protocol handler assignments
- Default web browser and email client
- Media player defaults
- Image and document viewer defaults
- System-wide application preferences
- File extension associations

## Development and Tools Templates

### PowerShell Settings Template
**Template**: `powershell.yaml`

- PowerShell execution policies
- Module installation and configuration
- PowerShell profiles for different hosts
- Custom functions and aliases
- PowerShell provider settings
- Remoting and security settings
- Package provider configurations
- Development environment settings

### WSL Settings Template
**Template**: `wsl.yaml`

- WSL distribution information and status
- Package manager inventories (apt, yum, pacman, etc.)
- Configuration file discovery (/etc/wsl.conf, ~/.bashrc, ~/.gitconfig)
- chezmoi dotfile management status
- WSL system and user registry settings
- Linux environment configurations
- Cross-platform development setup

## Application Templates

### Applications Template
**Template**: `applications.yaml`

- Installed application inventory (winget, chocolatey, scoop)
- Package manager configurations and sources
- Application installation paths and versions
- System-wide application settings
- Windows Store app configurations
- Application startup and service settings

### Browser Settings Template
**Template**: `browsers.yaml`

- Browser profiles for Chrome, Edge, Firefox, Brave, Opera, Vivaldi
- Bookmarks and favorites organization
- Browser preferences and customizations
- Extension and add-on configurations
- Custom search engines and shortcuts
- Privacy and security settings
- Sync and account settings

### Game Managers Template
**Template**: `gamemanagers.yaml`

- Steam client configuration and library
- Epic Games Launcher settings and library
- GOG Galaxy configuration and games
- EA App/Origin settings and library
- Battle.net configuration
- Game installation paths and metadata
- Gaming platform integrations and social features

## Productivity Software Templates

### OneNote Settings Template
**Template**: `onenote.yaml`

- OneNote application preferences and settings
- Notebook organization and locations
- Custom templates and page layouts
- Synchronization and backup settings
- User interface customizations
- Search and indexing preferences
- Integration settings with Office suite

### Outlook Settings Template
**Template**: `outlook.yaml`

- Email account configurations (excluding credentials)
- Outlook profiles and data files
- Email signatures and templates
- Rules and automatic processing
- Calendar and task settings
- Contact management preferences
- Security and privacy settings

### Word Settings Template
**Template**: `word.yaml`

- Document templates and building blocks
- AutoCorrect and AutoText entries
- Custom styles and formatting
- Ribbon and toolbar customizations
- User preferences and view settings
- File locations and recent documents
- Proofing and language settings

### Excel Settings Template
**Template**: `excel.yaml`

- Workbook templates and custom formats
- Add-ins and macro configurations
- Custom functions and formulas
- Chart and pivot table defaults
- Data connection settings
- Calculation and performance options
- Custom ribbon and toolbar layouts

### Visio Settings Template
**Template**: `visio.yaml`

- Drawing templates and stencils
- Shape and connector preferences
- Page setup and print settings
- Custom themes and color schemes
- Add-ins and macro configurations
- File format and export settings
- User interface customizations

## Security Templates

### KeePassXC Settings Template
**Template**: `keepassxc.yaml`

- KeePassXC application configuration
- Database connection settings
- Security and encryption preferences
- User interface and workflow settings
- Browser integration configuration
- Auto-type and hotkey settings
- Backup and synchronization settings

## Template Configuration

All templates are configured through the `Config/scripts-config.json` file which defines:

- **Enabled Templates**: Which templates are active for backup/restore operations
- **Categories**: Logical grouping of related templates
- **Descriptions**: User-friendly descriptions of what each template captures
- **Requirements**: Whether a template is required or optional for system recovery

Templates can be executed individually or as part of bulk operations through the Windows Melody Recovery PowerShell module.

## Template Structure

Each template includes:

- **Metadata**: Name, description, version, and categorization
- **Prerequisites**: Conditions that must be met before execution
- **Registry Components**: Windows registry keys and values to backup/restore
- **File Components**: Files and directories to capture
- **Application Components**: Software discovery and configuration management

For detailed information about template structure and development, see the `TEMPLATE_SCHEMA.md` documentation. 