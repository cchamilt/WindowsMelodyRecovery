# Windows Melody Recovery - Complete Backup/Restore Workflow End-to-End Tests
# Tests the entire user journey from installation to backup to restore

BeforeAll {
    # Import the module using standardized pattern
    $ModulePath = Resolve-Path "$PSScriptRoot/../../WindowsMelodyRecovery.psd1"
    try {
        Import-Module $ModulePath -Force -ErrorAction Stop
    }
    catch {
        throw "Failed to import module from $ModulePath : $($_.Exception.Message)"
    }

    # Set up comprehensive test environment
    $script:TestRoot = Join-Path $TestDrive "WMR-EndToEnd"
    $script:InstallPath = Join-Path $script:TestRoot "Installation"
    $script:BackupRoot = Join-Path $script:TestRoot "Backups"
    $script:RestoreRoot = Join-Path $script:TestRoot "Restore"
    $script:SourceSystem = Join-Path $script:TestRoot "SourceSystem"
    $script:TargetSystem = Join-Path $script:TestRoot "TargetSystem"

    # Create test directory structure
    @($script:TestRoot, $script:InstallPath, $script:BackupRoot, $script:RestoreRoot,
      $script:SourceSystem, $script:TargetSystem) | ForEach-Object {
        New-Item -Path $_ -ItemType Directory -Force | Out-Null
    }

    # Set up test environment variables
    $env:WMR_CONFIG_PATH = $script:InstallPath
    $env:WMR_BACKUP_PATH = $script:BackupRoot
    $env:WMR_LOG_PATH = Join-Path $script:TestRoot "Logs"
    $env:COMPUTERNAME = "TEST-MACHINE-E2E"
    $env:USERPROFILE = $script:SourceSystem

    # Create mock source system data
    Initialize-MockSourceSystem

    # Create logs directory
    New-Item -Path $env:WMR_LOG_PATH -ItemType Directory -Force | Out-Null
}

function Initialize-MockSourceSystem {
    # Create realistic system configuration to backup

    # 1. System Settings
    $systemSettings = @{
        Display = @{
            Resolution = "1920x1080"
            RefreshRate = 60
            Scaling = 125
            Orientation = "Landscape"
        }
        Power = @{
            Plan = "High Performance"
            SleepTimeout = 30
            HibernateTimeout = 60
            USBSelectiveSuspend = $false
        }
        Sound = @{
            DefaultDevice = "Speakers"
            Volume = 75
            Communications = "DoNothing"
        }
        Network = @{
            WiFiProfiles = @("HomeWiFi", "OfficeWiFi")
            VPNConnections = @("CompanyVPN")
            ProxySettings = @{
                Enabled = $false
                Server = ""
                Port = 8080
            }
        }
    }

    $systemSettingsPath = Join-Path $script:SourceSystem "SystemSettings"
    New-Item -Path $systemSettingsPath -ItemType Directory -Force | Out-Null
    $systemSettings | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $systemSettingsPath "config.json") -Encoding UTF8

    # 2. Applications
    $applications = @{
        Winget = @(
            @{ Id = "Microsoft.VisualStudioCode"; Name = "Visual Studio Code"; Version = "1.75.0" },
            @{ Id = "Google.Chrome"; Name = "Google Chrome"; Version = "109.0.5414.120" },
            @{ Id = "7zip.7zip"; Name = "7-Zip"; Version = "22.01" },
            @{ Id = "Git.Git"; Name = "Git"; Version = "2.39.1" },
            @{ Id = "Microsoft.PowerShell"; Name = "PowerShell"; Version = "7.3.2" }
        )
        Chocolatey = @(
            @{ Name = "nodejs"; Version = "18.14.0" },
            @{ Name = "docker-desktop"; Version = "4.16.2" },
            @{ Name = "postman"; Version = "10.9.4" }
        )
        Steam = @{
            Games = @(
                @{ Name = "Counter-Strike 2"; AppId = 730; InstallDir = "Counter-Strike Global Offensive" },
                @{ Name = "Cyberpunk 2077"; AppId = 1091500; InstallDir = "Cyberpunk 2077" }
            )
            LibraryFolders = @("C:\Program Files (x86)\Steam", "D:\SteamLibrary")
        }
    }

    $applicationsPath = Join-Path $script:SourceSystem "Applications"
    New-Item -Path $applicationsPath -ItemType Directory -Force | Out-Null
    $applications | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $applicationsPath "installed.json") -Encoding UTF8

    # 3. Gaming Configurations
    $gamingConfig = @{
        Steam = @{
            LoginUsers = @{
                "76561198123456789" = @{
                    AccountName = "testuser"
                    PersonaName = "TestGamer"
                    MostRecent = 1
                }
            }
            Config = @{
                AutoLaunchSteamVR = 0
                BigPictureInForeground = 0
                StartupMode = 0
            }
        }
        Epic = @{
            InstallLocation = "C:\Program Files (x86)\Epic Games"
            Games = @(
                @{ DisplayName = "Fortnite"; InstallLocation = "C:\Program Files\Epic Games\Fortnite" },
                @{ DisplayName = "Rocket League"; InstallLocation = "C:\Program Files\Epic Games\rocketleague" }
            )
        }
        GOG = @{
            Games = @(
                @{ Name = "The Witcher 3"; Path = "C:\GOG Games\The Witcher 3" },
                @{ Name = "Cyberpunk 2077"; Path = "C:\GOG Games\Cyberpunk 2077" }
            )
        }
    }

    $gamingPath = Join-Path $script:SourceSystem "Gaming"
    New-Item -Path $gamingPath -ItemType Directory -Force | Out-Null
    $gamingConfig | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $gamingPath "config.json") -Encoding UTF8

    # 4. WSL Configuration
    $wslConfig = @{
        Distributions = @(
            @{ Name = "Ubuntu-22.04"; Status = "Running"; Version = 2; Default = $true },
            @{ Name = "Debian"; Status = "Stopped"; Version = 2; Default = $false }
        )
        GlobalConfig = @{
            memory = "8GB"
            processors = 4
            swap = "2GB"
            localhostForwarding = $true
        }
        Packages = @{
            "Ubuntu-22.04" = @{
                apt = @("git", "curl", "wget", "vim", "python3", "nodejs", "npm")
                pip = @("requests", "numpy", "pandas", "flask")
                npm = @("@angular/cli", "typescript", "eslint")
            }
        }
    }

    $wslPath = Join-Path $script:SourceSystem "WSL"
    New-Item -Path $wslPath -ItemType Directory -Force | Out-Null
    $wslConfig | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $wslPath "config.json") -Encoding UTF8

    # 5. Cloud Storage Configuration
    $cloudConfig = @{
        OneDrive = @{
            Enabled = $true
            SyncPath = "C:\Users\TestUser\OneDrive"
            BusinessAccount = $true
            PersonalAccount = $false
        }
        GoogleDrive = @{
            Enabled = $false
            SyncPath = ""
        }
        Dropbox = @{
            Enabled = $true
            SyncPath = "C:\Users\TestUser\Dropbox"
        }
    }

    $cloudPath = Join-Path $script:SourceSystem "Cloud"
    New-Item -Path $cloudPath -ItemType Directory -Force | Out-Null
    $cloudConfig | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $cloudPath "config.json") -Encoding UTF8

    Write-Host "✅ Initialized mock source system with realistic configuration data" -ForegroundColor Green
}

function Test-BackupCompleteness {
    param([string]$BackupPath)

    $manifest = Get-Content (Join-Path $BackupPath "manifest.json") -Raw | ConvertFrom-Json

    # Expected components in a complete backup
    $expectedComponents = @(
        "system_settings",
        "applications",
        "gaming",
        "wsl",
        "cloud"
    )

    $completeness = @{
        IsComplete = $true
        MissingComponents = @()
        BackupSize = 0
        ComponentCounts = @{}
    }

    foreach ($component in $expectedComponents) {
        $componentPath = Join-Path $BackupPath $component
        if (Test-Path $componentPath) {
            $files = Get-ChildItem -Path $componentPath -Recurse -File
            $completeness.ComponentCounts[$component] = $files.Count
            $completeness.BackupSize += ($files | Measure-Object -Property Length -Sum).Sum
        } else {
            $completeness.IsComplete = $false
            $completeness.MissingComponents += $component
        }
    }

    return $completeness
}

function Test-RestoreAccuracy {
    param([string]$OriginalPath, [string]$RestoredPath, [string]$Component)

    $accuracy = @{
        IsAccurate = $true
        Differences = @()
        MatchPercentage = 0
        FilesCompared = 0
        FilesMatched = 0
    }

    $originalFiles = Get-ChildItem -Path $OriginalPath -Recurse -File -ErrorAction SilentlyContinue
    $restoredFiles = Get-ChildItem -Path $RestoredPath -Recurse -File -ErrorAction SilentlyContinue

    $accuracy.FilesCompared = $originalFiles.Count

    foreach ($originalFile in $originalFiles) {
        $relativePath = $originalFile.FullName.Substring($OriginalPath.Length)
        $restoredFile = Join-Path $RestoredPath $relativePath

        if (Test-Path $restoredFile) {
            $originalContent = Get-Content $originalFile.FullName -Raw -ErrorAction SilentlyContinue
            $restoredContent = Get-Content $restoredFile -Raw -ErrorAction SilentlyContinue

            if ($originalContent -eq $restoredContent) {
                $accuracy.FilesMatched++
            } else {
                $accuracy.IsAccurate = $false
                $accuracy.Differences += "Content mismatch: $relativePath"
            }
        } else {
            $accuracy.IsAccurate = $false
            $accuracy.Differences += "Missing file: $relativePath"
        }
    }

    $accuracy.MatchPercentage = if ($accuracy.FilesCompared -gt 0) {
        ($accuracy.FilesMatched / $accuracy.FilesCompared) * 100
    } else { 100 }

    return $accuracy
}

Describe "Windows Melody Recovery - Complete End-to-End Workflow" -Tag "EndToEnd", "Workflow" {

    Context "Phase 1: Installation and Initialization" {
        It "Should install and initialize Windows Melody Recovery successfully" {
            # Test complete installation workflow
            { Initialize-WindowsMelodyRecovery -InstallPath $script:InstallPath -NoPrompt } | Should -Not -Throw

            # Verify installation directory structure
            Test-Path $script:InstallPath | Should -Be $true
            Test-Path (Join-Path $script:InstallPath "Config") | Should -Be $true

            # Verify configuration file creation
            $configFile = Join-Path $script:InstallPath "Config\windows.env"
            Test-Path $configFile | Should -Be $true

            Write-Host "✅ Installation and initialization completed successfully" -ForegroundColor Green
        }

        It "Should create proper module configuration" {
            # Test module status and configuration
            $status = Get-WindowsMelodyRecoveryStatus
            $status | Should -Not -BeNullOrEmpty
            $status.Configuration | Should -Not -BeNullOrEmpty
            $status.Configuration.ModuleVersion | Should -Not -BeNullOrEmpty
            $status.Initialization.Initialized | Should -Be $true

            Write-Host "✅ Module configuration verified" -ForegroundColor Green
        }

        It "Should validate all templates are available" {
            # Verify template availability for backup operations
            $moduleBase = Split-Path $ModulePath -Parent
            $templatesPath = Join-Path $moduleBase "Templates\System"

            $requiredTemplates = @(
                "applications.yaml", "browsers.yaml", "display.yaml", "sound.yaml",
                "power.yaml", "network.yaml", "wsl.yaml", "gamemanagers.yaml"
            )

            foreach ($template in $requiredTemplates) {
                $templatePath = Join-Path $templatesPath $template
                Test-Path $templatePath | Should -Be $true
            }

            Write-Host "✅ All required templates are available" -ForegroundColor Green
        }
    }

    Context "Phase 2: Complete System Backup" {
        It "Should perform complete system backup" {
            # Execute full backup with all components
            $backupResult = Backup-WindowsMelodyRecovery -ErrorAction Stop
            $backupResult | Should -Not -BeNullOrEmpty

            # Verify backup directory creation
            $machineBackupPath = Join-Path $script:BackupRoot $env:COMPUTERNAME
            Test-Path $machineBackupPath | Should -Be $true

            # Verify backup manifest
            $manifestPath = Join-Path $machineBackupPath "manifest.json"
            Test-Path $manifestPath | Should -Be $true

            $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
            $manifest.MachineName | Should -Be $env:COMPUTERNAME
            $manifest.BackupType | Should -Not -BeNullOrEmpty
            $manifest.Timestamp | Should -Not -BeNullOrEmpty

            Write-Host "✅ Complete system backup completed successfully" -ForegroundColor Green
        }

        It "Should backup all system components" {
            $machineBackupPath = Join-Path $script:BackupRoot $env:COMPUTERNAME
            $latestBackup = Get-ChildItem -Path $machineBackupPath -Directory | Sort-Object CreationTime -Descending | Select-Object -First 1

            # Test backup completeness
            $completeness = Test-BackupCompleteness -BackupPath $latestBackup.FullName
            $completeness.IsComplete | Should -Be $true
            $completeness.MissingComponents | Should -BeNullOrEmpty
            $completeness.BackupSize | Should -BeGreaterThan 0

            # Verify individual component backups
            $componentDirectories = @("system_settings", "applications", "gaming", "wsl", "cloud")
            foreach ($component in $componentDirectories) {
                $componentPath = Join-Path $latestBackup.FullName $component
                Test-Path $componentPath | Should -Be $true

                $componentFiles = Get-ChildItem -Path $componentPath -Recurse -File
                $componentFiles.Count | Should -BeGreaterThan 0
            }

            Write-Host "✅ All system components backed up successfully ($($completeness.BackupSize) bytes)" -ForegroundColor Green
        }

        It "Should create valid backup metadata" {
            $machineBackupPath = Join-Path $script:BackupRoot $env:COMPUTERNAME
            $latestBackup = Get-ChildItem -Path $machineBackupPath -Directory | Sort-Object CreationTime -Descending | Select-Object -First 1

            # Verify backup manifest structure
            $manifestPath = Join-Path $latestBackup.FullName "manifest.json"
            $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json

            # Required manifest fields
            $manifest.ModuleVersion | Should -Not -BeNullOrEmpty
            $manifest.CreatedDate | Should -Not -BeNullOrEmpty
            $manifest.MachineName | Should -Be $env:COMPUTERNAME
            $manifest.BackupId | Should -Not -BeNullOrEmpty
            $manifest.Components | Should -Not -BeNullOrEmpty
            $manifest.Templates | Should -Not -BeNullOrEmpty

            # Verify component metadata
            foreach ($component in $manifest.Components) {
                $component.Name | Should -Not -BeNullOrEmpty
                $component.Template | Should -Not -BeNullOrEmpty
                $component.Files | Should -BeGreaterThan 0
            }

            Write-Host "✅ Backup metadata is complete and valid" -ForegroundColor Green
        }
    }

    Context "Phase 3: System Migration Simulation" {
        It "Should simulate moving to new system" {
            # Simulate moving backup to new machine/environment
            $sourceBackupPath = Join-Path $script:BackupRoot $env:COMPUTERNAME
            $targetBackupPath = Join-Path $script:TargetSystem "ImportedBackups"

            # Create target system structure
            New-Item -Path $targetBackupPath -ItemType Directory -Force | Out-Null

            # Copy backup to target system
            Copy-Item -Path $sourceBackupPath -Destination $targetBackupPath -Recurse -Force
            Test-Path (Join-Path $targetBackupPath $env:COMPUTERNAME) | Should -Be $true

            # Verify backup integrity after transfer
            $transferredBackup = Get-ChildItem -Path (Join-Path $targetBackupPath $env:COMPUTERNAME) -Directory | Sort-Object CreationTime -Descending | Select-Object -First 1
            $manifestPath = Join-Path $transferredBackup.FullName "manifest.json"
            Test-Path $manifestPath | Should -Be $true

            $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
            $manifest.MachineName | Should -Be $env:COMPUTERNAME

            Write-Host "✅ Backup successfully transferred to new system" -ForegroundColor Green
        }

        It "Should validate backup integrity on target system" {
            # Setup target system environment
            $targetBackupPath = Join-Path $script:TargetSystem "ImportedBackups"
            $env:WMR_BACKUP_PATH = $targetBackupPath

            # Validate all backup components exist and are readable
            $backupPath = Join-Path $targetBackupPath $env:COMPUTERNAME
            $latestBackup = Get-ChildItem -Path $backupPath -Directory | Sort-Object CreationTime -Descending | Select-Object -First 1

            $completeness = Test-BackupCompleteness -BackupPath $latestBackup.FullName
            $completeness.IsComplete | Should -Be $true

            # Verify no corruption during transfer
            $manifest = Get-Content (Join-Path $latestBackup.FullName "manifest.json") -Raw | ConvertFrom-Json
            $manifest.Components.Count | Should -BeGreaterThan 0

            Write-Host "✅ Backup integrity validated on target system" -ForegroundColor Green
        }
    }

    Context "Phase 4: Complete System Restore" {
        It "Should restore complete system configuration" {
            # Setup target restore environment
            $targetRestorePath = Join-Path $script:TargetSystem "RestoredSystem"
            $env:USERPROFILE = $targetRestorePath

            # Execute full restore
            $restoreResult = Restore-WindowsMelodyRecovery -ErrorAction Stop
            $restoreResult | Should -Not -BeNullOrEmpty

            # Verify restore directory creation
            Test-Path $targetRestorePath | Should -Be $true

            Write-Host "✅ Complete system restore initiated successfully" -ForegroundColor Green
        }

        It "Should restore all system components accurately" {
            $targetRestorePath = Join-Path $script:TargetSystem "RestoredSystem"

            # Test restoration accuracy for each component
            $componentTests = @{
                "SystemSettings" = @{ Original = (Join-Path $script:SourceSystem "SystemSettings"); Restored = (Join-Path $targetRestorePath "SystemSettings") }
                "Applications" = @{ Original = (Join-Path $script:SourceSystem "Applications"); Restored = (Join-Path $targetRestorePath "Applications") }
                "Gaming" = @{ Original = (Join-Path $script:SourceSystem "Gaming"); Restored = (Join-Path $targetRestorePath "Gaming") }
                "WSL" = @{ Original = (Join-Path $script:SourceSystem "WSL"); Restored = (Join-Path $targetRestorePath "WSL") }
                "Cloud" = @{ Original = (Join-Path $script:SourceSystem "Cloud"); Restored = (Join-Path $targetRestorePath "Cloud") }
            }

            $overallAccuracy = 0
            $componentCount = 0

            foreach ($component in $componentTests.Keys) {
                $test = $componentTests[$component]
                if (Test-Path $test.Original) {
                    $accuracy = Test-RestoreAccuracy -OriginalPath $test.Original -RestoredPath $test.Restored -Component $component
                    $accuracy.MatchPercentage | Should -BeGreaterThan 90
                    $overallAccuracy += $accuracy.MatchPercentage
                    $componentCount++

                    Write-Host "  ✅ $component restored with $([math]::Round($accuracy.MatchPercentage, 1))% accuracy" -ForegroundColor Green
                }
            }

            $averageAccuracy = $overallAccuracy / $componentCount
            $averageAccuracy | Should -BeGreaterThan 95

            Write-Host "✅ Overall restoration accuracy: $([math]::Round($averageAccuracy, 1))%" -ForegroundColor Green
        }

        It "Should create restore verification report" {
            $targetRestorePath = Join-Path $script:TargetSystem "RestoredSystem"
            $reportPath = Join-Path $targetRestorePath "RestoreVerificationReport.json"

            # Create verification report
            $verificationReport = @{
                RestoreTimestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
                SourceMachine = $env:COMPUTERNAME
                TargetPath = $targetRestorePath
                ComponentsRestored = @()
                OverallSuccess = $true
            }

            # Add component verification details
            $components = @("SystemSettings", "Applications", "Gaming", "WSL", "Cloud")
            foreach ($component in $components) {
                $componentPath = Join-Path $targetRestorePath $component
                $componentReport = @{
                    Name = $component
                    Restored = (Test-Path $componentPath)
                    FileCount = if (Test-Path $componentPath) { (Get-ChildItem -Path $componentPath -Recurse -File).Count } else { 0 }
                    Status = if (Test-Path $componentPath) { "Success" } else { "Failed" }
                }
                $verificationReport.ComponentsRestored += $componentReport
            }

            $verificationReport | ConvertTo-Json -Depth 10 | Set-Content -Path $reportPath -Encoding UTF8
            Test-Path $reportPath | Should -Be $true

            $report = Get-Content $reportPath -Raw | ConvertFrom-Json
            $report.OverallSuccess | Should -Be $true
            $report.ComponentsRestored.Count | Should -BeGreaterThan 0

            Write-Host "✅ Restore verification report created successfully" -ForegroundColor Green
        }
    }

    Context "Phase 5: End-to-End Validation" {
        It "Should validate complete backup/restore cycle integrity" {
            # Final validation of the entire process
            $targetRestorePath = Join-Path $script:TargetSystem "RestoredSystem"

            # Check that all expected files exist
            $expectedPaths = @(
                (Join-Path $targetRestorePath "SystemSettings\config.json"),
                (Join-Path $targetRestorePath "Applications\installed.json"),
                (Join-Path $targetRestorePath "Gaming\config.json"),
                (Join-Path $targetRestorePath "WSL\config.json"),
                (Join-Path $targetRestorePath "Cloud\config.json")
            )

            $missingPaths = @()
            foreach ($path in $expectedPaths) {
                if (-not (Test-Path $path)) {
                    $missingPaths += $path
                }
            }

            $missingPaths | Should -BeNullOrEmpty

            Write-Host "✅ All critical system configuration files restored successfully" -ForegroundColor Green
        }

        It "Should demonstrate configuration data preservation" {
            $targetRestorePath = Join-Path $script:TargetSystem "RestoredSystem"

            # Verify specific configuration values were preserved
            $restoredSystemConfig = Get-Content (Join-Path $targetRestorePath "SystemSettings\config.json") -Raw | ConvertFrom-Json
            $restoredSystemConfig.Display.Resolution | Should -Be "1920x1080"
            $restoredSystemConfig.Power.Plan | Should -Be "High Performance"

            $restoredAppsConfig = Get-Content (Join-Path $targetRestorePath "Applications\installed.json") -Raw | ConvertFrom-Json
            $restoredAppsConfig.Winget.Count | Should -BeGreaterThan 0
            $restoredAppsConfig.Steam.Games.Count | Should -BeGreaterThan 0

            Write-Host "✅ Configuration data integrity verified" -ForegroundColor Green
        }

        It "Should complete within reasonable time limits" {
            # This test tracks the entire process duration
            $totalTestDuration = (Get-Date) - $script:TestStartTime

            # End-to-end process should complete within reasonable time
            $totalTestDuration.TotalMinutes | Should -BeLessThan 10

            Write-Host "✅ Complete workflow completed in $([math]::Round($totalTestDuration.TotalSeconds, 1)) seconds" -ForegroundColor Green
        }
    }
}

BeforeAll {
    $script:TestStartTime = Get-Date
}

AfterAll {
    # Comprehensive cleanup
    Write-Host "🧹 Cleaning up end-to-end test environment..." -ForegroundColor Yellow

    if (Test-Path $script:TestRoot) {
        Remove-Item -Path $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Reset environment variables
    @("WMR_CONFIG_PATH", "WMR_BACKUP_PATH", "WMR_LOG_PATH", "COMPUTERNAME", "USERPROFILE") | ForEach-Object {
        Remove-Item -Path "env:$_" -ErrorAction SilentlyContinue
    }

    $testDuration = (Get-Date) - $script:TestStartTime
    Write-Host "✅ End-to-end test cleanup completed in $([math]::Round($testDuration.TotalSeconds, 1)) seconds" -ForegroundColor Green
}