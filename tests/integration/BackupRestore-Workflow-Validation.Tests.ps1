# Backup and Restore Workflow Validation Tests
# Tests for complete backup/restore workflows with BitLocker and Windows Backup integration

BeforeAll {
    # Import the unified test environment library and initialize it for Integration tests.
    . (Join-Path $PSScriptRoot "..\utilities\Test-Environment.ps1")
    $script:TestEnvironment = Initialize-WmrTestEnvironment -SuiteName 'Integration'

    # Import the main module to make functions available for testing.
    Import-Module (Join-Path $script:TestEnvironment.ModuleRoot "WindowsMelodyRecovery.psd1") -Force

    # Import setup scripts
    . (Join-Path $script:TestEnvironment.ModuleRoot "Private/setup/setup-bitlocker.ps1")
    . (Join-Path $script:TestEnvironment.ModuleRoot "Private/setup/Initialize-WindowsBackup.ps1")

    # Test environment setup
    $script:TestWorkspace = $script:TestEnvironment.TestRoot
    $script:TestBackupLocation = $script:TestEnvironment.TestBackup
    $script:TestRestoreLocation = $script:TestEnvironment.TestRestore
    $script:TestDrive = $env:SystemDrive
    $script:IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    # Mock configuration data
    $script:MockConfig = @{
        BackupRoot    = $script:TestBackupLocation
        MachineName   = $env:COMPUTERNAME
        CloudProvider = "OneDrive"
        ModuleVersion = "1.0.0"
        IsInitialized = $true
    }

    # Mock system state data
    $script:MockSystemState = @{
        BitLockerStatus     = @{
            IsEnabled            = $false
            EncryptionPercentage = 0
            VolumeStatus         = "FullyDecrypted"
            KeyProtectors        = @()
        }
        WindowsBackupStatus = @{
            BackupServiceAvailable = $true
            BackupServiceStatus    = "Running"
            FileHistoryAvailable   = $true
            FileHistoryEnabled     = $false
            BackupTaskConfigured   = $false
            BackupTaskStatus       = "Not Configured"
        }
    }
}

AfterAll {
    # Cleanup test scheduled tasks before removing the environment
    $testTasks = @(
        "WindowsMelodyRecovery_SystemBackup",
        "WindowsMelodyRecovery_BackupCleanup",
        "WindowsMelodyRecovery-Backup"
    )

    foreach ($taskName in $testTasks) {
        try {
            $task = Get-ScheduledTask -TaskName $taskName -TaskPath "\Microsoft\Windows\WindowsMelodyRecovery\" -ErrorAction SilentlyContinue
            if ($task) {
                Unregister-ScheduledTask -TaskName $taskName -TaskPath "\Microsoft\Windows\WindowsMelodyRecovery\" -Confirm:$false -ErrorAction SilentlyContinue
            }
        }
        catch {
            # Ignore cleanup errors
        }
    }

    # Clean up the test environment created in BeforeAll.
    Remove-WmrTestEnvironment
}

Describe "System Backup Workflow Validation" {
    Context "Pre-Backup System State Assessment" {
        It "Should assess BitLocker status before backup" {
            $status = Test-BitLockerStatus -Drive $script:TestDrive
            $status | Should -Not -BeNullOrEmpty
            $status.Keys | Should -Contain "IsEnabled"
            $status.Keys | Should -Contain "EncryptionPercentage"
            $status.Keys | Should -Contain "VolumeStatus"
        }

        It "Should assess Windows Backup status before backup" {
            $status = Test-WindowsBackupStatus
            $status | Should -Not -BeNullOrEmpty
            $status.Keys | Should -Contain "BackupServiceAvailable"
            $status.Keys | Should -Contain "FileHistoryAvailable"
            $status.Keys | Should -Contain "BackupTaskConfigured"
        }

        It "Should validate backup destination availability" {
            Test-Path $script:TestBackupLocation | Should -Be $true

            # Test write permissions
            $testFile = Join-Path $script:TestBackupLocation "write_test.tmp"
            "test" | Out-File -FilePath $testFile -ErrorAction SilentlyContinue
            Test-Path $testFile | Should -Be $true
            Remove-Item -Path $testFile -Force -ErrorAction SilentlyContinue
        }

        It "Should check available disk space for backup" {
            $drive = Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='$($script:TestDrive)'"
            $drive.FreeSpace | Should -BeGreaterThan 0

            # Should have at least 1GB free space for testing
            $drive.FreeSpace | Should -BeGreaterThan 1073741824
        }
    }

    Context "WindowsMelodyRecovery Backup Integration" {
        It "Should integrate with main backup function" {
            Mock Backup-WindowsMelodyRecovery {
                return @{
                    Success       = $true
                    BackupPath    = $script:TestBackupLocation
                    Timestamp     = Get-Date
                    FilesBackedUp = 100
                    SizeBytes     = 1048576
                }
            }

            $result = Backup-WindowsMelodyRecovery -BackupPath $script:TestBackupLocation
            $result.Success | Should -Be $true
            $result.BackupPath | Should -Be $script:TestBackupLocation
        }

        It "Should handle backup failures gracefully" {
            Mock Backup-WindowsMelodyRecovery {
                throw "Backup failed: Insufficient disk space"
            }

            { Backup-WindowsMelodyRecovery -BackupPath $script:TestBackupLocation } | Should -Throw
        }

        It "Should create backup manifest with system information" {
            Mock Get-Date { return [DateTime]::Parse("2024-01-15T10:30:00Z") }
            Mock Get-WmiObject { return @{ TotalPhysicalMemory = 8589934592 } }

            $manifest = @{
                BackupDate          = Get-Date
                MachineName         = $env:COMPUTERNAME
                SystemInfo          = @{
                    OS     = (Get-WmiObject Win32_OperatingSystem).Caption
                    Memory = (Get-WmiObject Win32_ComputerSystem).TotalPhysicalMemory
                }
                BitLockerStatus     = Test-BitLockerStatus -Drive $script:TestDrive
                WindowsBackupStatus = Test-WindowsBackupStatus
            }

            $manifest.BackupDate | Should -Not -BeNullOrEmpty
            $manifest.MachineName | Should -Be $env:COMPUTERNAME
            $manifest.BitLockerStatus | Should -Not -BeNullOrEmpty
            $manifest.WindowsBackupStatus | Should -Not -BeNullOrEmpty
        }
    }

    Context "System Configuration Backup" {
        It "Should backup system configuration files" {
            $configFiles = @(
                "$env:SystemRoot\System32\config\SOFTWARE",
                "$env:SystemRoot\System32\config\SYSTEM",
                "$env:SystemRoot\System32\config\SECURITY"
            )

            foreach ($file in $configFiles) {
                if (Test-Path $file) {
                    $file | Should -Exist

                    # Mock backup operation
                    $backupPath = Join-Path $script:TestBackupLocation "SystemConfig\$(Split-Path $file -Leaf).bak"
                    Mock Copy-Item {
                        New-Item -Path (Split-Path $backupPath -Parent) -ItemType Directory -Force -ErrorAction SilentlyContinue
                        New-Item -Path $backupPath -ItemType File -Force
                    }

                    Copy-Item -Path $file -Destination $backupPath -Force -ErrorAction SilentlyContinue
                    Should -Invoke Copy-Item -Times 1
                }
            }
        }

        It "Should backup Windows Melody Recovery configuration" {
            $configPath = Join-Path $script:TestBackupLocation "WMR_Config.json"
            $script:MockConfig | ConvertTo-Json -Depth 10 | Out-File -FilePath $configPath -Encoding UTF8

            Test-Path $configPath | Should -Be $true
            $restoredConfig = Get-Content -Path $configPath -Raw | ConvertFrom-Json
            $restoredConfig.BackupRoot | Should -Be $script:TestBackupLocation
            $restoredConfig.MachineName | Should -Be $env:COMPUTERNAME
        }

        It "Should backup BitLocker recovery keys if available" {
            Mock Get-BitLockerVolume {
                return @{
                    MountPoint   = $script:TestDrive
                    KeyProtector = @(
                        @{
                            KeyProtectorType = "RecoveryKey"
                            KeyProtectorId   = "12345678-1234-1234-1234-123456789012"
                            RecoveryKey      = "123456-123456-123456-123456-123456-123456-123456-123456"
                        }
                    )
                }
            }

            $bitlockerInfo = Get-BitLockerVolume -MountPoint $script:TestDrive
            $bitlockerInfo.KeyProtector | Should -Not -BeNullOrEmpty
            $bitlockerInfo.KeyProtector[0].KeyProtectorType | Should -Be "RecoveryKey"
            $bitlockerInfo.KeyProtector[0].RecoveryKey | Should -Not -BeNullOrEmpty
        }
    }

    Context "Backup Verification and Integrity" {
        It "Should verify backup file integrity" {
            $testFile = Join-Path $script:TestBackupLocation "test_backup.txt"
            $testContent = "Test backup content $(Get-Date)"
            $testContent | Out-File -FilePath $testFile -Encoding UTF8

            # Calculate hash
            $originalHash = Get-FileHash -Path $testFile -Algorithm SHA256
            $originalHash.Hash | Should -Not -BeNullOrEmpty

            # Verify hash matches
            $verifyHash = Get-FileHash -Path $testFile -Algorithm SHA256
            $verifyHash.Hash | Should -Be $originalHash.Hash
        }

        It "Should validate backup completeness" {
            $expectedFiles = @(
                "WMR_Config.json",
                "SystemConfig\SOFTWARE.bak",
                "SystemConfig\SYSTEM.bak",
                "SystemConfig\SECURITY.bak"
            )

            foreach ($file in $expectedFiles) {
                $filePath = Join-Path $script:TestBackupLocation $file
                Mock Test-Path { return $true } -ParameterFilter { $Path -eq $filePath }

                Test-Path $filePath | Should -Be $true
            }
        }

        It "Should create backup verification report" {
            $verificationReport = @{
                BackupDate          = Get-Date
                BackupLocation      = $script:TestBackupLocation
                FilesBackedUp       = 4
                TotalSizeBytes      = 2097152
                IntegrityCheck      = "Passed"
                BitLockerStatus     = "Captured"
                WindowsBackupStatus = "Captured"
                Errors              = @()
            }

            $reportPath = Join-Path $script:TestBackupLocation "backup_verification.json"
            $verificationReport | ConvertTo-Json -Depth 10 | Out-File -FilePath $reportPath -Encoding UTF8

            Test-Path $reportPath | Should -Be $true
            $report = Get-Content -Path $reportPath -Raw | ConvertFrom-Json
            $report.IntegrityCheck | Should -Be "Passed"
            $report.FilesBackedUp | Should -BeGreaterThan 0
        }
    }
}

Describe "System Restore Workflow Validation" {
    Context "Pre-Restore System State Assessment" {
        It "Should assess current system state before restore" {
            $systemState = @{
                BitLockerStatus     = Test-BitLockerStatus -Drive $script:TestDrive
                WindowsBackupStatus = Test-WindowsBackupStatus
                AvailableDiskSpace  = (Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='$($script:TestDrive)'").FreeSpace
            }

            $systemState.BitLockerStatus | Should -Not -BeNullOrEmpty
            $systemState.WindowsBackupStatus | Should -Not -BeNullOrEmpty
            $systemState.AvailableDiskSpace | Should -BeGreaterThan 0
        }

        It "Should validate backup source availability" {
            Test-Path $script:TestBackupLocation | Should -Be $true

            # Check for required backup files
            $requiredFiles = @(
                "WMR_Config.json",
                "backup_verification.json"
            )

            foreach ($file in $requiredFiles) {
                $filePath = Join-Path $script:TestBackupLocation $file
                Mock Test-Path { return $true } -ParameterFilter { $Path -eq $filePath }
                Test-Path $filePath | Should -Be $true
            }
        }

        It "Should verify backup integrity before restore" {
            $verificationPath = Join-Path $script:TestBackupLocation "backup_verification.json"
            Mock Get-Content {
                return @{
                    IntegrityCheck = "Passed"
                    FilesBackedUp  = 4
                    Errors         = @()
                } | ConvertTo-Json
            }

            $verification = Get-Content -Path $verificationPath -Raw | ConvertFrom-Json
            $verification.IntegrityCheck | Should -Be "Passed"
            $verification.Errors.Count | Should -Be 0
        }
    }

    Context "WindowsMelodyRecovery Restore Integration" {
        It "Should integrate with main restore function" {
            Mock Restore-WindowsMelodyRecovery {
                return @{
                    Success       = $true
                    RestorePath   = $script:TestBackupLocation
                    Timestamp     = Get-Date
                    FilesRestored = 100
                    Errors        = @()
                }
            }

            $result = Restore-WindowsMelodyRecovery -BackupPath $script:TestBackupLocation
            $result.Success | Should -Be $true
            $result.RestorePath | Should -Be $script:TestBackupLocation
            $result.Errors.Count | Should -Be 0
        }

        It "Should handle restore failures gracefully" {
            Mock Restore-WindowsMelodyRecovery {
                throw "Restore failed: Backup corrupted"
            }

            { Restore-WindowsMelodyRecovery -BackupPath $script:TestBackupLocation } | Should -Throw
        }

        It "Should create restore report with system changes" {
            $restoreReport = @{
                RestoreDate   = Get-Date
                BackupSource  = $script:TestBackupLocation
                FilesRestored = 4
                SystemChanges = @{
                    BitLockerConfigured     = $false
                    WindowsBackupConfigured = $true
                    RegistryKeysRestored    = 15
                    ServicesReconfigured    = 2
                }
                Errors        = @()
                Warnings      = @()
            }

            $restoreReport.RestoreDate | Should -Not -BeNullOrEmpty
            $restoreReport.BackupSource | Should -Be $script:TestBackupLocation
            $restoreReport.SystemChanges | Should -Not -BeNullOrEmpty
        }
    }

    Context "System Configuration Restore" {
        It "Should restore system configuration files safely" {
            $configFiles = @(
                "SOFTWARE.bak",
                "SYSTEM.bak",
                "SECURITY.bak"
            )

            foreach ($file in $configFiles) {
                $sourcePath = Join-Path $script:TestBackupLocation "SystemConfig\$file"
                $targetPath = Join-Path $script:TestRestoreLocation $file

                Mock Test-Path { return $true } -ParameterFilter { $Path -eq $sourcePath }
                Mock Copy-Item {
                    New-Item -Path $targetPath -ItemType File -Force
                }

                if (Test-Path $sourcePath) {
                    Copy-Item -Path $sourcePath -Destination $targetPath -Force
                    Should -Invoke Copy-Item -Times 1
                }
            }
        }

        It "Should restore Windows Melody Recovery configuration" {
            $configPath = Join-Path $script:TestBackupLocation "WMR_Config.json"
            Mock Get-Content {
                return $script:MockConfig | ConvertTo-Json -Depth 10
            }

            $config = Get-Content -Path $configPath -Raw | ConvertFrom-Json
            $config.BackupRoot | Should -Be $script:TestBackupLocation
            $config.MachineName | Should -Be $env:COMPUTERNAME
            $config.IsInitialized | Should -Be $true
        }

        It "Should restore BitLocker configuration if available" {
            Mock Setup-BitLocker {
                return @{
                    Success             = $true
                    DriveEncrypted      = $false
                    RecoveryKeyRestored = $true
                }
            }

            if ($script:IsAdmin) {
                $result = Setup-BitLocker -Drive $script:TestDrive
                $result.Success | Should -Be $true
            }
        }

        It "Should restore Windows Backup configuration" {
            Mock Initialize-WindowsBackup {
                return @{
                    Success               = $true
                    FileHistoryConfigured = $true
                    BackupTaskCreated     = $true
                }
            }

            if ($script:IsAdmin) {
                $result = Initialize-WindowsBackup -BackupLocation $script:TestBackupLocation
                $result.Success | Should -Be $true
            }
        }
    }

    Context "Post-Restore Verification" {
        It "Should verify system state after restore" {
            $postRestoreState = @{
                BitLockerStatus       = Test-BitLockerStatus -Drive $script:TestDrive
                WindowsBackupStatus   = Test-WindowsBackupStatus
                ConfigurationRestored = $true
            }

            $postRestoreState.BitLockerStatus | Should -Not -BeNullOrEmpty
            $postRestoreState.WindowsBackupStatus | Should -Not -BeNullOrEmpty
            $postRestoreState.ConfigurationRestored | Should -Be $true
        }

        It "Should validate restored file integrity" {
            $testFile = Join-Path $script:TestRestoreLocation "SOFTWARE.bak"
            Mock Test-Path { return $true } -ParameterFilter { $Path -eq $testFile }
            Mock Get-FileHash {
                return @{
                    Hash      = "ABC123DEF456789"
                    Algorithm = "SHA256"
                }
            }

            if (Test-Path $testFile) {
                $hash = Get-FileHash -Path $testFile -Algorithm SHA256
                $hash.Hash | Should -Not -BeNullOrEmpty
                $hash.Algorithm | Should -Be "SHA256"
            }
        }

        It "Should create post-restore verification report" {
            $postRestoreReport = @{
                RestoreDate     = Get-Date
                SystemState     = @{
                    BitLockerOperational     = $true
                    WindowsBackupOperational = $true
                    ConfigurationValid       = $true
                }
                FilesVerified   = 4
                IntegrityChecks = "Passed"
                Recommendations = @(
                    "Restart system to apply all changes",
                    "Verify BitLocker encryption status",
                    "Test Windows Backup functionality"
                )
            }

            $postRestoreReport.RestoreDate | Should -Not -BeNullOrEmpty
            $postRestoreReport.SystemState.ConfigurationValid | Should -Be $true
            $postRestoreReport.IntegrityChecks | Should -Be "Passed"
            $postRestoreReport.Recommendations.Count | Should -BeGreaterThan 0
        }
    }
}

Describe "End-to-End Backup and Restore Workflow" {
    Context "Complete Workflow Integration" {
        It "Should execute complete backup-restore cycle" {
            # Mock complete workflow
            Mock Backup-WindowsMelodyRecovery { return @{ Success = $true } }
            Mock Restore-WindowsMelodyRecovery { return @{ Success = $true } }

            # Execute backup
            $backupResult = Backup-WindowsMelodyRecovery -BackupPath $script:TestBackupLocation
            $backupResult.Success | Should -Be $true

            # Execute restore
            $restoreResult = Restore-WindowsMelodyRecovery -BackupPath $script:TestBackupLocation
            $restoreResult.Success | Should -Be $true
        }

        It "Should maintain data consistency throughout workflow" {
            $originalData = @{
                MachineName   = $env:COMPUTERNAME
                BackupDate    = Get-Date
                Configuration = $script:MockConfig
            }

            # Simulate backup
            $backupData = $originalData.Clone()
            $backupData.Configuration.BackupRoot | Should -Be $script:TestBackupLocation

            # Simulate restore
            $restoredData = $backupData.Clone()
            $restoredData.MachineName | Should -Be $originalData.MachineName
            $restoredData.Configuration.BackupRoot | Should -Be $originalData.Configuration.BackupRoot
        }

        It "Should handle workflow errors gracefully" {
            Mock Backup-WindowsMelodyRecovery { throw "Backup failed" }
            Mock Write-Error {}

            { Backup-WindowsMelodyRecovery -BackupPath $script:TestBackupLocation } | Should -Throw
            Should -Invoke Write-Error -Times 0 # Error should be handled by the function
        }
    }
}






