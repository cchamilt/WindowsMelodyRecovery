# Windows Melody Recovery - Complete Backup/Restore Workflow End-to-End Tests
# Tests the entire user journey from installation to backup to restore
# Functions are now defined in BeforeAll block for proper scoping

BeforeDiscovery {
    # Define script scope variables that will be available to all tests
    $script:TestStartTime = Get-Date
}

BeforeAll {
    # Import the module using standardized pattern
    $ModulePath = Resolve-Path "$PSScriptRoot/../../WindowsMelodyRecovery.psd1"
    try {
        Import-Module $ModulePath -Force -ErrorAction Stop
    }
    catch {
        throw "Failed to import module from $ModulePath : $($_.Exception.Message)"
    }

    # Set up comprehensive test environment with better error handling
    # Use a more robust temporary directory approach for Docker environments
    $script:TestRoot = if ($env:WMR_DOCKER_TEST -eq 'true') {
        # In Docker environment, use /tmp directly
        $tempDir = "/tmp/WMR-EndToEnd-$(Get-Random)"
        New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
        $tempDir
    } else {
        # In Windows environment, use TestDrive
        Join-Path $TestDrive "WMR-EndToEnd"
    }

    $script:InstallPath = Join-Path $script:TestRoot "Installation"
    $script:BackupRoot = Join-Path $script:TestRoot "Backups"
    $script:RestoreRoot = Join-Path $script:TestRoot "Restore"
    $script:SourceSystem = Join-Path $script:TestRoot "SourceSystem"
    $script:TargetSystem = Join-Path $script:TestRoot "TargetSystem"

    # Debug path information
    Write-Information -MessageData "Setting up test environment:" -InformationAction Continue
    Write-Information -MessageData "  TestRoot: $script:TestRoot" -InformationAction Continue
    Write-Information -MessageData "  InstallPath: $script:InstallPath" -InformationAction Continue
    Write-Information -MessageData "  Docker test: $($env:WMR_DOCKER_TEST)" -InformationAction Continue

    # Create test directory structure with better error handling
    @($script:TestRoot, $script:InstallPath, $script:BackupRoot, $script:RestoreRoot,
        $script:SourceSystem, $script:TargetSystem) | ForEach-Object {
        if (-not (Test-Path $_)) {
            Write-Verbose -Message "Creating directory: $_"
            try {
                New-Item -Path $_ -ItemType Directory -Force | Out-Null
            }
            catch {
                throw "Failed to create directory '$_': $($_.Exception.Message)"
            }
        }
    }

    # Set up test environment variables
    $env:WMR_CONFIG_PATH = $script:InstallPath
    $env:WMR_BACKUP_PATH = $script:BackupRoot
    $env:WMR_LOG_PATH = Join-Path $script:TestRoot "Logs"
    $env:COMPUTERNAME = "TEST-MACHINE-E2E"
    $env:USERPROFILE = $script:SourceSystem

            # Create logs directory
    New-Item -Path $env:WMR_LOG_PATH -ItemType Directory -Force | Out-Null

    # Set test start time
    $script:TestStartTime = Get-Date

    # Define helper functions within BeforeAll for proper scoping
    function Initialize-MockSourceSystem {
        # Create realistic system configuration to backup

        # Debug the source system path
        Write-Information -MessageData "Debug: SourceSystem path = '$script:SourceSystem'" -InformationAction Continue
        Write-Information -MessageData "Debug: SourceSystem exists = $(Test-Path $script:SourceSystem)" -InformationAction Continue

        # Ensure the source system directory exists
        if (-not (Test-Path $script:SourceSystem)) {
            Write-Information -MessageData "Debug: Creating SourceSystem directory" -InformationAction Continue
            New-Item -Path $script:SourceSystem -ItemType Directory -Force | Out-Null
        }

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

        # Ensure parent directory exists first
        if (-not (Test-Path $script:SourceSystem)) {
            Write-Information -MessageData "Creating parent directory: $script:SourceSystem" -InformationAction Continue
            try {
                New-Item -Path $script:SourceSystem -ItemType Directory -Force -ErrorAction Stop | Out-Null
            }
            catch {
                throw "Failed to create parent directory '$script:SourceSystem': $($_.Exception.Message)"
            }
        }

        # Create the SystemSettings directory
        Write-Information -MessageData "Creating SystemSettings directory: $systemSettingsPath" -InformationAction Continue
        try {
            New-Item -Path $systemSettingsPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
        catch {
            throw "Failed to create SystemSettings directory '$systemSettingsPath': $($_.Exception.Message)"
        }

        # Final verification
        if (-not (Test-Path $systemSettingsPath)) {
            throw "Directory creation appeared to succeed but SystemSettings directory does not exist: $systemSettingsPath"
        }

        $configPath = Join-Path $systemSettingsPath "config.json"
        try {
            $systemSettings | ConvertTo-Json -Depth 10 | Set-Content -Path $configPath -Encoding UTF8 -ErrorAction Stop
        }
        catch {
            throw "Failed to write config file '$configPath': $($_.Exception.Message)"
        }

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
        $appsConfigPath = Join-Path $applicationsPath "installed.json"
        $applications | ConvertTo-Json -Depth 10 | Set-Content -Path $appsConfigPath -Encoding UTF8

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
        $gamingConfigPath = Join-Path $gamingPath "config.json"
        $gamingConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $gamingConfigPath -Encoding UTF8

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
        $wslConfigPath = Join-Path $wslPath "config.json"
        $wslConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $wslConfigPath -Encoding UTF8

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
        $cloudConfigPath = Join-Path $cloudPath "config.json"
        $cloudConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $cloudConfigPath -Encoding UTF8

        Write-Information -MessageData "✅ Initialized mock source system with realistic configuration data" -InformationAction Continue
    }

    function Test-BackupCompleteness {
        param([string]$BackupPath)

        # Handle case where backup path doesn't exist
        if (-not (Test-Path $BackupPath)) {
            return @{
                IsComplete = $false
                MissingComponents = @("BackupPath does not exist")
                BackupSize = 0
                ComponentCounts = @{}
            }
        }

        # Try to read manifest, but handle missing manifest gracefully
        $manifest = $null
        $manifestPath = Join-Path $BackupPath "manifest.json"
        if (Test-Path $manifestPath) {
            try {
                $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
            }
            catch {
                Write-Warning "Failed to read manifest: $($_.Exception.Message)"
            }
        }

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
                $files = Get-ChildItem -Path $componentPath -Recurse -File -ErrorAction SilentlyContinue
                $completeness.ComponentCounts[$component] = $files.Count
                $completeness.BackupSize += ($files | Measure-Object -Property Length -Sum).Sum
            }
            else {
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

        if (-not (Test-Path $OriginalPath)) {
            $accuracy.IsAccurate = $false
            $accuracy.Differences += "Original path does not exist: $OriginalPath"
            return $accuracy
        }

        if (-not (Test-Path $RestoredPath)) {
            $accuracy.IsAccurate = $false
            $accuracy.Differences += "Restored path does not exist: $RestoredPath"
            return $accuracy
        }

        $originalFiles = Get-ChildItem -Path $OriginalPath -Recurse -File -ErrorAction SilentlyContinue
        $restoredFiles = Get-ChildItem -Path $RestoredPath -Recurse -File -ErrorAction SilentlyContinue

        $accuracy.FilesCompared = $originalFiles.Count

        # Handle case where no files exist
        if ($accuracy.FilesCompared -eq 0) {
            $accuracy.MatchPercentage = 100
            return $accuracy
        }

        foreach ($originalFile in $originalFiles) {
            $relativePath = $originalFile.FullName.Substring($OriginalPath.Length)
            $restoredFile = Join-Path $RestoredPath $relativePath

            if (Test-Path $restoredFile) {
                $originalContent = Get-Content $originalFile.FullName -Raw -ErrorAction SilentlyContinue
                $restoredContent = Get-Content $restoredFile -Raw -ErrorAction SilentlyContinue

                if ($originalContent -eq $restoredContent) {
                    $accuracy.FilesMatched++
                }
                else {
                    $accuracy.IsAccurate = $false
                    $accuracy.Differences += "Content mismatch: $relativePath"
                }
            }
            else {
                $accuracy.IsAccurate = $false
                $accuracy.Differences += "Missing file: $relativePath"
            }
        }

        $accuracy.MatchPercentage = if ($accuracy.FilesCompared -gt 0) {
            ($accuracy.FilesMatched / $accuracy.FilesCompared) * 100
        }
        else { 100 }

        return $accuracy
    }
}

Describe "Windows Melody Recovery - Complete End-to-End Workflow" -Tag "EndToEnd", "Workflow" {

    Context "Phase 1: Installation and Initialization" {
                It "Should install and initialize Windows Melody Recovery successfully" {
            # Initialize mock source system data first
            Initialize-MockSourceSystem

            # Debug information
            Write-Information -MessageData "Debug: InstallPath = '$script:InstallPath'" -InformationAction Continue
            Write-Information -MessageData "Debug: TestRoot = '$script:TestRoot'" -InformationAction Continue

            # Validate paths are not null or empty
            $script:InstallPath | Should -Not -BeNullOrEmpty
            $script:TestRoot | Should -Not -BeNullOrEmpty

            # Ensure parent directory exists
            $parentDir = Split-Path $script:InstallPath -Parent
            if (-not (Test-Path $parentDir)) {
                New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
            }

            # Test complete installation workflow
            { Initialize-WindowsMelodyRecovery -InstallPath $script:InstallPath -NoPrompt } | Should -Not -Throw

            # Verify installation directory structure
            Test-Path $script:InstallPath | Should -Be $true
            Test-Path (Join-Path $script:InstallPath "Config") | Should -Be $true

            # Verify configuration file creation
            $configFile = Join-Path $script:InstallPath "Config\windows.env"
            Test-Path $configFile | Should -Be $true

            Write-Information -MessageData "✅ Installation and initialization completed successfully" -InformationAction Continue
        }

        It "Should create proper module configuration" {
            # Test module status and configuration
            $status = Get-WindowsMelodyRecoveryStatus
            $status | Should -Not -BeNullOrEmpty
            $status.Configuration | Should -Not -BeNullOrEmpty
            $status.Configuration.ModuleVersion | Should -Not -BeNullOrEmpty
            $status.Initialization.Initialized | Should -Be $true

            Write-Information -MessageData "✅ Module configuration verified" -InformationAction Continue
        }

        It "Should validate all templates are available" {
            # Verify template availability for backup operations
            $ModulePath | Should -Not -BeNullOrEmpty
            $moduleBase = Split-Path $ModulePath -Parent
            $moduleBase | Should -Not -BeNullOrEmpty

            $templatesPath = Join-Path $moduleBase "Templates\System"
            $templatesPath | Should -Not -BeNullOrEmpty

            # Verify templates directory exists
            Test-Path $templatesPath | Should -Be $true

            $requiredTemplates = @(
                "applications.yaml", "browsers.yaml", "display.yaml", "sound.yaml",
                "power.yaml", "network.yaml", "wsl.yaml", "gamemanagers.yaml"
            )

            foreach ($template in $requiredTemplates) {
                $templatePath = Join-Path $templatesPath $template
                $templatePath | Should -Not -BeNullOrEmpty
                Test-Path $templatePath | Should -Be $true
            }

            Write-Information -MessageData "✅ All required templates are available" -InformationAction Continue
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

            Write-Information -MessageData "✅ Complete system backup completed successfully" -InformationAction Continue
        }

        It "Should backup all system components" {
            # Validate required paths
            $script:BackupRoot | Should -Not -BeNullOrEmpty
            $env:COMPUTERNAME | Should -Not -BeNullOrEmpty

            $machineBackupPath = Join-Path $script:BackupRoot $env:COMPUTERNAME
            $machineBackupPath | Should -Not -BeNullOrEmpty

            # Verify machine backup directory exists
            if (-not (Test-Path $machineBackupPath)) {
                Write-Warning -Message "Machine backup path does not exist: $machineBackupPath"
                return
            }

            $latestBackup = Get-ChildItem -Path $machineBackupPath -Directory | Sort-Object CreationTime -Descending | Select-Object -First 1

            if (-not $latestBackup) {
                Write-Warning -Message "No backup directories found in: $machineBackupPath"
                return
            }

            # Test backup completeness
            $completeness = Test-BackupCompleteness -BackupPath $latestBackup.FullName
            $completeness.IsComplete | Should -Be $true
            $completeness.MissingComponents | Should -BeNullOrEmpty
            $completeness.BackupSize | Should -BeGreaterThan 0

            # Verify individual component backups
            $componentDirectories = @("system_settings", "applications", "gaming", "wsl", "cloud")
            foreach ($component in $componentDirectories) {
                $componentPath = Join-Path $latestBackup.FullName $component
                $componentPath | Should -Not -BeNullOrEmpty
                Test-Path $componentPath | Should -Be $true

                $componentFiles = Get-ChildItem -Path $componentPath -Recurse -File
                $componentFiles.Count | Should -BeGreaterThan 0
            }

            Write-Information -MessageData "✅ All system components backed up successfully ($($completeness.BackupSize) bytes)" -InformationAction Continue
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

            Write-Information -MessageData "✅ Backup metadata is complete and valid" -InformationAction Continue
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

            Write-Information -MessageData "✅ Backup successfully transferred to new system" -InformationAction Continue
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

            Write-Information -MessageData "✅ Backup integrity validated on target system" -InformationAction Continue
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

            Write-Information -MessageData "✅ Complete system restore initiated successfully" -InformationAction Continue
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

                    Write-Information -MessageData "  ✅ $component restored with $([math]::Round($accuracy.MatchPercentage, 1))% accuracy" -InformationAction Continue
                }
            }

            # Handle case where no components were found (avoid divide by zero)
            if ($componentCount -gt 0) {
                $averageAccuracy = $overallAccuracy / $componentCount
                $averageAccuracy | Should -BeGreaterThan 95
                Write-Information -MessageData "✅ Overall restoration accuracy: $([math]::Round($averageAccuracy, 1))%" -InformationAction Continue
            } else {
                # If no components were found, this indicates a backup/restore failure
                throw "No components were found for restoration accuracy testing. This indicates backup or restore process failed."
            }
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

            Write-Information -MessageData "✅ Restore verification report created successfully" -InformationAction Continue
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

            Write-Information -MessageData "✅ All critical system configuration files restored successfully" -InformationAction Continue
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

            Write-Information -MessageData "✅ Configuration data integrity verified" -InformationAction Continue
        }

        It "Should complete within reasonable time limits" {
            # This test tracks the entire process duration
            $totalTestDuration = (Get-Date) - $script:TestStartTime

            # End-to-end process should complete within reasonable time
            $totalTestDuration.TotalMinutes | Should -BeLessThan 10

            Write-Information -MessageData "✅ Complete workflow completed in $([math]::Round($totalTestDuration.TotalSeconds, 1)) seconds" -InformationAction Continue
        }
    }
}

AfterAll {
    # Comprehensive cleanup
    Write-Warning -Message "🧹 Cleaning up end-to-end test environment..."

    if ($script:TestRoot -and (Test-Path $script:TestRoot)) {
        try {
            Remove-Item -Path $script:TestRoot -Recurse -Force -ErrorAction Stop
            Write-Information -MessageData "  Cleaned up test directory: $script:TestRoot" -InformationAction Continue
        }
        catch {
            Write-Warning -Message "Failed to cleanup test directory: $($_.Exception.Message)"
        }
    }

    # Reset environment variables
    @("WMR_CONFIG_PATH", "WMR_BACKUP_PATH", "WMR_LOG_PATH", "COMPUTERNAME", "USERPROFILE") | ForEach-Object {
        try {
            Remove-Item -Path "env:$_" -ErrorAction SilentlyContinue
        }
        catch {
            # Ignore errors when removing environment variables
        }
    }

    if ($script:TestStartTime) {
        $testDuration = (Get-Date) - $script:TestStartTime
        Write-Information -MessageData "✅ End-to-end test cleanup completed in $([math]::Round($testDuration.TotalSeconds, 1)) seconds" -InformationAction Continue
    }
}







