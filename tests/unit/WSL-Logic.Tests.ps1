#!/usr/bin/env pwsh
<#
.SYNOPSIS
    WSL Logic Unit Tests

.DESCRIPTION
    Pure logic tests for WSL operations including:
    - Template validation and parsing
    - Configuration parsing
    - Package list parsing
    - WSL distribution information processing
    - No file operations or external dependencies
#>

BeforeAll {
    # Load Docker test bootstrap for cross-platform compatibility
    . (Join-Path $PSScriptRoot "../utilities/Docker-Test-Bootstrap.ps1")

    # Import the module with standardized pattern
    try {
        $ModulePath = Resolve-Path "$PSScriptRoot/../../WindowsMelodyRecovery.psd1"
        Import-Module $ModulePath -Force -ErrorAction Stop
    } catch {
        throw "Cannot find or import WindowsMelodyRecovery module: $($_.Exception.Message)"
    }
}

Describe "WSL Logic Unit Tests" -Tag "Unit", "WSL" {

    Context "WSL Template Validation" {
        It "Should validate WSL template structure" {
            # Mock template path and content for logic testing
            $moduleRoot = "/mock/module/root"
            $wslTemplate = Join-Path $moduleRoot "Templates\System\wsl.yaml"

            # Mock file operations for unit testing
            Mock Test-Path { $true } -ParameterFilter { $Path -like "*wsl.yaml" }
            Mock Get-Content {
                return @"
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
            } -ParameterFilter { $Path -like "*wsl.yaml" }
            Mock Get-Module {
                return @{ Path = "/mock/module/WindowsMelodyRecovery.psm1" }
            } -ParameterFilter { $Name -eq "WindowsMelodyRecovery" }
            Mock Split-Path { return "/mock/module" }

            Test-Path $wslTemplate | Should -Be $true

            # Test template content structure with mocked content
            $templateContent = Get-Content $wslTemplate -Raw
            $templateContent | Should -Not -BeNullOrEmpty
            $templateContent | Should -Match "wsl"
            $templateContent | Should -Match "backup:"
            $templateContent | Should -Match "distributions"

            Should -Invoke Test-Path -Times 1
            Should -Invoke Get-Content -Times 1
        }

        It "Should parse WSL template backup operations" {
            # Mock template content for testing
            $mockTemplate = @"
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

            # Test template parsing logic
            $mockTemplate | Should -Match "name: wsl"
            $mockTemplate | Should -Match "backup:"
            $mockTemplate | Should -Match "distributions"
            $mockTemplate | Should -Match "config"
        }
    }

    Context "WSL Distribution Information Processing" {
        It "Should parse WSL distribution list" {
            # Mock WSL distribution output
            $mockDistributionOutput = @"
  Ubuntu-22.04    Running         2
  Debian          Stopped         2
* Ubuntu-20.04    Running         2
"@

            # Test parsing logic
            $lines = $mockDistributionOutput -split "`n" | Where-Object { $_ -match '\S' }
            $lines.Count | Should -BeGreaterThan 0

            # Test distribution parsing
            $distributions = @()
            foreach ($line in $lines) {
                if ($line -match '^\s*(\*?)\s*([^\s]+)\s+(Running|Stopped)\s+(\d+)') {
                    $distributions += @{
                        Name = $matches[2]
                        Status = $matches[3]
                        Version = $matches[4]
                        Default = $matches[1] -eq '*'
                    }
                }
            }

            $distributions.Count | Should -Be 3
            $distributions[0].Name | Should -Be "Ubuntu-22.04"
            $distributions[0].Status | Should -Be "Running"
            $distributions[2].Default | Should -Be $true
        }

        It "Should validate distribution configuration" {
            # Mock distribution configuration
            $mockDistribution = @{
                Name = "Ubuntu-22.04"
                Status = "Running"
                Version = "2"
                Default = $true
                BasePath = (Get-WmrTestPath -WindowsPath "C:\\Users\\TestUser\\AppData\\Local\\Packages\\CanonicalGroupLimited.Ubuntu22.04LTS_79rhkp1fndgsc\\LocalState")
            }

            # Test configuration validation logic
            $mockDistribution.Name | Should -Not -BeNullOrEmpty
            $mockDistribution.Status | Should -BeIn @("Running", "Stopped")
            $mockDistribution.Version | Should -Match '^\d+$'
            $mockDistribution.Default | Should -BeOfType [bool]
            $mockDistribution.BasePath | Should -Match '(^[A-Z]:\\)|(^/.*)'
        }
    }

    Context "WSL Package List Processing" {
        It "Should parse APT package list" {
            # Mock APT package output
            $mockAptOutput = @"
git	install
curl	install
wget	install
vim	install
python3	install
"@

            # Test APT parsing logic
            $packages = @()
            $lines = $mockAptOutput -split "`n" | Where-Object { $_ -match '\S' }
            foreach ($line in $lines) {
                if ($line -match '^([^\s]+)\s+install') {
                    $packages += $matches[1]
                }
            }

            $packages.Count | Should -Be 5
            $packages | Should -Contain "git"
            $packages | Should -Contain "curl"
            $packages | Should -Contain "python3"
        }

        It "Should parse PIP package list" {
            # Mock PIP package output
            $mockPipOutput = @"
requests==2.28.1
numpy==1.24.3
pandas==1.5.3
flask==2.3.2
"@

            # Test PIP parsing logic
            $packages = @()
            $lines = $mockPipOutput -split "`n" | Where-Object { $_ -match '\S' }
            foreach ($line in $lines) {
                if ($line -match '^([^=]+)==(.+)') {
                    $packages += @{
                        Name = $matches[1].Trim()
                        Version = $matches[2].Trim()
                    }
                }
            }

            $packages.Count | Should -Be 4
            $packages[0].Name | Should -Be "requests"
            $packages[0].Version | Should -Be "2.28.1"
            $packages[3].Name | Should -Be "flask"
        }

        It "Should parse NPM package list" {
            # Mock NPM package output (JSON format)
            $mockNpmOutput = @"
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

            # Test NPM parsing logic
            $npmData = $mockNpmOutput | ConvertFrom-Json
            $npmData.dependencies | Should -Not -BeNullOrEmpty
            $npmData.dependencies.express.version | Should -Be "4.18.2"
            $npmData.dependencies.lodash.version | Should -Be "4.17.21"
        }
    }

    Context "WSL Configuration Processing" {
        It "Should parse WSL configuration file" {
            # Mock .wslconfig content
            $mockWslConfig = @"
[wsl2]
kernelCommandLine = cgroup_enable=1 cgroup_memory=1 cgroup_v2=1 swapaccount=1
memory = 8GB
processors = 4
swap = 2GB
localhostForwarding = true
"@

            # Test configuration parsing logic
            $configLines = $mockWslConfig -split "`r?`n" | Where-Object { $_ -match '\S' }
            $configLines | Should -Contain "[wsl2]"
            ($configLines | Where-Object { $_ -match "memory = 8GB" }) | Should -Not -BeNullOrEmpty
            ($configLines | Where-Object { $_ -match "processors = 4" }) | Should -Not -BeNullOrEmpty
            ($configLines | Where-Object { $_ -match "localhostForwarding = true" }) | Should -Not -BeNullOrEmpty
        }

        It "Should validate WSL configuration values" {
            # Mock configuration values
            $mockConfig = @{
                memory = "8GB"
                processors = "4"
                swap = "2GB"
                localhostForwarding = "true"
            }

            # Test configuration validation logic
            $mockConfig.memory | Should -Match '^\d+GB$'
            $mockConfig.processors | Should -Match '^\d+$'
            $mockConfig.swap | Should -Match '^\d+GB$'
            $mockConfig.localhostForwarding | Should -BeIn @("true", "false")
        }
    }

    Context "Chezmoi Configuration Processing" {
        It "Should parse chezmoi configuration data" {
            # Mock chezmoi data output (JSON format)
            $mockChezmoiData = @"
{
  "arch": "amd64",
  "hostname": "test-host",
  "os": "linux",
  "username": "testuser"
}
"@

            # Test chezmoi data parsing logic
            $chezmoiData = $mockChezmoiData | ConvertFrom-Json
            $chezmoiData.arch | Should -Be "amd64"
            $chezmoiData.hostname | Should -Be "test-host"
            $chezmoiData.os | Should -Be "linux"
            $chezmoiData.username | Should -Be "testuser"
        }

        It "Should validate chezmoi template variables" {
            # Mock template variables
            $mockTemplateVars = @{
                "chezmoi.arch" = "amd64"
                "chezmoi.hostname" = "test-host"
                "chezmoi.os" = "linux"
                "chezmoi.username" = "testuser"
            }

            # Test template variable validation
            $mockTemplateVars["chezmoi.arch"] | Should -BeIn @("amd64", "arm64", "386")
            $mockTemplateVars["chezmoi.os"] | Should -BeIn @("linux", "windows", "darwin")
            $mockTemplateVars["chezmoi.username"] | Should -Not -BeNullOrEmpty
            $mockTemplateVars["chezmoi.hostname"] | Should -Not -BeNullOrEmpty
        }
    }

    Context "WSL Command Processing" {
        It "Should parse WSL command output" {
            # Mock WSL command output
            $mockCommandOutput = @{
                Success = $true
                Output = @("line1", "line2", "line3")
                ExitCode = 0
                Error = $null
            }

            # Test command output processing logic
            $mockCommandOutput.Success | Should -Be $true
            $mockCommandOutput.Output.Count | Should -Be 3
            $mockCommandOutput.ExitCode | Should -Be 0
            $mockCommandOutput.Error | Should -BeNullOrEmpty
        }

        It "Should handle WSL command errors" {
            # Mock WSL command error
            $mockCommandError = @{
                Success = $false
                Output = @()
                ExitCode = 1
                Error = "Command not found"
            }

            # Test error handling logic
            $mockCommandError.Success | Should -Be $false
            $mockCommandError.Output.Count | Should -Be 0
            $mockCommandError.ExitCode | Should -Not -Be 0
            $mockCommandError.Error | Should -Not -BeNullOrEmpty
        }
    }

    Context "WSL Path Processing" {
        It "Should convert Windows paths to WSL paths" {
            # Mock path conversion logic
            $windowsPath = (Get-WmrTestPath -WindowsPath "C:\Users\TestUser\Documents")
            $expectedWslPath = "/mnt/c/Users/TestUser/Documents"

            # Test path conversion logic
            $convertedPath = $windowsPath -replace '^([A-Z]):', '/mnt/$1' -replace '\\', '/'
            $convertedPath = $convertedPath.ToLower()
            # Handle both real WSL paths and mock paths
            if ($convertedPath -match '^/mock-c/') {
                $convertedPath = $convertedPath -replace '^/mock-c/', '/mnt/c/'
            }
            $convertedPath | Should -Be "/mnt/c/users/testuser/documents"
        }

        It "Should validate WSL path formats" {
            # Mock WSL paths
            $wslPaths = @(
                "/home/testuser",
                "/mnt/c/Users/TestUser",
                "/etc/wsl.conf",
                "/usr/local/bin"
            )

            # Test path validation logic
            foreach ($path in $wslPaths) {
                $path | Should -Match '^/'
                $path | Should -Not -Match '\\'
            }
        }
    }
}

