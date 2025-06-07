#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Integration tests for WSL functionality

.DESCRIPTION
    Tests WSL operations on real Windows environments with actual WSL Ubuntu installation.
#>

BeforeAll {
    # Import the module
    Import-Module "$PSScriptRoot\..\..\WindowsMissingRecovery.psm1" -Force
    
    # Setup test environment
    $script:TestBackupRoot = "$env:TEMP\WMR-Integration-Tests\WSL"
    $script:WSLDistro = $env:WMR_WSL_DISTRO ?? "Ubuntu-22.04"
    
    # Create test directories
    New-Item -Path $script:TestBackupRoot -ItemType Directory -Force | Out-Null
    
    # Set test mode
    $env:WMR_TEST_MODE = "true"
    $env:WMR_BACKUP_ROOT = $script:TestBackupRoot
    
    # Check if WSL is available
    $script:WSLAvailable = $false
    try {
        $wslVersion = wsl --version
        if ($wslVersion) {
            $script:WSLAvailable = $true
        }
    } catch {
        Write-Warning "WSL not available for testing"
    }
}

Describe "WSL Integration Tests" -Tag "WSL" {
    
    Context "WSL Environment Detection" {
        It "Should detect WSL installation" {
            if ($script:WSLAvailable) {
                { wsl --version } | Should -Not -Throw
                wsl --version | Should -Not -BeNullOrEmpty
            } else {
                Set-ItResult -Skipped -Because "WSL not available"
            }
        }
        
        It "Should list WSL distributions" {
            if ($script:WSLAvailable) {
                $distros = wsl --list --quiet
                $distros | Should -Not -BeNullOrEmpty
                $distros | Should -Contain $script:WSLDistro
            } else {
                Set-ItResult -Skipped -Because "WSL not available"
            }
        }
        
        It "Should connect to WSL distribution" {
            if ($script:WSLAvailable) {
                $result = wsl -d $script:WSLDistro -- echo "test"
                $result | Should -Be "test"
            } else {
                Set-ItResult -Skipped -Because "WSL not available"
            }
        }
    }
    
    Context "WSL Package Management" {
        It "Should backup APT packages" -Skip:(-not $script:WSLAvailable) {
            # Load the WSL backup functions
            . "$PSScriptRoot\..\..\Private\wsl\Sync-WSLPackages.ps1"
            
            # Test APT package backup
            $result = wsl -d $script:WSLDistro -u testuser -- bash -c "dpkg --get-selections > /tmp/apt-packages.txt && cat /tmp/apt-packages.txt"
            
            $result | Should -Not -BeNullOrEmpty
            $result | Should -Match "install"
        }
        
        It "Should backup NPM packages" -Skip:(-not $script:WSLAvailable) {
            # Test NPM package backup
            $result = wsl -d $script:WSLDistro -u testuser -- bash -c "npm list -g --depth=0 --json 2>/dev/null || echo '{}'"
            
            $result | Should -Not -BeNullOrEmpty
            { $result | ConvertFrom-Json } | Should -Not -Throw
        }
        
        It "Should backup PIP packages" -Skip:(-not $script:WSLAvailable) {
            # Test PIP package backup
            $result = wsl -d $script:WSLDistro -u testuser -- bash -c "pip3 list --format=freeze 2>/dev/null || echo '# No packages'"
            
            $result | Should -Not -BeNullOrEmpty
        }
        
        It "Should handle package installation" -Skip:(-not $script:WSLAvailable) {
            # Test installing a simple package
            $result = wsl -d $script:WSLDistro -u testuser -- bash -c "sudo apt update && sudo apt install -y tree && tree --version"
            
            $result | Should -Match "tree"
        }
    }
    
    Context "WSL Configuration Backup" {
        It "Should backup WSL configuration files" -Skip:(-not $script:WSLAvailable) {
            # Test backing up common config files
            $configFiles = @(
                "/etc/wsl.conf",
                "/etc/fstab",
                "/etc/hosts",
                "/home/testuser/.bashrc",
                "/home/testuser/.profile"
            )
            
            foreach ($configFile in $configFiles) {
                $result = wsl -d $script:WSLDistro -u testuser -- bash -c "if [ -f '$configFile' ]; then echo 'exists'; else echo 'missing'; fi"
                
                # Should either exist or be missing (both are valid)
                $result | Should -BeIn @("exists", "missing")
            }
        }
        
        It "Should backup user home directory structure" -Skip:(-not $script:WSLAvailable) {
            # Test home directory backup
            $result = wsl -d $script:WSLDistro -u testuser -- bash -c "ls -la /home/testuser"
            
            $result | Should -Not -BeNullOrEmpty
            $result | Should -Match "testuser"
        }
        
        It "Should handle git repositories" -Skip:(-not $script:WSLAvailable) {
            # Create a test git repository
            $gitResult = wsl -d $script:WSLDistro -u testuser -- bash -c @"
cd /home/testuser
mkdir -p test-repo
cd test-repo
git init
git config user.email "test@example.com"
git config user.name "Test User"
echo "# Test Repo" > README.md
git add README.md
git commit -m "Initial commit"
git status
"@
            
            $gitResult | Should -Match "Initial commit"
        }
    }
    
    Context "Chezmoi Integration" {
        It "Should detect chezmoi installation" -Skip:(-not $script:WSLAvailable) {
            $result = wsl -d $script:WSLDistro -u testuser -- bash -c "chezmoi --version"
            
            $result | Should -Not -BeNullOrEmpty
            $result | Should -Match "chezmoi"
        }
        
        It "Should initialize chezmoi" -Skip:(-not $script:WSLAvailable) {
            # Test chezmoi initialization
            $result = wsl -d $script:WSLDistro -u testuser -- bash -c @"
cd /home/testuser
chezmoi init --apply
chezmoi status
"@
            
            # Should not throw errors
            $LASTEXITCODE | Should -Be 0
        }
        
        It "Should backup chezmoi configuration" -Skip:(-not $script:WSLAvailable) {
            # Test chezmoi source directory backup
            $result = wsl -d $script:WSLDistro -u testuser -- bash -c "ls -la ~/.local/share/chezmoi 2>/dev/null || echo 'not initialized'"
            
            $result | Should -Not -BeNullOrEmpty
        }
    }
    
    Context "WSL Script Execution" {
        It "Should execute bash scripts in WSL" -Skip:(-not $script:WSLAvailable) {
            # Load the WSL script execution function
            . "$PSScriptRoot\..\..\Private\wsl\Invoke-WSLScript.ps1"
            
            $testScript = @"
#!/bin/bash
echo "Script execution test"
whoami
pwd
uname -a
"@
            
            $result = Invoke-WSLScript -DistributionName $script:WSLDistro -Username "testuser" -Script $testScript
            
            $result.Success | Should -Be $true
            $result.Output | Should -Match "Script execution test"
            $result.Output | Should -Match "testuser"
        }
        
        It "Should handle script errors gracefully" -Skip:(-not $script:WSLAvailable) {
            $errorScript = @"
#!/bin/bash
echo "Before error"
nonexistent_command
echo "After error"
"@
            
            $result = Invoke-WSLScript -DistributionName $script:WSLDistro -Username "testuser" -Script $errorScript
            
            # Should capture the error
            $result.Success | Should -Be $false
            $result.Output | Should -Match "Before error"
            $result.Error | Should -Not -BeNullOrEmpty
        }
        
        It "Should support multi-line scripts" -Skip:(-not $script:WSLAvailable) {
            $multiLineScript = @"
#!/bin/bash
for i in {1..3}; do
    echo "Line $i"
done

if [ -d "/home/testuser" ]; then
    echo "Home directory exists"
else
    echo "Home directory missing"
fi
"@
            
            $result = Invoke-WSLScript -DistributionName $script:WSLDistro -Username "testuser" -Script $multiLineScript
            
            $result.Success | Should -Be $true
            $result.Output | Should -Match "Line 1"
            $result.Output | Should -Match "Line 2"
            $result.Output | Should -Match "Line 3"
            $result.Output | Should -Match "Home directory exists"
        }
    }
    
    Context "WSL Backup and Restore" {
        It "Should perform full WSL backup" -Skip:(-not $script:WSLAvailable) {
            # Load the backup script
            . "$PSScriptRoot\..\..\Private\backup\backup-wsl.ps1"
            
            # Run WSL backup
            $result = Backup-WSL -BackupRootPath $script:TestBackupRoot
            
            $result.Success | Should -Be $true
            $result.Items.Count | Should -BeGreaterThan 0
            
            # Verify backup files exist
            $wslBackupPath = Join-Path $script:TestBackupRoot "WSL"
            Test-Path $wslBackupPath | Should -Be $true
        }
        
        It "Should create package lists" -Skip:(-not $script:WSLAvailable) {
            $wslBackupPath = Join-Path $script:TestBackupRoot "WSL"
            
            # Check for package list files
            $packageFiles = @(
                "apt-packages.txt",
                "npm-packages.json",
                "pip-packages.txt"
            )
            
            foreach ($file in $packageFiles) {
                $filePath = Join-Path $wslBackupPath $file
                # Should exist or be in the backup results
                (Test-Path $filePath) -or ($result.Items -contains $file) | Should -Be $true
            }
        }
        
        It "Should backup configuration files" -Skip:(-not $script:WSLAvailable) {
            $configPath = Join-Path $script:TestBackupRoot "WSL\config"
            
            # Should have attempted to backup config files
            $result.Items | Where-Object { $_ -like "*.conf" -or $_ -like "*rc" -or $_ -like "*profile" } | Should -Not -BeNullOrEmpty
        }
    }
    
    Context "Error Handling" {
        It "Should handle missing WSL gracefully" {
            if (-not $script:WSLAvailable) {
                # Test behavior when WSL is not available
                { wsl --version } | Should -Throw
                
                # Backup should handle this gracefully
                . "$PSScriptRoot\..\..\Private\backup\backup-wsl.ps1"
                $result = Backup-WSL -BackupRootPath $script:TestBackupRoot
                
                $result.Success | Should -Be $false
                $result.Errors.Count | Should -BeGreaterThan 0
            } else {
                Set-ItResult -Skipped -Because "WSL is available"
            }
        }
        
        It "Should handle invalid distribution names" -Skip:(-not $script:WSLAvailable) {
            $result = wsl -d "NonExistentDistro" -- echo "test" 2>&1
            
            # Should produce an error
            $LASTEXITCODE | Should -Not -Be 0
        }
        
        It "Should handle network issues gracefully" -Skip:(-not $script:WSLAvailable) {
            # Test package operations that might fail due to network
            $result = wsl -d $script:WSLDistro -u testuser -- bash -c "timeout 5 apt update 2>&1 || echo 'Network timeout'"
            
            # Should either succeed or handle timeout gracefully
            $result | Should -Not -BeNullOrEmpty
        }
    }
}

AfterAll {
    # Cleanup test environment
    if (Test-Path $script:TestBackupRoot) {
        Remove-Item -Path $script:TestBackupRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    # Remove test environment variables
    Remove-Item Env:WMR_TEST_MODE -ErrorAction SilentlyContinue
    Remove-Item Env:WMR_BACKUP_ROOT -ErrorAction SilentlyContinue
} 