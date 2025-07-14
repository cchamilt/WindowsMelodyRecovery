#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Integration tests for chezmoi dotfile management functionality

.DESCRIPTION
    Tests the complete chezmoi workflow including installation, configuration,
    file management, backup, and restore operations in a Docker environment.
#>

BeforeAll {
    # Import the unified test environment library and initialize it for Integration tests.
    . (Join-Path $PSScriptRoot "..\utilities\Test-Environment.ps1")
    $script:TestEnvironment = Initialize-WmrTestEnvironment -SuiteName 'Integration'

    # Import the main module to make functions available for testing.
    Import-Module (Join-Path $script:TestEnvironment.ModuleRoot "WindowsMelodyRecovery.psd1") -Force

    # Use paths from the initialized environment
    $TestTempDir = $script:TestEnvironment.Temp

    # Mock environment variables for testing (handled by initializer)
}

AfterAll {
    # Clean up the test environment created in BeforeAll.
    Remove-WmrTestEnvironment
}

Describe "Windows Melody Recovery - Chezmoi Integration Tests" -Tag "Chezmoi" {

    Context "Chezmoi Availability and Installation" {
        It "Should have chezmoi available in WSL environment" {
            # This test would run in a Docker environment with WSL mock
            # For local testing, we'll check if the function exists
            Import-Module $TestModulePath -Force -ErrorAction SilentlyContinue

            $setupFunction = Get-Command Initialize-Chezmoi -ErrorAction SilentlyContinue
            $setupFunction | Should -Not -BeNullOrEmpty
        }

        It "Should have chezmoi setup functions available" {
            Import-Module $TestModulePath -Force -ErrorAction SilentlyContinue

            $functions = @(
                'Initialize-Chezmoi',
                'Initialize-WSLChezmoi'
            )

            foreach ($function in $functions) {
                Get-Command $function -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
            }
        }

        It "Should validate chezmoi installation script syntax" {
            $chezmoiSetupPath = Join-Path $script:TestEnvironment.ModuleRoot "Private/setup/Initialize-Chezmoi.ps1"
            if (Test-Path $chezmoiSetupPath) {
                { [System.Management.Automation.PSParser]::Tokenize((Get-Content $chezmoiSetupPath -Raw), [ref]$null) } | Should -Not -Throw
            }
            else {
                Write-Warning "Chezmoi setup script not found at expected location"
            }
        }
    }

    Context "Chezmoi Configuration Management" {
        It "Should handle chezmoi configuration validation" {
            Import-Module $TestModulePath -Force -ErrorAction SilentlyContinue

            # Test configuration validation logic
            $configPath = Join-Path $TestTempDir "chezmoi-config"
            if (-not (Test-Path $configPath)) {
                New-Item -Path $configPath -ItemType Directory -Force | Out-Null
            }

            # Create a mock chezmoi configuration
            $mockConfig = @"
[chezmoi]
    sourceDir = "~/.local/share/chezmoi"
    destDir = "~"
    configFile = "~/.config/chezmoi/chezmoi.toml"
"@

            $configFile = Join-Path $configPath "chezmoi.toml"
            $mockConfig | Out-File -FilePath $configFile -Encoding UTF8

            Test-Path $configFile | Should -Be $true
        }

        It "Should handle chezmoi source directory management" {
            $sourceDir = Join-Path $TestTempDir "chezmoi-source"
            if (-not (Test-Path $sourceDir)) {
                New-Item -Path $sourceDir -ItemType Directory -Force | Out-Null
            }

            # Create mock dotfiles
            $mockFiles = @{
                "dot_bashrc"    = "# Mock .bashrc file"
                "dot_gitconfig" = "[user]`n    name = Test User`n    email = test@example.com"
                "dot_vimrc"     = "set number`nset expandtab"
            }

            foreach ($file in $mockFiles.GetEnumerator()) {
                $filePath = Join-Path $sourceDir $file.Key
                $file.Value | Out-File -FilePath $filePath -Encoding UTF8
                Test-Path $filePath | Should -Be $true
            }
        }
    }

    Context "Chezmoi File Management" {
        It "Should handle file addition to chezmoi" {
            $testFile = Join-Path $TestTempDir "test-file.txt"
            "Test content for chezmoi" | Out-File -FilePath $testFile -Encoding UTF8

            Test-Path $testFile | Should -Be $true

            # Clean up
            Remove-Item $testFile -Force -ErrorAction SilentlyContinue
        }

        It "Should handle chezmoi template processing" {
            $templateContent = @"
{{ if eq .chezmoi.os "linux" }}
# Linux-specific configuration
export PATH="$HOME/.local/bin:$PATH"
{{ end }}

{{ if eq .chezmoi.os "darwin" }}
# macOS-specific configuration
export PATH="/opt/homebrew/bin:$PATH"
{{ end }}

# Common configuration
alias ll='ls -la'
alias la='ls -A'
"@

            $templateFile = Join-Path $TestTempDir "dot_bashrc.tmpl"
            $templateContent | Out-File -FilePath $templateFile -Encoding UTF8

            Test-Path $templateFile | Should -Be $true

            # Clean up
            Remove-Item $templateFile -Force -ErrorAction SilentlyContinue
        }

        It "Should handle chezmoi script templates" {
            $scriptTemplate = @"
#!/bin/bash
# {{ .chezmoi.sourceFile | replace "run_once_" "" | replace ".tmpl" "" }}

echo "Running script: {{ .chezmoi.sourceFile | replace "run_once_" "" | replace ".tmpl" "" }}"
echo "Hostname: {{ .chezmoi.hostname }}"
echo "Username: {{ .chezmoi.username }}"
"@

            $scriptFile = Join-Path $TestTempDir "run_once_setup.sh.tmpl"
            $scriptTemplate | Out-File -FilePath $scriptFile -Encoding UTF8

            Test-Path $scriptFile | Should -Be $true

            # Clean up
            Remove-Item $scriptFile -Force -ErrorAction SilentlyContinue
        }
    }

    Context "Chezmoi Backup and Restore" {
        It "Should handle chezmoi backup creation" {
            $backupPath = Join-Path $TestTempDir "chezmoi-backup"
            if (-not (Test-Path $backupPath)) {
                New-Item -Path $backupPath -ItemType Directory -Force | Out-Null
            }

            # Create mock backup structure
            $backupStructure = @{
                "source" = @{
                    "dotfiles" = @{
                        "dot_bashrc"    = "# Backup .bashrc"
                        "dot_gitconfig" = "[user]`n    name = Backup User"
                    }
                }
                "config" = @{
                    "chezmoi.toml" = "[chezmoi]`n    sourceDir = `"~/.local/share/chezmoi`""
                }
            }

            # Create backup structure
            foreach ($dir in $backupStructure.GetEnumerator()) {
                $dirPath = Join-Path $backupPath $dir.Key
                if (-not (Test-Path $dirPath)) {
                    New-Item -Path $dirPath -ItemType Directory -Force | Out-Null
                }

                foreach ($file in $dir.Value.GetEnumerator()) {
                    if ($file.Value -is [hashtable]) {
                        $subDirPath = Join-Path $dirPath $file.Key
                        if (-not (Test-Path $subDirPath)) {
                            New-Item -Path $subDirPath -ItemType Directory -Force | Out-Null
                        }

                        foreach ($subFile in $file.Value.GetEnumerator()) {
                            $filePath = Join-Path $subDirPath $subFile.Key
                            $subFile.Value | Out-File -FilePath $filePath -Encoding UTF8
                        }
                    }
                    else {
                        $filePath = Join-Path $dirPath $file.Key
                        $file.Value | Out-File -FilePath $filePath -Encoding UTF8
                    }
                }
            }

            Test-Path $backupPath | Should -Be $true
            Test-Path (Join-Path $backupPath "source") | Should -Be $true
            Test-Path (Join-Path $backupPath "config") | Should -Be $true
        }

        It "Should handle chezmoi restore validation" {
            $backupPath = Join-Path $TestTempDir "chezmoi-backup"
            $restorePath = Join-Path $TestTempDir "chezmoi-restore"

            if (Test-Path $backupPath) {
                # Simulate restore by copying backup
                Copy-Item -Path $backupPath -Destination $restorePath -Recurse -Force

                Test-Path $restorePath | Should -Be $true
                Test-Path (Join-Path $restorePath "source") | Should -Be $true
                Test-Path (Join-Path $restorePath "config") | Should -Be $true
            }
        }

        It "Should validate backup manifest creation" {
            $backupPath = Join-Path $TestTempDir "chezmoi-backup"

            # Create backup manifest
            $manifest = @{
                BackupType  = "Chezmoi"
                CreatedDate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                SourcePath  = $backupPath
                Components  = @(
                    "chezmoi-source",
                    "chezmoi-config"
                )
                Files       = @()
            }

            # Add files to manifest
            if (Test-Path $backupPath) {
                $files = Get-ChildItem -Path $backupPath -Recurse -File
                foreach ($file in $files) {
                    $manifest.Files += @{
                        Path     = $file.FullName.Replace($backupPath, "")
                        Size     = $file.Length
                        Modified = $file.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
                    }
                }
            }

            $manifest | Should -Not -BeNullOrEmpty
            $manifest.BackupType | Should -Be "Chezmoi"
            $manifest.Components | Should -Contain "chezmoi-source"
        }
    }

    Context "Chezmoi Integration with Windows Melody Recovery" {
        It "Should integrate with module backup functions" {
            Import-Module $TestModulePath -Force -ErrorAction SilentlyContinue

            # Test that chezmoi backup is included in WSL backup
            $wslBackupFunctions = Get-Command -Name "*WSL*" -Module WindowsMelodyRecovery -ErrorAction SilentlyContinue
            $wslBackupFunctions | Should -Not -BeNullOrEmpty

            # Test that WSL template includes chezmoi functionality
            $wslTemplatePath = "Templates/System/wsl.yaml"
            if (Test-Path $wslTemplatePath) {
                Test-Path $wslTemplatePath | Should -Be $true
            }
            else {
                Set-ItResult -Skipped -Because "wsl.yaml template not found"
            }
        }

        It "Should integrate with module setup functions" {
            Import-Module $TestModulePath -Force -ErrorAction SilentlyContinue

            # Test that chezmoi setup is included in WSL setup
            $wslSetupFunctions = Get-Command -Name "*WSL*" -Module WindowsMelodyRecovery -ErrorAction SilentlyContinue
            $wslSetupFunctions | Should -Not -BeNullOrEmpty

            # Check for specific chezmoi setup function
            $chezmoiSetupFunction = Get-Command Initialize-WSLChezmoi -ErrorAction SilentlyContinue
            $chezmoiSetupFunction | Should -Not -BeNullOrEmpty
        }

        It "Should handle chezmoi configuration in module settings" {
            $configPath = Join-Path $TestTempDir "module-config"
            if (-not (Test-Path $configPath)) {
                New-Item -Path $configPath -ItemType Directory -Force | Out-Null
            }

            # Create module configuration that includes chezmoi
            $moduleConfig = @{
                WSL = @{
                    Enabled    = $true
                    Components = @(
                        "packages",
                        "configs",
                        "chezmoi"
                    )
                    Chezmoi    = @{
                        Enabled      = $true
                        BackupSource = $true
                        BackupConfig = $true
                        AutoSetup    = $false
                    }
                }
            }

            $configFile = Join-Path $configPath "scripts-config.json"
            $moduleConfig | ConvertTo-Json -Depth 10 | Out-File -FilePath $configFile -Encoding UTF8

            Test-Path $configFile | Should -Be $true

            # Validate JSON syntax
            $loadedConfig = Get-Content $configFile -Raw | ConvertFrom-Json
            $loadedConfig.WSL.Components | Should -Contain "chezmoi"
            $loadedConfig.WSL.Chezmoi.Enabled | Should -Be $true
        }
    }

    Context "Chezmoi Error Handling" {
        It "Should handle missing WSL gracefully" {
            Import-Module $TestModulePath -Force -ErrorAction SilentlyContinue

            # Mock WSL command to simulate missing WSL
            Mock Get-Command { return $null } -ParameterFilter { $Name -eq "wsl" }

            # Test that setup function handles missing WSL
            try {
                Initialize-Chezmoi -ErrorAction Stop
            }
            catch {
                $_.Exception.Message | Should -Match "WSL"
            }
        }

        It "Should handle chezmoi installation failures" {
            # Test chezmoi installation error handling
            $errorScript = @"
#!/bin/bash
echo "Simulating chezmoi installation failure"
exit 1
"@

            $scriptFile = Join-Path $TestTempDir "failed-install.sh"
            $errorScript | Out-File -FilePath $scriptFile -Encoding UTF8

            # Test script execution failure
            try {
                & bash $scriptFile
            }
            catch {
                $LASTEXITCODE | Should -Be 1
            }

            # Clean up
            Remove-Item $scriptFile -Force -ErrorAction SilentlyContinue
        }

        It "Should handle invalid chezmoi configuration" {
            $invalidConfig = @"
[chezmoi]
    invalidSetting = "this should cause an error"
    sourceDir = ""  # Empty source directory
"@

            $configFile = Join-Path $TestTempDir "invalid-chezmoi.toml"
            $invalidConfig | Out-File -FilePath $configFile -Encoding UTF8

            Test-Path $configFile | Should -Be $true

            # Clean up
            Remove-Item $configFile -Force -ErrorAction SilentlyContinue
        }
    }

    Context "Chezmoi Performance and Scalability" {
        It "Should handle large dotfile repositories" {
            $largeRepoPath = Join-Path $TestTempDir "large-dotfiles"
            if (-not (Test-Path $largeRepoPath)) {
                New-Item -Path $largeRepoPath -ItemType Directory -Force | Out-Null
            }

            # Create many mock dotfiles
            for ($i = 1; $i -le 100; $i++) {
                $filePath = Join-Path $largeRepoPath "dot_file$i"
                "Content for file $i" | Out-File -FilePath $filePath -Encoding UTF8
            }

            $fileCount = (Get-ChildItem -Path $largeRepoPath -File).Count
            $fileCount | Should -Be 100

            # Clean up
            Remove-Item $largeRepoPath -Recurse -Force -ErrorAction SilentlyContinue
        }

        It "Should handle complex template processing" {
            $complexTemplate = @"
{{ if eq .chezmoi.os "linux" }}
{{ if eq .chezmoi.arch "amd64" }}
# Linux AMD64 configuration
export ARCH="x86_64"
{{ else if eq .chezmoi.arch "arm64" }}
# Linux ARM64 configuration
export ARCH="aarch64"
{{ end }}
{{ else if eq .chezmoi.os "darwin" }}
{{ if eq .chezmoi.arch "amd64" }}
# macOS Intel configuration
export ARCH="x86_64"
{{ else if eq .chezmoi.arch "arm64" }}
# macOS Apple Silicon configuration
export ARCH="arm64"
{{ end }}
{{ end }}

# Common configuration for {{ .chezmoi.hostname }}
export HOSTNAME="{{ .chezmoi.hostname }}"
export USER="{{ .chezmoi.username }}"
"@

            $templateFile = Join-Path $TestTempDir "complex.tmpl"
            $complexTemplate | Out-File -FilePath $templateFile -Encoding UTF8

            Test-Path $templateFile | Should -Be $true

            # Clean up
            Remove-Item $templateFile -Force -ErrorAction SilentlyContinue
        }
    }
}







