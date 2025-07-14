# Windows Melody Recovery - Module File Operations Tests
# Tests module functionality with actual file operations (File-Operations Level)
# Logic tests moved to tests/unit/module-tests-Logic.Tests.ps1

BeforeAll {
    # Load Docker test bootstrap for cross-platform compatibility
    . (Join-Path $PSScriptRoot "../utilities/Docker-Test-Bootstrap.ps1")

    # Import only the specific scripts needed to avoid TUI dependencies
    try {
        # Import core module scripts without TUI dependencies
        $CoreScripts = @(
            "Private/Core/WindowsMelodyRecovery.Core.ps1",
            "Private/Core/WindowsMelodyRecovery.Initialization.ps1",
            "Private/Core/PathUtilities.ps1",
            "Private/Core/FileState.ps1",
            "Private/Core/ApplicationState.ps1",
            "Private/Core/ConfigurationValidation.ps1",
            "Private/Core/EncryptionUtilities.ps1",
            "Private/Core/Prerequisites.ps1",
            "Public/Initialize-WindowsMelodyRecovery.ps1",
            "Public/Set-WindowsMelodyRecovery.ps1"
        )

        foreach ($script in $CoreScripts) {
            $scriptPath = Resolve-Path "$PSScriptRoot/../../$script"
            . $scriptPath
        }

        # Initialize script:Config variable that's needed by Set-WindowsMelodyRecovery
        $script:Config = @{
            BackupRoot = $null
            MachineName = $env:COMPUTERNAME
            WindowsMelodyRecoveryPath = $null
            CloudProvider = $null
            ModuleVersion = "1.0.0"
            LastConfigured = $null
            IsInitialized = $false
            EmailSettings = @{
                FromAddress = $null
                ToAddress = $null
                Password = $null
                SmtpServer = $null
                SmtpPort = 587
                EnableSsl = $true
            }
            BackupSettings = @{
                RetentionDays = 30
                ExcludePaths = @()
                IncludePaths = @()
            }
            ScheduleSettings = @{
                BackupSchedule = $null
                UpdateSchedule = $null
            }
            NotificationSettings = @{
                EnableEmail = $false
                NotifyOnSuccess = $false
                NotifyOnFailure = $true
            }
            RecoverySettings = @{
                Mode = "Selective"
                ForceOverwrite = $false
            }
            LoggingSettings = @{
                Path = $null
                Level = "Information"
            }
            UpdateSettings = @{
                AutoUpdate = $true
                ExcludePackages = @()
            }
        }

        # Initialize test environment
        $TestEnvironmentScript = Resolve-Path "$PSScriptRoot/../utilities/Test-Environment.ps1"
        . $TestEnvironmentScript
        Initialize-TestEnvironment -SuiteName 'FileOps' | Out-Null
    }
    catch {
        throw "Cannot find or import required scripts: $($_.Exception.Message)"
    }

    # Set up test environment with real paths in safe test directories
    $TestModulePath = if (Get-Command Get-WmrModulePath -ErrorAction SilentlyContinue) {
        $path = Get-WmrModulePath
        # Ensure we get the actual module file, not the directory
        if (Test-Path $path -PathType Container) {
            Join-Path $path "WindowsMelodyRecovery.psm1"
        }
        else {
            $path
        }
    }
    else {
        # Fallback: determine module path based on current environment
        $moduleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        Join-Path $moduleRoot "WindowsMelodyRecovery.psm1"
    }
    $TestManifestPath = (Resolve-Path "$PSScriptRoot/../../WindowsMelodyRecovery.psd1").Path
    $TestInstallScriptPath = (Resolve-Path "$PSScriptRoot/../../Install-Module.ps1").Path

    # Create temporary test directory in environment-appropriate safe location
    $isDockerEnvironment = ($env:DOCKER_TEST -eq 'true') -or ($env:CONTAINER -eq 'true') -or
    (Test-Path '/.dockerenv' -ErrorAction SilentlyContinue)

    if ($isDockerEnvironment) {
        $TestTempDir = Join-Path "/workspace/Temp" "WindowsMelodyRecovery-FileOps"
    }
    else {
        # Use project Temp directory for local Windows environments
        $moduleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $TestTempDir = Join-Path $moduleRoot "Temp" "WindowsMelodyRecovery-FileOps"
    }

    if (-not (Test-Path $TestTempDir)) {
        New-Item -Path $TestTempDir -ItemType Directory -Force | Out-Null
    }

    # Set up test environment variables
    $env:WMR_CONFIG_PATH = $TestTempDir
    $env:WMR_BACKUP_PATH = Join-Path $TestTempDir "backups"
    $env:WMR_LOG_PATH = Join-Path $TestTempDir "logs"
    $env:COMPUTERNAME = "TEST-MACHINE"
    $env:USERPROFILE = $TestTempDir

    # Create backup and log directories
    New-Item -Path $env:WMR_BACKUP_PATH -ItemType Directory -Force | Out-Null
    New-Item -Path $env:WMR_LOG_PATH -ItemType Directory -Force | Out-Null
}

Describe "Windows Melody Recovery Module - File Operations Tests" -Tag "FileOperations", "Safe" {

    Context "Module File Validation" {
        It "Should have valid module manifest file" {
            Test-Path $TestManifestPath | Should -Be $true

            $manifest = Import-PowerShellDataFile $TestManifestPath
            $manifest.ModuleVersion | Should -Not -BeNullOrEmpty
            $manifest.Author | Should -Not -BeNullOrEmpty
            $manifest.Description | Should -Not -BeNullOrEmpty
            $manifest.PowerShellVersion | Should -Not -BeNullOrEmpty
        }

        It "Should have valid main module file" {
            Test-Path $TestModulePath | Should -Be $true

            # Test syntax by reading and parsing content
            $content = Get-Content $TestModulePath -Raw
            $content | Should -Not -BeNullOrEmpty
            { [System.Management.Automation.PSParser]::Tokenize($content, [ref]$null) } | Should -Not -Throw
        }

        It "Should have valid installation script file" {
            Test-Path $TestInstallScriptPath | Should -Be $true

            # Test syntax by reading and parsing content
            $content = Get-Content $TestInstallScriptPath -Raw
            $content | Should -Not -BeNullOrEmpty
            { [System.Management.Automation.PSParser]::Tokenize($content, [ref]$null) } | Should -Not -Throw
        }
    }

    Context "Directory Creation Operations" {
        It "Should create test directory successfully" {
            $testDir = Join-Path $TestTempDir "creation-test"
            New-Item -Path $testDir -ItemType Directory -Force | Out-Null
            Test-Path $testDir | Should -Be $true

            # Cleanup
            Remove-Item -Path $testDir -Force -ErrorAction SilentlyContinue
        }

        It "Should create configuration directories" {
            $expectedDirs = @(
                (Join-Path $TestTempDir "Config"),
                (Join-Path $TestTempDir "backups"),
                (Join-Path $TestTempDir "logs"),
                (Join-Path $TestTempDir "scripts")
            )

            foreach ($dir in $expectedDirs) {
                New-Item -Path $dir -ItemType Directory -Force | Out-Null
                Test-Path $dir | Should -Be $true
            }
        }

        It "Should create nested directory structures" {
            $nestedDir = Join-Path $TestTempDir "nested\sub\structure"
            New-Item -Path $nestedDir -ItemType Directory -Force | Out-Null
            Test-Path $nestedDir | Should -Be $true
        }
    }

    Context "File Creation and Content Operations" {
        It "Should create and write configuration files" {
            $configDir = Join-Path $TestTempDir "Config"
            New-Item -Path $configDir -ItemType Directory -Force | Out-Null

            $configFile = Join-Path $configDir "windows.env"
            $configContent = @"
# Windows Melody Recovery Configuration
WMR_BACKUP_ROOT=$($TestTempDir)\backups
WMR_LOG_PATH=$($TestTempDir)\logs
"@
            Set-Content -Path $configFile -Value $configContent -Encoding UTF8

            Test-Path $configFile | Should -Be $true
            $readContent = Get-Content $configFile -Raw
            $readContent | Should -Match "WMR_BACKUP_ROOT"
            $readContent | Should -Match "WMR_LOG_PATH"
        }

        It "Should create backup manifest files" {
            $backupPath = Join-Path $TestTempDir "test-backup"
            New-Item -Path $backupPath -ItemType Directory -Force | Out-Null

            $manifestPath = Join-Path $backupPath "manifest.json"
            $testManifest = @{
                ModuleVersion = "1.0.0"
                CreatedDate   = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                BackupType    = "Full"
                Components    = @("SystemSettings", "Applications")
                MachineName   = $env:COMPUTERNAME
            }

            $testManifest | ConvertTo-Json -Depth 10 | Out-File -FilePath $manifestPath -Encoding UTF8

            Test-Path $manifestPath | Should -Be $true
            $manifestContent = Get-Content $manifestPath -Raw | ConvertFrom-Json
            $manifestContent.ModuleVersion | Should -Be "1.0.0"
            $manifestContent.BackupType | Should -Be "Full"
            $manifestContent.MachineName | Should -Be $env:COMPUTERNAME
        }

        It "Should create script files with proper encoding" {
            $scriptDir = Join-Path $TestTempDir "scripts"
            New-Item -Path $scriptDir -ItemType Directory -Force | Out-Null

            $scriptFile = Join-Path $scriptDir "test-script.ps1"
            $scriptContent = @"
# Test Script for Windows Melody Recovery
param(
    [string]`$TestParam = "default"
)

Write-Information -MessageData "Test script executed with parameter: `$TestParam" -InformationAction Continue
"@
            Set-Content -Path $scriptFile -Value $scriptContent -Encoding UTF8

            Test-Path $scriptFile | Should -Be $true
            $readContent = Get-Content $scriptFile -Raw
            $readContent | Should -Match "Test Script for Windows Melody Recovery"
            $readContent | Should -Match "param\("

            # Test script syntax
            { [System.Management.Automation.PSParser]::Tokenize($readContent, [ref]$null) } | Should -Not -Throw
        }
    }

    Context "Initialization File Operations" {
        It "Should initialize with custom configuration path" {
            $customConfigPath = Join-Path $TestTempDir "custom-config"

            # This will create actual directories and files
            { Initialize-WindowsMelodyRecovery -InstallPath $customConfigPath -NoPrompt } | Should -Not -Throw

            Test-Path $customConfigPath | Should -Be $true
        }

        It "Should copy template files during initialization" {
            $initPath = Join-Path $TestTempDir "init-test"

            # Initialize with NoPrompt to avoid user interaction
            { Initialize-WindowsMelodyRecovery -InstallPath $initPath -NoPrompt } | Should -Not -Throw

            Test-Path $initPath | Should -Be $true
            $configDir = Join-Path $initPath "Config"
            Test-Path $configDir | Should -Be $true
        }

        It "Should handle directory creation with special characters" {
            $specialDir = Join-Path $TestTempDir "test-dir with spaces & symbols"
            New-Item -Path $specialDir -ItemType Directory -Force | Out-Null
            Test-Path $specialDir | Should -Be $true

            # Test file creation in special directory
            $testFile = Join-Path $specialDir "config.json"
            '{"test": "data"}' | Out-File -FilePath $testFile -Encoding UTF8
            Test-Path $testFile | Should -Be $true
        }
    }

    Context "Backup File Operations" {
        It "Should create backup directory structure" {
            $backupRoot = Join-Path $TestTempDir "backup-test"
            $machineName = $env:COMPUTERNAME
            $expectedBackupPath = Join-Path $backupRoot $machineName

            New-Item -Path $expectedBackupPath -ItemType Directory -Force | Out-Null
            Test-Path $expectedBackupPath | Should -Be $true

            # Create subdirectories
            $subdirs = @("system_settings", "applications", "gaming", "cloud")
            foreach ($subdir in $subdirs) {
                $subdirPath = Join-Path $expectedBackupPath $subdir
                New-Item -Path $subdirPath -ItemType Directory -Force | Out-Null
                Test-Path $subdirPath | Should -Be $true
            }
        }

        It "Should create backup files with correct timestamps" {
            $backupPath = Join-Path $TestTempDir "timestamp-test"
            New-Item -Path $backupPath -ItemType Directory -Force | Out-Null

            $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
            $timestampedFile = Join-Path $backupPath "backup_$timestamp.json"

            $backupData = @{
                Timestamp   = $timestamp
                Data        = "test backup data"
                MachineName = $env:COMPUTERNAME
            }

            $backupData | ConvertTo-Json | Out-File -FilePath $timestampedFile -Encoding UTF8
            Test-Path $timestampedFile | Should -Be $true

            $readData = Get-Content $timestampedFile -Raw | ConvertFrom-Json
            $readData.Timestamp | Should -Be $timestamp
            $readData.MachineName | Should -Be $env:COMPUTERNAME
        }

        It "Should handle large backup files" {
            $backupPath = Join-Path $TestTempDir "large-backup-test"
            New-Item -Path $backupPath -ItemType Directory -Force | Out-Null

            # Create a larger JSON structure to test file handling
            $largeData = @{
                Configuration  = @{}
                Applications   = @()
                SystemSettings = @{}
            }

            # Add test data
            for ($i = 1; $i -le 100; $i++) {
                $largeData.Applications += @{
                    Name        = "TestApp$i"
                    Version     = "1.0.$i"
                    InstallPath = "C:\Program Files\TestApp$i"
                }
            }

            $largeFile = Join-Path $backupPath "large-backup.json"
            $largeData | ConvertTo-Json -Depth 10 | Out-File -FilePath $largeFile -Encoding UTF8

            Test-Path $largeFile | Should -Be $true
            $fileSize = (Get-Item $largeFile).Length
            $fileSize | Should -BeGreaterThan 1KB

            # Verify content integrity
            $readData = Get-Content $largeFile -Raw | ConvertFrom-Json
            $readData.Applications.Count | Should -Be 100
        }
    }

    Context "Error Handling File Operations" {
        It "Should handle permission errors gracefully" {
            $restrictedPath = Join-Path $TestTempDir "restricted-test"

            # Create directory first
            New-Item -Path $restrictedPath -ItemType Directory -Force | Out-Null

            # Test file creation in the directory
            $testFile = Join-Path $restrictedPath "test.txt"
            { "test content" | Out-File -FilePath $testFile -Encoding UTF8 } | Should -Not -Throw
            Test-Path $testFile | Should -Be $true
        }

        It "Should handle corrupted file recovery" {
            $corruptedDir = Join-Path $TestTempDir "corrupted-test"
            New-Item -Path $corruptedDir -ItemType Directory -Force | Out-Null

            # Create a corrupted JSON file
            $corruptedFile = Join-Path $corruptedDir "corrupted.json"
            "{ invalid json content" | Out-File -FilePath $corruptedFile -Encoding UTF8

            Test-Path $corruptedFile | Should -Be $true

            # Test recovery by creating backup and recreating
            $backupFile = Join-Path $corruptedDir "corrupted.json.backup"
            Copy-Item -Path $corruptedFile -Destination $backupFile
            Test-Path $backupFile | Should -Be $true

            # Create valid replacement
            '{"recovered": true}' | Out-File -FilePath $corruptedFile -Encoding UTF8 -Force
            $validContent = Get-Content $corruptedFile -Raw | ConvertFrom-Json
            $validContent.recovered | Should -Be $true
        }

        It "Should handle long file paths" {
            $longPath = Join-Path $TestTempDir "very\long\nested\directory\structure\with\many\levels\for\testing\path\limits"
            New-Item -Path $longPath -ItemType Directory -Force | Out-Null
            Test-Path $longPath | Should -Be $true

            $longFile = Join-Path $longPath "test-file-with-very-long-name.json"
            '{"longPath": true}' | Out-File -FilePath $longFile -Encoding UTF8
            Test-Path $longFile | Should -Be $true
        }
    }

    Context "Cleanup and Maintenance Operations" {
        It "Should clean up temporary files" {
            $tempDir = Join-Path $TestTempDir "temp-cleanup-test"
            New-Item -Path $tempDir -ItemType Directory -Force | Out-Null

            # Create some temporary files
            $tempFiles = @()
            for ($i = 1; $i -le 5; $i++) {
                $tempFile = Join-Path $tempDir "temp$i.tmp"
                "temporary content $i" | Out-File -FilePath $tempFile -Encoding UTF8
                $tempFiles += $tempFile
                Test-Path $tempFile | Should -Be $true
            }

            # Cleanup temporary files
            foreach ($file in $tempFiles) {
                Remove-Item -Path $file -Force -ErrorAction SilentlyContinue
                Test-Path $file | Should -Be $false
            }

            # Remove directory
            Remove-Item -Path $tempDir -Force -ErrorAction SilentlyContinue
            Test-Path $tempDir | Should -Be $false
        }

        It "Should handle directory removal with content" {
            $removeTestDir = Join-Path $TestTempDir "remove-test"
            New-Item -Path $removeTestDir -ItemType Directory -Force | Out-Null

            # Create nested structure with files
            $nestedDir = Join-Path $removeTestDir "nested"
            New-Item -Path $nestedDir -ItemType Directory -Force | Out-Null
            "test content" | Out-File -FilePath (Join-Path $nestedDir "test.txt") -Encoding UTF8

            Test-Path $removeTestDir | Should -Be $true
            Test-Path $nestedDir | Should -Be $true

            # Remove entire structure
            Remove-Item -Path $removeTestDir -Recurse -Force -ErrorAction SilentlyContinue
            Test-Path $removeTestDir | Should -Be $false
        }
    }
}

AfterAll {
    # Comprehensive cleanup
    if (Test-Path $TestTempDir) {
        Remove-Item -Path $TestTempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Reset environment variables
    Remove-Item -Path "env:WMR_CONFIG_PATH" -ErrorAction SilentlyContinue
    Remove-Item -Path "env:WMR_BACKUP_PATH" -ErrorAction SilentlyContinue
    Remove-Item -Path "env:WMR_LOG_PATH" -ErrorAction SilentlyContinue
    Remove-Item -Path "env:COMPUTERNAME" -ErrorAction SilentlyContinue
    Remove-Item -Path "env:USERPROFILE" -ErrorAction SilentlyContinue
}







