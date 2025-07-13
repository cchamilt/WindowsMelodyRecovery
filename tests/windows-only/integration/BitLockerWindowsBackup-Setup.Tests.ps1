# BitLocker and Windows Backup Setup Integration Tests
# Tests for setup-bitlocker.ps1 and Initialize-WindowsBackup.ps1

BeforeAll {
    # Import the module
    Import-Module (Resolve-Path "$PSScriptRoot/../../WindowsMelodyRecovery.psd1") -Force

    # Import setup scripts
    . "$PSScriptRoot/../../Private/setup/setup-bitlocker.ps1"
    . "$PSScriptRoot/../../Private/setup/Initialize-WindowsBackup.ps1"

    # Test data setup
    $script:TestBackupLocation = Join-Path $env:TEMP "TestBackup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    $script:TestDrive = $env:SystemDrive
    $script:IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    # Mock data for testing
    $script:MockBitLockerStatus = @{
        MountPoint = $script:TestDrive
        ProtectionStatus = "Off"
        EncryptionPercentage = 0
        VolumeStatus = "FullyDecrypted"
        KeyProtector = @()
    }

    $script:MockTPMStatus = @{
        TpmPresent = $true
        TpmReady = $true
        TpmEnabled = $true
    }
}

AfterAll {
    # Cleanup test backup location
    if (Test-Path $script:TestBackupLocation) {
        Remove-Item -Path $script:TestBackupLocation -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Cleanup test scheduled tasks
    $testTasks = @(
        "WindowsMelodyRecovery_SystemBackup",
        "WindowsMelodyRecovery_BackupCleanup"
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
}

Describe "BitLocker Setup Script Tests" {
    Context "BitLocker Status Checking" {
        It "Should have Test-BitLockerStatus function available" {
            Get-Command Test-BitLockerStatus -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It "Should return BitLocker status information" {
            $status = Test-BitLockerStatus -Drive $script:TestDrive
            $status | Should -Not -BeNullOrEmpty
            $status.Keys | Should -Contain "IsEnabled"
            $status.Keys | Should -Contain "EncryptionPercentage"
            $status.Keys | Should -Contain "VolumeStatus"
            $status.Keys | Should -Contain "KeyProtectors"
        }

        It "Should handle invalid drive gracefully" {
            $status = Test-BitLockerStatus -Drive "Z:"
            $status | Should -Not -BeNullOrEmpty
            $status.IsEnabled | Should -Be $false
        }
    }

    Context "BitLocker Setup Function Validation" {
        It "Should have Setup-BitLocker function available" {
            Get-Command Setup-BitLocker -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It "Should require administrator privileges" {
            if (-not $script:IsAdmin) {
                Mock Write-Warning {}
                $result = Setup-BitLocker -Drive $script:TestDrive
                $result | Should -Be $false
                Should -Invoke Write-Warning -Times 1
            }
        }

        It "Should validate drive parameter" {
            $result = Setup-BitLocker -Drive "InvalidDrive"
            $result | Should -Be $false
        }

        It "Should accept valid protector types" {
            { Setup-BitLocker -Drive $script:TestDrive -ProtectorTypes @('TPM', 'RecoveryKey') } | Should -Not -Throw
        }

        It "Should reject invalid protector types" {
            { Setup-BitLocker -Drive $script:TestDrive -ProtectorTypes @('InvalidType') } | Should -Throw
        }
    }

    Context "BitLocker Feature Availability" {
        It "Should check for BitLocker Windows feature" {
            Mock Get-WindowsOptionalFeature { return @{ State = "Enabled" } }
            Mock Write-Information -MessageData {} -InformationAction Continue

            if ($script:IsAdmin) {
                $result = Setup-BitLocker -Drive $script:TestDrive
                Should -Invoke Get-WindowsOptionalFeature -Times 1
            }
        }

        It "Should handle missing BitLocker feature" {
            Mock Get-WindowsOptionalFeature { return $null }
            Mock Enable-WindowsOptionalFeature { throw "Feature not available" }
            Mock Write-Error {}

            if ($script:IsAdmin) {
                $result = Setup-BitLocker -Drive $script:TestDrive
                $result | Should -Be $false
            }
        }
    }

    Context "TPM Status Checking" {
        It "Should check TPM availability" {
            Mock Get-Tpm { return $script:MockTPMStatus }
            Mock Write-Information -MessageData {} -InformationAction Continue

            if ($script:IsAdmin) {
                Setup-BitLocker -Drive $script:TestDrive
                Should -Invoke Get-Tpm -Times 1
            }
        }

        It "Should handle missing TPM gracefully" {
            Mock Get-Tpm { throw "TPM not available" }
            Mock Write-Warning {}

            if ($script:IsAdmin) {
                Setup-BitLocker -Drive $script:TestDrive
                Should -Invoke Write-Warning -AtLeast 1
            }
        }
    }

    Context "BitLocker Configuration" {
        It "Should configure BitLocker policies" {
            Mock Test-Path { return $true }
            Mock New-Item {}
            Mock Set-ItemProperty {}
            Mock Write-Information -MessageData {} -InformationAction Continue

            if ($script:IsAdmin) {
                Setup-BitLocker -Drive $script:TestDrive
                Should -Invoke Set-ItemProperty -AtLeast 1
            }
        }

        It "Should handle registry configuration errors" {
            Mock Set-ItemProperty { throw "Registry access denied" }
            Mock Write-Warning {}

            if ($script:IsAdmin) {
                Setup-BitLocker -Drive $script:TestDrive
                Should -Invoke Write-Warning -AtLeast 1
            }
        }
    }
}

Describe "Windows Backup Setup Script Tests" {
    Context "Windows Backup Service Checking" {
        It "Should have Test-WindowsBackupStatus function available" {
            Get-Command Test-WindowsBackupStatus -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It "Should return Windows Backup status information" {
            $status = Test-WindowsBackupStatus
            $status | Should -Not -BeNullOrEmpty
            $status.Keys | Should -Contain "BackupServiceAvailable"
            $status.Keys | Should -Contain "BackupServiceStatus"
            $status.Keys | Should -Contain "FileHistoryAvailable"
            $status.Keys | Should -Contain "FileHistoryEnabled"
            $status.Keys | Should -Contain "BackupTaskConfigured"
            $status.Keys | Should -Contain "BackupTaskStatus"
        }
    }

    Context "Windows Backup Setup Function Validation" {
        It "Should have Initialize-WindowsBackup function available" {
            Get-Command Initialize-WindowsBackup -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It "Should require administrator privileges" {
            if (-not $script:IsAdmin) {
                Mock Write-Warning {}
                $result = Initialize-WindowsBackup -BackupLocation $script:TestBackupLocation
                $result | Should -Be $false
                Should -Invoke Write-Warning -Times 1
            }
        }

        It "Should accept valid backup frequency values" {
            { Initialize-WindowsBackup -BackupLocation $script:TestBackupLocation -BackupFrequency 'Daily' } | Should -Not -Throw
            { Initialize-WindowsBackup -BackupLocation $script:TestBackupLocation -BackupFrequency 'Weekly' } | Should -Not -Throw
            { Initialize-WindowsBackup -BackupLocation $script:TestBackupLocation -BackupFrequency 'Monthly' } | Should -Not -Throw
        }

        It "Should reject invalid backup frequency values" {
            { Initialize-WindowsBackup -BackupLocation $script:TestBackupLocation -BackupFrequency 'Hourly' } | Should -Throw
        }
    }

    Context "Backup Service Configuration" {
        It "Should check for Windows Backup service" {
            Mock Get-Service { return @{ Status = "Running" } }
            Mock Write-Information -MessageData {} -InformationAction Continue

            if ($script:IsAdmin) {
                Initialize-WindowsBackup -BackupLocation $script:TestBackupLocation
                Should -Invoke Get-Service -Times 1
            }
        }

        It "Should handle missing backup service gracefully" {
            Mock Get-Service { return $null }
            Mock Get-WindowsOptionalFeature { return $null }
            Mock Write-Warning {}

            if ($script:IsAdmin) {
                Initialize-WindowsBackup -BackupLocation $script:TestBackupLocation
                Should -Invoke Write-Warning -AtLeast 1
            }
        }

        It "Should start stopped backup service" {
            Mock Get-Service { return @{ Status = "Stopped" } }
            Mock Start-Service {}
            Mock Write-Information -MessageData {} -InformationAction Continue

            if ($script:IsAdmin) {
                Initialize-WindowsBackup -BackupLocation $script:TestBackupLocation
                Should -Invoke Start-Service -Times 1
            }
        }
    }

    Context "File History Configuration" {
        It "Should configure File History when enabled" {
            Mock Get-WmiObject { return @{ State = 0; TargetUrl = ""; SetState = { param($state) }; Put = {} } }
            Mock Test-Path { return $true }
            Mock Write-Information -MessageData {} -InformationAction Continue

            if ($script:IsAdmin) {
                Initialize-WindowsBackup -BackupLocation $script:TestBackupLocation -EnableFileHistory
                Should -Invoke Get-WmiObject -Times 1
            }
        }

        It "Should handle File History configuration errors" {
            Mock Get-WmiObject { throw "WMI access denied" }
            Mock Write-Warning {}

            if ($script:IsAdmin) {
                Initialize-WindowsBackup -BackupLocation $script:TestBackupLocation -EnableFileHistory
                Should -Invoke Write-Warning -AtLeast 1
            }
        }

        It "Should create backup location if it doesn't exist" {
            Mock Test-Path { return $false }
            Mock New-Item {}
            Mock Get-WmiObject { return @{ State = 0; TargetUrl = ""; SetState = { param($state) }; Put = {} } }
            Mock Write-Information -MessageData {} -InformationAction Continue

            if ($script:IsAdmin) {
                Initialize-WindowsBackup -BackupLocation $script:TestBackupLocation -EnableFileHistory
                Should -Invoke New-Item -Times 1
            }
        }
    }

    Context "System Image Backup Configuration" {
        It "Should configure system image backup when enabled" {
            Mock Test-Path { return $true }
            Mock New-Item {}
            Mock Set-ItemProperty {}
            Mock Write-Information -MessageData {} -InformationAction Continue

            if ($script:IsAdmin) {
                Initialize-WindowsBackup -BackupLocation $script:TestBackupLocation -EnableSystemImageBackup
                Should -Invoke Set-ItemProperty -AtLeast 1
            }
        }

        It "Should handle system image backup configuration errors" {
            Mock Set-ItemProperty { throw "Registry access denied" }
            Mock Write-Warning {}

            if ($script:IsAdmin) {
                Initialize-WindowsBackup -BackupLocation $script:TestBackupLocation -EnableSystemImageBackup
                Should -Invoke Write-Warning -AtLeast 1
            }
        }
    }

    Context "Backup Task Scheduling" {
        It "Should create scheduled backup task" {
            Mock Get-ScheduledTask { return $null }
            Mock New-ScheduledTaskAction { return @{} }
            Mock New-ScheduledTaskTrigger { return @{} }
            Mock New-ScheduledTaskSettingsSet { return @{} }
            Mock New-ScheduledTaskPrincipal { return @{} }
            Mock Register-ScheduledTask {}
            Mock Out-File {}
            Mock Write-Information -MessageData {} -InformationAction Continue

            if ($script:IsAdmin) {
                Initialize-WindowsBackup -BackupLocation $script:TestBackupLocation
                Should -Invoke Register-ScheduledTask -Times 1
            }
        }

        It "Should remove existing backup task before creating new one" {
            Mock Get-ScheduledTask { return @{ TaskName = "WindowsMelodyRecovery_SystemBackup" } }
            Mock Unregister-ScheduledTask {}
            Mock New-ScheduledTaskAction { return @{} }
            Mock New-ScheduledTaskTrigger { return @{} }
            Mock New-ScheduledTaskSettingsSet { return @{} }
            Mock New-ScheduledTaskPrincipal { return @{} }
            Mock Register-ScheduledTask {}
            Mock Out-File {}
            Mock Write-Information -MessageData {} -InformationAction Continue

            if ($script:IsAdmin) {
                Initialize-WindowsBackup -BackupLocation $script:TestBackupLocation
                Should -Invoke Unregister-ScheduledTask -Times 1
            }
        }

        It "Should handle task scheduling errors" {
            Mock Register-ScheduledTask { throw "Task scheduler access denied" }
            Mock Write-Warning {}

            if ($script:IsAdmin) {
                Initialize-WindowsBackup -BackupLocation $script:TestBackupLocation
                Should -Invoke Write-Warning -AtLeast 1
            }
        }
    }

    Context "Backup Retention Policy" {
        It "Should configure backup retention cleanup task" {
            Mock Test-Path { return $true }
            Mock Get-ChildItem { return @() }
            Mock New-ScheduledTaskAction { return @{} }
            Mock New-ScheduledTaskTrigger { return @{} }
            Mock New-ScheduledTaskSettingsSet { return @{} }
            Mock New-ScheduledTaskPrincipal { return @{} }
            Mock Register-ScheduledTask {}
            Mock Out-File {}
            Mock Write-Information -MessageData {} -InformationAction Continue

            if ($script:IsAdmin) {
                Initialize-WindowsBackup -BackupLocation $script:TestBackupLocation -RetentionDays 7
                Should -Invoke Register-ScheduledTask -Times 2 # Main backup + cleanup task
            }
        }

        It "Should handle retention policy configuration errors" {
            Mock Register-ScheduledTask { throw "Task scheduler access denied" }
            Mock Write-Warning {}

            if ($script:IsAdmin) {
                Initialize-WindowsBackup -BackupLocation $script:TestBackupLocation
                Should -Invoke Write-Warning -AtLeast 1
            }
        }
    }
}

Describe "Manual Backup Functionality Tests" {
    Context "Manual Backup Execution" {
        It "Should have Start-WindowsBackupManual function available" {
            Get-Command Start-WindowsBackupManual -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It "Should create backup location if it doesn't exist" {
            Mock Test-Path { return $false }
            Mock New-Item {}
            Mock Write-Information -MessageData {} -InformationAction Continue

            $result = Start-WindowsBackupManual -BackupLocation $script:TestBackupLocation
            Should -Invoke New-Item -Times 1
        }

        It "Should handle system image backup" {
            Mock Test-Path { return $true }
            Mock Invoke-Expression {}
            Mock Write-Information -MessageData {} -InformationAction Continue

            $result = Start-WindowsBackupManual -BackupLocation $script:TestBackupLocation -SystemImageOnly
            Should -Invoke Invoke-Expression -Times 1
        }

        It "Should handle File History backup" {
            Mock Test-Path { return $true }
            Mock Write-Information -MessageData {} -InformationAction Continue

            $result = Start-WindowsBackupManual -BackupLocation $script:TestBackupLocation -FileHistoryOnly
            $result | Should -Be $true
        }

        It "Should handle manual backup errors" {
            Mock Test-Path { throw "Access denied" }
            Mock Write-Error {}

            $result = Start-WindowsBackupManual -BackupLocation $script:TestBackupLocation
            $result | Should -Be $false
        }
    }
}

Describe "Setup Scripts Integration Tests" {
    Context "Setup Script Initialization" {
        It "Should load environment configuration" {
            Mock Import-Environment {}
            Mock Write-Verbose {}
            Mock Write-Information -MessageData {} -InformationAction Continue

            if ($script:IsAdmin) {
                Setup-BitLocker -Drive $script:TestDrive
                Should -Invoke Import-Environment -Times 1
            }
        }

        It "Should handle environment loading errors gracefully" {
            Mock Import-Environment { throw "Environment not found" }
            Mock Write-Verbose {}
            Mock Write-Information -MessageData {} -InformationAction Continue

            if ($script:IsAdmin) {
                Setup-BitLocker -Drive $script:TestDrive
                Should -Invoke Write-Verbose -Times 1
            }
        }
    }

    Context "Setup Script Error Handling" {
        It "Should handle general setup errors in BitLocker setup" {
            Mock Get-WindowsOptionalFeature { throw "Unexpected error" }
            Mock Write-Information -MessageData {} -InformationAction Continue

            if ($script:IsAdmin) {
                $result = Setup-BitLocker -Drive $script:TestDrive
                $result | Should -Be $false
            }
        }

        It "Should handle general setup errors in Windows Backup setup" {
            Mock Get-Service { throw "Unexpected error" }
            Mock Write-Information -MessageData {} -InformationAction Continue

            if ($script:IsAdmin) {
                $result = Initialize-WindowsBackup -BackupLocation $script:TestBackupLocation
                $result | Should -Be $false
            }
        }
    }

    Context "Setup Script Return Values" {
        It "Should return boolean values from BitLocker setup" {
            Mock Get-WindowsOptionalFeature { return @{ State = "Enabled" } }
            Mock Get-BitLockerVolume { return $null }
            Mock Write-Information -MessageData {} -InformationAction Continue

            if ($script:IsAdmin) {
                $result = Setup-BitLocker -Drive $script:TestDrive
                $result | Should -BeOfType [bool]
            }
        }

        It "Should return boolean values from Windows Backup setup" {
            Mock Get-Service { return $null }
            Mock Get-WindowsOptionalFeature { return $null }
            Mock Write-Information -MessageData {} -InformationAction Continue

            if ($script:IsAdmin) {
                $result = Initialize-WindowsBackup -BackupLocation $script:TestBackupLocation
                $result | Should -BeOfType [bool]
            }
        }
    }
}

Describe "Setup Scripts Configuration Validation" {
    Context "Configuration Summary" {
        It "Should provide configuration summary for BitLocker" {
            Mock Get-WindowsOptionalFeature { return @{ State = "Enabled" } }
            Mock Get-BitLockerVolume { return @{ ProtectionStatus = "On"; EncryptionPercentage = 100; VolumeStatus = "FullyEncrypted" } }
            Mock Write-Information -MessageData {} -InformationAction Continue

            if ($script:IsAdmin) {
                $result = Setup-BitLocker -Drive $script:TestDrive
                Should -Invoke Write-Host -ParameterFilter { $Object -match "configuration|completed|successfully" }
            }
        }

        It "Should provide configuration summary for Windows Backup" {
            Mock Get-Service { return $null }
            Mock Format-Table { return "Configuration Summary" }
            Mock Write-Information -MessageData {} -InformationAction Continue

            if ($script:IsAdmin) {
                $result = Initialize-WindowsBackup -BackupLocation $script:TestBackupLocation
                Should -Invoke Write-Host -ParameterFilter { $Object -match "configuration|completed|successfully" }
            }
        }
    }
}








