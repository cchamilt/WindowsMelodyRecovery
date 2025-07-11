# tests/file-operations/Prerequisites-FileOperations.Tests.ps1

<#
.SYNOPSIS
    File Operations Tests for Prerequisites

.DESCRIPTION
    Tests the Prerequisites functions' file and registry operations within safe test directories.
    Performs actual file operations but only in designated test paths.

.NOTES
    These are file operation tests - they create and manipulate actual files!
    Pure logic tests are in tests/unit/Prerequisites-Logic.Tests.ps1
#>

BeforeAll {
    # Import test environment utilities
    . (Join-Path $PSScriptRoot "..\utilities\Test-Environment.ps1")

    # Initialize test environment to ensure directories exist
    $script:TestEnvironment = Initialize-TestEnvironment

    # Get standardized test paths
    $script:TestBackupDir = $script:TestEnvironment.TestBackup
    $script:TestRestoreDir = $script:TestEnvironment.TestRestore

    # Import the module with standardized pattern
    try {
        $ModulePath = Resolve-Path "$PSScriptRoot/../../WindowsMelodyRecovery.psd1"
        Import-Module $ModulePath -Force -ErrorAction Stop
    } catch {
        throw "Cannot find or import WindowsMelodyRecovery module: $($_.Exception.Message)"
    }

    # Dot-source Prerequisites.ps1 to ensure all functions are available
    . (Join-Path (Split-Path $ModulePath) "Private\Core\Prerequisites.ps1")

    # Ensure test directories exist with null checks
    @($script:TestBackupDir, $script:TestRestoreDir) | ForEach-Object {
        if ($_ -and -not (Test-Path $_)) {
            New-Item -ItemType Directory -Path $_ -Force | Out-Null
        }
    }
}

Describe "Prerequisites File Operations" -Tag "FileOperations" {

    Context "Script File Creation and Execution" {

        It "Should create and execute temporary script files" {
            $scriptPath = Join-Path $script:TestBackupDir "temp-script.ps1"
            $scriptContent = @"
Write-Output "Script executed successfully"
Write-Output "Current directory: `$(Get-Location)"
"@

            try {
                # Create temporary script
                $scriptContent | Out-File $scriptPath -Encoding UTF8
                Test-Path $scriptPath | Should -Be $true

                # Execute script and capture output, filtering out test runner banner
                $allOutput = & pwsh -File $scriptPath 2>&1
                $result = $allOutput | Where-Object {
                    $_ -notlike "*Test Runner*" -and
                    $_ -notlike "*Available commands*" -and
                    $_ -notlike "*🧪*" -and
                    $_ -and $_.ToString().Trim() -ne ""
                }

                # Check that we got the expected outputs
                $result | Should -Contain "Script executed successfully"
                ($result | Where-Object { $_ -match "Current directory:" }) | Should -Not -BeNullOrEmpty

            } finally {
                if ($scriptPath) {
                    Remove-Item $scriptPath -Force -ErrorAction SilentlyContinue
                }
            }
        }

        It "Should handle script files with different encodings" {
            $utf8Script = Join-Path $script:TestBackupDir "utf8-script.ps1"
            $utf8Content = @"
Write-Output "UTF-8 test content"
Write-Output "ASCII safe output"
"@

            try {
                # Create UTF-8 script
                $utf8Content | Out-File $utf8Script -Encoding UTF8
                Test-Path $utf8Script | Should -Be $true

                # Execute script and verify output (using ASCII-safe content)
                $result = & pwsh -File $utf8Script
                $result | Should -Contain "UTF-8 test content"
                $result | Should -Contain "ASCII safe output"

                # Test file encoding by reading the raw content
                $rawContent = Get-Content $utf8Script -Raw
                $rawContent | Should -Match "UTF-8 test content"

            } finally {
                if ($utf8Script) {
                    Remove-Item $utf8Script -Force -ErrorAction SilentlyContinue
                }
            }
        }

        It "Should create prerequisite validation scripts" {
            $validationScript = Join-Path $script:TestBackupDir "validation-script.ps1"
            $validationContent = @"
# Prerequisite validation script
param([string]`$ExpectedVersion = "1.0.0")

try {
    `$version = "1.0.0"
    if (`$version -eq `$ExpectedVersion) {
        Write-Output "PASS: Version `$version matches expected `$ExpectedVersion"
        exit 0
    } else {
        Write-Output "FAIL: Version `$version does not match expected `$ExpectedVersion"
        exit 1
    }
} catch {
    Write-Output "ERROR: `$(`$_.Exception.Message)"
    exit 2
}
"@

            try {
                # Create validation script
                $validationContent | Out-File $validationScript -Encoding UTF8
                Test-Path $validationScript | Should -Be $true

                # Execute with parameter
                $result = & $validationScript -ExpectedVersion "1.0.0"
                $result | Should -Match "PASS:"

            } finally {
                if ($validationScript) {
                    Remove-Item $validationScript -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }

    Context "Registry Test Key Creation and Cleanup" {
        BeforeAll {
            # Skip all registry tests in Docker/Linux environment
            if ($IsLinux -or $IsMacOS -or ($env:DOCKER_ENVIRONMENT -eq "true") -or ($env:CONTAINER_NAME -like "*wmr*")) {
                Write-Warning "Registry tests skipped in non-Windows environment"
                return
            }
        }

        It "Should create and clean up test registry keys" -Skip:($IsLinux -or $IsMacOS -or ($env:DOCKER_ENVIRONMENT -eq "true") -or ($env:CONTAINER_NAME -like "*wmr*")) {
            $testKeyPath = "HKCU:\Software\WindowsMelodyRecovery\Test"

            try {
                # Create test registry key
                if (-not (Test-Path $testKeyPath)) {
                    New-Item -Path $testKeyPath -Force | Out-Null
                }
                Test-Path $testKeyPath | Should -Be $true

                # Set test value
                Set-ItemProperty -Path $testKeyPath -Name "TestValue" -Value "TestData"
                $value = Get-ItemProperty -Path $testKeyPath -Name "TestValue"
                $value.TestValue | Should -Be "TestData"

            } finally {
                # Clean up test registry key
                if (Test-Path $testKeyPath) {
                    Remove-Item $testKeyPath -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }

        It "Should handle registry keys with special characters" -Skip:($IsLinux -or $IsMacOS -or ($env:DOCKER_ENVIRONMENT -eq "true") -or ($env:CONTAINER_NAME -like "*wmr*")) {
            $specialKeyPath = "HKCU:\Software\WindowsMelodyRecovery\Test With Spaces"

            try {
                # Create registry key with spaces
                if (-not (Test-Path $specialKeyPath)) {
                    New-Item -Path $specialKeyPath -Force | Out-Null
                }
                Test-Path $specialKeyPath | Should -Be $true

                # Set value with special characters
                Set-ItemProperty -Path $specialKeyPath -Name "Special Value" -Value "Data with émojis 🚀"
                $value = Get-ItemProperty -Path $specialKeyPath -Name "Special Value"
                $value."Special Value" | Should -Be "Data with émojis 🚀"

            } finally {
                # Clean up
                if (Test-Path $specialKeyPath) {
                    Remove-Item $specialKeyPath -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }

        It "Should handle different registry data types" -Skip:($IsLinux -or $IsMacOS -or ($env:DOCKER_ENVIRONMENT -eq "true") -or ($env:CONTAINER_NAME -like "*wmr*")) {
            $testKeyPath = "HKCU:\Software\WindowsMelodyRecovery\DataTypes"

            try {
                # Create test registry key
                if (-not (Test-Path $testKeyPath)) {
                    New-Item -Path $testKeyPath -Force | Out-Null
                }

                # Test different data types (only on Windows)
                if ($IsWindows) {
                    Set-ItemProperty -Path $testKeyPath -Name "StringValue" -Value "Test String"
                    Set-ItemProperty -Path $testKeyPath -Name "DWordValue" -Value 12345 -Type DWord
                    Set-ItemProperty -Path $testKeyPath -Name "BinaryValue" -Value @(0x01, 0x02, 0x03) -Type Binary

                    # Verify values
                    $props = Get-ItemProperty -Path $testKeyPath
                    $props.StringValue | Should -Be "Test String"
                    $props.DWordValue | Should -Be 12345
                    $props.BinaryValue | Should -Be @(1, 2, 3)
                }

            } finally {
                # Clean up
                if (Test-Path $testKeyPath) {
                    Remove-Item $testKeyPath -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }

    Context "Application Executable Testing" {

        It "Should create and test mock application executables" {
            $mockAppPath = Join-Path $script:TestBackupDir "mock-app.ps1"
            $mockAppContent = @"
param([string]`$Command)

switch (`$Command) {
    "--version" { Write-Output "MockApp v1.2.3" }
    "--help" { Write-Output "MockApp Help" }
    default { Write-Output "Unknown command: `$Command" }
}
"@

            try {
                # Create mock application
                $mockAppContent | Out-File $mockAppPath -Encoding UTF8
                Test-Path $mockAppPath | Should -Be $true

                # Test version command
                $versionResult = & $mockAppPath "--version"
                $versionResult | Should -Be "MockApp v1.2.3"

                # Test help command
                $helpResult = & $mockAppPath "--help"
                $helpResult | Should -Be "MockApp Help"

            } finally {
                if ($mockAppPath) {
                    Remove-Item $mockAppPath -Force -ErrorAction SilentlyContinue
                }
            }
        }

        It "Should test application availability checking" {
            $testAppPath = Join-Path $script:TestBackupDir "test-availability.ps1"
            $testAppContent = @"
# Test application availability
param([string]`$AppName)

`$testApps = @{
    "git" = "git version 2.40.0"
    "pwsh" = "PowerShell 7.3.0"
    "nonexistent" = `$null
}

if (`$testApps.ContainsKey(`$AppName) -and `$testApps[`$AppName]) {
    Write-Output `$testApps[`$AppName]
    exit 0
} else {
    Write-Error "Application '`$AppName' not found"
    exit 1
}
"@

            try {
                # Create test script
                $testAppContent | Out-File $testAppPath -Encoding UTF8
                Test-Path $testAppPath | Should -Be $true

                # Test existing application
                $gitResult = & $testAppPath "git"
                $gitResult | Should -Match "git version"

                # Test non-existent application (should fail)
                $nonExistentResult = & $testAppPath "nonexistent" 2>&1
                $LASTEXITCODE | Should -Be 1

            } finally {
                if ($testAppPath) {
                    Remove-Item $testAppPath -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }

    Context "Configuration File Validation" {

        It "Should create and validate prerequisite configuration files" {
            $configPath = Join-Path $script:TestBackupDir "prerequisites-config.json"
            $configData = @{
                prerequisites = @(
                    @{
                        type = "script"
                        name = "Test Script"
                        inline_script = "Write-Output 'Success'"
                        expected_output = "Success"
                        on_missing = "warn"
                    },
                    @{
                        type = "registry"
                        name = "Test Registry"
                        path = "HKCU:\Software\Test"
                        on_missing = "fail_backup"
                    }
                )
            }

            try {
                # Create configuration file
                $configData | ConvertTo-Json -Depth 3 | Out-File $configPath -Encoding UTF8
                Test-Path $configPath | Should -Be $true

                # Read and validate configuration
                $readConfig = Get-Content $configPath -Raw | ConvertFrom-Json
                $readConfig.prerequisites.Count | Should -Be 2
                $readConfig.prerequisites[0].type | Should -Be "script"
                $readConfig.prerequisites[1].type | Should -Be "registry"

            } finally {
                if ($configPath) {
                    Remove-Item $configPath -Force -ErrorAction SilentlyContinue
                }
            }
        }

        It "Should handle large prerequisite configuration files" {
            $largeConfigPath = Join-Path $script:TestBackupDir "large-prerequisites.json"
            $largeConfigData = @{
                prerequisites = @()
            }

            # Create many prerequisite entries
            for ($i = 1; $i -le 50; $i++) {
                $largeConfigData.prerequisites += @{
                    type = "script"
                    name = "Test Script $i"
                    inline_script = "Write-Output 'Test $i'"
                    expected_output = "Test $i"
                    on_missing = "warn"
                }
            }

            try {
                # Create large configuration file
                $largeConfigData | ConvertTo-Json -Depth 3 | Out-File $largeConfigPath -Encoding UTF8
                Test-Path $largeConfigPath | Should -Be $true

                # Verify file size and content
                $fileInfo = Get-Item $largeConfigPath
                $fileInfo.Length | Should -BeGreaterThan 1000  # Should be reasonably large

                # Read and validate
                $readConfig = Get-Content $largeConfigPath -Raw | ConvertFrom-Json
                $readConfig.prerequisites.Count | Should -Be 50

            } finally {
                if ($largeConfigPath) {
                    Remove-Item $largeConfigPath -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }

    Context "Temporary File and Directory Management" {

        It "Should create and clean up temporary directories" {
            $tempDir = Join-Path $script:TestBackupDir "temp-prerequisites"

            try {
                # Create temporary directory
                New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
                Test-Path $tempDir | Should -Be $true

                # Create subdirectories
                $subDirs = @("scripts", "registry", "logs")
                foreach ($subDir in $subDirs) {
                    $subDirPath = Join-Path $tempDir $subDir
                    New-Item -ItemType Directory -Path $subDirPath -Force | Out-Null
                    Test-Path $subDirPath | Should -Be $true
                }

                # Create test files in subdirectories
                $testFile = Join-Path $tempDir "scripts\test.ps1"
                "Write-Output 'Test'" | Out-File $testFile
                Test-Path $testFile | Should -Be $true

            } finally {
                # Clean up temporary directory
                if ($tempDir -and (Test-Path $tempDir)) {
                    Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }

        It "Should handle permission and access issues" {
            $restrictedPath = Join-Path $script:TestBackupDir "restricted-test.txt"

            try {
                # Create test file
                "Test content" | Out-File $restrictedPath
                Test-Path $restrictedPath | Should -Be $true

                # Set as read-only (handle different platforms)
                if ($IsLinux -or $env:DOCKER_TEST -eq 'true') {
                    # Linux/Docker: Use chmod to set read-only
                    & chmod 444 $restrictedPath
                    # Check if file is read-only by testing write access
                    $beforeWrite = Get-Content $restrictedPath
                    try {
                        "New content" | Out-File $restrictedPath 2>$null
                        $isReadOnly = (Get-Content $restrictedPath) -eq $beforeWrite
                    } catch {
                        $isReadOnly = $true
                    }
                    $isReadOnly | Should -Be $true
                } else {
                    # Windows: Use Set-ItemProperty
                    Set-ItemProperty -Path $restrictedPath -Name IsReadOnly -Value $true
                    $fileInfo = Get-Item $restrictedPath
                    $fileInfo.IsReadOnly | Should -Be $true
                }

                # Should still be able to read
                $content = Get-Content $restrictedPath
                $content | Should -Be "Test content"

            } finally {
                # Clean up (remove read-only first)
                if (Test-Path $restrictedPath) {
                    if ($IsLinux -or $env:DOCKER_TEST -eq 'true') {
                        & chmod 644 $restrictedPath
                    } else {
                        Set-ItemProperty -Path $restrictedPath -Name IsReadOnly -Value $false
                    }
                    Remove-Item $restrictedPath -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }

    Context "Error Handling and Recovery" {

        It "Should handle corrupted configuration files" {
            $corruptedConfigPath = Join-Path $script:TestBackupDir "corrupted-config.json"
            $corruptedContent = '{ "prerequisites": [ { "type": "script", "name": "Test" } ]'  # Missing closing brace

            try {
                # Create corrupted file
                $corruptedContent | Out-File $corruptedConfigPath -Encoding UTF8
                Test-Path $corruptedConfigPath | Should -Be $true

                # Attempting to parse should fail
                { Get-Content $corruptedConfigPath -Raw | ConvertFrom-Json } | Should -Throw

            } finally {
                if ($corruptedConfigPath) {
                    Remove-Item $corruptedConfigPath -Force -ErrorAction SilentlyContinue
                }
            }
        }

        It "Should handle missing prerequisite files gracefully" {
            $missingFilePath = Join-Path $script:TestBackupDir "missing-file.json"

            # File should not exist
            Test-Path $missingFilePath | Should -Be $false

            # Attempting to read should handle gracefully
            $content = Get-Content $missingFilePath -ErrorAction SilentlyContinue
            $content | Should -BeNullOrEmpty
        }
    }
}

AfterAll {
    # Final cleanup of test directories
    @($script:TestBackupDir, $script:TestRestoreDir) | ForEach-Object {
        if ($_ -and (Test-Path $_)) {
            $items = Get-ChildItem $_ -Recurse -ErrorAction SilentlyContinue
            if ($items) {
                $itemsToRemove = $items | Where-Object { $_.FullName }
                if ($itemsToRemove) {
                    $itemsToRemove | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
                }
            }
        }
    }
}






