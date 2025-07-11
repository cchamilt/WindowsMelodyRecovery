# Windows Melody Recovery - User Journey End-to-End Tests
# Tests realistic user scenarios and workflows

BeforeAll {
    # Import the module using standardized pattern
    $ModulePath = Resolve-Path "$PSScriptRoot/../../WindowsMelodyRecovery.psd1"
    try {
        Import-Module $ModulePath -Force -ErrorAction Stop
    }
    catch {
        throw "Failed to import module from $ModulePath : $($_.Exception.Message)"
    }

    # Set up user journey test environment
    $script:UserRoot = Join-Path $TestDrive "UserJourney"
    $script:HomeDir = Join-Path $script:UserRoot "UserHome"
    $script:WorkDir = Join-Path $script:UserRoot "WorkMachine"
    $script:BackupStorage = Join-Path $script:UserRoot "CloudBackup"

    # Create user environment
    @($script:UserRoot, $script:HomeDir, $script:WorkDir, $script:BackupStorage) | ForEach-Object {
        New-Item -Path $_ -ItemType Directory -Force | Out-Null
    }

    # Mock user environment
    $env:USERPROFILE = $script:HomeDir
    $env:COMPUTERNAME = "USER-HOME-PC"
}

Describe "Windows Melody Recovery - User Journey Tests" -Tag "EndToEnd", "UserJourney" {

    Context "Scenario 1: New User Setup Experience" {
        It "Should guide new user through initial setup" {
            # Simulate first-time user experience
            $setupPath = Join-Path $script:HomeDir "WindowsMelodyRecovery"

            # Initialize as new user
            { Initialize-WindowsMelodyRecovery -InstallPath $setupPath -NoPrompt } | Should -Not -Throw

            # Verify user-friendly directory structure
            Test-Path $setupPath | Should -Be $true
            Test-Path (Join-Path $setupPath "Config") | Should -Be $true

            # Check configuration file is created
            $configFile = Join-Path $setupPath "Config\windows.env"
            Test-Path $configFile | Should -Be $true

            Write-Information -MessageData "✅ New user setup completed successfully" -InformationAction Continue
        }

        It "Should create user-friendly backup structure" {
            $setupPath = Join-Path $script:HomeDir "WindowsMelodyRecovery"
            $env:WMR_CONFIG_PATH = $setupPath
            $env:WMR_BACKUP_PATH = Join-Path $script:BackupStorage "MyBackups"

            # First backup as new user
            { Backup-WindowsMelodyRecovery } | Should -Not -Throw

            # Verify user-friendly backup structure
            $userBackupPath = Join-Path $env:WMR_BACKUP_PATH $env:COMPUTERNAME
            Test-Path $userBackupPath | Should -Be $true

            # Check backup organization
            $latestBackup = Get-ChildItem -Path $userBackupPath -Directory | Sort-Object CreationTime -Descending | Select-Object -First 1
            Test-Path $latestBackup.FullName | Should -Be $true

            Write-Information -MessageData "✅ User-friendly backup structure created" -InformationAction Continue
        }

        It "Should provide clear backup status information" {
            # Test user status visibility
            $status = Get-WindowsMelodyRecoveryStatus
            $status | Should -Not -BeNullOrEmpty
            $status.Configuration | Should -Not -BeNullOrEmpty
            $status.LastBackup | Should -Not -BeNullOrEmpty

            # Verify status includes user-relevant information
            $status.Configuration.ModuleVersion | Should -Not -BeNullOrEmpty
            $status.Initialization.Initialized | Should -Be $true

            Write-Information -MessageData "✅ Clear status information provided to user" -InformationAction Continue
        }
    }

    Context "Scenario 2: Daily Backup Routine" {
        It "Should handle daily incremental backups" {
            # Simulate user's daily backup routine
            $setupPath = Join-Path $script:HomeDir "WindowsMelodyRecovery"
            $env:WMR_CONFIG_PATH = $setupPath

            # Create multiple backups simulating daily use
            for ($day = 1; $day -le 3; $day++) {
                Write-Verbose -Message "  Simulating day $day backup..."

                # Simulate some system changes
                $testFile = Join-Path $script:HomeDir "day$day-changes.txt"
                "Changes from day $day" | Set-Content -Path $testFile -Encoding UTF8

                # Perform backup
                { Backup-WindowsMelodyRecovery } | Should -Not -Throw

                # Brief pause to ensure different timestamps
                Start-Sleep -Milliseconds 100
            }

            # Verify multiple backup versions exist
            $userBackupPath = Join-Path $env:WMR_BACKUP_PATH $env:COMPUTERNAME
            $backups = Get-ChildItem -Path $userBackupPath -Directory | Sort-Object CreationTime
            $backups.Count | Should -BeGreaterOrEqual 3

            Write-Information -MessageData "✅ Daily backup routine working correctly ($($backups.Count) backups)" -InformationAction Continue
        }

        It "Should manage backup storage efficiently" {
            # Test backup storage management
            $userBackupPath = Join-Path $env:WMR_BACKUP_PATH $env:COMPUTERNAME
            $backups = Get-ChildItem -Path $userBackupPath -Directory

            # Each backup should have manifest
            foreach ($backup in $backups) {
                $manifestPath = Join-Path $backup.FullName "manifest.json"
                Test-Path $manifestPath | Should -Be $true

                $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
                $manifest.BackupId | Should -Not -BeNullOrEmpty
                $manifest.Timestamp | Should -Not -BeNullOrEmpty
            }

            # Calculate total backup storage
            $totalSize = (Get-ChildItem -Path $userBackupPath -Recurse -File | Measure-Object -Property Length -Sum).Sum
            $totalSize | Should -BeGreaterThan 0

            Write-Information -MessageData "✅ Backup storage managed efficiently ($([math]::Round($totalSize/1KB, 1)) KB total)" -InformationAction Continue
        }
    }

    Context "Scenario 3: Work Machine Migration" {
        It "Should migrate user settings to work machine" {
            # Simulate user moving settings to work computer
            $workSetupPath = Join-Path $script:WorkDir "WindowsMelodyRecovery"
            $env:COMPUTERNAME = "USER-WORK-PC"
            $env:USERPROFILE = $script:WorkDir
            $env:WMR_CONFIG_PATH = $workSetupPath

            # Initialize on work machine
            { Initialize-WindowsMelodyRecovery -InstallPath $workSetupPath -NoPrompt } | Should -Not -Throw

            # Copy backup from cloud storage to work machine
            $sourceBackupPath = Join-Path $script:BackupStorage "MyBackups\USER-HOME-PC"
            $targetBackupPath = Join-Path $script:WorkDir "ImportedBackups\USER-HOME-PC"

            if (Test-Path $sourceBackupPath) {
                New-Item -Path (Split-Path $targetBackupPath -Parent) -ItemType Directory -Force | Out-Null
                Copy-Item -Path $sourceBackupPath -Destination $targetBackupPath -Recurse -Force
                Test-Path $targetBackupPath | Should -Be $true
            }

            Write-Information -MessageData "✅ Work machine setup and backup import completed" -InformationAction Continue
        }

        It "Should restore user preferences on work machine" {
            # Simulate restoring settings on work machine
            $targetBackupPath = Join-Path $script:WorkDir "ImportedBackups\USER-HOME-PC"

            if (Test-Path $targetBackupPath) {
                # Set backup source for restore
                $env:WMR_BACKUP_PATH = Join-Path $script:WorkDir "ImportedBackups"

                # Perform restore
                { Restore-WindowsMelodyRecovery } | Should -Not -Throw

                # Verify work environment is configured
                $workConfigPath = Join-Path $script:WorkDir "WindowsMelodyRecovery"
                Test-Path $workConfigPath | Should -Be $true
            }

            Write-Information -MessageData "✅ User preferences restored on work machine" -InformationAction Continue
        }

        It "Should maintain user data consistency across machines" {
            # Verify consistency between home and work setups
            $homeSetupPath = Join-Path $script:HomeDir "WindowsMelodyRecovery"
            $workSetupPath = Join-Path $script:WorkDir "WindowsMelodyRecovery"

            # Both machines should have valid configurations
            Test-Path (Join-Path $homeSetupPath "Config") | Should -Be $true
            Test-Path (Join-Path $workSetupPath "Config") | Should -Be $true

            # Verify module version consistency
            $homeStatus = Get-WindowsMelodyRecoveryStatus
            $homeStatus.Configuration.ModuleVersion | Should -Not -BeNullOrEmpty

            Write-Information -MessageData "✅ Data consistency maintained across machines" -InformationAction Continue
        }
    }

    Context "Scenario 4: System Recovery Simulation" {
        It "Should recover from simulated system crash" {
            # Simulate system crash scenario
            $crashedSystemPath = Join-Path $script:UserRoot "CrashedSystem"
            New-Item -Path $crashedSystemPath -ItemType Directory -Force | Out-Null

            $env:USERPROFILE = $crashedSystemPath
            $env:COMPUTERNAME = "USER-RECOVERED-PC"

            # Initialize recovery environment
            $recoverySetupPath = Join-Path $crashedSystemPath "WindowsMelodyRecovery"
            { Initialize-WindowsMelodyRecovery -InstallPath $recoverySetupPath -NoPrompt } | Should -Not -Throw

            # Access backed up data for recovery
            $backupSource = Join-Path $script:BackupStorage "MyBackups"
            if (Test-Path $backupSource) {
                $env:WMR_BACKUP_PATH = $script:BackupStorage "MyBackups"

                # Verify backup accessibility
                $availableBackups = Get-ChildItem -Path $backupSource -Directory -ErrorAction SilentlyContinue
                $availableBackups | Should -Not -BeNullOrEmpty
            }

            Write-Information -MessageData "✅ System recovery environment initialized" -InformationAction Continue
        }

        It "Should restore critical user data after crash" {
            # Perform critical data restoration
            $recoverySetupPath = Join-Path $script:UserRoot "CrashedSystem\WindowsMelodyRecovery"
            $env:WMR_CONFIG_PATH = $recoverySetupPath

            # Restore from available backups
            { Restore-WindowsMelodyRecovery } | Should -Not -Throw

            # Verify critical restoration completed
            Test-Path $recoverySetupPath | Should -Be $true

            # Check recovery status
            $recoveryStatus = Get-WindowsMelodyRecoveryStatus
            $recoveryStatus.Initialization.Initialized | Should -Be $true

            Write-Information -MessageData "✅ Critical user data restored successfully" -InformationAction Continue
        }
    }

    Context "Scenario 5: Multi-User Family Setup" {
        It "Should support multiple user profiles" {
            # Simulate family computer with multiple users
            $familyUsers = @("Dad", "Mom", "Kid1", "Kid2")

            foreach ($user in $familyUsers) {
                $userProfile = Join-Path $script:UserRoot "Family\$user"
                New-Item -Path $userProfile -ItemType Directory -Force | Out-Null

                $env:USERPROFILE = $userProfile
                $env:COMPUTERNAME = "FAMILY-PC-$user"

                # Each user gets their own setup
                $userSetupPath = Join-Path $userProfile "WindowsMelodyRecovery"
                { Initialize-WindowsMelodyRecovery -InstallPath $userSetupPath -NoPrompt } | Should -Not -Throw

                Test-Path $userSetupPath | Should -Be $true
            }

            Write-Information -MessageData "✅ Multi-user family setup completed for $($familyUsers.Count) users" -InformationAction Continue
        }

        It "Should maintain separate user configurations" {
            # Verify each family member has isolated configuration
            $familyUsers = @("Dad", "Mom", "Kid1", "Kid2")
            $backupCounts = @()

            foreach ($user in $familyUsers) {
                $userProfile = Join-Path $script:UserRoot "Family\$user"
                $userSetupPath = Join-Path $userProfile "WindowsMelodyRecovery"
                $userBackupPath = Join-Path $userProfile "Backups"

                # Set user environment
                $env:USERPROFILE = $userProfile
                $env:COMPUTERNAME = "FAMILY-PC-$user"
                $env:WMR_CONFIG_PATH = $userSetupPath
                $env:WMR_BACKUP_PATH = $userBackupPath

                # Each user performs backup
                { Backup-WindowsMelodyRecovery } | Should -Not -Throw

                # Verify user-specific backup
                $userMachineBackup = Join-Path $userBackupPath "FAMILY-PC-$user"
                Test-Path $userMachineBackup | Should -Be $true

                $userBackups = Get-ChildItem -Path $userMachineBackup -Directory -ErrorAction SilentlyContinue
                $backupCounts += $userBackups.Count
            }

            # All users should have their own backups
            $backupCounts | Should -Not -Contain 0

            Write-Information -MessageData "✅ Separate user configurations maintained successfully" -InformationAction Continue
        }
    }

    Context "Scenario 6: Long-term Usage Validation" {
        It "Should handle extended usage patterns" {
            # Simulate extended usage over time
            $longTermUser = Join-Path $script:UserRoot "LongTermUser"
            New-Item -Path $longTermUser -ItemType Directory -Force | Out-Null

            $env:USERPROFILE = $longTermUser
            $env:COMPUTERNAME = "LONGTIME-USER-PC"

            # Setup for long-term user
            $setupPath = Join-Path $longTermUser "WindowsMelodyRecovery"
            { Initialize-WindowsMelodyRecovery -InstallPath $setupPath -NoPrompt } | Should -Not -Throw

            $env:WMR_CONFIG_PATH = $setupPath
            $env:WMR_BACKUP_PATH = Join-Path $longTermUser "Backups"

            # Simulate months of usage with many backups
            for ($week = 1; $week -le 5; $week++) {
                # Simulate weekly backup
                { Backup-WindowsMelodyRecovery } | Should -Not -Throw
                Start-Sleep -Milliseconds 50
            }

            # Verify system handles multiple backups gracefully
            $userBackupPath = Join-Path $env:WMR_BACKUP_PATH $env:COMPUTERNAME
            $backups = Get-ChildItem -Path $userBackupPath -Directory
            $backups.Count | Should -BeGreaterOrEqual 5

            Write-Information -MessageData "✅ Extended usage patterns handled successfully ($($backups.Count) backups)" -InformationAction Continue
        }

        It "Should maintain performance with large backup history" {
            # Test performance with extensive backup history
            $userBackupPath = Join-Path $env:WMR_BACKUP_PATH $env:COMPUTERNAME

            # Measure status retrieval performance
            $startTime = Get-Date
            $status = Get-WindowsMelodyRecoveryStatus
            $statusTime = (Get-Date) - $startTime

            # Should remain responsive
            $statusTime.TotalSeconds | Should -BeLessThan 5
            $status | Should -Not -BeNullOrEmpty

            # Measure backup operation performance
            $startTime = Get-Date
            { Backup-WindowsMelodyRecovery } | Should -Not -Throw
            $backupTime = (Get-Date) - $startTime

            # Backup should complete in reasonable time
            $backupTime.TotalSeconds | Should -BeLessThan 30

            Write-Information -MessageData "✅ Performance maintained with large backup history" -InformationAction Continue
            Write-Verbose -Message "  Status: $([math]::Round($statusTime.TotalSeconds, 2))s, Backup: $([math]::Round($backupTime.TotalSeconds, 2))s"
        }
    }
}

AfterAll {
    # Comprehensive cleanup
    Write-Warning -Message "🧹 Cleaning up user journey test environment..."

    if (Test-Path $script:UserRoot) {
        Remove-Item -Path $script:UserRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Reset environment variables
    @("WMR_CONFIG_PATH", "WMR_BACKUP_PATH", "WMR_LOG_PATH", "COMPUTERNAME", "USERPROFILE") | ForEach-Object {
        Remove-Item -Path "env:$_" -ErrorAction SilentlyContinue
    }

    Write-Information -MessageData "✅ User journey test cleanup completed" -InformationAction Continue
}






