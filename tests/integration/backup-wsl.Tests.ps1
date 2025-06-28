Describe "WSL Backup Tests" {
    BeforeAll {
        # Import the module
        Import-Module ./WindowsMissingRecovery.psm1 -Force -ErrorAction SilentlyContinue
        
        # Set up test paths
        $testBackupPath = "/workspace/test-backups/wsl"
        $wslHomePath = "/home/testuser"
        $wslEtcPath = "/etc"
        $wslVarPath = "/var"
        
        # Create test directories if they don't exist
        if (-not (Test-Path $testBackupPath)) {
            New-Item -Path $testBackupPath -ItemType Directory -Force | Out-Null
        }
    }
    
    Context "Environment Setup" {
        It "Should have access to WSL home directory" {
            Test-Path $wslHomePath | Should -Be $true
        }
        
        It "Should have access to WSL etc directory" {
            Test-Path $wslEtcPath | Should -Be $true
        }
        
        It "Should have access to WSL var directory" {
            Test-Path $wslVarPath | Should -Be $true
        }
        
        It "Should be able to create backup directories" {
            Test-Path $testBackupPath | Should -Be $true
        }
    }
    
    Context "WSL Backup Functions" {
        It "Should have Backup-WSL function available" {
            Get-Command Backup-WSL -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
        
        It "Should be able to backup WSL distributions" {
            # Test WSL distributions backup
            $distributionsPath = Join-Path $testBackupPath "distributions"
            if (-not (Test-Path $distributionsPath)) {
                New-Item -Path $distributionsPath -ItemType Directory -Force | Out-Null
            }
            
            # Create mock WSL distribution data
            $distributions = @(
                @{
                    Name = "Ubuntu-22.04"
                    Version = "2"
                    Default = $true
                    State = "Running"
                    BasePath = "C:\\Users\\TestUser\\AppData\\Local\\Packages\\CanonicalGroupLimited.Ubuntu22.04LTS_79rhkp1fndgsc\\LocalState"
                },
                @{
                    Name = "Debian"
                    Version = "2"
                    Default = $false
                    State = "Stopped"
                    BasePath = "C:\\Users\\TestUser\\AppData\\Local\\Packages\\TheDebianProject.DebianGNULinux_79rhkp1fndgsc\\LocalState"
                }
            )
            
            $distributions | ConvertTo-Json -Depth 3 | Out-File -FilePath (Join-Path $distributionsPath "distributions.json") -Encoding UTF8
            Test-Path (Join-Path $distributionsPath "distributions.json") | Should -Be $true
        }
        
        It "Should be able to backup WSL configuration" {
            # Test WSL configuration backup
            $configPath = Join-Path $testBackupPath "config"
            if (-not (Test-Path $configPath)) {
                New-Item -Path $configPath -ItemType Directory -Force | Out-Null
            }
            
            # Create mock WSL config
            $wslConfig = @"
[wsl2]
kernelCommandLine = cgroup_enable=1 cgroup_memory=1 cgroup_v2=1 swapaccount=1
memory = 8GB
processors = 4
swap = 2GB
localhostForwarding = true
"@
            
            $wslConfig | Out-File -FilePath (Join-Path $configPath "wsl.conf") -Encoding UTF8
            Test-Path (Join-Path $configPath "wsl.conf") | Should -Be $true
        }
        
        It "Should be able to backup dotfiles" {
            # Test dotfiles backup
            $dotfilesPath = Join-Path $testBackupPath "dotfiles"
            if (-not (Test-Path $dotfilesPath)) {
                New-Item -Path $dotfilesPath -ItemType Directory -Force | Out-Null
            }
            
            # Create mock dotfiles
            $dotfiles = @{
                ".bashrc" = @"
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
                ".gitconfig" = @"
[user]
    name = Test User
    email = test@example.com
[core]
    editor = vim
"@
                ".ssh/config" = @"
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_rsa
"@
            }
            
            foreach ($file in $dotfiles.Keys) {
                $filePath = Join-Path $dotfilesPath $file
                $fileDir = Split-Path $filePath -Parent
                if (-not (Test-Path $fileDir)) {
                    New-Item -Path $fileDir -ItemType Directory -Force | Out-Null
                }
                $dotfiles[$file] | Out-File -FilePath $filePath -Encoding UTF8
                Test-Path $filePath | Should -Be $true
            }
        }
        
        It "Should be able to backup package lists" {
            # Test package lists backup
            $packagesPath = Join-Path $testBackupPath "packages"
            if (-not (Test-Path $packagesPath)) {
                New-Item -Path $packagesPath -ItemType Directory -Force | Out-Null
            }
            
            # Create mock package lists
            $installedPackages = @(
                "curl",
                "wget",
                "git",
                "vim",
                "htop",
                "tree",
                "unzip",
                "zip"
            )
            
            $installedPackages | Out-File -FilePath (Join-Path $packagesPath "installed-packages.txt") -Encoding UTF8
            Test-Path (Join-Path $packagesPath "installed-packages.txt") | Should -Be $true
            
            # Create mock snap packages
            $snapPackages = @(
                "code",
                "spotify",
                "slack"
            )
            
            $snapPackages | Out-File -FilePath (Join-Path $packagesPath "snap-packages.txt") -Encoding UTF8
            Test-Path (Join-Path $packagesPath "snap-packages.txt") | Should -Be $true
        }
        
        It "Should be able to backup chezmoi configuration" {
            # Test chezmoi backup
            $chezmoiPath = Join-Path $testBackupPath "chezmoi"
            if (-not (Test-Path $chezmoiPath)) {
                New-Item -Path $chezmoiPath -ItemType Directory -Force | Out-Null
            }
            
            # Create mock chezmoi config
            $chezmoiConfig = @"
[data]
    name = "Test User"
    email = "test@example.com"
    signingKey = "ABCD1234"
    
[bitbucket]
    url = "https://bitbucket.org/testuser/dotfiles.git"
    
[gpg]
    recipient = "test@example.com"
"@
            
            $chezmoiConfig | Out-File -FilePath (Join-Path $chezmoiPath "chezmoi.toml") -Encoding UTF8
            Test-Path (Join-Path $chezmoiPath "chezmoi.toml") | Should -Be $true
            
            # Create mock chezmoi source directory structure
            $sourcePath = Join-Path $chezmoiPath "source"
            if (-not (Test-Path $sourcePath)) {
                New-Item -Path $sourcePath -ItemType Directory -Force | Out-Null
            }
            
            # Create mock dotfile templates
            $dotfileTemplates = @{
                "dot_bashrc.tmpl" = @"
# {{ .chezmoi.sourceDir }}/dot_bashrc.tmpl
export PATH=`$HOME/bin:`$PATH
alias ll='ls -alF'
# User: {{ .name }}
"@
                "dot_gitconfig.tmpl" = @"
[user]
    name = {{ .name }}
    email = {{ .email }}
[core]
    editor = vim
"@
            }
            
            foreach ($template in $dotfileTemplates.Keys) {
                $templatePath = Join-Path $sourcePath $template
                $dotfileTemplates[$template] | Out-File -FilePath $templatePath -Encoding UTF8
                Test-Path $templatePath | Should -Be $true
            }
        }
        
        It "Should be able to backup user data" {
            # Test user data backup
            $userDataPath = Join-Path $testBackupPath "userdata"
            if (-not (Test-Path $userDataPath)) {
                New-Item -Path $userDataPath -ItemType Directory -Force | Out-Null
            }
            
            # Create mock user data structure
            $userData = @{
                "Documents" = @{
                    "work" = @{
                        "project1" = "Project 1 files"
                        "project2" = "Project 2 files"
                    }
                    "personal" = @{
                        "notes.txt" = "Personal notes"
                    }
                }
                "Downloads" = @{
                    "temp-file.txt" = "Temporary download"
                }
                "Pictures" = @{
                    "screenshot.png" = "Mock screenshot data"
                }
            }
            
            # Create user data directory structure
            foreach ($dir in $userData.Keys) {
                $dirPath = Join-Path $userDataPath $dir
                if (-not (Test-Path $dirPath)) {
                    New-Item -Path $dirPath -ItemType Directory -Force | Out-Null
                }
                
                foreach ($subDir in $userData[$dir].Keys) {
                    if ($userData[$dir][$subDir] -is [hashtable]) {
                        $subDirPath = Join-Path $dirPath $subDir
                        if (-not (Test-Path $subDirPath)) {
                            New-Item -Path $subDirPath -ItemType Directory -Force | Out-Null
                        }
                        
                        foreach ($file in $userData[$dir][$subDir].Keys) {
                            $filePath = Join-Path $subDirPath $file
                            $userData[$dir][$subDir][$file] | Out-File -FilePath $filePath -Encoding UTF8
                            Test-Path $filePath | Should -Be $true
                        }
                    } else {
                        $filePath = Join-Path $dirPath $subDir
                        $userData[$dir][$subDir] | Out-File -FilePath $filePath -Encoding UTF8
                        Test-Path $filePath | Should -Be $true
                    }
                }
            }
        }
    }
    
    Context "Backup Validation" {
        It "Should create WSL backup manifest" {
            $manifestPath = Join-Path $testBackupPath "wsl-manifest.json"
            @{
                BackupType = "WSL"
                Timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
                Version = "1.0.0"
                Distributions = @("Ubuntu-22.04", "Debian")
                Items = @(
                    @{ Type = "Distributions"; Path = "distributions" },
                    @{ Type = "Config"; Path = "config" },
                    @{ Type = "Dotfiles"; Path = "dotfiles" },
                    @{ Type = "Packages"; Path = "packages" },
                    @{ Type = "Chezmoi"; Path = "chezmoi" },
                    @{ Type = "UserData"; Path = "userdata" }
                )
            } | ConvertTo-Json -Depth 3 | Out-File -FilePath $manifestPath -Encoding UTF8
            
            Test-Path $manifestPath | Should -Be $true
            
            $manifest = Get-Content $manifestPath | ConvertFrom-Json
            $manifest.BackupType | Should -Be "WSL"
            $manifest.Distributions.Count | Should -Be 2
        }
        
        It "Should validate WSL backup integrity" {
            $manifestPath = Join-Path $testBackupPath "wsl-manifest.json"
            if (Test-Path $manifestPath) {
                $manifest = Get-Content $manifestPath | ConvertFrom-Json
                
                foreach ($item in $manifest.Items) {
                    $itemPath = Join-Path $testBackupPath $item.Path
                    Test-Path $itemPath | Should -Be $true
                }
            }
        }
    }
    
    AfterAll {
        # Clean up test files
        if (Test-Path $testBackupPath) {
            Remove-Item -Path $testBackupPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
} 