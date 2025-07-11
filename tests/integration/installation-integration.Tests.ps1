#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Integration tests for Windows Melody Recovery installation and initialization

.DESCRIPTION
    Tests the complete installation and initialization workflow in a Docker environment.
#>

BeforeAll {
    # Import Pester for Mock functionality
    Import-Module Pester -Force

    # Import test utilities
    . $PSScriptRoot/../utilities/Test-Utilities.ps1
    . $PSScriptRoot/../utilities/Mock-Utilities.ps1

    # For Docker testing, use the installed module
    $moduleInfo = Get-Module -ListAvailable WindowsMelodyRecovery | Select-Object -First 1
    if ($moduleInfo) {
        $TestModulePath = $moduleInfo.Path
        $TestManifestPath = Join-Path $moduleInfo.ModuleBase "WindowsMelodyRecovery.psd1"
        $modulePath = $moduleInfo.ModuleBase
    } else {
        # Fallback to relative paths for local testing
        $TestModulePath = Join-Path $PSScriptRoot "../../WindowsMelodyRecovery.psm1"
        $TestManifestPath = Join-Path $PSScriptRoot "../../WindowsMelodyRecovery.psd1"
        $modulePath = Join-Path $PSScriptRoot "../.."
    }
    $TestInstallScriptPath = Join-Path $PSScriptRoot "../../Install-Module.ps1"

    # Create temporary test directory
    $tempPath = if ($env:TEMP) { $env:TEMP } else { "/tmp" }
    $TestTempDir = Join-Path $tempPath "WindowsMelodyRecovery-Integration-Tests"
    if (-not (Test-Path $TestTempDir)) {
        New-Item -Path $TestTempDir -ItemType Directory -Force | Out-Null
    }

    # Mock environment variables for testing
    $env:WMR_CONFIG_PATH = $TestTempDir
    $env:WMR_BACKUP_PATH = Join-Path $TestTempDir "backups"
    $env:WMR_LOG_PATH = Join-Path $TestTempDir "logs"
}

Describe "Windows Melody Recovery - Installation Integration Tests" -Tag "Installation" {

    Context "Module Installation Process" {
        It "Should have all required installation files" {
            # Check core files
            Test-Path $TestModulePath | Should -Be $true
            Test-Path $TestManifestPath | Should -Be $true
            Test-Path $TestInstallScriptPath | Should -Be $true

            # Check public functions
            $publicFunctions = Get-ChildItem -Path (Join-Path $modulePath "Public") -Filter "*.ps1" -ErrorAction SilentlyContinue
            $publicFunctions.Count | Should -BeGreaterThan 0

            # Check private functions
            $privateFunctions = Get-ChildItem -Path (Join-Path $modulePath "Private") -Recurse -Filter "*.ps1" -ErrorAction SilentlyContinue
            $privateFunctions.Count | Should -BeGreaterThan 0
        }

        It "Should have valid PowerShell syntax in all scripts" {
            $allScripts = @(
                $TestModulePath,
                $TestInstallScriptPath
            ) + (Get-ChildItem -Path (Join-Path $modulePath "Public") -Filter "*.ps1" -ErrorAction SilentlyContinue).FullName +
               (Get-ChildItem -Path (Join-Path $modulePath "Private") -Recurse -Filter "*.ps1" -ErrorAction SilentlyContinue).FullName

            foreach ($script in $allScripts) {
                if (Test-Path $script) {
                    { [System.Management.Automation.PSParser]::Tokenize((Get-Content $script -Raw), [ref]$null) } | Should -Not -Throw
                }
            }
        }

        It "Should have proper module manifest structure" {
            $manifest = Import-PowerShellDataFile $TestManifestPath

            # Required fields
            $manifest.ModuleVersion | Should -Not -BeNullOrEmpty
            $manifest.Author | Should -Not -BeNullOrEmpty
            $manifest.Description | Should -Not -BeNullOrEmpty
            $manifest.PowerShellVersion | Should -Not -BeNullOrEmpty

            # Optional but recommended fields
            $manifest.PrivateData.PSData.ProjectUri | Should -Not -BeNullOrEmpty
            $manifest.PrivateData.PSData.LicenseUri | Should -Not -BeNullOrEmpty
            $manifest.PrivateData.PSData.Tags | Should -Not -BeNullOrEmpty
        }
    }

    Context "Module Import and Loading" {
        It "Should import module successfully" {
            { Import-Module $TestModulePath -Force -ErrorAction Stop } | Should -Not -Throw
        }

        It "Should export all expected functions" {
            Import-Module $TestModulePath -Force

            $exportedFunctions = Get-Command -Module WindowsMelodyRecovery -ErrorAction SilentlyContinue
            $exportedFunctions | Should -Not -BeNullOrEmpty

            # Check for core functions
            $coreFunctions = @(
                'Initialize-WindowsMelodyRecovery',
                'Get-WindowsMelodyRecoveryStatus',
                'Backup-WindowsMelodyRecovery',
                'Restore-WindowsMelodyRecovery',
                'Setup-WindowsMelodyRecovery'
            )

            foreach ($function in $coreFunctions) {
                Get-Command $function -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
            }
        }

        It "Should load all private functions" {
            Import-Module $TestModulePath -Force

            # Debug: List all available functions from the module
            Write-Warning -Message "Available functions after module import:"
            Get-Command -Module WindowsMelodyRecovery | ForEach-Object { Write-Verbose -Message "  - $($_.Name)" }

            # Check for key core functions (they should be available after import)
            $coreFunctions = @(
                'Get-WmrRegistryState',
                'Get-WmrFileState',
                'Invoke-WmrTemplate'
            )

            foreach ($function in $coreFunctions) {
                $cmd = Get-Command $function -ErrorAction SilentlyContinue
                if ($cmd) {
                    Write-Information -MessageData "✓ Found core function: $function" -InformationAction Continue
                } else {
                    Write-Error -Message "✗ Missing core function: $function"
                }
                $cmd | Should -Not -BeNullOrEmpty
            }
        }
    }
}

Describe "Windows Melody Recovery - Initialization Integration Tests" -Tag "Initialization" {

    BeforeAll {
        Import-Module $TestModulePath -Force
    }

    Context "Environment Initialization" {
        It "Should initialize with default configuration" {
            { Initialize-WindowsMelodyRecovery -NoPrompt -ErrorAction Stop } | Should -Not -Throw
        }

        It "Should create required directories" {
            $configPath = Join-Path $TestTempDir "default-config"
            # Ensure parent directory exists
            $parentDir = Split-Path $configPath -Parent
            if (-not (Test-Path $parentDir)) {
                New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
            }
            Initialize-WindowsMelodyRecovery -InstallPath $configPath -NoPrompt

            $expectedDirs = @(
                (Join-Path $configPath "Config")
            )

            foreach ($dir in $expectedDirs) {
                Test-Path $dir | Should -Be $true
            }
        }

        It "Should copy template files correctly" {
            $configPath = Join-Path $TestTempDir "template-test"
            # Ensure parent directory exists
            $parentDir = Split-Path $configPath -Parent
            if (-not (Test-Path $parentDir)) {
                New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
            }
            Initialize-WindowsMelodyRecovery -InstallPath $configPath -NoPrompt

            $configDir = Join-Path $configPath "Config"

            # Check if configuration file was created
            $configFile = Join-Path $configDir "windows.env"
            Test-Path $configFile | Should -Be $true
        }

        It "Should set environment variables" {
            $configPath = Join-Path $TestTempDir "env-test"
            # Ensure parent directory exists
            $parentDir = Split-Path $configPath -Parent
            if (-not (Test-Path $parentDir)) {
                New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
            }
            Initialize-WindowsMelodyRecovery -InstallPath $configPath -NoPrompt

            # Check if configuration file contains expected variables
            $configFile = Join-Path $configPath "Config\windows.env"
            $configContent = Get-Content $configFile -ErrorAction SilentlyContinue
            $configContent | Should -Not -BeNullOrEmpty
        }
    }

    Context "Status and Health Checks" {
        It "Should return valid status information" {
            $status = Get-WindowsMelodyRecoveryStatus

            $status | Should -Not -BeNullOrEmpty
            $status.ModuleVersion | Should -Not -BeNullOrEmpty
            $status.InitializationStatus | Should -Not -BeNullOrEmpty
            $status.ConfigurationPath | Should -Not -BeNullOrEmpty
        }

        It "Should detect initialization state correctly" {
            $status = Get-WindowsMelodyRecoveryStatus

            if ($status.InitializationStatus -eq "Initialized") {
                $status.ConfigurationPath | Should -Not -BeNullOrEmpty
                Test-Path $status.ConfigurationPath | Should -Be $true
            }
        }

        It "Should provide detailed status information" {
            $status = Get-WindowsMelodyRecoveryStatus -Detailed

            $status | Should -Not -BeNullOrEmpty
            $status.ModuleVersion | Should -Not -BeNullOrEmpty
            $status.PowerShellVersion | Should -Not -BeNullOrEmpty
            $status.OperatingSystem | Should -Not -BeNullOrEmpty
        }
    }

    Context "Configuration Management" {
        It "Should handle multiple initialization calls gracefully" {
            $configPath = Join-Path $TestTempDir "multi-init"

            # Ensure parent directory exists
            $parentDir = Split-Path $configPath -Parent
            if (-not (Test-Path $parentDir)) {
                New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
            }

            # First initialization
            { Initialize-WindowsMelodyRecovery -InstallPath $configPath -NoPrompt -ErrorAction Stop } | Should -Not -Throw

            # Second initialization (should not fail)
            { Initialize-WindowsMelodyRecovery -InstallPath $configPath -NoPrompt -ErrorAction Stop } | Should -Not -Throw

            # Verify configuration is still valid
            Test-Path (Join-Path $configPath "Config") | Should -Be $true
        }
    }

    Context "Cross-Platform Validation" {
        It "Should load module successfully on any platform" {
            # Test that the module loads without errors on any platform
            { Import-Module $TestModulePath -Force -ErrorAction Stop } | Should -Not -Throw
        }

        It "Should provide basic status information" {
            # Test that status information is available regardless of platform
            $status = Get-WindowsMelodyRecoveryStatus -ErrorAction SilentlyContinue
            $status | Should -Not -BeNullOrEmpty
        }

        It "Should handle platform differences gracefully" {
            # Test that the module doesn't crash on non-Windows platforms
            { Test-WindowsMelodyRecovery -ErrorAction SilentlyContinue } | Should -Not -Throw
        }
    }

    Context "Error Handling and Recovery" {
        It "Should handle invalid configuration paths" {
            $invalidPath = "/NonExistent/Path/That/Really/Does/Not/Exist/At/All"
            { Initialize-WindowsMelodyRecovery -InstallPath $invalidPath -NoPrompt -ErrorAction Stop } | Should -Throw
        }

        It "Should handle permission errors gracefully" {
            # Test permission errors with a path that should be inaccessible
            # Use /proc which exists but is read-only in Linux
            $inaccessiblePath = "/proc"
            { Initialize-WindowsMelodyRecovery -InstallPath $inaccessiblePath -NoPrompt -ErrorAction Stop } | Should -Throw
        }

        It "Should provide meaningful error messages" {
            try {
                Initialize-WindowsMelodyRecovery -InstallPath "" -NoPrompt -ErrorAction Stop
            } catch {
                $_.Exception.Message | Should -Not -BeNullOrEmpty
                $_.Exception.Message | Should -Match "configuration|install|path"
            }
        }
    }
}

Describe "Windows Melody Recovery - Pester Integration Tests" -Tag "Pester" {

    Context "Pester Test Infrastructure" {
        It "Should have Pester available" {
            $pesterModule = Get-Module -ListAvailable Pester | Select-Object -First 1
            $pesterModule | Should -Not -BeNullOrEmpty
            $pesterModule.Version | Should -BeGreaterThan "5.0.0"
        }

        It "Should have test files in expected locations" {
            $testPaths = @(
                (Join-Path $PSScriptRoot "../unit"),
                (Join-Path $PSScriptRoot ".")
            )

            foreach ($path in $testPaths) {
                Test-Path $path | Should -Be $true

                $testFiles = Get-ChildItem -Path $path -Filter "*.Tests.ps1" -Recurse -ErrorAction SilentlyContinue
                $testFiles.Count | Should -BeGreaterThan 0
            }
        }

        It "Should have valid Pester test syntax" {
            $testFiles = Get-ChildItem -Path (Join-Path $PSScriptRoot "../..") -Filter "*.Tests.ps1" -Recurse -ErrorAction SilentlyContinue

            foreach ($testFile in $testFiles) {
                { [System.Management.Automation.PSParser]::Tokenize((Get-Content $testFile.FullName -Raw), [ref]$null) } | Should -Not -Throw
            }
        }
    }

    Context "Test Execution" {
        It "Should have unit test files available" {
            $unitTestPath = Join-Path $PSScriptRoot "../unit"
            if (Test-Path $unitTestPath) {
                $testFiles = Get-ChildItem -Path $unitTestPath -Filter "*.Tests.ps1" -ErrorAction SilentlyContinue
                $testFiles.Count | Should -BeGreaterThan 0
            }
        }

        It "Should have integration test files available" {
            $integrationTestPath = Join-Path $PSScriptRoot "."
            if (Test-Path $integrationTestPath) {
                $testFiles = Get-ChildItem -Path $integrationTestPath -Filter "*.Tests.ps1" -ErrorAction SilentlyContinue
                $testFiles.Count | Should -BeGreaterThan 0
            }
        }
    }
}

AfterAll {
    # Cleanup
    if (Test-Path $TestTempDir) {
        Remove-Item -Path $TestTempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Remove module
    Remove-Module WindowsMelodyRecovery -ErrorAction SilentlyContinue
}
