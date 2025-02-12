# Requires admin privileges
#Requires -RunAsAdministrator

# At the start after admin check
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path (Split-Path $scriptPath -Parent) "scripts\load-environment.ps1")

if (!(Load-Environment)) {
    Write-Host "Failed to load environment configuration" -ForegroundColor Red
    exit 1
}

try {
    Write-Host "Setting up KeePassXC..." -ForegroundColor Blue

    # Install KeePassXC if not already installed
    if (!(Get-Command keepassxc -ErrorAction SilentlyContinue)) {
        Write-Host "Installing KeePassXC..." -ForegroundColor Yellow
        winget install -e --id KeePassXC.KeePassXC
    }

    # Get database location from user
    Write-Host "`nConfigure KeePassXC database location:" -ForegroundColor Blue
    $dbPath = Read-Host "Enter the full path to your KeePass database (or press Enter to browse)"
    
    if ([string]::IsNullOrWhiteSpace($dbPath)) {
        # Open file dialog to select database
        Add-Type -AssemblyName System.Windows.Forms
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Filter = "KeePass Database (*.kdbx)|*.kdbx|All files (*.*)|*.*"
        $dialog.Title = "Select KeePass Database"
        $dialog.InitialDirectory = $env:USERPROFILE
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $dbPath = $dialog.FileName
        }
    }
    
    if (![string]::IsNullOrWhiteSpace($dbPath)) {
        # Remove quotes and create directory if it doesn't exist
        $dbPath = $dbPath.Trim('"')
        $dbDirectory = Split-Path -Parent $dbPath
        
        if (!(Test-Path $dbDirectory)) {
            try {
                New-Item -ItemType Directory -Path $dbDirectory -Force | Out-Null
            } catch {
                throw "Failed to create database directory: $_"
            }
        }

        # Save database location to environment variable
        [Environment]::SetEnvironmentVariable('KEEPASSXC_DB', $dbPath, 'User')

        # Create desktop shortcut
        $WshShell = New-Object -ComObject WScript.Shell
        $desktopPath = [System.IO.Path]::Combine($env:USERPROFILE, "Desktop", "KeePassXC.lnk")
        $Shortcut = $WshShell.CreateShortcut($desktopPath)
        $Shortcut.TargetPath = "keepassxc"
        $Shortcut.Arguments = $dbPath
        $Shortcut.Save()

        Write-Host "`nKeePassXC setup completed!" -ForegroundColor Green
        Write-Host "Database location: $dbPath" -ForegroundColor Yellow
        Write-Host "Desktop shortcut created" -ForegroundColor Yellow
    } else {
        Write-Host "No database location provided. Setup cancelled." -ForegroundColor Yellow
    }

} catch {
    Write-Host "Failed to setup KeePassXC: $_" -ForegroundColor Red
} 