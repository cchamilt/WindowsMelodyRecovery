# TUI Screenshot Capture Guide

## Overview

This guide provides instructions for capturing high-quality screenshots of the Windows Melody Recovery TUI wizard for documentation purposes.

## Prerequisites

1. **Windows Terminal** or **PowerShell 7+** with good terminal emulator
2. **Microsoft.PowerShell.ConsoleGuiTools** module installed
3. **Windows Melody Recovery** module properly installed
4. **Screenshot tool** (Windows Snipping Tool, Greenshot, or similar)

## Setup for Best Screenshot Quality

### 1. Terminal Configuration

**Windows Terminal (Recommended):**
```json
{
    "profiles": {
        "defaults": {
            "font": {
                "face": "Cascadia Code",
                "size": 12
            },
            "colorScheme": "Campbell Powershell"
        }
    }
}
```

**PowerShell Console:**
- Right-click title bar → Properties
- Font: Consolas, size 12-14
- Screen Buffer Size: Width 120, Height 9999
- Window Size: Width 120, Height 30

### 2. Terminal Window Sizing

Set terminal to optimal size for screenshots:
```powershell
# Set console window size (PowerShell 5.1/Windows PowerShell)
$Host.UI.RawUI.WindowSize = New-Object System.Management.Automation.Host.Size(120, 30)

# For Windows Terminal, use Ctrl+Shift+Plus/Minus to adjust
```

### 3. Clean Environment

```powershell
# Clear screen before launching
Clear-Host

# Ensure module is loaded
Import-Module WindowsMelodyRecovery -Force

# Launch TUI for screenshot
Initialize-WindowsMelodyRecovery
```

## Screenshot Capture Process

### 1. Main TUI Interface

**Target View:** Components tab with tree expanded
**Steps:**
1. Launch TUI: `Initialize-WindowsMelodyRecovery`
2. Navigate to Components tab
3. Expand 2-3 category nodes to show structure
4. Select an item to show description in content pane
5. Capture screenshot

**Key Elements to Include:**
- Menu bar with File and Actions menus
- Three tabs (Components, Initialization, Status)
- TreeView with categorized items and checkboxes
- Content pane showing selected item description
- Status bar at bottom

### 2. Initialization Wizard Tab

**Target View:** Initialization tab with form fields
**Steps:**
1. Click on "Initialization" tab
2. Fill in sample data:
   - Backup Root: `C:\Backups\WindowsMelodyRecovery`
   - Machine Name: `DEMO-PC`
   - Cloud Provider: `OneDrive`
   - Email: `user@example.com`
3. Show Auto-Detect and Browse buttons
4. Capture screenshot

### 3. Status Tab

**Target View:** Status tab showing module information
**Steps:**
1. Click on "Status" tab
2. Ensure status shows initialized state
3. Capture screenshot showing system information

## Screenshot Tools and Settings

### Windows Snipping Tool
- Use "Rectangular Snip" mode
- Capture just the terminal window
- Save as PNG with high quality

### Greenshot (Recommended)
- Settings → Output → PNG quality: 100%
- Use region capture (Ctrl+Shift+Print Screen)
- Include slight border around terminal

### PowerToys Screen Ruler
- Useful for consistent sizing
- Measure terminal dimensions before capture

## Post-Processing

### 1. Image Optimization
- **Format:** PNG (for crisp text)
- **Resolution:** Keep original (no scaling)
- **Compression:** Minimal (preserve text clarity)

### 2. Annotations (Optional)
- Add subtle arrows pointing to key features
- Use consistent color scheme (blue/green)
- Keep annotations minimal and professional

### 3. File Naming
- `tui-wizard.png` - Main interface
- `tui-initialization.png` - Initialization tab
- `tui-status.png` - Status tab

## Example Screenshot Commands

```powershell
# Complete setup for screenshot
Clear-Host
Import-Module WindowsMelodyRecovery -Force
Initialize-WindowsMelodyRecovery

# After TUI launches:
# 1. Navigate to desired tab
# 2. Expand relevant sections
# 3. Fill in sample data (if initialization tab)
# 4. Take screenshot
# 5. Press Ctrl+Q to quit TUI
```

## Tips for High-Quality Screenshots

1. **Consistent Lighting:** Use consistent desktop background
2. **Terminal Focus:** Ensure terminal has focus (active window)
3. **Stable Content:** Don't capture during animations or transitions
4. **Representative Data:** Use realistic but generic sample data
5. **Multiple Angles:** Capture different tabs/states for comprehensive documentation

## File Locations

Save screenshots to:
- `docs/images/tui-wizard.png` - Main interface
- `docs/images/tui-initialization.png` - Initialization wizard
- `docs/images/tui-status.png` - Status view

## Markdown Integration

Reference in documentation:
```markdown
![TUI Configuration Wizard](docs/images/tui-wizard.png)
*Interactive TUI Configuration Wizard*
```

## Troubleshooting

**TUI doesn't launch:**
- Check `Microsoft.PowerShell.ConsoleGuiTools` is installed
- Verify PowerShell version (7.2+)
- Try `Import-Module Microsoft.PowerShell.ConsoleGuiTools -Force`

**Poor text quality:**
- Increase terminal font size
- Use PNG format (not JPEG)
- Avoid scaling/resizing after capture

**Layout issues:**
- Ensure terminal window is wide enough (120+ characters)
- Check terminal height (30+ lines)
- Verify TUI renders correctly before screenshot
