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

    # Install KeePassXC
    Write-Host "Installing KeePassXC..." -ForegroundColor Yellow
    try {
        # Try winget first
        $wingetResult = winget list KeePassXC
        if ($LASTEXITCODE -ne 0) {
            Write-Host "KeePassXC not found, installing..." -ForegroundColor Yellow
            winget install -e --id KeePassXCTeam.KeePassXC
        } else {
            Write-Host "KeePassXC is already installed" -ForegroundColor Green
        }
    } catch {
        # Fallback to chocolatey if winget fails
        if (Get-Command choco -ErrorAction SilentlyContinue) {
            Write-Host "Attempting to install via Chocolatey..." -ForegroundColor Yellow
            choco install keepassxc -y
        } else {
            throw "Failed to install KeePassXC. Please install manually."
        }
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
        try {
            $WshShell = New-Object -ComObject WScript.Shell
            $desktopPath = [System.IO.Path]::Combine($env:USERPROFILE, "Desktop", "KeePassXC.lnk")
            
            # Verify KeePassXC is in PATH
            $keepassPath = (Get-Command keepassxc -ErrorAction SilentlyContinue).Source
            if (!$keepassPath) {
                $keepassPath = "${env:ProgramFiles}\KeePassXC\KeePassXC.exe"
                if (!(Test-Path $keepassPath)) {
                    throw "KeePassXC executable not found. Please ensure it's installed correctly."
                }
            }
            
            $Shortcut = $WshShell.CreateShortcut($desktopPath)
            $Shortcut.TargetPath = $keepassPath
            $Shortcut.Arguments = "`"$dbPath`""
            $Shortcut.WorkingDirectory = Split-Path $keepassPath -Parent
            $Shortcut.Save()
            
            Write-Host "Desktop shortcut created successfully" -ForegroundColor Green
        } catch {
            Write-Host "Warning: Failed to create desktop shortcut" -ForegroundColor Yellow
            Write-Host "Error details:" -ForegroundColor Yellow
            Write-Host "  Type: $($_.Exception.GetType().FullName)" -ForegroundColor Yellow
            Write-Host "  Message: $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host "  Target Path: $keepassPath" -ForegroundColor Yellow
            Write-Host "  Shortcut Path: $desktopPath" -ForegroundColor Yellow
            Write-Host "  Working Directory: $(Split-Path $keepassPath -Parent)" -ForegroundColor Yellow
            Write-Host "You can manually create a shortcut to KeePassXC with the database path: $dbPath" -ForegroundColor Yellow
        }

        Write-Host "`nKeePassXC setup completed!" -ForegroundColor Green
        Write-Host "Database location: $dbPath" -ForegroundColor Yellow
    } else {
        Write-Host "No database location provided. Setup cancelled." -ForegroundColor Yellow
    }

} catch {
    Write-Host "Failed to setup KeePassXC: $_" -ForegroundColor Red
} 