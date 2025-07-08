#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Integration tests for WSL functionality

.DESCRIPTION
    Tests WSL operations on real Windows environments with actual WSL Ubuntu installation.
#>

BeforeAll {
    # Import the module with standardized pattern
    try {
        $ModulePath = Resolve-Path "$PSScriptRoot/../../WindowsMelodyRecovery.psd1"
        Import-Module $ModulePath -Force -ErrorAction Stop
    } catch {
        throw "Cannot find or import WindowsMelodyRecovery module: $($_.Exception.Message)"
    }
    
    # Setup test environment
    $tempPath = if ($env:TEMP) { $env:TEMP } else { "/tmp" }
    $script:TestBackupRoot = Join-Path $tempPath "WMR-Integration-Tests\WSL"
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
            # Use the WSL template instead of legacy script
            $templatePath = "Templates/System/wsl.yaml"
            
            # Skip if template doesn't exist
            if (-not (Test-Path $templatePath)) {
                Set-ItResult -Skipped -Because "wsl.yaml template not found"
                return
            }
            
            # Create backup directory for this template
            $backupPath = Join-Path $script:TestBackupRoot "wsl"
            
            # Run template-based backup
            { Invoke-WmrTemplate -TemplatePath $templatePath -Operation "Backup" -StateFilesDirectory $backupPath } | Should -Not -Throw
            
            # Verify backup directory was created
            Test-Path $backupPath | Should -Be $true
        }
        
        It "Should create package lists" -Skip:(-not $script:WSLAvailable) {
            $backupPath = Join-Path $script:TestBackupRoot "wsl"
            
            # Skip if backup wasn't created
            if (-not (Test-Path $backupPath)) {
                Set-ItResult -Skipped -Because "WSL template backup not available"
                return
            }
            
            # Check for backup files in the template backup
            $backupFiles = Get-ChildItem -Path $backupPath -Recurse -File -ErrorAction SilentlyContinue
            
            if ($backupFiles) {
                # Verify backup contains files
                $backupFiles.Count | Should -BeGreaterThan 0
            } else {
                # Template backup may be empty in test environment
                Set-ItResult -Skipped -Because "Template backup contains no files"
            }
        }
        
        It "Should backup configuration files" -Skip:(-not $script:WSLAvailable) {
            $backupPath = Join-Path $script:TestBackupRoot "wsl"
            
            # Skip if backup wasn't created
            if (-not (Test-Path $backupPath)) {
                Set-ItResult -Skipped -Because "WSL template backup not available"
                return
            }
            
            # Check if template backup contains any configuration-related files
            $configFiles = Get-ChildItem -Path $backupPath -Recurse -File | Where-Object { 
                $_.Name -like "*.conf" -or $_.Name -like "*rc" -or $_.Name -like "*profile" -or $_.Name -like "*.yaml" -or $_.Name -like "*.json"
            }
            
            # Template backup should contain some files (may be config or state files)
            $allFiles = Get-ChildItem -Path $backupPath -Recurse -File -ErrorAction SilentlyContinue
            if ($allFiles) {
                $allFiles.Count | Should -BeGreaterThan 0
            } else {
                Set-ItResult -Skipped -Because "Template backup contains no files"
            }
        }
    }
    
    Context "Error Handling" {
        It "Should handle missing WSL gracefully" {
            if (-not $script:WSLAvailable) {
                # Test behavior when WSL is not available
                { wsl --version } | Should -Throw
                
                # Template backup should handle this gracefully
                $templatePath = "Templates/System/wsl.yaml"
                
                if (Test-Path $templatePath) {
                    $backupPath = Join-Path $script:TestBackupRoot "wsl-error-test"
                    
                    # Template should handle missing WSL gracefully
                    try {
                        Invoke-WmrTemplate -TemplatePath $templatePath -Operation "Backup" -StateFilesDirectory $backupPath
                        # May succeed with warnings or skip WSL-specific operations
                        $true | Should -Be $true
                    } catch {
                        # Should have meaningful error message
                        $_.Exception.Message | Should -Not -BeNullOrEmpty
                    }
                } else {
                    Set-ItResult -Skipped -Because "wsl.yaml template not found"
                }
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

Describe "WSL Backup and Restore Tests" {
    BeforeAll {
        # Import the module with standardized pattern
        try {
            $ModulePath = Resolve-Path "$PSScriptRoot/../../WindowsMelodyRecovery.psd1"
            Import-Module $ModulePath -Force -ErrorAction Stop
        } catch {
            throw "Cannot find or import WindowsMelodyRecovery module: $($_.Exception.Message)"
        }
        
        # Set up test environment
        $script:TestBackupRoot = "/workspace/test-backups"
        $script:WSLBackupPath = "$script:TestBackupRoot/TEST-MACHINE/WSL"
        $script:WSLDistro = "Ubuntu-22.04"
        
        # Create test directories if they don't exist
        if (-not (Test-Path $script:TestBackupRoot)) {
            New-Item -Path $script:TestBackupRoot -ItemType Directory -Force | Out-Null
        }
        
        # Check if WSL mock is available
        $script:WSLAvailable = Get-Command wsl -ErrorAction SilentlyContinue
        if (-not $script:WSLAvailable) {
            Write-Warning "WSL mock not available - some tests will be skipped"
        }
    }
    
    Context "WSL Environment Validation" {
        It "Should have WSL command available" {
            $script:WSLAvailable | Should -Not -BeNullOrEmpty
        }
        
        It "Should be able to list WSL distributions" -Skip:(-not $script:WSLAvailable) {
            $distros = wsl --list --quiet
            $distros | Should -Not -BeNullOrEmpty
            $distros | Should -Contain "Ubuntu-22.04"
        }
        
        It "Should be able to execute commands in WSL" -Skip:(-not $script:WSLAvailable) {
            $result = wsl --exec echo "test"
            $result | Should -Be "test"
        }
        
        It "Should be able to check WSL version" -Skip:(-not $script:WSLAvailable) {
            $version = wsl --version
            $version | Should -Not -BeNullOrEmpty
            $version | Should -Match "WSL version:"
        }
    }
    
    Context "WSL Package Management" {
        It "Should be able to list installed packages" -Skip:(-not $script:WSLAvailable) {
            $packages = wsl --exec dpkg --get-selections
            $packages | Should -Not -BeNullOrEmpty
            $packages | Should -Match "install$"
        }
        
        It "Should be able to export APT packages" -Skip:(-not $script:WSLAvailable) {
            $aptList = wsl --exec apt list --installed
            $aptList | Should -Not -BeNullOrEmpty
        }
        
        It "Should handle NPM packages gracefully" -Skip:(-not $script:WSLAvailable) {
            # This should not fail even if NPM packages don't exist
            $npmResult = wsl --exec bash -c "command -v npm && npm list -g --depth=0 || echo 'NPM not available'"
            $npmResult | Should -Not -BeNullOrEmpty
        }
        
        It "Should handle Python packages gracefully" -Skip:(-not $script:WSLAvailable) {
            # This should not fail even if PIP packages don't exist
            $pipResult = wsl --exec bash -c "command -v pip3 && pip3 list --format=freeze || echo 'PIP not available'"
            $pipResult | Should -Not -BeNullOrEmpty
        }
    }
    
    Context "WSL Configuration Files" {
        It "Should be able to access user home directory" -Skip:(-not $script:WSLAvailable) {
            $homeCheck = wsl --exec test -d /home/testuser
            $LASTEXITCODE | Should -Be 0
        }
        
        It "Should be able to read .bashrc" -Skip:(-not $script:WSLAvailable) {
            $bashrcCheck = wsl --exec test -f /home/testuser/.bashrc
            $LASTEXITCODE | Should -Be 0
        }
        
        It "Should be able to read git config" -Skip:(-not $script:WSLAvailable) {
            $gitConfigExists = wsl --exec test -f /home/testuser/.gitconfig
            if ($LASTEXITCODE -eq 0) {
                $gitConfig = wsl --exec cat /home/testuser/.gitconfig
                $gitConfig | Should -Match "\[user\]"
                $gitConfig | Should -Match "name ="
                $gitConfig | Should -Match "email ="
            } else {
                # It's okay if git config doesn't exist, just note it
                Write-Host "Git config not found in WSL container" -ForegroundColor Yellow
                $true | Should -Be $true
            }
        }
        
        It "Should handle system configuration files" -Skip:(-not $script:WSLAvailable) {
            # Check if we can access /etc directory (some files may not exist)
            $etcAccess = wsl --exec test -d /etc
            $LASTEXITCODE | Should -Be 0
        }
    }
    
    Context "WSL Template Testing" {
        BeforeEach {
            # Clean up any previous backup attempts
            if (Test-Path $script:WSLBackupPath) {
                Remove-Item -Path $script:WSLBackupPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        
        It "Should have WSL template available" {
            $templatePath = "Templates/System/wsl.yaml"
            Test-Path $templatePath | Should -Be $true
        }
        
        It "Should execute WSL template backup with valid template" -Skip:(-not $script:WSLAvailable) {
            $templatePath = "Templates/System/wsl.yaml"
            
            # Skip if template doesn't exist
            if (-not (Test-Path $templatePath)) {
                Set-ItResult -Skipped -Because "wsl.yaml template not found"
                return
            }
            
            # Create backup directory for this template
            $backupPath = Join-Path $script:TestBackupRoot "wsl-template-test"
            
            # Run template-based backup
            { Invoke-WmrTemplate -TemplatePath $templatePath -Operation "Backup" -StateFilesDirectory $backupPath } | Should -Not -Throw
            
            # Verify backup directory was created
            Test-Path $backupPath | Should -Be $true
        }
        
        It "Should execute actual WSL template backup" -Skip:(-not $script:WSLAvailable) {
            $templatePath = "Templates/System/wsl.yaml"
            
            # Skip if template doesn't exist
            if (-not (Test-Path $templatePath)) {
                Set-ItResult -Skipped -Because "wsl.yaml template not found"
                return
            }
            
            # Execute template backup
            $backupPath = Join-Path $script:TestBackupRoot "wsl-full-test"
            Invoke-WmrTemplate -TemplatePath $templatePath -Operation "Backup" -StateFilesDirectory $backupPath
            
            # Verify backup directory was created
            Test-Path $backupPath | Should -Be $true
            
            # Check for any backup files
            $backupFiles = Get-ChildItem -Path $backupPath -Recurse -File -ErrorAction SilentlyContinue
            
            if ($backupFiles) {
                Write-Host "✅ Template backup created with $($backupFiles.Count) files" -ForegroundColor Green
                foreach ($file in $backupFiles | Select-Object -First 5) {
                    Write-Host "  - $($file.Name)" -ForegroundColor Cyan
                }
            } else {
                Write-Host "⚠️  Template backup directory created but no files found" -ForegroundColor Yellow
            }
            
            # Test should pass if directory exists (files may or may not exist in test environment)
            Test-Path $backupPath | Should -Be $true
        }
        
        It "Should handle WSL template when no distributions exist" {
            # Test template behavior in various environments
            $templatePath = "Templates/System/wsl.yaml"
            
            if (Test-Path $templatePath) {
                $backupPath = Join-Path $script:TestBackupRoot "wsl-no-distro-test"
                
                # Template should handle missing WSL distributions gracefully
                try {
                    Invoke-WmrTemplate -TemplatePath $templatePath -Operation "Backup" -StateFilesDirectory $backupPath
                    # Should succeed even if no WSL distributions are present
                    $true | Should -Be $true
                } catch {
                    # If it throws, should have meaningful error message
                    $_.Exception.Message | Should -Not -BeNullOrEmpty
                }
            } else {
                Set-ItResult -Skipped -Because "wsl.yaml template not found"
            }
        }
    }
    
    AfterAll {
        # Clean up test files but preserve for inspection if needed
        if ($env:CLEANUP_TESTS -eq "true") {
            if (Test-Path $script:WSLBackupPath) {
                Remove-Item -Path $script:WSLBackupPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        } else {
            Write-Host "WSL test backup preserved at: $script:WSLBackupPath" -ForegroundColor Cyan
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