Describe "WSL Integration Tests" {
    BeforeAll {
        # Import the module with standardized pattern
        try {
            $ModulePath = Resolve-Path "$PSScriptRoot/../../WindowsMelodyRecovery.psd1"
            Import-Module $ModulePath -Force -ErrorAction Stop
        } catch {
            throw "Cannot find or import WindowsMelodyRecovery module: $($_.Exception.Message)"
        }
        
        # Import WSL Docker communication utilities
        . "$PSScriptRoot\..\utilities\WSL-Docker-Communication.ps1"
        
        # Test WSL container connectivity first
        Write-Host "Testing WSL container connectivity..." -ForegroundColor Cyan
        $script:WSLConnectivity = Test-WSLDockerConnectivity
        if (-not $script:WSLConnectivity) {
            throw "WSL Docker container connectivity test failed"
        }
        Write-Host "WSL Docker container connectivity: PASSED" -ForegroundColor Green
        
        # Set up test environment
        $script:TestBackupPath = "/workspace/test-backups/wsl"
        $script:ContainerName = "wmr-wsl-mock"
    }
    
    Context "WSL Container Communication" {
        It "Should have working WSL Docker container communication" {
            $script:WSLConnectivity | Should -Be $true
        }
        
        It "Should list WSL distributions" {
            $distributions = Get-WSLDockerDistributions -ContainerName $script:ContainerName
            $distributions | Should -Not -BeNullOrEmpty
            $distributions.Name | Should -Be "Ubuntu-22.04"
            $distributions.Status | Should -Be "Running"
        }
        
        It "Should execute commands in WSL container" {
            $result = Invoke-WSLDockerCommand -Command "whoami" -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
            $result.Output | Should -Be "testuser"
        }
        
        It "Should handle command execution errors gracefully" {
            $result = Invoke-WSLDockerCommand -Command "nonexistentcommand" -ContainerName $script:ContainerName
            $result.Success | Should -Be $false
            $result.ExitCode | Should -Not -Be 0
        }
    }
    
    Context "WSL Environment Validation" {
        It "Should have proper user environment" {
            $result = Invoke-WSLDockerCommand -Command "echo `$HOME" -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
            $result.Output | Should -Be "/home/testuser"
        }
        
        It "Should have development tools available" {
            $tools = @("python3", "node", "git", "chezmoi")
            foreach ($tool in $tools) {
                $result = Invoke-WSLDockerCommand -Command "which $tool" -ContainerName $script:ContainerName
                $result.Success | Should -Be $true
                $result.Output | Should -Not -BeNullOrEmpty
            }
        }
        
        It "Should have package managers available" {
            $managers = @("apt", "pip3", "npm")
            foreach ($manager in $managers) {
                $result = Invoke-WSLDockerCommand -Command "$manager --version" -ContainerName $script:ContainerName
                $result.Success | Should -Be $true
                $result.Output | Should -Not -BeNullOrEmpty
            }
        }
        
        It "Should have proper PATH environment" {
            $result = Invoke-WSLDockerCommand -Command "echo `$PATH" -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
            $result.Output | Should -Match "/usr/bin"
            $result.Output | Should -Match "/usr/local/bin"
        }
    }
    
    Context "WSL File System Operations" {
        It "Should handle file operations in WSL" {
            $testFile = "/tmp/wsl-test-$(Get-Random).txt"
            $testContent = "WSL test content $(Get-Date)"
            
            # Create file
            $createResult = Invoke-WSLDockerCommand -Command "echo '$testContent' > $testFile" -ContainerName $script:ContainerName
            $createResult.Success | Should -Be $true
            
            # Read file
            $readResult = Invoke-WSLDockerCommand -Command "cat $testFile" -ContainerName $script:ContainerName
            $readResult.Success | Should -Be $true
            $readResult.Output | Should -Be $testContent
            
            # Clean up
            Invoke-WSLDockerCommand -Command "rm -f $testFile" -ContainerName $script:ContainerName | Out-Null
        }
        
        It "Should handle directory operations in WSL" {
            $testDir = "/tmp/wsl-test-dir-$(Get-Random)"
            
            # Create directory
            $createResult = Invoke-WSLDockerCommand -Command "mkdir -p $testDir" -ContainerName $script:ContainerName
            $createResult.Success | Should -Be $true
            
            # Check directory exists
            $checkResult = Invoke-WSLDockerCommand -Command "test -d $testDir && echo 'exists'" -ContainerName $script:ContainerName
            $checkResult.Success | Should -Be $true
            $checkResult.Output | Should -Be "exists"
            
            # Clean up
            Invoke-WSLDockerCommand -Command "rmdir $testDir" -ContainerName $script:ContainerName | Out-Null
        }
        
        It "Should handle permission checks" {
            # Test readable file
            $result = Invoke-WSLDockerCommand -Command "test -r /home/testuser/.bashrc && echo 'readable'" -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
            $result.Output | Should -Be "readable"
            
            # Test writable directory
            $result = Invoke-WSLDockerCommand -Command "test -w /home/testuser && echo 'writable'" -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
            $result.Output | Should -Be "writable"
        }
    }
    
    Context "WSL Package Management" {
        It "Should list installed APT packages" {
            $packages = Get-WSLDockerPackages -PackageManager "apt" -ContainerName $script:ContainerName
            $packages.Success | Should -Be $true
            $packages.Count | Should -BeGreaterThan 100
            $packages.Packages | Should -Match "install"
        }
        
        It "Should list installed Python packages" {
            $packages = Get-WSLDockerPackages -PackageManager "pip3" -ContainerName $script:ContainerName
            $packages.Success | Should -Be $true
            $packages.Count | Should -BeGreaterThan 0
            $packages.Packages | Should -Match "=="
        }
        
        It "Should list installed Node.js packages" {
            $packages = Get-WSLDockerPackages -PackageManager "npm" -ContainerName $script:ContainerName
            $packages.Success | Should -Be $true
            # NPM global packages might be empty, so just check it doesn't error
            $packages.Packages | Should -Not -BeNullOrEmpty
        }
        
        It "Should handle package manager operations" {
            # Test APT update (dry run)
            $result = Invoke-WSLDockerCommand -Command "apt list --upgradable 2>/dev/null | head -5" -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
            
            # Test pip list
            $result = Invoke-WSLDockerCommand -Command "pip3 list | head -5" -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
            
            # Test npm version
            $result = Invoke-WSLDockerCommand -Command "npm --version" -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
        }
    }
    
    Context "WSL User Configuration" {
        It "Should have user configuration files" {
            $configFiles = @(".bashrc", ".gitconfig")
            foreach ($file in $configFiles) {
                $result = Invoke-WSLDockerCommand -Command "test -f /home/testuser/$file && echo 'exists'" -ContainerName $script:ContainerName
                $result.Success | Should -Be $true
                $result.Output | Should -Be "exists"
            }
        }
        
        It "Should have chezmoi configuration" {
            $result = Invoke-WSLDockerCommand -Command "test -f /home/testuser/.config/chezmoi/chezmoi.toml && echo 'exists'" -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
            $result.Output | Should -Be "exists"
        }
        
        It "Should have chezmoi source directory" {
            $result = Invoke-WSLDockerCommand -Command "test -d /home/testuser/.local/share/chezmoi && echo 'exists'" -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
            $result.Output | Should -Be "exists"
        }
        
        It "Should have proper git configuration" {
            $result = Invoke-WSLDockerCommand -Command "git config --global user.name" -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
            $result.Output | Should -Be "Test User"
            
            $result = Invoke-WSLDockerCommand -Command "git config --global user.email" -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
            $result.Output | Should -Be "test@example.com"
        }
    }
    
    Context "WSL Script Execution" {
        It "Should execute bash scripts in WSL" {
            $testScript = @"
#!/bin/bash
echo "Script execution test"
whoami
pwd
uname -a
"@
            
            $result = Invoke-WSLDockerScript -ScriptContent $testScript -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
            $result.Output | Should -Match "Script execution test"
            $result.Output | Should -Match "testuser"
            $result.Output | Should -Match "Linux"
        }
        
        It "Should handle script errors gracefully" {
            $errorScript = @"
#!/bin/bash
echo "Before error"
false  # This command will fail
echo "After error"
"@
            
            $result = Invoke-WSLDockerScript -ScriptContent $errorScript -ContainerName $script:ContainerName
            
            # The script should execute but return non-zero exit code
            $result.Success | Should -Be $false
            $result.ExitCode | Should -Not -Be 0
            $result.Output | Should -Match "Before error"
        }
        
        It "Should handle complex script operations" {
            $complexScript = @"
#!/bin/bash
# Create a temporary directory
TEST_DIR="/tmp/complex-test-$(date +%s)"
mkdir -p "\$TEST_DIR"
cd "\$TEST_DIR"

# Create some test files
echo "File 1" > file1.txt
echo "File 2" > file2.txt
mkdir subdir
echo "Subfile" > subdir/subfile.txt

# List contents
echo "Directory contents:"
ls -la

# Count files
FILE_COUNT=\$(find . -type f | wc -l)
echo "File count: \$FILE_COUNT"

# Clean up
cd /tmp
rm -rf "\$TEST_DIR"

echo "Complex script completed successfully"
"@
            
            $result = Invoke-WSLDockerScript -ScriptContent $complexScript -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
            $result.Output | Should -Match "Directory contents:"
            $result.Output | Should -Match "File count: 3"
            $result.Output | Should -Match "Complex script completed successfully"
        }
    }
    
    Context "WSL Configuration Backup" {
        BeforeAll {
            # Create backup directory at context level
            $script:backupPath = "/workspace/test-backups/wsl-config"
            New-Item -Path $script:backupPath -ItemType Directory -Force | Out-Null
        }
        
        It "Should backup WSL configuration files" {
            # Perform backup
            $backupResults = Backup-WSLDockerConfiguration -BackupPath $script:backupPath -ContainerName $script:ContainerName
            
            # Verify backup results
            $backupResults | Should -Not -BeNullOrEmpty
            $successfulBackups = $backupResults | Where-Object { $_.Success -eq $true }
            $successfulBackups.Count | Should -BeGreaterThan 0
            
            # Verify at least .bashrc was backed up
            $bashrcBackup = $backupResults | Where-Object { $_.File -eq "/home/testuser/.bashrc" }
            $bashrcBackup.Success | Should -Be $true
            Test-Path $bashrcBackup.BackupPath | Should -Be $true
        }
        
        It "Should validate backup file contents" {
            # Test that backed up files contain expected content
            $bashrcPath = Join-Path $script:backupPath "home/testuser/.bashrc"
            $bashrcPath | Should -Exist
            
            $bashrcContent = Get-Content $bashrcPath -Raw
            # Check for chezmoi-managed content instead of just "testuser"
            $bashrcContent | Should -Match "chezmoi"
            $bashrcContent | Should -Match "export PATH"
            
            # Test git config if it exists
            $gitconfigPath = Join-Path $script:backupPath "home/testuser/.gitconfig"
            if (Test-Path $gitconfigPath) {
                $gitconfigContent = Get-Content $gitconfigPath -Raw
                $gitconfigContent | Should -Match "\[user\]"
            }
        }
    }
    
    Context "WSL Integration Validation" {
        It "Should validate WSL integration completeness" {
            # Test that all expected components are available
            $components = @{
                "User Environment" = "echo `$HOME"
                "Development Tools" = "which python3 && which node && which git"
                "Package Managers" = "apt --version && pip3 --version && npm --version"
                "Version Control" = "git --version"
                "Dotfile Management" = "chezmoi --version"
            }
            
            foreach ($component in $components.GetEnumerator()) {
                $result = Invoke-WSLDockerCommand -Command $component.Value -ContainerName $script:ContainerName
                $result.Success | Should -Be $true -Because "Component '$($component.Key)' should be available"
            }
        }
        
        It "Should validate container health" {
            # Test basic system health
            $healthChecks = @{
                "System Load" = "uptime"
                "Memory Usage" = "free -h"
                "Disk Usage" = "df -h /"
                "Process Count" = "ps aux | wc -l"
            }
            
            foreach ($check in $healthChecks.GetEnumerator()) {
                $result = Invoke-WSLDockerCommand -Command $check.Value -ContainerName $script:ContainerName
                $result.Success | Should -Be $true -Because "Health check '$($check.Key)' should pass"
            }
        }
    }
    
    AfterAll {
        # Clean up test files
        if (Test-Path "/workspace/test-backups/wsl-config") {
            Remove-Item -Path "/workspace/test-backups/wsl-config" -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
} 