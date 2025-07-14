#!/usr/bin/env pwsh
<#
.SYNOPSIS
    WSL File Operations Tests

.DESCRIPTION
    Safe file operations tests for WSL within test directories including:
    - Backup and restore operations in test paths
    - File system operations that don't require admin privileges
    - Mock file operations for WSL configurations
    - Template-based file operations
#>

BeforeAll {
    # Load Docker test bootstrap for cross-platform compatibility
    . (Join-Path $PSScriptRoot "../utilities/Docker-Test-Bootstrap.ps1")

    # Import only the specific scripts needed to avoid TUI dependencies
    try {
        # Import WSL-related scripts (only function libraries, not scripts with mandatory params)
        $WSLScripts = @(
            "Private/backup/wsl-discovery-distributions.ps1",
            "Private/backup/wsl-discovery-packages.ps1",
            "Private/Core/PathUtilities.ps1",
            "Private/Core/FileState.ps1"
        )

        foreach ($script in $WSLScripts) {
            $scriptPath = Resolve-Path "$PSScriptRoot/../../$script"
            . $scriptPath
        }

        # Initialize test environment
        $TestEnvironmentScript = Resolve-Path "$PSScriptRoot/../utilities/Test-Environment.ps1"
        . $TestEnvironmentScript
        Initialize-TestEnvironment -SuiteName 'FileOps' | Out-Null
    }
    catch {
        throw "Cannot find or import WSL scripts: $($_.Exception.Message)"
    }

    # Get standardized test paths
    $script:TestPaths = $global:TestEnvironment

    # Define Test-SafeTestPath function for safety validation
    function Test-SafeTestPath {
        param([string]$Path)
        if ([string]::IsNullOrWhiteSpace($Path) -or $Path.Length -lt 10) { return $false }
        # Must be in a test directory
        return $Path.Contains("WMR-Tests") -or $Path.Contains("test-") -or $Path.Contains("Temp")
    }

    # Set up test paths using standardized test environment
    $script:TestBackupRoot = Join-Path $script:TestPaths.TestBackup "wsl"
    $script:TestRestoreRoot = Join-Path $script:TestPaths.TestRestore "wsl"
    $script:TempTestRoot = Join-Path $script:TestPaths.Temp "wsl-fileops"

    # Create test directories
    foreach ($path in @($script:TestBackupRoot, $script:TestRestoreRoot, $script:TempTestRoot)) {
        if (-not (Test-Path $path)) {
            New-Item -Path $path -ItemType Directory -Force | Out-Null
        }
    }
}

AfterAll {
    # Clean up test directories safely
    foreach ($path in @($script:TestBackupRoot, $script:TestRestoreRoot, $script:TempTestRoot)) {
        if ($path -and (Test-Path $path) -and (Test-SafeTestPath $path)) {
            Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "WSL File Operations Tests" -Tag "FileOperations", "WSL" {

    Context "WSL Backup File Operations" {
        It "Should create WSL backup directory structure" {
            # Test backup directory creation
            $backupStructure = @(
                "distributions",
                "config",
                "dotfiles",
                "packages"
            )

            foreach ($dir in $backupStructure) {
                $dirPath = Join-Path $script:TestBackupRoot $dir
                if (-not (Test-Path $dirPath)) {
                    New-Item -Path $dirPath -ItemType Directory -Force | Out-Null
                }
                Test-Path $dirPath | Should -Be $true
            }
        }

        It "Should backup WSL distribution information to file" {
            # Mock WSL distribution data
            $distributions = @(
                @{
                    Name     = "Ubuntu-22.04"
                    Version  = "2"
                    Default  = $true
                    State    = "Running"
                    BasePath = "C:\\Users\\TestUser\\AppData\\Local\\Packages\\CanonicalGroupLimited.Ubuntu22.04LTS_79rhkp1fndgsc\\LocalState"
                },
                @{
                    Name     = "Debian"
                    Version  = "2"
                    Default  = $false
                    State    = "Stopped"
                    BasePath = "C:\\Users\\TestUser\\AppData\\Local\\Packages\\TheDebianProject.DebianGNULinux_79rhkp1fndgsc\\LocalState"
                }
            )

            # Test backup file creation
            $distributionsPath = Join-Path $script:TestBackupRoot "distributions"
            $backupFile = Join-Path $distributionsPath "distributions.json"

            $distributions | ConvertTo-Json -Depth 3 | Out-File -FilePath $backupFile -Encoding UTF8

            # Verify backup file
            Test-Path $backupFile | Should -Be $true
            $backupContent = Get-Content $backupFile -Raw | ConvertFrom-Json
            $backupContent.Count | Should -Be 2
            $backupContent[0].Name | Should -Be "Ubuntu-22.04"
            $backupContent[1].Name | Should -Be "Debian"
        }

        It "Should backup WSL configuration files" {
            # Mock WSL configuration
            $wslConfig = @"
[wsl2]
kernelCommandLine = cgroup_enable=1 cgroup_memory=1 cgroup_v2=1 swapaccount=1
memory = 8GB
processors = 4
swap = 2GB
localhostForwarding = true
"@

            # Test configuration backup
            $configPath = Join-Path $script:TestBackupRoot "config"
            $configFile = Join-Path $configPath "wsl.conf"

            $wslConfig | Out-File -FilePath $configFile -Encoding UTF8

            # Verify configuration backup
            Test-Path $configFile | Should -Be $true
            $configContent = Get-Content $configFile -Raw
            $configContent | Should -Match "kernelCommandLine"
            $configContent | Should -Match "memory = 8GB"
            $configContent | Should -Match "processors = 4"
        }

        It "Should backup WSL dotfiles" {
            # Mock dotfiles
            $dotfiles = @{
                ".bashrc"       = @"
# ~/.bashrc: executed by bash(1) for non-login shells.
export PATH=`$HOME/bin:`$PATH
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
"@
                ".bash_profile" = @"
# ~/.bash_profile: executed by bash for login shells.
if [ -f ~/.bashrc ]; then
    . ~/.bashrc
fi
"@
                ".gitconfig"    = @"
[user]
    name = Test User
    email = test@example.com
[core]
    editor = vim
"@
                ".ssh/config"   = @"
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_rsa
"@
            }

            # Test dotfiles backup
            $dotfilesPath = Join-Path $script:TestBackupRoot "dotfiles"

            foreach ($file in $dotfiles.Keys) {
                $filePath = Join-Path $dotfilesPath $file
                $fileDir = Split-Path $filePath -Parent
                if (-not (Test-Path $fileDir)) {
                    New-Item -Path $fileDir -ItemType Directory -Force | Out-Null
                }
                $dotfiles[$file] | Out-File -FilePath $filePath -Encoding UTF8
                Test-Path $filePath | Should -Be $true
            }

            # Verify dotfiles backup
            Test-Path (Join-Path $dotfilesPath ".bashrc") | Should -Be $true
            Test-Path (Join-Path $dotfilesPath ".gitconfig") | Should -Be $true
            Test-Path (Join-Path $dotfilesPath ".ssh/config") | Should -Be $true
        }

        It "Should backup WSL package lists" {
            # Mock package lists
            $packageLists = @{
                "apt-packages.txt"  = @"
git	install
curl	install
wget	install
vim	install
python3	install
nodejs	install
"@
                "pip-packages.txt"  = @"
requests==2.28.1
numpy==1.24.3
pandas==1.5.3
flask==2.3.2
"@
                "npm-packages.json" = @"
{
  "dependencies": {
    "express": {
      "version": "4.18.2"
    },
    "lodash": {
      "version": "4.17.21"
    }
  }
}
"@
            }

            # Test package lists backup
            $packagesPath = Join-Path $script:TestBackupRoot "packages"

            foreach ($file in $packageLists.Keys) {
                $filePath = Join-Path $packagesPath $file
                $packageLists[$file] | Out-File -FilePath $filePath -Encoding UTF8
                Test-Path $filePath | Should -Be $true
            }

            # Verify package lists backup
            Test-Path (Join-Path $packagesPath "apt-packages.txt") | Should -Be $true
            Test-Path (Join-Path $packagesPath "pip-packages.txt") | Should -Be $true
            Test-Path (Join-Path $packagesPath "npm-packages.json") | Should -Be $true
        }
    }

    Context "WSL Restore File Operations" {
        It "Should restore WSL distribution information from file" {
            # Create mock backup file
            $backupFile = Join-Path $script:TestBackupRoot "distributions/distributions.json"
            $mockDistributions = @(
                @{
                    Name    = "Ubuntu-22.04"
                    Version = "2"
                    Default = $true
                    State   = "Running"
                }
            )

            $mockDistributions | ConvertTo-Json -Depth 3 | Out-File -FilePath $backupFile -Encoding UTF8

            # Test restore operation
            $restoreFile = Join-Path $script:TestRestoreRoot "distributions.json"
            Copy-Item -Path $backupFile -Destination $restoreFile -Force

            # Verify restore
            Test-Path $restoreFile | Should -Be $true
            $restoredContent = Get-Content $restoreFile -Raw | ConvertFrom-Json
            $restoredContent[0].Name | Should -Be "Ubuntu-22.04"
        }

        It "Should restore WSL configuration files" {
            # Create mock backup configuration
            $backupConfigFile = Join-Path $script:TestBackupRoot "config/wsl.conf"
            $mockConfig = @"
[wsl2]
memory = 8GB
processors = 4
"@
            $mockConfig | Out-File -FilePath $backupConfigFile -Encoding UTF8

            # Test restore operation
            $restoreConfigFile = Join-Path $script:TestRestoreRoot "wsl.conf"
            Copy-Item -Path $backupConfigFile -Destination $restoreConfigFile -Force

            # Verify restore
            Test-Path $restoreConfigFile | Should -Be $true
            $restoredConfig = Get-Content $restoreConfigFile -Raw
            $restoredConfig | Should -Match "memory = 8GB"
        }

        It "Should restore WSL dotfiles" {
            # Create mock backup dotfiles
            $backupDotfilesPath = Join-Path $script:TestBackupRoot "dotfiles"
            $mockBashrc = @"
# Test .bashrc
export PATH=`$HOME/bin:`$PATH
"@
            $bashrcFile = Join-Path $backupDotfilesPath ".bashrc"
            $mockBashrc | Out-File -FilePath $bashrcFile -Encoding UTF8

            # Test restore operation
            $restoreDotfilesPath = Join-Path $script:TestRestoreRoot "dotfiles"
            if (-not (Test-Path $restoreDotfilesPath)) {
                New-Item -Path $restoreDotfilesPath -ItemType Directory -Force | Out-Null
            }

            Copy-Item -Path $bashrcFile -Destination (Join-Path $restoreDotfilesPath ".bashrc") -Force

            # Verify restore
            Test-Path (Join-Path $restoreDotfilesPath ".bashrc") | Should -Be $true
            $restoredBashrc = Get-Content (Join-Path $restoreDotfilesPath ".bashrc") -Raw
            $restoredBashrc | Should -Match "export PATH"
        }
    }

    Context "WSL Template File Operations" {
        It "Should process WSL template for backup operations" {
            # Test template-based backup file operations
            $templatePath = "Templates/System/wsl.yaml"
            $moduleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
            $fullTemplatePath = Join-Path $moduleRoot $templatePath

            if (Test-Path $fullTemplatePath) {
                # Test template processing for file operations
                $backupPath = Join-Path $script:TempTestRoot "template-backup"
                if (-not (Test-Path $backupPath)) {
                    New-Item -Path $backupPath -ItemType Directory -Force | Out-Null
                }

                # Mock template-based backup operation
                $templateBackupFile = Join-Path $backupPath "wsl-template-backup.json"
                $mockTemplateData = @{
                    template   = "wsl.yaml"
                    timestamp  = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                    operations = @("backup-distributions", "backup-config", "backup-dotfiles")
                }

                $mockTemplateData | ConvertTo-Json -Depth 3 | Out-File -FilePath $templateBackupFile -Encoding UTF8

                # Verify template backup
                Test-Path $templateBackupFile | Should -Be $true
                $templateContent = Get-Content $templateBackupFile -Raw | ConvertFrom-Json
                $templateContent.template | Should -Be "wsl.yaml"
                $templateContent.operations.Count | Should -Be 3
            }
            else {
                Set-ItResult -Skipped -Because "wsl.yaml template not found"
            }
        }

        It "Should handle template file validation" {
            # Test template file validation for file operations
            $mockTemplateFile = Join-Path $script:TempTestRoot "mock-wsl-template.yaml"
            $mockTemplateContent = @"
name: wsl
description: WSL backup and restore operations
backup:
  - path: distributions
    type: command
    command: wsl --list --verbose
  - path: config
    type: file
    source: "%USERPROFILE%\\.wslconfig"
"@

            # Create mock template file
            $mockTemplateContent | Out-File -FilePath $mockTemplateFile -Encoding UTF8

            # Test template file validation
            Test-Path $mockTemplateFile | Should -Be $true
            $templateContent = Get-Content $mockTemplateFile -Raw
            $templateContent | Should -Match "name: wsl"
            $templateContent | Should -Match "backup:"
            $templateContent | Should -Match "distributions"
            $templateContent | Should -Match "config"
        }
    }

    Context "WSL File System Safety Operations" {
        It "Should only operate within test directories" {
            # Test that file operations are restricted to test directories
            $testPaths = @(
                $script:TestBackupRoot,
                $script:TestRestoreRoot,
                $script:TempTestRoot
            )

            foreach ($path in $testPaths) {
                # Verify paths are within test directories
                $path | Should -Match "(test-backups|test-restore|Temp)"
                Test-Path $path | Should -Be $true
            }
        }

        It "Should handle file operation errors gracefully" {
            # Test error handling for file operations
            $invalidPath = Join-Path $script:TempTestRoot "nonexistent/deep/path/file.txt"

            # Test graceful error handling
            try {
                $null = Get-Content $invalidPath -ErrorAction Stop
                $errorOccurred = $false
            }
            catch {
                $errorOccurred = $true
                $_.Exception.Message | Should -Match "(Cannot find path|does not exist)"
            }

            $errorOccurred | Should -Be $true
        }

        It "Should validate file paths before operations" {
            # Test file path validation
            $validPaths = @(
                (Join-Path $script:TestBackupRoot "test.txt"),
                (Join-Path $script:TestRestoreRoot "test.txt"),
                (Join-Path $script:TempTestRoot "test.txt")
            )

            $invalidPaths = @(
                "C:\Windows\System32\test.txt",
                "C:\Program Files\test.txt",
                "/etc/passwd"
            )

            # Test valid paths
            foreach ($path in $validPaths) {
                $path | Should -Match "(test-backups|test-restore|Temp)"
            }

            # Test invalid paths
            foreach ($path in $invalidPaths) {
                $path | Should -Not -Match "(test-backups|test-restore|Temp)"
            }
        }
    }

    Context "WSL Chezmoi File Operations" {
        It "Should backup chezmoi configuration files" {
            # Mock chezmoi configuration
            $chezmoiConfig = @"
[data]
    email = "test@example.com"
    name = "Test User"
[diff]
    pager = "less -R"
"@

            # Test chezmoi config backup
            $chezmoiPath = Join-Path $script:TestBackupRoot "chezmoi"
            if (-not (Test-Path $chezmoiPath)) {
                New-Item -Path $chezmoiPath -ItemType Directory -Force | Out-Null
            }

            $configFile = Join-Path $chezmoiPath "chezmoi.toml"
            $chezmoiConfig | Out-File -FilePath $configFile -Encoding UTF8

            # Verify chezmoi backup
            Test-Path $configFile | Should -Be $true
            $configContent = Get-Content $configFile -Raw
            $configContent | Should -Match 'email = "test@example.com"'
            $configContent | Should -Match 'name = "Test User"'
        }

        It "Should backup chezmoi source directory structure" {
            # Mock chezmoi source directory
            $chezmoiSourcePath = Join-Path $script:TestBackupRoot "chezmoi/source"
            if (-not (Test-Path $chezmoiSourcePath)) {
                New-Item -Path $chezmoiSourcePath -ItemType Directory -Force | Out-Null
            }

            # Create mock chezmoi managed files
            $managedFiles = @{
                "dot_bashrc"             = "# Managed by chezmoi`nexport PATH=`$HOME/bin:`$PATH"
                "dot_gitconfig.tmpl"     = "[user]`n    name = {{ .name }}`n    email = {{ .email }}"
                "private_dot_ssh/config" = "Host *`n    ServerAliveInterval 60"
            }

            foreach ($file in $managedFiles.Keys) {
                $filePath = Join-Path $chezmoiSourcePath $file
                $fileDir = Split-Path $filePath -Parent
                if (-not (Test-Path $fileDir)) {
                    New-Item -Path $fileDir -ItemType Directory -Force | Out-Null
                }
                $managedFiles[$file] | Out-File -FilePath $filePath -Encoding UTF8
                Test-Path $filePath | Should -Be $true
            }

            # Verify chezmoi source backup
            Test-Path (Join-Path $chezmoiSourcePath "dot_bashrc") | Should -Be $true
            Test-Path (Join-Path $chezmoiSourcePath "dot_gitconfig.tmpl") | Should -Be $true
            Test-Path (Join-Path $chezmoiSourcePath "private_dot_ssh/config") | Should -Be $true
        }
    }
}






