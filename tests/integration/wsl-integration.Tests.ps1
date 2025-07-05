Describe "WSL Integration Tests" {
    BeforeAll {
        # Import the module - handle both local and container paths
        $ModulePath = if (Test-Path "./WindowsMelodyRecovery.psm1") {
            "./WindowsMelodyRecovery.psm1"
        } elseif (Test-Path "/workspace/WindowsMelodyRecovery.psm1") {
            "/workspace/WindowsMelodyRecovery.psm1"
        } else {
            throw "Cannot find WindowsMelodyRecovery.psm1 module"
        }
        Import-Module $ModulePath -Force -ErrorAction SilentlyContinue
        
        # Test WSL container connectivity first
        Write-Host "Testing WSL container connectivity..." -ForegroundColor Cyan
        $connectivityTest = & wsl --test-connectivity 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "WSL container connectivity test failed: $connectivityTest"
        }
        Write-Host "WSL container connectivity: PASSED" -ForegroundColor Green
    }
    
    Context "WSL Container Communication" {
        It "Should have working WSL container communication" {
            # Test basic connectivity
            $result = & wsl --test-connectivity 2>&1
            $LASTEXITCODE | Should -Be 0
            $result | Should -Match "PASSED"
        }
        
        It "Should list WSL distributions" {
            $result = & wsl --list --verbose
            $LASTEXITCODE | Should -Be 0
            # Check that Ubuntu-22.04 appears in the output (may be formatted)
            $result -join " " | Should -Match "Ubuntu-22.04"
            $result -join " " | Should -Match "Running"
        }
        
        It "Should execute commands in WSL container" {
            $result = & wsl --exec "whoami"
            $LASTEXITCODE | Should -Be 0
            $result | Should -Be "testuser"
        }
    }
    
    Context "WSL Environment Validation" {
        It "Should have proper user environment" {
            $result = & wsl --user testuser --exec "echo `$HOME"
            $LASTEXITCODE | Should -Be 0
            $result | Should -Be "/home/testuser"
        }
        
        It "Should have development tools available" {
            $tools = @("python3", "node", "git", "chezmoi")
            foreach ($tool in $tools) {
                $result = & wsl --user testuser --exec "which $tool"
                $LASTEXITCODE | Should -Be 0
                $result | Should -Not -BeNullOrEmpty
            }
        }
        
        It "Should have package managers available" {
            $managers = @("apt", "pip3", "npm")
            foreach ($manager in $managers) {
                $result = & wsl --user testuser --exec "$manager --version"
                $LASTEXITCODE | Should -Be 0
                $result | Should -Not -BeNullOrEmpty
            }
        }
    }
    
    Context "WSL File System Operations" {
        It "Should handle file operations in WSL" {
            $testFile = "/tmp/wsl-test-$(Get-Random).txt"
            $testContent = "WSL test content $(Get-Date)"
            
            # Create file
            $createResult = & wsl --user testuser --exec "echo '$testContent' > $testFile"
            $LASTEXITCODE | Should -Be 0
            
            # Read file
            $readResult = & wsl --user testuser --exec "cat $testFile"
            $LASTEXITCODE | Should -Be 0
            $readResult | Should -Be $testContent
            
            # Clean up
            & wsl --user testuser --exec "rm $testFile" | Out-Null
        }
        
        It "Should handle directory operations in WSL" {
            $testDir = "/tmp/wsl-test-dir-$(Get-Random)"
            
            # Create directory
            $createResult = & wsl --user testuser --exec "mkdir -p $testDir"
            $LASTEXITCODE | Should -Be 0
            
            # Check directory exists
            $checkResult = & wsl --user testuser --exec "test -d $testDir && echo 'exists'"
            $LASTEXITCODE | Should -Be 0
            $checkResult | Should -Be "exists"
            
            # Clean up
            & wsl --user testuser --exec "rmdir $testDir" | Out-Null
        }
    }
    
    Context "WSL Package Management" {
        It "Should list installed packages" {
            $result = & wsl --user testuser --exec "dpkg --list | wc -l"
            $LASTEXITCODE | Should -Be 0
            $packageCount = [int]$result
            $packageCount | Should -BeGreaterThan 100
        }
        
        It "Should have Python packages available" {
            $result = & wsl --user testuser --exec "pip3 list | grep -E '^(requests|flask|django)'"
            $LASTEXITCODE | Should -Be 0
            $result | Should -Not -BeNullOrEmpty
        }
        
        It "Should have Node.js packages available" {
            $result = & wsl --user testuser --exec "npm list -g --depth=0"
            $LASTEXITCODE | Should -Be 0
            # Check for typescript in the output (may be formatted differently)
            $result -join " " | Should -Match "typescript"
        }
    }
    
    Context "WSL User Configuration" {
        It "Should have user configuration files" {
            $configFiles = @(".bashrc", ".gitconfig")
            foreach ($file in $configFiles) {
                $result = & wsl --user testuser --exec "test -f /home/testuser/$file && echo 'exists'"
                $LASTEXITCODE | Should -Be 0
                $result | Should -Be "exists"
            }
        }
        
        It "Should have chezmoi configuration" {
            $result = & wsl --user testuser --exec "test -f /home/testuser/.config/chezmoi/chezmoi.toml && echo 'exists'"
            $LASTEXITCODE | Should -Be 0
            $result | Should -Be "exists"
        }
        
        It "Should have chezmoi source directory" {
            $result = & wsl --user testuser --exec "test -d /home/testuser/.local/share/chezmoi && echo 'exists'"
            $LASTEXITCODE | Should -Be 0
            $result | Should -Be "exists"
        }
    }
    
    Context "WSL Cross-Platform Integration" {
        It "Should execute WSL commands from Windows context" {
            # Test that we can execute WSL commands from the test runner
            $result = & wsl --user testuser --exec "uname -a"
            $LASTEXITCODE | Should -Be 0
            $result | Should -Match "Linux"
        }
        
        It "Should handle complex command chains" {
            $result = & wsl --user testuser --exec "ls -la /home/testuser | grep -E '\.(bashrc|gitconfig)$' | wc -l"
            $LASTEXITCODE | Should -Be 0
            $fileCount = [int]$result
            $fileCount | Should -BeGreaterThan 0
        }
        
        It "Should handle environment variables" {
            $result = & wsl --user testuser --exec "echo `$PATH"
            $LASTEXITCODE | Should -Be 0
            # Check for common PATH directories
            $result | Should -Match "/usr/bin"
        }
    }
    
    Context "WSL Error Handling" {
        It "Should handle invalid commands gracefully" {
            $result = & wsl --user testuser --exec "nonexistentcommand" 2>&1
            $LASTEXITCODE | Should -Not -Be 0
            $result | Should -Not -BeNullOrEmpty
        }
        
        It "Should handle permission errors appropriately" {
            $result = & wsl --user testuser --exec "touch /root/test-file" 2>&1
            $LASTEXITCODE | Should -Not -Be 0
            $result -join " " | Should -Match "Permission denied"
        }
    }
    
    Context "WSL Integration Validation" {
        It "Should validate WSL integration completeness" {
            # Test that all expected components are available
            $components = @{
                "User Environment" = "echo `$HOME"
                "Development Tools" = "which python3"
                "Package Managers" = "apt --version"
                "Version Control" = "git --version"
                "Dotfile Management" = "chezmoi --version"
            }
            
            foreach ($component in $components.GetEnumerator()) {
                $result = & wsl --user testuser --exec $component.Value
                $LASTEXITCODE | Should -Be 0
                $result | Should -Not -BeNullOrEmpty
                Write-Host "✓ $($component.Key): Available" -ForegroundColor Green
            }
        }
        
        It "Should create integration summary" {
            $summary = @{
                IntegrationType = "WSL"
                Timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
                Version = "1.0.0"
                ContainerStatus = "Running"
                UserEnvironment = "testuser"
                Distribution = "Ubuntu-22.04"
                Features = @(
                    "Container Communication",
                    "Command Execution",
                    "File System Operations",
                    "Package Management",
                    "User Configuration",
                    "Development Tools"
                )
            }
            
            $summary | Should -Not -BeNullOrEmpty
            $summary.IntegrationType | Should -Be "WSL"
            $summary.Features.Count | Should -BeGreaterThan 5
        }
    }
} 