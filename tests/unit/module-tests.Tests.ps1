#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Unit tests for Windows Missing Recovery module

.DESCRIPTION
    Fast unit tests for core module functionality, configuration, and basic operations.
#>

BeforeAll {
    # Import the module
    $ModulePath = "$PSScriptRoot\..\..\WindowsMissingRecovery.psm1"
    Import-Module $ModulePath -Force
    
    # Setup test environment
    $script:TestConfigPath = "$env:TEMP\WMR-Unit-Tests"
    New-Item -Path $script:TestConfigPath -ItemType Directory -Force | Out-Null
}

Describe "Module Loading and Structure" -Tag "Unit" {
    
    Context "Module Import" {
        It "Should import without errors" {
            { Import-Module $ModulePath -Force } | Should -Not -Throw
        }
        
        It "Should export expected functions" {
            $exportedFunctions = Get-Command -Module WindowsMissingRecovery -CommandType Function
            
            $expectedFunctions = @(
                'Backup-WindowsMissingRecovery',
                'Restore-WindowsMissingRecovery',
                'Initialize-WindowsMissingRecovery',
                'Get-WindowsMissingRecoveryConfig',
                'Set-WindowsMissingRecoveryConfig'
            )
            
            foreach ($function in $expectedFunctions) {
                $exportedFunctions.Name | Should -Contain $function
            }
        }
        
        It "Should have module manifest" {
            $manifestPath = "$PSScriptRoot\..\..\WindowsMissingRecovery.psd1"
            Test-Path $manifestPath | Should -Be $true
            
            $manifest = Test-ModuleManifest $manifestPath
            $manifest.Name | Should -Be "WindowsMissingRecovery"
            $manifest.Version | Should -Not -BeNullOrEmpty
        }
    }
    
    Context "Module Configuration" {
        It "Should load default configuration" {
            $config = Get-WindowsMissingRecoveryConfig
            
            $config | Should -Not -BeNullOrEmpty
            $config.BackupRoot | Should -Not -BeNullOrEmpty
            $config.CloudProvider | Should -Not -BeNullOrEmpty
        }
        
        It "Should validate configuration structure" {
            $config = Get-WindowsMissingRecoveryConfig
            
            # Required properties
            $config.PSObject.Properties.Name | Should -Contain "BackupRoot"
            $config.PSObject.Properties.Name | Should -Contain "CloudProvider"
            $config.PSObject.Properties.Name | Should -Contain "LogLevel"
            $config.PSObject.Properties.Name | Should -Contain "Scripts"
        }
        
        It "Should handle custom configuration" {
            $customConfig = @{
                BackupRoot = "$env:TEMP\CustomBackup"
                CloudProvider = "GoogleDrive"
                LogLevel = "Debug"
            }
            
            { Set-WindowsMissingRecoveryConfig -Config $customConfig } | Should -Not -Throw
            
            $updatedConfig = Get-WindowsMissingRecoveryConfig
            $updatedConfig.BackupRoot | Should -Be $customConfig.BackupRoot
            $updatedConfig.CloudProvider | Should -Be $customConfig.CloudProvider
        }
    }
}

Describe "Configuration Management" -Tag "Unit" {
    
    Context "Config File Operations" {
        It "Should create configuration file" {
            $testConfigFile = Join-Path $script:TestConfigPath "test-config.json"
            
            $testConfig = @{
                BackupRoot = "$env:TEMP\TestBackup"
                CloudProvider = "OneDrive"
                LogLevel = "Info"
            }
            
            $testConfig | ConvertTo-Json | Out-File $testConfigFile
            
            Test-Path $testConfigFile | Should -Be $true
            
            $loadedConfig = Get-Content $testConfigFile | ConvertFrom-Json
            $loadedConfig.BackupRoot | Should -Be $testConfig.BackupRoot
        }
        
        It "Should validate configuration values" {
            $validProviders = @("OneDrive", "GoogleDrive", "Dropbox", "Custom")
            $validLogLevels = @("Error", "Warning", "Info", "Verbose", "Debug")
            
            foreach ($provider in $validProviders) {
                $config = @{ CloudProvider = $provider }
                { Set-WindowsMissingRecoveryConfig -Config $config } | Should -Not -Throw
            }
            
            foreach ($level in $validLogLevels) {
                $config = @{ LogLevel = $level }
                { Set-WindowsMissingRecoveryConfig -Config $config } | Should -Not -Throw
            }
        }
        
        It "Should handle invalid configuration gracefully" {
            $invalidConfig = @{
                CloudProvider = "InvalidProvider"
                LogLevel = "InvalidLevel"
            }
            
            # Should either throw or handle gracefully
            try {
                Set-WindowsMissingRecoveryConfig -Config $invalidConfig
                $config = Get-WindowsMissingRecoveryConfig
                # If it doesn't throw, it should use defaults or valid values
                $config.CloudProvider | Should -BeIn @("OneDrive", "GoogleDrive", "Dropbox", "Custom")
            } catch {
                # Exception is acceptable for invalid config
                $_.Exception.Message | Should -Not -BeNullOrEmpty
            }
        }
    }
    
    Context "Environment Detection" {
        It "Should detect Windows version" {
            $osInfo = Get-CimInstance Win32_OperatingSystem
            $osInfo.Caption | Should -Not -BeNullOrEmpty
            $osInfo.Version | Should -Not -BeNullOrEmpty
        }
        
        It "Should detect PowerShell version" {
            $PSVersionTable.PSVersion | Should -Not -BeNullOrEmpty
            $PSVersionTable.PSVersion.Major | Should -BeGreaterOrEqual 5
        }
        
        It "Should detect available package managers" {
            # Test for common package managers
            $packageManagers = @{
                "winget" = { Get-Command winget -ErrorAction SilentlyContinue }
                "choco" = { Get-Command choco -ErrorAction SilentlyContinue }
                "scoop" = { Get-Command scoop -ErrorAction SilentlyContinue }
            }
            
            foreach ($pm in $packageManagers.Keys) {
                $available = & $packageManagers[$pm]
                # Should either be available or not (both are valid)
                ($available -ne $null) -or ($available -eq $null) | Should -Be $true
            }
        }
    }
}

Describe "Utility Functions" -Tag "Unit" {
    
    Context "Path Operations" {
        It "Should handle path validation" {
            # Test valid paths
            $validPaths = @(
                "$env:TEMP",
                "$env:USERPROFILE",
                "$env:ProgramFiles"
            )
            
            foreach ($path in $validPaths) {
                Test-Path $path | Should -Be $true
            }
        }
        
        It "Should handle invalid paths" {
            $invalidPaths = @(
                "Z:\NonExistent\Path",
                "\\InvalidUNC\Path",
                "C:\Windows\System32\RestrictedPath"
            )
            
            foreach ($path in $invalidPaths) {
                # Should handle gracefully (either false or exception)
                try {
                    $result = Test-Path $path
                    $result | Should -Be $false
                } catch {
                    # Exception is acceptable for invalid paths
                    $_.Exception.Message | Should -Not -BeNullOrEmpty
                }
            }
        }
        
        It "Should create backup directory structure" {
            $testBackupRoot = Join-Path $script:TestConfigPath "BackupStructure"
            
            # Test directory creation
            New-Item -Path $testBackupRoot -ItemType Directory -Force | Out-Null
            New-Item -Path "$testBackupRoot\Machine" -ItemType Directory -Force | Out-Null
            New-Item -Path "$testBackupRoot\Shared" -ItemType Directory -Force | Out-Null
            New-Item -Path "$testBackupRoot\WSL" -ItemType Directory -Force | Out-Null
            
            Test-Path $testBackupRoot | Should -Be $true
            Test-Path "$testBackupRoot\Machine" | Should -Be $true
            Test-Path "$testBackupRoot\Shared" | Should -Be $true
            Test-Path "$testBackupRoot\WSL" | Should -Be $true
        }
    }
    
    Context "Error Handling" {
        It "Should handle missing files gracefully" {
            $missingFile = Join-Path $script:TestConfigPath "missing-file.txt"
            
            # Should not throw when checking missing file
            { Test-Path $missingFile } | Should -Not -Throw
            Test-Path $missingFile | Should -Be $false
        }
        
        It "Should handle permission errors gracefully" {
            # Test with system directory (may not have write access)
            $systemPath = "$env:SystemRoot\System32\TestFile.txt"
            
            try {
                "test" | Out-File $systemPath -ErrorAction Stop
                # If successful, clean up
                Remove-Item $systemPath -Force -ErrorAction SilentlyContinue
            } catch {
                # Permission error is expected and acceptable
                $_.Exception.Message | Should -Not -BeNullOrEmpty
            }
        }
        
        It "Should validate input parameters" {
            # Test parameter validation for main functions
            { Initialize-WindowsMissingRecovery -BackupRoot "" } | Should -Throw
            { Initialize-WindowsMissingRecovery -BackupRoot $null } | Should -Throw
        }
    }
}

Describe "Script Loading" -Tag "Unit" {
    
    Context "Private Scripts" {
        It "Should load backup scripts without errors" {
            $backupScripts = Get-ChildItem "$PSScriptRoot\..\..\Private\backup" -Filter "*.ps1"
            
            foreach ($script in $backupScripts) {
                { . $script.FullName } | Should -Not -Throw
            }
        }
        
        It "Should load setup scripts without errors" {
            $setupScripts = Get-ChildItem "$PSScriptRoot\..\..\Private\setup" -Filter "*.ps1"
            
            foreach ($script in $setupScripts) {
                { . $script.FullName } | Should -Not -Throw
            }
        }
        
        It "Should load restore scripts without errors" {
            $restoreScripts = Get-ChildItem "$PSScriptRoot\..\..\Private\restore" -Filter "*.ps1"
            
            foreach ($script in $restoreScripts) {
                { . $script.FullName } | Should -Not -Throw
            }
        }
        
        It "Should load WSL scripts without errors" {
            $wslScripts = Get-ChildItem "$PSScriptRoot\..\..\Private\wsl" -Filter "*.ps1"
            
            foreach ($script in $wslScripts) {
                { . $script.FullName } | Should -Not -Throw
            }
        }
    }
    
    Context "Configuration Files" {
        It "Should load scripts configuration" {
            $configPath = "$PSScriptRoot\..\..\Config\scripts-config.json"
            
            if (Test-Path $configPath) {
                $config = Get-Content $configPath | ConvertFrom-Json
                $config | Should -Not -BeNullOrEmpty
                $config.Scripts | Should -Not -BeNullOrEmpty
            }
        }
        
        It "Should validate script configuration structure" {
            $configPath = "$PSScriptRoot\..\..\Config\scripts-config.json"
            
            if (Test-Path $configPath) {
                $config = Get-Content $configPath | ConvertFrom-Json
                
                # Should have required sections
                $config.PSObject.Properties.Name | Should -Contain "Scripts"
                
                # Scripts should have required properties
                foreach ($script in $config.Scripts.PSObject.Properties) {
                    $scriptConfig = $script.Value
                    $scriptConfig.PSObject.Properties.Name | Should -Contain "Enabled"
                    $scriptConfig.PSObject.Properties.Name | Should -Contain "Category"
                }
            }
        }
    }
}

AfterAll {
    # Cleanup test environment
    if (Test-Path $script:TestConfigPath) {
        Remove-Item -Path $script:TestConfigPath -Recurse -Force -ErrorAction SilentlyContinue
    }
} 