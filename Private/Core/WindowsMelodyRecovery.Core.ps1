# Core utility functions for WindowsMelodyRecovery module

function Import-Environment {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ConfigPath = $null
    )

    # If no ConfigPath provided, try to use module's configuration
    if (-not $ConfigPath) {
        $moduleConfig = Get-WindowsMelodyRecovery
        if ($moduleConfig -and $moduleConfig.BackupRoot) {
            # Set up environment variables from module configuration
            $script:BACKUP_ROOT = $moduleConfig.BackupRoot
            $script:MACHINE_NAME = $moduleConfig.MachineName
            $script:CLOUD_PROVIDER = $moduleConfig.CloudProvider
            $script:WINDOWS_MELODY_RECOVERY_PATH = $moduleConfig.WindowsMelodyRecoveryPath

            Write-Verbose "Environment loaded from module configuration"
            return $true
        }
        else {
            Write-Warning "Module not initialized and no ConfigPath provided. Please run Initialize-WindowsMelodyRecovery first."
            return $false
        }
    }

    if (-not (Test-Path $ConfigPath)) {
        Write-Warning "Configuration file not found at: $ConfigPath"
        return $false
    }

    try {
        $config = Get-Content $ConfigPath | ConvertFrom-StringData
        foreach ($key in $config.Keys) {
            Set-Variable -Name $key -Value $config[$key] -Scope Script
        }
        return $true
    }
    catch {
        Write-Warning "Failed to load environment from ${ConfigPath}: $($_.Exception.Message)"
        return $false
    }
}

function Get-ConfigValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Key
    )

    return $script:Config[$Key]
}

function Set-ConfigValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Key,

        [Parameter(Mandatory = $true)]
        $Value
    )

    $script:Config[$Key] = $Value
}

function Test-ModuleInitialized {
    return $script:Config.IsInitialized
}

function Get-BackupRoot {
    return $script:Config.BackupRoot
}

function Get-MachineName {
    return $script:Config.MachineName
}

function Get-CloudProvider {
    return $script:Config.CloudProvider
}

function Get-ModulePath {
    return $PSScriptRoot
}

function Get-ScriptsConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateSet('backup', 'restore', 'setup')]
        [string]$Category
    )

    # Try to load from user's config directory first, then fall back to module template
    $moduleRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $userConfigPath = Join-Path $moduleRoot "Config\scripts-config.json"
    $templateConfigPath = Join-Path $moduleRoot "Templates\scripts-config.json"

    $configPath = if (Test-Path $userConfigPath) { $userConfigPath } else { $templateConfigPath }

    if (-not (Test-Path $configPath)) {
        Write-Warning "Scripts configuration not found at: $configPath"
        return $null
    }

    try {
        $config = Get-Content $configPath -Raw | ConvertFrom-Json

        if ($Category) {
            return $config.$Category.enabled | Where-Object { $_.enabled -eq $true }
        }
        else {
            return $config
        }
    }
    catch {
        Write-Warning "Failed to load scripts configuration: $($_.Exception.Message)"
        return $null
    }
}

function Set-ScriptsConfig {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Category,

        [Parameter(Mandatory = $true)]
        [string]$ScriptName,

        [Parameter(Mandatory = $true)]
        [bool]$Enabled
    )

    $moduleRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $userConfigPath = Join-Path $moduleRoot "Config\scripts-config.json"
    $templateConfigPath = Join-Path $moduleRoot "Templates\scripts-config.json"

    # Copy template to user config if it doesn't exist
    if (-not (Test-Path $userConfigPath) -and (Test-Path $templateConfigPath)) {
        $configDir = Split-Path $userConfigPath -Parent
        if (-not (Test-Path $configDir)) {
            New-Item -ItemType Directory -Path $configDir -Force | Out-Null
        }
        Copy-Item -Path $templateConfigPath -Destination $userConfigPath -Force
    }

    if (-not (Test-Path $userConfigPath)) {
        Write-Error "Cannot create or find scripts configuration file"
        return $false
    }

    try {
        $config = Get-Content $userConfigPath -Raw | ConvertFrom-Json

        # Find and update the script
        $scriptConfig = $config.$Category.enabled | Where-Object { $_.name -eq $ScriptName -or $_.function -eq $ScriptName }
        if ($scriptConfig) {
            if ($PSCmdlet.ShouldProcess("$userConfigPath", "Update $ScriptName in $Category to enabled=$Enabled")) {
                $scriptConfig.enabled = $Enabled

                # Save the updated configuration
                $config | ConvertTo-Json -Depth 10 | Set-Content -Path $userConfigPath -Force
                Write-Verbose "Updated $ScriptName in $Category to enabled=$Enabled"
                return $true
            }
            return $false
        }
        else {
            Write-Warning "Script '$ScriptName' not found in category '$Category'"
            return $false
        }
    }
    catch {
        Write-Error "Failed to update scripts configuration: $($_.Exception.Message)"
        return $false
    }
}

function Initialize-ModuleFromConfig {
    # Try to load configuration from the module's config directory
    $moduleRoot = Split-Path $PSScriptRoot -Parent
    $configFile = Join-Path $moduleRoot "Config\windows.env"

    if (Test-Path $configFile) {
        try {
            $config = Get-Content $configFile | ConvertFrom-StringData

            # Update module configuration from file
            if ($config.BACKUP_ROOT) { $script:Config.BackupRoot = $config.BACKUP_ROOT }
            if ($config.MACHINE_NAME) { $script:Config.MachineName = $config.MACHINE_NAME }
            if ($config.WINDOWS_MELODY_RECOVERY_PATH) { $script:Config.WindowsMelodyRecoveryPath = $config.WINDOWS_MELODY_RECOVERY_PATH }
            if ($config.CLOUD_PROVIDER) { $script:Config.CloudProvider = $config.CLOUD_PROVIDER }

            $script:Config.IsInitialized = $true
            Write-Verbose "Module configuration loaded from: $configFile"
            return $true
        }
        catch {
            Write-Warning "Failed to load configuration from: $configFile - $($_.Exception.Message)"
            return $false
        }
    }

    return $false
}

function Invoke-WSLScript {
    <#
    .SYNOPSIS
    Execute a bash script inside WSL from PowerShell

    .DESCRIPTION
    Creates a temporary bash script and executes it inside WSL with proper error handling

    .PARAMETER ScriptContent
    The bash script content to execute

    .PARAMETER Distribution
    Specific WSL distribution to use (optional)

    .PARAMETER AsRoot
    Run the script with sudo privileges

    .PARAMETER WorkingDirectory
    Set working directory inside WSL

    .PARAMETER PassThru
    Return the exit code and output

    .EXAMPLE
    Invoke-WSLScript -ScriptContent "apt update && apt list --upgradable"

    .EXAMPLE
    $script = @"
    #!/bin/bash
    mkdir -p /home/user/backup
    rsync -av /home/user/documents/ /home/user/backup/
    "@
    Invoke-WSLScript -ScriptContent $script -AsRoot
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptContent,

        [Parameter(Mandatory = $false)]
        [string]$Distribution,

        [Parameter(Mandatory = $false)]
        [switch]$AsRoot,

        [Parameter(Mandatory = $false)]
        [string]$WorkingDirectory,

        [Parameter(Mandatory = $false)]
        [switch]$PassThru
    )

    # Check if WSL is available
    if (!(Get-Command wsl -ErrorAction SilentlyContinue)) {
        throw "WSL is not available on this system"
    }

    try {
        # Create temporary script file
        $tempPath = if ($env:TEMP) { $env:TEMP } else { "/tmp" }
        $tempScript = Join-Path $tempPath "wsl-script-$(Get-Random).sh"

        # Prepare script content with proper shebang and error handling
        $fullScript = @"
#!/bin/bash
set -e
set -o pipefail

$(if ($WorkingDirectory) { "cd `"$WorkingDirectory`"" })

$ScriptContent
"@

        # Write script with UTF-8 encoding without BOM
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($tempScript, $fullScript, $utf8NoBom)

        # Convert Windows path to WSL path
        $wslScriptPath = "/mnt/" + (($tempScript -replace '\\', '/') -replace ':', '').ToLower()

        # Build WSL command
        $wslArgs = @()
        if ($Distribution) {
            $wslArgs += @("-d", $Distribution)
        }
        $wslArgs += @("--exec", "bash", "-c")

        # Build bash command
        $bashCommand = "chmod +x '$wslScriptPath'"
        if ($AsRoot) {
            $bashCommand += " && sudo '$wslScriptPath'"
        }
        else {
            $bashCommand += " && '$wslScriptPath'"
        }
        $wslArgs += $bashCommand

        Write-Verbose "Executing WSL command: wsl $($wslArgs -join ' ')"

        if ($PassThru) {
            # Capture output and exit code
            $process = Start-Process -FilePath "wsl" -ArgumentList $wslArgs -Wait -PassThru -NoNewWindow -RedirectStandardOutput -RedirectStandardError
            $output = $process.StandardOutput.ReadToEnd()
            $errorOutput = $process.StandardError.ReadToEnd()

            return @{
                ExitCode = $process.ExitCode
                Output = $output
                Error = $errorOutput
                Success = $process.ExitCode -eq 0
            }
        }
        else {
            # Direct execution
            & wsl @wslArgs
            if ($LASTEXITCODE -ne 0) {
                throw "WSL script execution failed with exit code $LASTEXITCODE"
            }
        }

    }
    finally {
        # Cleanup temporary script
        if (Test-Path $tempScript) {
            Remove-Item $tempScript -Force -ErrorAction SilentlyContinue
        }
    }
}

function Sync-WSLPackage {
    <#
    .SYNOPSIS
    Sync WSL package lists to OneDrive backup

    .DESCRIPTION
    Exports APT, NPM, and PIP package lists from WSL to OneDrive for backup

    .PARAMETER BackupPath
    Override the default backup path

    .EXAMPLE
    Sync-WSLPackages
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$BackupPath
    )

    if (!$BackupPath) {
        $config = Get-WindowsMelodyRecovery
        if ($config.CloudProvider -eq "OneDrive") {
            $BackupPath = "$env:USERPROFILE\OneDrive\WSL-Packages"
        }
        else {
            $BackupPath = "$env:USERPROFILE\WSL-Packages"
        }
    }

    $packageSyncScript = @"
#!/bin/bash
set -e

USER_NAME=\$(whoami)
BACKUP_DIR="/mnt/c/Users/\$USER_NAME/OneDrive/WSL-Packages"

echo "Syncing WSL packages for user: \$USER_NAME"
mkdir -p "\$BACKUP_DIR"

echo "Exporting APT packages..."
dpkg --get-selections > "\$BACKUP_DIR/apt-packages.txt"

echo "Exporting NPM packages..."
if command -v npm &> /dev/null; then
    npm list -g --depth=0 > "\$BACKUP_DIR/npm-packages.txt" 2>/dev/null || echo "No global NPM packages found"
fi

echo "Exporting PIP packages..."
if command -v pip &> /dev/null; then
    pip list --format=freeze > "\$BACKUP_DIR/pip-packages.txt" 2>/dev/null || echo "No PIP packages found"
fi

echo "Package sync completed!"
"@

    try {
        Invoke-WSLScript -ScriptContent $packageSyncScript
        Write-Information -MessageData "WSL packages synced to: $BackupPath" -InformationAction Continue
        return $true
    }
    catch {
        Write-Error -Message "Failed to sync WSL packages: $($_.Exception.Message)"
        return $false
    }
}

function Sync-WSLHome {
    <#
    .SYNOPSIS
    Sync WSL home directory to backup location

    .DESCRIPTION
    Uses rsync to backup WSL home directory with exclusions for large/temporary files

    .PARAMETER ExcludePatterns
    Additional patterns to exclude from sync

    .EXAMPLE
    Sync-WSLHome -ExcludePatterns @('*.log', 'temp/*')
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$ExcludePatterns = @()
    )

    $defaultExcludes = @(
        'work/*/repos',
        '.cache',
        '.npm',
        '.local/share/Trash',
        'snap',
        '*.log',
        '.vscode-server'
    )

    $allExcludes = $defaultExcludes + $ExcludePatterns
    $excludeArgs = ($allExcludes | ForEach-Object { "--exclude '$_'" }) -join ' '

    $homeSyncScript = @"
#!/bin/bash
set -e

USER_NAME=\$(whoami)
SOURCE_DIR="/home/\$USER_NAME"
BACKUP_DIR="/mnt/c/Users/\$USER_NAME/OneDrive/WSL-Home"

echo "Syncing WSL home directory..."
mkdir -p "\$BACKUP_DIR"

rsync -avz --progress $excludeArgs "\$SOURCE_DIR/" "\$BACKUP_DIR/"

echo "Home directory sync completed!"
"@

    try {
        Invoke-WSLScript -ScriptContent $homeSyncScript
        Write-Information -MessageData "WSL home directory synced successfully" -InformationAction Continue
        return $true
    }
    catch {
        Write-Error -Message "Failed to sync WSL home directory: $($_.Exception.Message)"
        return $false
    }
}

function Test-WSLRepository {
    <#
    .SYNOPSIS
    Check git repositories in WSL for uncommitted changes

    .DESCRIPTION
    Scans work directories for git repositories and reports status

    .PARAMETER WorkDirectory
    Base directory to scan for repositories

    .EXAMPLE
    Test-WSLRepositories -WorkDirectory "/home/user/projects"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$WorkDirectory = "/home/\$(whoami)/work/repos"
    )

    $repoCheckScript = @'
#!/bin/bash
set -e

WORK_DIR="$workDirLinux"

echo "Checking for git repositories in: $WORK_DIR"

if [ ! -d "$WORK_DIR" ]; then
    echo "Work directory does not exist: $WORK_DIR"
    exit 0
fi

echo "Checking git repositories in $WORK_DIR..."

find "$WORK_DIR" -name ".git" -type d | while read gitdir; do
    repo_dir=$(dirname "$gitdir")
    repo_name=$(basename "$repo_dir")
    echo "Checking: $repo_name"

    cd "$repo_dir"

    # Check for uncommitted changes
    if ! git diff --quiet; then
        echo "  ⚠️  Uncommitted changes found"
    fi

    # Check for untracked files
    if [ -n "$(git ls-files --others --exclude-standard)" ]; then
        echo "  ⚠️  Untracked files found"
    fi

    # Check if ahead/behind remote
    if git remote -v | grep -q origin; then
        git fetch origin 2>/dev/null || true
        current_branch=$(git branch --show-current)
        if [ -n "$current_branch" ]; then
            local_commit=$(git rev-parse HEAD)
            remote_commit=$(git rev-parse origin/$current_branch 2>/dev/null || echo "")

            if [ "$local_commit" != "$remote_commit" ] && [ -n "$remote_commit" ]; then
                echo "  ⚠️  Out of sync with remote"
            fi
        fi
    fi

    echo "  ✅ $repo_name checked"
done

echo "Repository check completed!"
'@

    try {
        Invoke-WSLScript -ScriptContent $repoCheckScript
        return $true
    }
    catch {
        Write-Error -Message "Failed to check WSL repositories: $($_.Exception.Message)"
        return $false
    }
}

function Initialize-WSLChezmoi {
    <#
    .SYNOPSIS
    Install and configure chezmoi for dotfile management in WSL

    .DESCRIPTION
    Installs chezmoi in WSL and optionally initializes it with a git repository

    .PARAMETER GitRepository
    Git repository URL for dotfiles (optional)

    .PARAMETER InitializeRepo
    Whether to initialize chezmoi with the repository

    .EXAMPLE
    Initialize-WSLChezmoi -GitRepository "https://github.com/username/dotfiles.git" -InitializeRepo
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$GitRepository,

        [Parameter(Mandatory = $false)]
        [switch]$InitializeRepo
    )

    # Check if WSL is available
    if (!(Get-Command wsl -ErrorAction SilentlyContinue)) {
        throw "WSL is not available on this system"
    }

    try {
        $chezmoiSetupScript = @'
#!/bin/bash
set -e

echo "🏠 Setting up chezmoi for dotfile management..."

# Check if chezmoi is already installed
if command -v chezmoi &> /dev/null; then
    echo "✅ chezmoi is already installed"
    chezmoi --version
else
    echo "📦 Installing chezmoi..."

    # Install chezmoi using the official installer
    sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/bin"

    # Add to PATH if not already there
    if ! grep -q 'export PATH="$HOME/bin:$PATH"' ~/.bashrc; then
        echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc
        export PATH="$HOME/bin:$PATH"
    fi

    echo "✅ chezmoi installed successfully"
fi

# Initialize chezmoi if requested and repository provided
if [ -n "$GitRepository" ] && [ "$InitializeRepo" = "True" ]; then
    echo "🔧 Initializing chezmoi with repository: $GitRepository"

    if [ ! -d "$HOME/.local/share/chezmoi" ]; then
        chezmoi init "$GitRepository"
        echo "✅ chezmoi initialized with repository"
    else
        echo "ℹ️  chezmoi already initialized"
    fi

    # Apply dotfiles
    echo "📋 Applying dotfiles..."
    chezmoi apply
    echo "✅ Dotfiles applied"
else
    echo "🔧 Initializing empty chezmoi repository..."

    if [ ! -d "$HOME/.local/share/chezmoi" ]; then
        chezmoi init
        echo "✅ chezmoi initialized (empty repository)"
        echo "💡 Add files with: chezmoi add ~/.bashrc"
        echo "💡 Edit files with: chezmoi edit ~/.bashrc"
        echo "💡 Apply changes with: chezmoi apply"
    else
        echo "ℹ️  chezmoi already initialized"
    fi
fi

# Create useful aliases
echo "🔗 Setting up chezmoi aliases..."
if ! grep -q "alias cm=" ~/.bashrc; then
    cat >> ~/.bashrc << 'EOF'

# Chezmoi aliases
alias cm='chezmoi'
alias cma='chezmoi apply'
alias cme='chezmoi edit'
alias cms='chezmoi status'
alias cmd='chezmoi diff'
alias cmu='chezmoi update'
alias cmcd='cd $(chezmoi source-path)'
EOF
    echo "✅ chezmoi aliases added to ~/.bashrc"
else
    echo "ℹ️  chezmoi aliases already exist"
fi

echo "🎉 chezmoi setup completed!"
echo ""
echo "📚 Quick chezmoi commands:"
echo "  chezmoi add ~/.bashrc     # Add file to chezmoi"
echo "  chezmoi edit ~/.bashrc    # Edit managed file"
echo "  chezmoi apply             # Apply all changes"
echo "  chezmoi status            # Show status"
echo "  chezmoi diff              # Show differences"
echo "  chezmoi cd                # Go to source directory"
echo ""
echo "🔗 Useful aliases (restart shell or source ~/.bashrc):"
echo "  cm, cma, cme, cms, cmd, cmu, cmcd"
'@

        $params = @{
            ScriptContent = $chezmoiSetupScript
        }

        Invoke-WSLScript @params

        Write-Information -MessageData "✅ chezmoi setup completed in WSL" -InformationAction Continue
        return $true

    }
    catch {
        Write-Error -Message "❌ Failed to setup chezmoi in WSL: $($_.Exception.Message)"
        return $false
    }
}

function Backup-WSLChezmoi {
    <#
    .SYNOPSIS
    Backup chezmoi configuration and dotfiles from WSL

    .DESCRIPTION
    Backs up chezmoi source directory and configuration to Windows

    .PARAMETER BackupPath
    Path to backup chezmoi data

    .EXAMPLE
    Backup-WSLChezmoi -BackupPath "C:\Backup\chezmoi"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BackupPath
    )

    # Check if WSL is available
    if (!(Get-Command wsl -ErrorAction SilentlyContinue)) {
        Write-Warning -Message "WSL is not available on this system"
        return $false
    }

    try {
        # Convert Windows path to WSL path
        $chezmoiBackupPath = $BackupPath + "/chezmoi"
        $chezmoiBackupPathLinux = $chezmoiBackupPath -replace '\\', '/' -replace 'C:', '/mnt/c'

        $chezmoiBackupScript = @'
#!/bin/bash
set -e

BACKUP_DIR="$chezmoiBackupPathLinux"

echo "🏠 Backing up chezmoi configuration to: $BACKUP_DIR"

# Check if chezmoi is installed
if ! command -v chezmoi &> /dev/null; then
    echo "ℹ️  chezmoi not installed, skipping backup"
    exit 0
fi

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Check if chezmoi is initialized
if [ ! -d "$HOME/.local/share/chezmoi" ]; then
    echo "ℹ️  chezmoi not initialized, skipping backup"
    exit 0
fi

echo "📦 Backing up chezmoi source directory..."
# Backup the entire chezmoi source directory
rsync -av "$HOME/.local/share/chezmoi/" "$BACKUP_DIR/source/"

# Backup chezmoi configuration
if [ -f "$HOME/.config/chezmoi/chezmoi.toml" ]; then
    mkdir -p "$BACKUP_DIR/config"
    cp "$HOME/.config/chezmoi/chezmoi.toml" "$BACKUP_DIR/config/"
    echo "✅ chezmoi configuration backed up"
fi

# Create a list of managed files
echo "📋 Creating list of managed files..."
chezmoi managed > "$BACKUP_DIR/managed-files.txt" 2>/dev/null || echo "Could not list managed files"

# Create status report
echo "📊 Creating status report..."
chezmoi status > "$BACKUP_DIR/status.txt" 2>/dev/null || echo "Could not get status"

# Get chezmoi data info
echo "ℹ️  Creating chezmoi info..."
cat > "$BACKUP_DIR/info.txt" << EOF
Chezmoi Backup Information
Generated: $(date)
User: $(whoami)
Chezmoi Version: $(chezmoi --version 2>/dev/null || echo "unknown")
Source Path: $(chezmoi source-path 2>/dev/null || echo "unknown")
EOF

echo "✅ chezmoi backup completed!"
'@

        Invoke-WSLScript -ScriptContent $chezmoiBackupScript
        Write-Information -MessageData "✅ chezmoi backup completed" -InformationAction Continue
        return $true

    }
    catch {
        Write-Error -Message "❌ Failed to backup chezmoi: $($_.Exception.Message)"
        return $false
    }
}

function Restore-WSLChezmoi {
    <#
    .SYNOPSIS
    Restore chezmoi configuration and dotfiles to WSL

    .DESCRIPTION
    Restores chezmoi source directory and configuration from Windows backup

    .PARAMETER BackupPath
    Path to restore chezmoi data from

    .EXAMPLE
    Restore-WSLChezmoi -BackupPath "C:\Backup\chezmoi"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BackupPath
    )

    # Check if WSL is available
    if (!(Get-Command wsl -ErrorAction SilentlyContinue)) {
        Write-Warning -Message "WSL is not available on this system"
        return $false
    }

    try {
        # Convert Windows path to WSL path
        $chezmoiBackupPath = $BackupPath + "/chezmoi"
        $chezmoiBackupPathLinux = $chezmoiBackupPath -replace '\\', '/' -replace 'C:', '/mnt/c'

        $chezmoiRestoreScript = @'
#!/bin/bash
set -e

BACKUP_DIR="$chezmoiBackupPathLinux"

echo "🏠 Restoring chezmoi configuration from: $BACKUP_DIR"

# Check if backup exists
if [ ! -d "$BACKUP_DIR" ]; then
    echo "ℹ️  No chezmoi backup found, skipping restore"
    exit 0
fi

# Install chezmoi if not present
if ! command -v chezmoi &> /dev/null; then
    echo "📦 Installing chezmoi..."
    sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/bin"

    # Add to PATH
    if ! grep -q 'export PATH="$HOME/bin:$PATH"' ~/.bashrc; then
        echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc
    fi
    export PATH="$HOME/bin:$PATH"
    echo "✅ chezmoi installed"
fi

# Restore chezmoi source directory
if [ -d "$BACKUP_DIR/source" ]; then
    echo "📦 Restoring chezmoi source directory..."
    mkdir -p "$HOME/.local/share"
    rsync -av "$BACKUP_DIR/source/" "$HOME/.local/share/chezmoi/"
    echo "✅ chezmoi source directory restored"
fi

# Restore chezmoi configuration
if [ -f "$BACKUP_DIR/config/chezmoi.toml" ]; then
    echo "🔧 Restoring chezmoi configuration..."
    mkdir -p "$HOME/.config/chezmoi"
    cp "$BACKUP_DIR/config/chezmoi.toml" "$HOME/.config/chezmoi/"
    echo "✅ chezmoi configuration restored"
fi

# Apply dotfiles if source directory exists
if [ -d "$HOME/.local/share/chezmoi" ]; then
    echo "📋 Applying dotfiles..."
    chezmoi apply
    echo "✅ Dotfiles applied"
fi

# Show status
if command -v chezmoi &> /dev/null && [ -d "$HOME/.local/share/chezmoi" ]; then
    echo ""
    echo "📊 chezmoi status:"
    chezmoi status || echo "Could not get status"
fi

echo "✅ chezmoi restore completed!"
'@

        Invoke-WSLScript -ScriptContent $chezmoiRestoreScript
        Write-Information -MessageData "✅ chezmoi restore completed" -InformationAction Continue
        return $true

    }
    catch {
        Write-Error -Message "❌ Failed to restore chezmoi: $($_.Exception.Message)"
        return $false
    }
}
