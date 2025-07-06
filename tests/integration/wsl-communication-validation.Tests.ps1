Describe "WSL Communication Validation Tests" {
    BeforeAll {
        # Import communication utilities
        . "$PSScriptRoot\..\utilities\WSL-Docker-Communication.ps1"
        . "$PSScriptRoot\..\utilities\WSL-SSH-Communication.ps1"
        
        # Test both communication methods
        Write-Host "Testing WSL communication methods..." -ForegroundColor Cyan
        
        $script:DockerConnectivity = Test-WSLDockerConnectivity
        Write-Host "Docker exec connectivity: $(if ($script:DockerConnectivity) { 'PASSED' } else { 'FAILED' })" -ForegroundColor $(if ($script:DockerConnectivity) { 'Green' } else { 'Red' })
        
        # SSH might not be immediately available, so we'll test it but not fail if it's not ready
        $script:SSHConnectivity = Test-WSLSSHConnectivity
        Write-Host "SSH connectivity: $(if ($script:SSHConnectivity) { 'PASSED' } else { 'FAILED (expected in some environments)' })" -ForegroundColor $(if ($script:SSHConnectivity) { 'Green' } else { 'Yellow' })
        
        $script:ContainerName = "wmr-wsl-mock"
    }
    
    Context "Docker Exec Communication" {
        It "Should execute basic commands via Docker exec" {
            $script:DockerConnectivity | Should -Be $true
            
            $result = Invoke-WSLDockerCommand -Command "echo 'Docker exec test'" -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
            $result.Output | Should -Be "Docker exec test"
            $result.Method | Should -Be $null  # Docker method doesn't set this
        }
        
        It "Should handle complex commands via Docker exec" {
            $complexCommand = "ls -la /home/testuser | grep -E '\.(bashrc|gitconfig)$' | wc -l"
            $result = Invoke-WSLDockerCommand -Command $complexCommand -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
            [int]$result.Output | Should -BeGreaterThan 0
        }
        
        It "Should execute multi-line scripts via Docker exec" {
            $script = @"
#!/bin/bash
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
            $result = Invoke-WSLDockerCommand -Command "echo \${HOME}:\${USER}:\${PATH}" -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
            $result.Output | Should -Match "/home/testuser:testuser:"
            $result.Output | Should -Match "/usr/bin"
        }
    }
    
    Context "SSH Communication" -Skip:(-not $script:SSHConnectivity) {
        It "Should execute basic commands via SSH" {
            $result = Invoke-WSLSSHCommand -Command "echo 'SSH test'"
            $result.Success | Should -Be $true
            $result.Output | Should -Be "SSH test"
            $result.Method | Should -Be "SSH"
        }
        
        It "Should handle complex commands via SSH" {
            $complexCommand = "ps aux | grep -v grep | grep bash | wc -l"
            $result = Invoke-WSLSSHCommand -Command $complexCommand
            $result.Success | Should -Be $true
            [int]$result.Output | Should -BeGreaterThan 0
        }
        
        It "Should execute scripts via SSH" {
            $script = @"
#!/bin/bash
echo "SSH script test"
whoami
hostname
uname -a
"@
            
            $result = Invoke-WSLSSHScript -ScriptContent $script -ScriptType "bash"
            $result.Success | Should -Be $true
            $result.Output | Should -Match "SSH script test"
            $result.Output | Should -Match "testuser"
            $result.Method | Should -Be "SSH"
        }
        
        It "Should handle file operations via SSH" {
            $testFile = "/tmp/ssh-test-$(Get-Random).txt"
            $testContent = "SSH file test content"
            
            # Create file
            $result = Invoke-WSLSSHCommand -Command "echo '$testContent' > $testFile"
            $result.Success | Should -Be $true
            
            # Read file
            $result = Invoke-WSLSSHCommand -Command "cat $testFile"
            $result.Success | Should -Be $true
            $result.Output | Should -Be $testContent
            
            # Clean up
            Invoke-WSLSSHCommand -Command "rm -f $testFile" | Out-Null
        }
    }
    
    Context "Linux Environment Validation" {
        It "Should have proper Linux distribution" {
            $result = Invoke-WSLDockerCommand -Command "cat /etc/os-release | grep -E '^(NAME|VERSION)='" -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
            $result.Output | Should -Match "Ubuntu"
            $result.Output | Should -Match "22.04"
        }
        
        It "Should have proper kernel and system info" {
            $result = Invoke-WSLDockerCommand -Command "uname -a" -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
            $result.Output | Should -Match "Linux"
            $result.Output | Should -Match "x86_64"
        }
        
        It "Should have proper filesystem structure" {
            $directories = @("/home", "/etc", "/usr", "/var", "/tmp", "/opt")
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
            $result.Output | Should -Match "gid=.*testuser"
        }
        
        It "Should have proper shell environment" {
            $result = Invoke-WSLDockerCommand -Command "echo \$SHELL" -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
            $result.Output | Should -Match "/bin/bash"
        }
    }
    
    Context "Development Environment Validation" {
        It "Should have development tools installed" {
            $tools = @(
                @{ Name = "python3"; Command = "python3 --version"; Expected = "Python 3" },
                @{ Name = "node"; Command = "node --version"; Expected = "v" },
                @{ Name = "git"; Command = "git --version"; Expected = "git version" },
                @{ Name = "chezmoi"; Command = "chezmoi --version"; Expected = "chezmoi" },
                @{ Name = "curl"; Command = "curl --version"; Expected = "curl" },
                @{ Name = "wget"; Command = "wget --version"; Expected = "GNU Wget" }
            )
            
            foreach ($tool in $tools) {
                $result = Invoke-WSLDockerCommand -Command $tool.Command -ContainerName $script:ContainerName
                $result.Success | Should -Be $true -Because "$($tool.Name) should be available"
                $result.Output | Should -Match $tool.Expected -Because "$($tool.Name) should return expected output"
            }
        }
        
        It "Should have package managers working" {
            $managers = @(
                @{ Name = "apt"; Command = "apt --version"; Expected = "apt" },
                @{ Name = "pip3"; Command = "pip3 --version"; Expected = "pip" },
                @{ Name = "npm"; Command = "npm --version"; Expected = "\d+\.\d+\.\d+" }
            )
            
            foreach ($manager in $managers) {
                $result = Invoke-WSLDockerCommand -Command $manager.Command -ContainerName $script:ContainerName
                $result.Success | Should -Be $true -Because "$($manager.Name) should be available"
                $result.Output | Should -Match $manager.Expected -Because "$($manager.Name) should return expected output"
            }
        }
        
        It "Should have programming languages available" {
            $languages = @(
                @{ Name = "Python"; Command = "python3 -c 'import sys; print(sys.version)'"; Expected = "3\." },
                @{ Name = "Node.js"; Command = "node -e 'console.log(process.version)'"; Expected = "v\d+" },
                @{ Name = "Go"; Command = "go version"; Expected = "go version" },
                @{ Name = "Rust"; Command = "rustc --version"; Expected = "rustc" }
            )
            
            foreach ($language in $languages) {
                $result = Invoke-WSLDockerCommand -Command $language.Command -ContainerName $script:ContainerName
                $result.Success | Should -Be $true -Because "$($language.Name) should be available"
                $result.Output | Should -Match $language.Expected -Because "$($language.Name) should return expected output"
            }
        }
    }
    
    Context "Package Management Validation" {
        It "Should list installed system packages" {
            $packages = Get-WSLDockerPackages -PackageManager "apt" -ContainerName $script:ContainerName
            $packages.Success | Should -Be $true
            $packages.Count | Should -BeGreaterThan 100
            $packages.Packages | Should -Match "git.*install"
            $packages.Packages | Should -Match "curl.*install"
        }
        
        It "Should list installed Python packages" {
            $packages = Get-WSLDockerPackages -PackageManager "pip3" -ContainerName $script:ContainerName
            $packages.Success | Should -Be $true
            $packages.Count | Should -BeGreaterThan 0
            $packages.Packages | Should -Match "requests=="
        }
        
        It "Should handle package installation simulation" {
            # Test package installation (dry run)
            $result = Invoke-WSLDockerCommand -Command "apt list --installed | grep -E '^(git|curl|wget)/' | wc -l" -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
            [int]$result.Output | Should -BeGreaterThan 2
        }
    }
    
    Context "File System and Permissions Validation" {
        It "Should have proper file permissions" {
            # Test user home directory permissions
            $result = Invoke-WSLDockerCommand -Command "ls -ld /home/testuser" -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
            $result.Output | Should -Match "drwx.*testuser.*testuser"
            
            # Test SSH directory permissions
            $result = Invoke-WSLDockerCommand -Command "ls -ld /home/testuser/.ssh" -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
            $result.Output | Should -Match "drwx------.*testuser"
        }
        
        It "Should handle file operations correctly" {
            $testDir = "/tmp/validation-test-$(Get-Random)"
            
            # Create directory structure
            $result = Invoke-WSLDockerCommand -Command "mkdir -p $testDir/subdir && echo 'test content' > $testDir/test.txt" -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
            
            # Verify structure
            $result = Invoke-WSLDockerCommand -Command "find $testDir -type f -name '*.txt' | wc -l" -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
            [int]$result.Output | Should -Be 1
            
            # Clean up
            Invoke-WSLDockerCommand -Command "rm -rf $testDir" -ContainerName $script:ContainerName | Out-Null
        }
        
        It "Should handle symbolic links correctly" {
            $testFile = "/tmp/test-link-$(Get-Random).txt"
            $linkFile = "/tmp/test-link-$(Get-Random).link"
            
            # Create file and symbolic link
            $result = Invoke-WSLDockerCommand -Command "echo 'link test' > $testFile && ln -s $testFile $linkFile" -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
            
            # Test link
            $result = Invoke-WSLDockerCommand -Command "cat $linkFile" -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
            $result.Output | Should -Be "link test"
            
            # Clean up
            Invoke-WSLDockerCommand -Command "rm -f $testFile $linkFile" -ContainerName $script:ContainerName | Out-Null
        }
    }
    
    Context "Network and Connectivity Validation" {
        It "Should have network connectivity" {
            # Test localhost connectivity
            $result = Invoke-WSLDockerCommand -Command "ping -c 1 localhost > /dev/null 2>&1 && echo 'success'" -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
            $result.Output | Should -Be "success"
        }
        
        It "Should have proper hostname resolution" {
            $result = Invoke-WSLDockerCommand -Command "hostname" -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
            $result.Output | Should -Not -BeNullOrEmpty
        }
        
        It "Should have network tools available" {
            $tools = @("netstat", "ss", "nc")
            foreach ($tool in $tools) {
                $result = Invoke-WSLDockerCommand -Command "which $tool" -ContainerName $script:ContainerName
                $result.Success | Should -Be $true
                $result.Output | Should -Match "/$tool$"
            }
        }
    }
    
    Context "Performance and Resource Validation" {
        It "Should have reasonable system performance" {
            # Test CPU info
            $result = Invoke-WSLDockerCommand -Command "nproc" -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
            [int]$result.Output | Should -BeGreaterThan 0
            
            # Test memory info
            $result = Invoke-WSLDockerCommand -Command "free -m | grep '^Mem:' | awk '{print \$2}'" -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
            [int]$result.Output | Should -BeGreaterThan 100  # At least 100MB
        }
        
        It "Should handle concurrent operations" {
            # Test multiple simultaneous operations
            $jobs = @()
            for ($i = 1; $i -le 3; $i++) {
                $jobs += Start-Job -ScriptBlock {
                    param($ContainerName, $TestId)
                    . "$using:PSScriptRoot\..\utilities\WSL-Docker-Communication.ps1"
                    $result = Invoke-WSLDockerCommand -Command "echo 'Concurrent test $TestId' && sleep 1 && echo 'Done $TestId'" -ContainerName $ContainerName
                    return $result
                } -ArgumentList $script:ContainerName, $i
            }
            
            # Wait for all jobs to complete
            $results = $jobs | Wait-Job | Receive-Job
            $jobs | Remove-Job
            
            # Verify all jobs succeeded
            $results | ForEach-Object { $_.Success | Should -Be $true }
            $results.Count | Should -Be 3
        }
    }
    
    Context "Communication Method Comparison" {
        It "Should produce consistent results between Docker exec and SSH" -Skip:(-not $script:SSHConnectivity) {
            $testCommand = "echo 'consistency test' && whoami && pwd"
            
            # Execute via Docker exec
            $dockerResult = Invoke-WSLDockerCommand -Command $testCommand -ContainerName $script:ContainerName
            
            # Execute via SSH
            $sshResult = Invoke-WSLSSHCommand -Command $testCommand
            
            # Both should succeed
            $dockerResult.Success | Should -Be $true
            $sshResult.Success | Should -Be $true
            
            # Results should be similar (allowing for minor formatting differences)
            $dockerResult.Output | Should -Match "consistency test"
            $sshResult.Output | Should -Match "consistency test"
            $dockerResult.Output | Should -Match "testuser"
            $sshResult.Output | Should -Match "testuser"
        }
        
        It "Should handle file operations consistently" -Skip:(-not $script:SSHConnectivity) {
            $testFile = "/tmp/consistency-test-$(Get-Random).txt"
            $testContent = "Consistency test content"
            
            # Create file via Docker exec
            $dockerCreate = Invoke-WSLDockerCommand -Command "echo '$testContent' > $testFile" -ContainerName $script:ContainerName
            $dockerCreate.Success | Should -Be $true
            
            # Read file via SSH
            $sshRead = Invoke-WSLSSHCommand -Command "cat $testFile"
            $sshRead.Success | Should -Be $true
            $sshRead.Output | Should -Be $testContent
            
            # Clean up via Docker exec
            Invoke-WSLDockerCommand -Command "rm -f $testFile" -ContainerName $script:ContainerName | Out-Null
        }
    }
} 