#!/usr/bin/env pwsh
<#
.SYNOPSIS
    WSL Integration Tests (Docker Mock)

.DESCRIPTION
    Integration tests for WSL functionality using a mocked Docker container.
    These tests are cross-platform and do not require a real WSL installation.
    They validate the module's logic for communicating with a WSL-like environment.
#>

BeforeAll {
    # Import the unified test environment library and initialize it for Integration tests.
    . (Join-Path $PSScriptRoot "..\utilities\Test-Environment.ps1")
    $script:TestEnvironment = Initialize-WmrTestEnvironment -SuiteName 'Integration'

    # Import the main module to make functions available for testing.
    Import-Module (Join-Path $script:TestEnvironment.ModuleRoot "WindowsMelodyRecovery.psd1") -Force

    # Import WSL Docker communication utilities
    . (Join-Path $script:TestEnvironment.ModuleRoot "tests/utilities/WSL-Docker-Communication.ps1")

    # Setup test environment paths
    $script:TestBackupRoot = $script:TestEnvironment.TestBackup
    $script:WSLDistro = $env:WMR_WSL_DISTRO ?? "Ubuntu-22.04"
    $script:ContainerName = "wmr-wsl-mock"

    # Test WSL container connectivity
    Write-Information -MessageData "Testing WSL container connectivity..." -InformationAction Continue
    $script:WSLConnectivity = Test-WSLDockerConnectivity -ContainerName $script:ContainerName
    if ($script:WSLConnectivity) {
        Write-Information -MessageData "WSL Docker container connectivity: PASSED" -InformationAction Continue
    }
    else {
        Write-Error -Message "WSL Docker container connectivity: FAILED"
    }
}

AfterAll {
    # Clean up the test environment created in BeforeAll.
    Remove-WmrTestEnvironment
}

Describe "WSL Integration Tests (Docker Mock)" -Tag "Integration", "WSL" {

    Context "WSL Container Communication" {
        It "Should have working WSL Docker container communication" {
            if ($script:WSLConnectivity) {
                $script:WSLConnectivity | Should -Be $true
            }
            else {
                Set-ItResult -Skipped -Because "WSL Docker container not available"
            }
        }

        It "Should list WSL distributions via container" {
            if ($script:WSLConnectivity) {
                $distributions = Get-WSLDockerDistributions -ContainerName $script:ContainerName
                $distributions | Should -Not -BeNullOrEmpty
                $distributions.Name | Should -Be "Ubuntu-22.04"
                $distributions.Status | Should -Be "Running"
            }
            else {
                Set-ItResult -Skipped -Because "WSL Docker container not available"
            }
        }

        It "Should execute commands in WSL container" {
            if ($script:WSLConnectivity) {
                $result = Invoke-WSLDockerCommand -Command "whoami" -ContainerName $script:ContainerName
                $result.Success | Should -Be $true
                $result.Output | Should -Be "testuser"
            }
            else {
                Set-ItResult -Skipped -Because "WSL Docker container not available"
            }
        }

        It "Should handle command execution errors gracefully" {
            if ($script:WSLConnectivity) {
                $result = Invoke-WSLDockerCommand -Command "nonexistentcommand" -ContainerName $script:ContainerName
                $result.Success | Should -Be $false
                $result.ExitCode | Should -Not -Be 0
            }
            else {
                Set-ItResult -Skipped -Because "WSL Docker container not available"
            }
        }
    }

    Context "WSL Environment Validation" {
        It "Should have proper user environment" {
            if ($script:WSLConnectivity) {
                $result = Invoke-WSLDockerCommand -Command "echo `$HOME" -ContainerName $script:ContainerName
                $result.Success | Should -Be $true
                $result.Output | Should -Be "/home/testuser"
            }
            else {
                Set-ItResult -Skipped -Because "WSL Docker container not available"
            }
        }

        It "Should have development tools available" {
            if ($script:WSLConnectivity) {
                $tools = @("python3", "node", "git", "chezmoi")
                foreach ($tool in $tools) {
                    $result = Invoke-WSLDockerCommand -Command "which $tool" -ContainerName $script:ContainerName
                    $result.Success | Should -Be $true
                    $result.Output | Should -Not -BeNullOrEmpty
                }
            }
            else {
                Set-ItResult -Skipped -Because "WSL Docker container not available"
            }
        }

        It "Should have package managers available" {
            if ($script:WSLConnectivity) {
                $managers = @("apt", "pip3", "npm")
                foreach ($manager in $managers) {
                    $result = Invoke-WSLDockerCommand -Command "$manager --version" -ContainerName $script:ContainerName
                    $result.Success | Should -Be $true
                    $result.Output | Should -Not -BeNullOrEmpty
                }
            }
            else {
                Set-ItResult -Skipped -Because "WSL Docker container not available"
            }
        }

        It "Should have proper PATH environment" {
            if ($script:WSLConnectivity) {
                $result = Invoke-WSLDockerCommand -Command "echo `$PATH" -ContainerName $script:ContainerName
                $result.Success | Should -Be $true
                $result.Output | Should -Match "/usr/bin"
                $result.Output | Should -Match "/usr/local/bin"
            }
            else {
                Set-ItResult -Skipped -Because "WSL Docker container not available"
            }
        }
    }

    Context "WSL Package Management Integration" {
        It "Should list installed APT packages" {
            if ($script:WSLConnectivity) {
                $packages = Get-WSLDockerPackages -PackageManager "apt" -ContainerName $script:ContainerName
                $packages.Success | Should -Be $true
                $packages.Count | Should -BeGreaterThan 100
                $packages.Packages | Should -Match "install"
            }
            else {
                Set-ItResult -Skipped -Because "WSL Docker container not available"
            }
        }

        It "Should list installed Python packages" {
            if ($script:WSLConnectivity) {
                $packages = Get-WSLDockerPackages -PackageManager "pip3" -ContainerName $script:ContainerName
                $packages.Success | Should -Be $true
                $packages.Count | Should -BeGreaterThan 0
                $packages.Packages | Should -Match "=="
            }
            else {
                Set-ItResult -Skipped -Because "WSL Docker container not available"
            }
        }

        It "Should list installed Node.js packages" {
            if ($script:WSLConnectivity) {
                $packages = Get-WSLDockerPackages -PackageManager "npm" -ContainerName $script:ContainerName
                $packages.Success | Should -Be $true
                # NPM global packages might be empty, so just check it doesn't error
                $packages.Packages | Should -Not -BeNullOrEmpty
            }
            else {
                Set-ItResult -Skipped -Because "WSL Docker container not available"
            }
        }

        It "Should backup APT packages" {
            if ($script:WSLConnectivity) {
                # Test APT package backup via Docker mock
                $result = Get-WSLDockerPackages -PackageManager "apt" -ContainerName $script:ContainerName
                $result.Success | Should -Be $true
                $result.Packages | Should -Not -BeNullOrEmpty
                $result.Packages | Should -Contain "install"
            }
            else {
                Set-ItResult -Skipped -Because "WSL Docker container not available"
            }
        }

        It "Should backup NPM packages" {
            if ($script:WSLConnectivity) {
                # Test NPM package backup via Docker mock
                $result = Get-WSLDockerPackages -PackageManager "npm" -ContainerName $script:ContainerName
                $result.Success | Should -Be $true
                $result.Packages | Should -Not -BeNullOrEmpty
            }
            else {
                Set-ItResult -Skipped -Because "WSL Docker container not available"
            }
        }

        It "Should backup PIP packages" {
            if ($script:WSLConnectivity) {
                # Test PIP package backup
                $result = Invoke-WSLDockerCommand -Command "pip3 list --format=freeze 2>/dev/null || echo '# No packages'" -ContainerName $script:ContainerName

                $result | Should -Not -BeNullOrEmpty
            }
            else {
                Set-ItResult -Skipped -Because "WSL Docker container not available"
            }
        }

        It "Should handle package installation" {
            if ($script:WSLConnectivity) {
                # Test installing a simple package
                $result = Invoke-WSLDockerCommand -Command "sudo apt update && sudo apt install -y tree && tree --version" -ContainerName $script:ContainerName

                $result | Should -Match "tree"
            }
            else {
                Set-ItResult -Skipped -Because "WSL Docker container not available"
            }
        }

        It "Should handle package manager operations via container" {
            if ($script:WSLConnectivity) {
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
            else {
                Set-ItResult -Skipped -Because "WSL Docker container not available"
            }
        }
    }

    Context "WSL File System Operations" {
        It "Should handle file operations in WSL" {
            if ($script:WSLConnectivity) {
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
            else {
                Set-ItResult -Skipped -Because "WSL Docker container not available"
            }
        }

        It "Should handle directory operations in WSL" {
            if ($script:WSLConnectivity) {
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
            else {
                Set-ItResult -Skipped -Because "WSL Docker container not available"
            }
        }

        It "Should handle permission checks" {
            if ($script:WSLConnectivity) {
                # Test readable file
                $result = Invoke-WSLDockerCommand -Command "test -r /home/testuser/.bashrc && echo 'readable'" -ContainerName $script:ContainerName
                $result.Success | Should -Be $true
                $result.Output | Should -Be "readable"

                # Test writable directory
                $result = Invoke-WSLDockerCommand -Command "test -w /home/testuser && echo 'writable'" -ContainerName $script:ContainerName
                $result.Success | Should -Be $true
                $result.Output | Should -Be "writable"
            }
            else {
                Set-ItResult -Skipped -Because "WSL Docker container not available"
            }
        }
    }

    Context "Chezmoi Integration" {
        It "Should detect chezmoi installation" -Skip:(-not $script:WSLAvailable) {
            if ($script:WSLAvailable) {
                $result = wsl -d $script:WSLDistro -u testuser -- bash -c "chezmoi --version"

                $result | Should -Not -BeNullOrEmpty
                $result | Should -Match "chezmoi"
            }
            else {
                Set-ItResult -Skipped -Because "WSL not available"
            }
        }

        It "Should have chezmoi installed and accessible via container" {
            if ($script:WSLConnectivity) {
                $result = Invoke-WSLDockerCommand -Command "chezmoi --version" -ContainerName $script:ContainerName
                $result.Success | Should -Be $true
                $result.Output | Should -Match "chezmoi"
            }
            else {
                Set-ItResult -Skipped -Because "WSL Docker container not available"
            }
        }

        It "Should have chezmoi configuration directory" {
            if ($script:WSLConnectivity) {
                $result = Invoke-WSLDockerCommand -Command "test -d /home/testuser/.config/chezmoi && echo 'exists'" -ContainerName $script:ContainerName
                $result.Success | Should -Be $true
                $result.Output | Should -Be "exists"
            }
            else {
                Set-ItResult -Skipped -Because "WSL Docker container not available"
            }
        }

        It "Should have chezmoi source directory" {
            if ($script:WSLConnectivity) {
                $result = Invoke-WSLDockerCommand -Command "test -d /home/testuser/.local/share/chezmoi && echo 'exists'" -ContainerName $script:ContainerName
                $result.Success | Should -Be $true
                $result.Output | Should -Be "exists"
            }
            else {
                Set-ItResult -Skipped -Because "WSL Docker container not available"
            }
        }

        It "Should have valid chezmoi configuration" {
            if ($script:WSLConnectivity) {
                $result = Invoke-WSLDockerCommand -Command "chezmoi doctor" -ContainerName $script:ContainerName
                $result.Success | Should -Be $true
                # chezmoi doctor should not report critical errors
                $result.Output | Should -Not -Match "FATAL|ERROR"
            }
            else {
                Set-ItResult -Skipped -Because "WSL Docker container not available"
            }
        }

        It "Should show chezmoi status without errors" {
            if ($script:WSLConnectivity) {
                $result = Invoke-WSLDockerCommand -Command "chezmoi status" -ContainerName $script:ContainerName
                $result.Success | Should -Be $true
            }
            else {
                Set-ItResult -Skipped -Because "WSL Docker container not available"
            }
        }

        It "Should list chezmoi managed files" {
            if ($script:WSLConnectivity) {
                $result = Invoke-WSLDockerCommand -Command "chezmoi managed" -ContainerName $script:ContainerName
                $result.Success | Should -Be $true
            }
            else {
                Set-ItResult -Skipped -Because "WSL Docker container not available"
            }
        }

        It "Should show chezmoi data" {
            if ($script:WSLConnectivity) {
                $result = Invoke-WSLDockerCommand -Command "chezmoi data" -ContainerName $script:ContainerName
                $result.Success | Should -Be $true
                # Check that the output contains JSON with arch and username (use -match with multiline)
                ($result.Output -join "`n") | Should -Match "arch.*amd64"
                ($result.Output -join "`n") | Should -Match "username.*testuser"
            }
            else {
                Set-ItResult -Skipped -Because "WSL Docker container not available"
            }
        }

        It "Should initialize chezmoi" -Skip:(-not $script:WSLAvailable) {
            if ($script:WSLAvailable) {
                # Test chezmoi initialization
                $result = wsl -d $script:WSLDistro -u testuser -- bash -c @"
cd /home/testuser
chezmoi init --apply
chezmoi status
"@

                # Should not throw errors
                $LASTEXITCODE | Should -Be 0
                $result | Should -Not -BeNullOrEmpty
            }
            else {
                Set-ItResult -Skipped -Because "WSL not available"
            }
        }

        It "Should backup chezmoi configuration" -Skip:(-not $script:WSLAvailable) {
            if ($script:WSLAvailable) {
                # Test chezmoi source directory backup
                $result = wsl -d $script:WSLDistro -u testuser -- bash -c "ls -la ~/.local/share/chezmoi 2>/dev/null || echo 'not initialized'"

                $result | Should -Not -BeNullOrEmpty
            }
            else {
                Set-ItResult -Skipped -Because "WSL not available"
            }
        }
    }

    Context "WSL Template Integration" {
        It "Should process WSL template for backup operations" {
            # Test template-based WSL backup
            $templatePath = "Templates/System/wsl.yaml"
            $moduleRoot = Split-Path (Get-Module WindowsMelodyRecovery).Path -Parent
            $fullTemplatePath = Join-Path $moduleRoot $templatePath

            if (Test-Path $fullTemplatePath) {
                # Test template processing
                $backupPath = Join-Path $script:TestBackupRoot "template-test"
                if (-not (Test-Path $backupPath)) {
                    New-Item -Path $backupPath -ItemType Directory -Force | Out-Null
                }

                # Mock template-based backup using Invoke-WmrTemplate
                try {
                    Invoke-WmrTemplate -TemplatePath $fullTemplatePath -Operation "Backup" -StateFilesDirectory $backupPath
                    $templateProcessed = $true
                }
                catch {
                    $templateProcessed = $false
                    Write-Warning "Template processing failed: $($_.Exception.Message)"
                }

                # Template should be processed without errors
                $templateProcessed | Should -Be $true
            }
            else {
                Set-ItResult -Skipped -Because "wsl.yaml template not found"
            }
        }
    }

    Context "WSL Communication Validation" {
        It "Should execute basic commands via Docker exec" {
            if ($script:WSLConnectivity) {
                $result = Invoke-WSLDockerCommand -Command "echo 'Docker exec test'" -ContainerName $script:ContainerName
                $result.Success | Should -Be $true
                $result.Output | Should -Be "Docker exec test"
            }
            else {
                Set-ItResult -Skipped -Because "WSL Docker container not available"
            }
        }

        It "Should handle complex commands via Docker exec" {
            if ($script:WSLConnectivity) {
                $complexCommand = "ls /home | wc -l"
                $result = Invoke-WSLDockerCommand -Command $complexCommand -ContainerName $script:ContainerName
                $result.Success | Should -Be $true
                [int]$result.Output | Should -BeGreaterThan 0
            }
            else {
                Set-ItResult -Skipped -Because "WSL Docker container not available"
            }
        }

        It "Should execute multi-line scripts via Docker exec" {
            if ($script:WSLConnectivity) {
                $script = @"
echo "Multi-line script test"
cd /tmp
touch test-file-$(Get-Date +%s).txt
ls -la test-file-*.txt | wc -l
rm -f test-file-*.txt
"@

                $result = Invoke-WSLDockerScript -ScriptContent $script -ContainerName $script:ContainerName
                $result.Success | Should -Be $true
                $result.Output | Should -Match "Multi-line script test"
            }
            else {
                Set-ItResult -Skipped -Because "WSL Docker container not available"
            }
        }

        It "Should handle environment variables via Docker exec" {
            if ($script:WSLConnectivity) {
                $result = Invoke-WSLDockerCommand -Command "echo `$HOME:`$USER" -ContainerName $script:ContainerName
                $result.Success | Should -Be $true
                $result.Output | Should -Match "/home/testuser:testuser"
            }
            else {
                Set-ItResult -Skipped -Because "WSL Docker container not available"
            }
        }
    }
}







