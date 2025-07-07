# tests/integration/wsl-communication-validation.Tests.ps1
# WSL Communication Validation Tests
# Tests Docker exec communication methods

BeforeAll {
    # Import communication utilities
    . "$PSScriptRoot/../utilities/WSL-Docker-Communication.ps1"
    
    # Test connectivity
    Write-Host "Testing WSL communication methods..." -ForegroundColor Yellow
    
    $script:ContainerName = "wmr-wsl-mock"
    $script:DockerConnectivity = Test-WSLDockerConnectivity -ContainerName $script:ContainerName
    
    Write-Host "Docker exec connectivity: $(if ($script:DockerConnectivity) { 'PASSED' } else { 'FAILED' })" -ForegroundColor $(if ($script:DockerConnectivity) { 'Green' } else { 'Red' })
}

Describe "WSL Communication Validation Tests" {
    
    Context "Docker Exec Communication" {
        It "Should execute basic commands via Docker exec" {
            $result = Invoke-WSLDockerCommand -Command "echo 'Docker exec test'" -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
            $result.Output | Should -Be "Docker exec test"
        }
        
        It "Should handle complex commands via Docker exec" {
            $complexCommand = "ls /home | wc -l"
            $result = Invoke-WSLDockerCommand -Command $complexCommand -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
            [int]$result.Output | Should -BeGreaterThan 0
        }
        
        It "Should execute multi-line scripts via Docker exec" {
            $script = @"
echo "Multi-line script test"
cd /tmp
touch test-file-$(date +%s).txt
ls -la test-file-*.txt | wc -l
rm -f test-file-*.txt
"@
            
            $result = Invoke-WSLDockerScript -ScriptContent $script -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
            $result.Output | Should -Match "Multi-line script test"
        }
        
        It "Should handle environment variables via Docker exec" {
            $result = Invoke-WSLDockerCommand -Command "echo `$HOME:`$USER" -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
            $result.Output | Should -Match "/home/testuser:testuser"
        }
    }
    
    Context "Linux Environment Validation" {
        It "Should have proper Linux distribution" {
            $result = Invoke-WSLDockerCommand -Command "cat /etc/os-release | grep 'NAME='" -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
            $result.Output | Should -Match "Ubuntu"
        }
        
        It "Should have proper filesystem structure" {
            $directories = @("/home", "/etc", "/usr", "/var", "/tmp")
            foreach ($dir in $directories) {
                $result = Invoke-WSLDockerCommand -Command "test -d $dir && echo 'exists'" -ContainerName $script:ContainerName
                $result.Success | Should -Be $true
                $result.Output | Should -Be "exists"
            }
        }
        
        It "Should have proper user environment" {
            $result = Invoke-WSLDockerCommand -Command "id testuser" -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
            $result.Output | Should -Match "uid=.*testuser"
        }
    }
    
    Context "Development Environment Validation" {
        It "Should have essential development tools" {
            $tools = @("python3", "node", "git", "chezmoi", "curl", "wget")
            
            foreach ($tool in $tools) {
                $result = Invoke-WSLDockerCommand -Command "which $tool" -ContainerName $script:ContainerName
                $result.Success | Should -Be $true -Because "$tool should be available"
                $result.Output | Should -Match "/$tool$" -Because "$tool should return a valid path"
            }
        }
        
        It "Should have package managers working" {
            $managers = @("apt", "pip3", "npm")
            
            foreach ($manager in $managers) {
                $result = Invoke-WSLDockerCommand -Command "which $manager" -ContainerName $script:ContainerName
                $result.Success | Should -Be $true -Because "$manager should be available"
            }
        }
    }
    
    Context "Package Management Validation" {
        It "Should list installed system packages" {
            $packages = Get-WSLDockerPackages -PackageManager "apt" -ContainerName $script:ContainerName
            $packages.Success | Should -Be $true
            $packages.Count | Should -BeGreaterThan 50
            $packages.Packages | Should -Match "git/"
        }
        
        It "Should list installed Python packages" {
            $packages = Get-WSLDockerPackages -PackageManager "pip3" -ContainerName $script:ContainerName
            $packages.Success | Should -Be $true
            $packages.Count | Should -BeGreaterThan 0
        }
        
        It "Should handle package operations" {
            $result = Invoke-WSLDockerCommand -Command "apt list --installed | grep -E '^(git|curl|wget)/' | wc -l" -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
            $packageCount = [int]($result.Output -split "`n" | Where-Object { $_ -match '^\d+$' } | Select-Object -First 1)
            $packageCount | Should -BeGreaterThan 2
        }
    }
    
    Context "File System Operations" {
        It "Should handle file operations correctly" {
            $testDir = "/tmp/validation-test-$(Get-Random)"
            
            # Create directory and file
            $result = Invoke-WSLDockerCommand -Command "mkdir -p $testDir && echo 'test content' > $testDir/test.txt" -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
            
            # Verify file exists and has content
            $result = Invoke-WSLDockerCommand -Command "cat $testDir/test.txt" -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
            $result.Output | Should -Be "test content"
            
            # Clean up
            Invoke-WSLDockerCommand -Command "rm -rf $testDir" -ContainerName $script:ContainerName | Out-Null
        }
        
        It "Should handle symbolic links correctly" {
            $testFile = "/tmp/link-test-$(Get-Random).txt"
            $linkFile = "/tmp/link-$(Get-Random).txt"
            
            # Create file and symlink
            $result = Invoke-WSLDockerCommand -Command "echo 'link test' > $testFile && ln -s $testFile $linkFile" -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
            
            # Test symlink
            $result = Invoke-WSLDockerCommand -Command "cat $linkFile" -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
            $result.Output | Should -Be "link test"
            
            # Clean up
            Invoke-WSLDockerCommand -Command "rm -f $testFile $linkFile" -ContainerName $script:ContainerName | Out-Null
        }
    }
    
    Context "Script Execution Validation" {
        It "Should handle complex bash scripts" {
            $complexScript = @"
#!/bin/bash
echo "Complex script execution test"
cd /tmp
TEST_VAR="test-value"
echo "Variable: `$TEST_VAR"
for i in {1..3}; do
    echo "Loop iteration: `$i"
done
echo "Script completed successfully"
"@
            
            $result = Invoke-WSLDockerScript -ScriptContent $complexScript -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
            $result.Output | Should -Match "Complex script execution test"
            $result.Output | Should -Match "Variable: test-value"
            $result.Output | Should -Match "Loop iteration: 1"
            $result.Output | Should -Match "Script completed successfully"
        }
        
        It "Should handle script with package manager operations" {
            $packageScript = @"
#!/bin/bash
echo "Package management test"
apt list --installed | grep -E '^(git|curl)/' | head -2
pip3 list | head -3
npm list -g --depth=0 2>/dev/null | head -3 || echo "npm global packages not found"
echo "Package operations completed"
"@
            
            $result = Invoke-WSLDockerScript -ScriptContent $packageScript -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
            $result.Output | Should -Match "Package management test"
            $result.Output | Should -Match "git/"
            $result.Output | Should -Match "Package operations completed"
        }
    }
} 