# Requires admin privileges
#Requires -RunAsAdministrator

# At the start after admin check
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path (Split-Path $scriptPath -Parent) "scripts\Load-Environment.ps1")

if (!(Load-Environment)) {
    Write-Host "Failed to load environment configuration" -ForegroundColor Red
    exit 1
}

try {
    Write-Host "Setting up KeePassXC..." -ForegroundColor Blue

    # Install KeePassXC if not already installed
    if (!(Get-Command keepassxc -ErrorAction SilentlyContinue)) {
        Write-Host "Installing KeePassXC..." -ForegroundColor Yellow
        winget install KeePassXC.KeePassXC --accept-source-agreements --accept-package-agreements
    }

    # Prompt for database location
    Write-Host "`nConfigure KeePassXC database location:" -ForegroundColor Blue
    $dbLocation = Read-Host "Enter the full path to your KeePass database (or press Enter to browse)"

    if ([string]::IsNullOrWhiteSpace($dbLocation)) {
        # Open file dialog to select database
        Add-Type -AssemblyName System.Windows.Forms
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Filter = "KeePass Database (*.kdbx)|*.kdbx|All files (*.*)|*.*"
        $dialog.Title = "Select KeePass Database"
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $dbLocation = $dialog.FileName
        }
    }

    if (![string]::IsNullOrWhiteSpace($dbLocation)) {
        # Verify the path exists or create it
        $dbDirectory = Split-Path -Parent $dbLocation
        if (!(Test-Path $dbDirectory)) {
            New-Item -ItemType Directory -Path $dbDirectory -Force | Out-Null
        }

        # Save database location to environment variable
        [Environment]::SetEnvironmentVariable('KEEPASSXC_DB', $dbLocation, 'User')

        # Create desktop shortcut
        $WshShell = New-Object -comObject WScript.Shell
        $shortcut = $WshShell.CreateShortcut("$env:USERPROFILE\Desktop\KeePassXC.lnk")
        $shortcut.TargetPath = "C:\Program Files\KeePassXC\KeePassXC.exe"
        $shortcut.Arguments = "`"$dbLocation`""
        $shortcut.Save()

        Write-Host "`nKeePassXC setup completed!" -ForegroundColor Green
        Write-Host "Database location: $dbLocation" -ForegroundColor Yellow
        Write-Host "Desktop shortcut created" -ForegroundColor Yellow
    } else {
        Write-Host "No database location provided. Setup cancelled." -ForegroundColor Yellow
    }

} catch {
    Write-Host "Failed to setup KeePassXC: $_" -ForegroundColor Red
} 