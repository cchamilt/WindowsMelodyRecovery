function Setup-WSL {
    [CmdletBinding()]
    param()

    # Load environment configuration (optional - module will use fallback configuration)
    try {
        Load-Environment | Out-Null
    } catch {
        Write-Verbose "Using module configuration fallback"
    }

    try {
        Write-Host "Setting up WSL (Windows Subsystem for Linux)..." -ForegroundColor Blue

        # Check if WSL is available
        $wslFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -ErrorAction SilentlyContinue

        if (!$wslFeature) {
            Write-Host "WSL feature not available on this system." -ForegroundColor Red
            return $false
        }

        # 1. Enable WSL if not already enabled
        if ($wslFeature.State -ne "Enabled") {
            Write-Host "Enabling WSL feature..." -ForegroundColor Yellow
            try {
                Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -All -NoRestart
                Write-Host "✅ WSL feature enabled (restart may be required)" -ForegroundColor Green
            } catch {
                Write-Host "❌ Failed to enable WSL feature: $($_.Exception.Message)" -ForegroundColor Red
                return $false
            }
        } else {
            Write-Host "✅ WSL feature is already enabled" -ForegroundColor Green
        }

        # 2. Enable Virtual Machine Platform for WSL2
        $vmFeature = Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -ErrorAction SilentlyContinue
        if ($vmFeature -and $vmFeature.State -ne "Enabled") {
            Write-Host "Enabling Virtual Machine Platform for WSL2..." -ForegroundColor Yellow
            try {
                Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -All -NoRestart
                Write-Host "✅ Virtual Machine Platform enabled" -ForegroundColor Green
            } catch {
                Write-Host "❌ Failed to enable Virtual Machine Platform: $($_.Exception.Message)" -ForegroundColor Red
            }
        }

        # 3. Check if WSL command is available
        if (!(Get-Command wsl -ErrorAction SilentlyContinue)) {
            Write-Host "WSL command not available. Please restart your computer and run this setup again." -ForegroundColor Yellow
            return $false
        }

        # 4. Check WSL version and set default to WSL2
        try {
            $wslVersion = wsl --version 2>$null
            if ($wslVersion) {
                Write-Host "Current WSL version:" -ForegroundColor Green
                Write-Host $wslVersion -ForegroundColor Gray

                # Set default version to WSL2
                wsl --set-default-version 2 2>$null
                Write-Host "✅ Default WSL version set to WSL2" -ForegroundColor Green
            }
        } catch {
            Write-Host "Could not determine WSL version" -ForegroundColor Yellow
        }

        # 5. List installed distributions
        try {
            $distros = wsl --list --verbose 2>$null
            if ($distros) {
                Write-Host "`nInstalled WSL distributions:" -ForegroundColor Green
                Write-Host $distros -ForegroundColor Gray
            } else {
                Write-Host "`nNo WSL distributions installed." -ForegroundColor Yellow
                Write-Host "You can install Ubuntu with: wsl --install -d Ubuntu" -ForegroundColor Cyan
                Write-Host "Or browse available distributions with: wsl --list --online" -ForegroundColor Cyan
            }
        } catch {
            Write-Host "Could not list WSL distributions" -ForegroundColor Yellow
        }

        # 6. Offer to install Ubuntu if no distributions are present
        if (!$distros -or $distros.Count -eq 0) {
            $response = Read-Host "`nWould you like to install Ubuntu? (Y/N)"
            if ($response -eq 'Y') {
                Write-Host "Installing Ubuntu..." -ForegroundColor Yellow
                try {
                    wsl --install -d Ubuntu
                    Write-Host "✅ Ubuntu installation started" -ForegroundColor Green
                    Write-Host "Note: You'll need to complete the Ubuntu setup when it launches" -ForegroundColor Cyan
                } catch {
                    Write-Host "❌ Failed to install Ubuntu: $($_.Exception.Message)" -ForegroundColor Red
                }
            }
        }

        # 7. Setup WSL configuration file
        $wslConfigPath = "$env:USERPROFILE\.wslconfig"
        if (!(Test-Path $wslConfigPath)) {
            Write-Host "`nCreating WSL configuration file..." -ForegroundColor Yellow
            $wslConfig = @"
[wsl2]
# Limits VM memory to use no more than 4 GB
memory=4GB

# Sets the VM to use two virtual processors
processors=2

# Specify a custom Linux kernel to use with your installed distros
# kernel=C:\\temp\\myCustomKernel

# Sets additional kernel parameters
# kernelCommandLine = vsyscall=emulate

# Sets amount of swap storage space to 8GB
swap=8GB

# Sets swapfile path location
# swapfile=C:\\temp\\wsl-swap.vhdx

# Disable page reporting so WSL retains all allocated memory claimed from Windows
# pageReporting=false

# Turn off default connection to bind WSL 2 localhost to Windows localhost
# localhostforwarding=true

# Disables nested virtualization
# nestedVirtualization=false

# Turns on output console showing contents of dmesg when opening a WSL 2 distro for debugging
# debugConsole=true

# Enable experimental features
[experimental]
sparseVhd=true
"@
            $wslConfig | Out-File -FilePath $wslConfigPath -Encoding UTF8
            Write-Host "✅ WSL configuration file created at: $wslConfigPath" -ForegroundColor Green
        } else {
            Write-Host "✅ WSL configuration file already exists" -ForegroundColor Green
        }

        # 8. Setup repository checking functionality
        Write-Host "`nSetting up WSL development tools..." -ForegroundColor Blue

        # Check if we have any WSL distributions to work with
        try {
            $activeDistros = wsl --list --quiet 2>$null | Where-Object { $_ -and $_.Trim() -ne "" }
            if ($activeDistros) {
                Write-Host "Setting up repository checking tools..." -ForegroundColor Yellow

                # Create a script for checking git repositories
                $repoCheckScript = @"
#!/bin/bash
# WSL Repository Status Checker
# Created by Windows Melody Recovery Setup

set -e

WORK_DIR="/home/\$(whoami)/work/repos"
PROJECTS_DIR="/home/\$(whoami)/projects"

echo "🔍 Checking Git Repositories..."
echo "================================"

check_directory() {
    local dir="\$1"
    local dir_name="\$2"

    if [ ! -d "\$dir" ]; then
        echo "📁 \$dir_name directory not found: \$dir"
        return 0
    fi

    echo "📁 Checking \${dir_name}: \${dir}"

    find "\$dir" -name ".git" -type d | while read gitdir; do
        repo_dir=\$(dirname "\$gitdir")
        repo_name=\$(basename "\$repo_dir")

        echo "  🔍 Checking: \$repo_name"
        cd "\$repo_dir"

        # Check for uncommitted changes
        if ! git diff --quiet 2>/dev/null; then
            echo "    ⚠️  Uncommitted changes found"
        fi

        # Check for staged changes
        if ! git diff --cached --quiet 2>/dev/null; then
            echo "    ⚠️  Staged changes found"
        fi

        # Check for untracked files
        if [ -n "\$(git ls-files --others --exclude-standard 2>/dev/null)" ]; then
            echo "    ⚠️  Untracked files found"
        fi

        # Check if ahead/behind remote
        if git remote -v 2>/dev/null | grep -q origin; then
            git fetch origin 2>/dev/null || true
            current_branch=\$(git branch --show-current 2>/dev/null)

            if [ -n "\$current_branch" ]; then
                local_commit=\$(git rev-parse HEAD 2>/dev/null)
                remote_commit=\$(git rev-parse origin/\$current_branch 2>/dev/null || echo "")

                if [ "\$local_commit" != "\$remote_commit" ] && [ -n "\$remote_commit" ]; then
                    # Check if ahead or behind
                    ahead=\$(git rev-list --count HEAD..origin/\$current_branch 2>/dev/null || echo "0")
                    behind=\$(git rev-list --count origin/\$current_branch..HEAD 2>/dev/null || echo "0")

                    if [ "\$ahead" -gt 0 ]; then
                        echo "    ⬇️  Behind remote by \$ahead commits"
                    fi
                    if [ "\$behind" -gt 0 ]; then
                        echo "    ⬆️  Ahead of remote by \$behind commits"
                    fi
                fi
            fi
        fi

        # Check last commit date
        last_commit=\$(git log -1 --format="%cr" 2>/dev/null || echo "unknown")
        echo "    📅 Last commit: \$last_commit"

        echo "    ✅ \$repo_name checked"
        echo ""
    done
}

# Check both common directories
check_directory "\$WORK_DIR" "Work"
check_directory "\$PROJECTS_DIR" "Projects"

echo "🎉 Repository check completed!"
echo ""
echo "💡 Tips:"
echo "   • Use 'git status' in each repo for detailed status"
echo "   • Use 'git add .' and 'git commit -m \"message\"' to commit changes"
echo "   • Use 'git push' to sync with remote repositories"
echo "   • Use 'git pull' to get latest changes from remote"
"@

                # Write the script to WSL
                try {
                    $installScript = @"
#!/bin/bash
set -e

# Create the script in user's bin directory
mkdir -p /home/\$(whoami)/bin

cat > /home/\$(whoami)/bin/check-repos << 'EOF'
$repoCheckScript
EOF

# Make it executable
chmod +x /home/\$(whoami)/bin/check-repos

# Add to PATH if not already there
if ! grep -q 'export PATH="\\$HOME/bin:\\$PATH"' /home/\$(whoami)/.bashrc; then
    echo 'export PATH="\\$HOME/bin:\\$PATH"' >> /home/\$(whoami)/.bashrc
fi

echo "Repository checker installed successfully!"
echo "Usage: check-repos"
"@
                    Invoke-WSLScript -ScriptContent $installScript
                    Write-Host "✅ Repository checking tool installed in WSL" -ForegroundColor Green
                    Write-Host "   Use 'wsl check-repos' from PowerShell or 'check-repos' from within WSL" -ForegroundColor Cyan
                } catch {
                    Write-Host "❌ Failed to install repository checking tool: $($_.Exception.Message)" -ForegroundColor Red
                }
            }
        } catch {
            Write-Host "Could not setup WSL development tools (no active distributions)" -ForegroundColor Yellow
        }

        # 9. Setup chezmoi for dotfile management
        Write-Host "`nSetting up chezmoi for dotfile management..." -ForegroundColor Blue
        try {
            $activeDistros = wsl --list --quiet 2>$null | Where-Object { $_ -and $_.Trim() -ne "" }
            if ($activeDistros) {
                $response = Read-Host "Would you like to setup chezmoi for dotfile management? (Y/N)"
                if ($response -eq 'Y') {
                    $gitRepo = Read-Host "Enter your dotfiles git repository URL (or press Enter to skip)"
                    if ($gitRepo) {
                        Setup-WSLChezmoi -GitRepository $gitRepo -InitializeRepo
                    } else {
                        Setup-WSLChezmoi
                    }
                    Write-Host "✅ chezmoi setup completed" -ForegroundColor Green
                } else {
                    Write-Host "⏭️ Skipped chezmoi setup" -ForegroundColor Gray
                }
            }
        } catch {
            Write-Host "❌ Failed to setup chezmoi: $($_.Exception.Message)" -ForegroundColor Red
        }

        # 10. Final recommendations
        Write-Host "`nWSL Setup Complete! 🎉" -ForegroundColor Green
        Write-Host "`nNext steps:" -ForegroundColor Cyan
        Write-Host "• If you installed a new distribution, complete its initial setup" -ForegroundColor Yellow
        Write-Host "• Install development tools: sudo apt update && sudo apt install git curl wget" -ForegroundColor Yellow
        Write-Host "• Configure Git: git config --global user.name 'Your Name'" -ForegroundColor Yellow
        Write-Host "• Configure Git: git config --global user.email 'your.email@example.com'" -ForegroundColor Yellow
        Write-Host "• Use 'wsl check-repos' to check your git repositories" -ForegroundColor Yellow
        Write-Host "• Use 'Sync-WSLPackages' and 'Sync-WSLHome' to backup your WSL environment" -ForegroundColor Yellow
        Write-Host "• Use chezmoi to manage your dotfiles: 'chezmoi add ~/.bashrc'" -ForegroundColor Yellow

        return $true

    } catch {
        Write-Host "Failed to setup WSL: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}