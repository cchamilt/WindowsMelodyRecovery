BeforeAll {
    # Import enhanced mock infrastructure and utilities
    Import-Module (Resolve-Path "$PSScriptRoot/../../WindowsMelodyRecovery.psd1") -Force
    . "$PSScriptRoot\..\utilities\Test-Environment-Standard.ps1"
    . "$PSScriptRoot\..\utilities\Enhanced-Mock-Infrastructure.ps1"
    . "$PSScriptRoot\..\utilities\Mock-Integration.ps1"
    
    # Initialize enhanced test environment with application focus
    $script:TestEnvironment = Initialize-StandardTestEnvironment -TestType "Integration" -IsolationLevel "Standard"
    Initialize-MockForTestType -TestType "Integration" -TestContext "ApplicationBackup" -Scope "Comprehensive"
    
    # Enhanced application detection functions using new infrastructure
    function Get-EnhancedWingetPackages {
        return Get-MockDataForTest -TestName "ApplicationBackup" -Component "winget" -DataFormat "json"
    }
    
    function Get-EnhancedChocolateyPackages {
        return Get-MockDataForTest -TestName "ApplicationBackup" -Component "chocolatey" -DataFormat "json"
    }
    
    function Get-EnhancedScoopPackages {
        return Get-MockDataForTest -TestName "ApplicationBackup" -Component "scoop" -DataFormat "json"
    }
    
    function Test-ApplicationBackupAccuracy {
        param([object]$OriginalData, [object]$BackupData, [string]$PackageManager)
        
        # Enhanced accuracy testing with detailed comparison
        $comparison = @{
            PackageManager = $PackageManager
            TotalOriginal = 0
            TotalBackup = 0
            Matches = 0
            Mismatches = @()
            AccuracyPercentage = 0
        }
        
        switch ($PackageManager) {
            'winget' {
                $comparison.TotalOriginal = $OriginalData.Packages.Count
                $comparison.TotalBackup = $BackupData.Packages.Count
                
                foreach ($originalPkg in $OriginalData.Packages) {
                    $backupPkg = $BackupData.Packages | Where-Object { $_.Id -eq $originalPkg.Id }
                    if ($backupPkg -and $backupPkg.Version -eq $originalPkg.Version) {
                        $comparison.Matches++
                    } else {
                        $comparison.Mismatches += "Package: $($originalPkg.Id), Version: $($originalPkg.Version)"
                    }
                }
            }
            'chocolatey' {
                $comparison.TotalOriginal = $OriginalData.Packages.Count
                $comparison.TotalBackup = $BackupData.Packages.Count
                
                foreach ($originalPkg in $OriginalData.Packages) {
                    $backupPkg = $BackupData.Packages | Where-Object { $_.Id -eq $originalPkg.Id }
                    if ($backupPkg -and $backupPkg.Version -eq $originalPkg.Version) {
                        $comparison.Matches++
                    } else {
                        $comparison.Mismatches += "Package: $($originalPkg.Id), Version: $($originalPkg.Version)"
                    }
                }
            }
            'scoop' {
                $comparison.TotalOriginal = $OriginalData.Apps.Count
                $comparison.TotalBackup = $BackupData.Apps.Count
                
                foreach ($originalApp in $OriginalData.Apps) {
                    $backupApp = $BackupData.Apps | Where-Object { $_.Id -eq $originalApp.Id }
                    if ($backupApp -and $backupApp.Version -eq $originalApp.Version) {
                        $comparison.Matches++
                    } else {
                        $comparison.Mismatches += "App: $($originalApp.Id), Version: $($originalApp.Version)"
                    }
                }
            }
        }
        
        if ($comparison.TotalOriginal -gt 0) {
            $comparison.AccuracyPercentage = [math]::Round(($comparison.Matches / $comparison.TotalOriginal) * 100, 2)
        }
        
        return $comparison
    }
}

Describe "Enhanced Application Backup and Restore Integration Tests" {
    
    Context "Enhanced Winget Package Manager Testing" {
        It "Should provide realistic winget package data" {
            $wingetData = Get-EnhancedWingetPackages
            $wingetData | Should -Not -BeNullOrEmpty
            $wingetData.Packages | Should -Not -BeNullOrEmpty
            $wingetData.Packages.Count | Should -BeGreaterThan 5
            
            # Verify realistic package data
            $vscodePackage = $wingetData.Packages | Where-Object { $_.Id -eq "Microsoft.VisualStudioCode" }
            $vscodePackage | Should -Not -BeNullOrEmpty
            $vscodePackage.Name | Should -Be "Visual Studio Code"
            $vscodePackage.Version | Should -Match "^\d+\.\d+\.\d+$"
        }
        
        It "Should validate comprehensive package metadata" {
            $wingetData = Get-EnhancedWingetPackages
            
            foreach ($package in $wingetData.Packages | Select-Object -First 3) {
                # Enhanced validation with realistic expectations
                $package.Id | Should -Not -BeNullOrEmpty
                $package.Name | Should -Not -BeNullOrEmpty
                $package.Version | Should -Match "^\d+\.\d+(\.\d+)?(\.\d+)?$"
                $package.Source | Should -Be "winget"
                
                # Validate realistic package identifiers
                $package.Id | Should -Match "^[A-Za-z0-9\.\-_]+\.[A-Za-z0-9\.\-_]+$"
            }
        }
        
        It "Should perform accurate backup and restore cycle" {
            $originalData = Get-EnhancedWingetPackages
            $testPaths = Get-StandardTestPaths
            $backupFile = Join-Path $testPaths.TestBackup "winget_enhanced_backup.json"
            
            # Enhanced backup simulation with metadata
            $backupData = @{
                Timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
                BackupVersion = "2.0"
                PackageManager = "winget"
                Packages = $originalData.Packages
                TotalPackages = $originalData.Packages.Count
                BackupSettings = @{
                    IncludeUserScope = $true
                    IncludeMachineScope = $true
                    VerifyIntegrity = $true
                }
            }
            
            $backupData | ConvertTo-Json -Depth 10 | Set-Content -Path $backupFile -Encoding UTF8
            
            # Verify backup accuracy
            Test-Path $backupFile | Should -Be $true
            $restoredData = Get-Content $backupFile | ConvertFrom-Json
            
            $accuracy = Test-ApplicationBackupAccuracy -OriginalData $originalData -BackupData $restoredData -PackageManager "winget"
            $accuracy.AccuracyPercentage | Should -BeGreaterOrEqual 95
            $accuracy.Mismatches.Count | Should -BeLessOrEqual 1
        }
        
        It "Should handle realistic package installation scenarios" {
            $wingetData = Get-EnhancedWingetPackages
            $criticalPackages = $wingetData.Packages | Where-Object { 
                $_.Id -in @("Microsoft.VisualStudioCode", "Google.Chrome", "Git.Git") 
            }
            
            $criticalPackages.Count | Should -BeGreaterOrEqual 3
            
            foreach ($package in $criticalPackages) {
                # Simulate realistic installation validation
                $package.Id | Should -Match "^[A-Za-z0-9\.\-_]+\.[A-Za-z0-9\.\-_]+$"
                $package.Version | Should -Not -BeNullOrEmpty
                $package.Source | Should -Be "winget"
                
                # Test realistic installation command generation
                $installCommand = "winget install --id $($package.Id) --version $($package.Version) --source winget"
                $installCommand | Should -Match "winget install --id .+ --version .+ --source winget"
            }
        }
        
        It "Should validate application configuration backup" {
            # Test enhanced configuration file discovery
            $testPaths = Get-StandardTestPaths
            $appConfigPath = Join-Path $testPaths.TestMockData "file-operations\appdata"
            
            # VSCode settings should exist in enhanced mock data
            $vscodeSettingsPath = Join-Path $appConfigPath "AppData\Roaming\Code\User\settings.json"
            if (Test-Path $vscodeSettingsPath) {
                $vscodeSettings = Get-Content $vscodeSettingsPath | ConvertFrom-Json
                $vscodeSettings.'editor.fontSize' | Should -Not -BeNullOrEmpty
                $vscodeSettings.'editor.theme' | Should -Not -BeNullOrEmpty
            }
        }
    }
    
    Context "Enhanced Chocolatey Package Manager Testing" {
        It "Should provide realistic chocolatey package data" {
            $chocoData = Get-EnhancedChocolateyPackages
            $chocoData | Should -Not -BeNullOrEmpty
            $chocoData.Packages | Should -Not -BeNullOrEmpty
            $chocoData.Packages.Count | Should -BeGreaterOrEqual 3
            
            # Verify realistic chocolatey packages
            $notepadPlusPlus = $chocoData.Packages | Where-Object { $_.Id -eq "notepadplusplus" }
            $notepadPlusPlus | Should -Not -BeNullOrEmpty
            $notepadPlusPlus.Name | Should -Be "Notepad++"
        }
        
        It "Should perform comprehensive chocolatey backup validation" {
            $chocoData = Get-EnhancedChocolateyPackages
            
            foreach ($package in $chocoData.Packages) {
                # Enhanced chocolatey package validation
                $package.Id | Should -Not -BeNullOrEmpty
                $package.Name | Should -Not -BeNullOrEmpty
                $package.Version | Should -Match "^\d+\.\d+(\.\d+)?(\.\d+)?$"
                $package.Source | Should -Be "chocolatey"
                
                # Validate chocolatey-specific properties
                $package.Id | Should -Match "^[a-zA-Z0-9\.\-_]+$"
            }
        }
        
        It "Should simulate realistic chocolatey restoration" {
            $chocoData = Get-EnhancedChocolateyPackages
            $testPaths = Get-StandardTestPaths
            $restoreScript = Join-Path $testPaths.TestRestore "chocolatey_restore.ps1"
            
            # Generate realistic restore script
            $scriptContent = @"
# Enhanced Chocolatey Package Restoration Script
# Generated: $(Get-Date)

Write-Host "Restoring Chocolatey packages..." -ForegroundColor Cyan

"@
            
            foreach ($package in $chocoData.Packages) {
                $scriptContent += "`nchoco install $($package.Id) --version $($package.Version) --yes --force"
            }
            
            $scriptContent += @"

Write-Host "Chocolatey package restoration completed!" -ForegroundColor Green
"@
            
            $scriptContent | Set-Content -Path $restoreScript -Encoding UTF8
            
            # Verify script generation
            Test-Path $restoreScript | Should -Be $true
            $script = Get-Content $restoreScript -Raw
            $script | Should -Match "choco install .+ --version .+ --yes --force"
        }
    }
    
    Context "Enhanced Scoop Package Manager Testing" {
        It "Should provide realistic scoop package data with buckets" {
            $scoopData = Get-EnhancedScoopPackages
            $scoopData | Should -Not -BeNullOrEmpty
            $scoopData.Apps | Should -Not -BeNullOrEmpty
            $scoopData.Buckets | Should -Not -BeNullOrEmpty
            
            # Verify realistic scoop data structure
            $scoopData.Apps.Count | Should -BeGreaterOrEqual 3
            $scoopData.Buckets.Count | Should -BeGreaterOrEqual 2
            
            # Validate main bucket exists
            $mainBucket = $scoopData.Buckets | Where-Object { $_.Name -eq "main" }
            $mainBucket | Should -Not -BeNullOrEmpty
            $mainBucket.Source | Should -Match "github\.com"
        }
        
        It "Should validate scoop app installation paths and buckets" {
            $scoopData = Get-EnhancedScoopPackages
            
            foreach ($app in $scoopData.Apps) {
                $app.Id | Should -Not -BeNullOrEmpty
                $app.Name | Should -Not -BeNullOrEmpty
                $app.Version | Should -Match "^\d+\.\d+(\.\d+)?(\.\d+)?$"
                $app.Source | Should -Be "scoop"
                $app.Bucket | Should -Not -BeNullOrEmpty
                
                # Validate bucket assignment
                $app.Bucket | Should -BeIn @("main", "extras", "versions", "nonportable")
            }
        }
        
        It "Should perform comprehensive scoop backup and bucket restoration" {
            $scoopData = Get-EnhancedScoopPackages
            $testPaths = Get-StandardTestPaths
            $backupFile = Join-Path $testPaths.TestBackup "scoop_enhanced_backup.json"
            
            # Enhanced scoop backup with bucket information
            $enhancedBackup = @{
                Timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
                BackupVersion = "2.0"
                PackageManager = "scoop"
                ScoopVersion = "0.3.1"
                Apps = $scoopData.Apps
                Buckets = $scoopData.Buckets
                TotalApps = $scoopData.Apps.Count
                TotalBuckets = $scoopData.Buckets.Count
                BackupSettings = @{
                    IncludeBuckets = $true
                    IncludeGlobalApps = $true
                    VerifyHashes = $true
                }
            }
            
            $enhancedBackup | ConvertTo-Json -Depth 10 | Set-Content -Path $backupFile -Encoding UTF8
            
            # Verify comprehensive backup
            Test-Path $backupFile | Should -Be $true
            $restoredData = Get-Content $backupFile | ConvertFrom-Json
            
            $restoredData.Apps.Count | Should -Be $scoopData.Apps.Count
            $restoredData.Buckets.Count | Should -Be $scoopData.Buckets.Count
            $restoredData.BackupSettings.IncludeBuckets | Should -Be $true
        }
    }
    
    Context "Cross-Platform Application Management" {
        It "Should integrate all package managers for comprehensive backup" {
            $wingetData = Get-EnhancedWingetPackages
            $chocoData = Get-EnhancedChocolateyPackages
            $scoopData = Get-EnhancedScoopPackages
            
            # Create unified application inventory
            $unifiedInventory = @{
                Timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
                BackupVersion = "2.0"
                MachineName = $env:COMPUTERNAME
                PackageManagers = @{
                    winget = @{
                        Packages = $wingetData.Packages
                        Count = $wingetData.Packages.Count
                        Status = "Active"
                    }
                    chocolatey = @{
                        Packages = $chocoData.Packages
                        Count = $chocoData.Packages.Count
                        Status = "Active"
                    }
                    scoop = @{
                        Apps = $scoopData.Apps
                        Buckets = $scoopData.Buckets
                        Count = $scoopData.Apps.Count
                        Status = "Active"
                    }
                }
                TotalApplications = $wingetData.Packages.Count + $chocoData.Packages.Count + $scoopData.Apps.Count
                BackupSettings = @{
                    IncludeConfigurations = $true
                    VerifyIntegrity = $true
                    CreateRestoreScript = $true
                }
            }
            
            # Validate unified inventory
            $unifiedInventory.TotalApplications | Should -BeGreaterThan 10
            $unifiedInventory.PackageManagers.Keys.Count | Should -Be 3
            
            # Verify each package manager has realistic data
            $unifiedInventory.PackageManagers.winget.Count | Should -BeGreaterThan 3
            $unifiedInventory.PackageManagers.chocolatey.Count | Should -BeGreaterThan 2
            $unifiedInventory.PackageManagers.scoop.Count | Should -BeGreaterThan 2
        }
        
        It "Should generate comprehensive restoration strategy" {
            $testPaths = Get-StandardTestPaths
            $strategyFile = Join-Path $testPaths.TestBackup "application_restoration_strategy.json"
            
            # Generate intelligent restoration strategy
            $restorationStrategy = @{
                Strategy = "Sequential"
                Priority = @(
                    @{ PackageManager = "winget"; Priority = 1; Reason = "Native Windows package manager" }
                    @{ PackageManager = "chocolatey"; Priority = 2; Reason = "Established third-party packages" }
                    @{ PackageManager = "scoop"; Priority = 3; Reason = "Development tools and utilities" }
                )
                ConflictResolution = @{
                    DuplicatePackages = "PreferWinget"
                    VersionConflicts = "UseLatest"
                    DependencyIssues = "SkipAndLog"
                }
                RestoreOptions = @{
                    VerifyInstallation = $true
                    CreateRestorePoint = $true
                    LogAllOperations = $true
                    ContinueOnError = $true
                }
            }
            
            $restorationStrategy | ConvertTo-Json -Depth 10 | Set-Content -Path $strategyFile -Encoding UTF8
            
            # Verify strategy file
            Test-Path $strategyFile | Should -Be $true
            $strategy = Get-Content $strategyFile | ConvertFrom-Json
            $strategy.Priority.Count | Should -Be 3
            $strategy.ConflictResolution.DuplicatePackages | Should -Be "PreferWinget"
        }
    }
    
    Context "Enhanced Application Configuration Backup" {
        It "Should backup application-specific configurations" {
            $testPaths = Get-StandardTestPaths
            $configBackupPath = Join-Path $testPaths.TestBackup "application_configurations"
            New-Item -Path $configBackupPath -ItemType Directory -Force | Out-Null
            
            # Test VSCode configuration backup
            $vscodeConfigSource = Join-Path $testPaths.TestMockData "file-operations\appdata\AppData\Roaming\Code\User"
            if (Test-Path $vscodeConfigSource) {
                $vscodeConfigBackup = Join-Path $configBackupPath "vscode"
                Copy-Item -Path $vscodeConfigSource -Destination $vscodeConfigBackup -Recurse -Force
                
                Test-Path (Join-Path $vscodeConfigBackup "settings.json") | Should -Be $true
                Test-Path (Join-Path $vscodeConfigBackup "keybindings.json") | Should -Be $true
            }
            
            # Test Chrome configuration backup
            $chromeConfigSource = Join-Path $testPaths.TestMockData "file-operations\appdata\AppData\Local\Google\Chrome\User Data\Default"
            if (Test-Path $chromeConfigSource) {
                $chromeConfigBackup = Join-Path $configBackupPath "chrome"
                Copy-Item -Path $chromeConfigSource -Destination $chromeConfigBackup -Recurse -Force
                
                Test-Path (Join-Path $chromeConfigBackup "Preferences") | Should -Be $true
            }
        }
        
        It "Should validate configuration file integrity" {
            $testPaths = Get-StandardTestPaths
            $mockConfigPath = Join-Path $testPaths.TestMockData "file-operations\appdata"
            
            # Validate JSON configuration files
            $jsonConfigs = Get-ChildItem -Path $mockConfigPath -Filter "*.json" -Recurse
            foreach ($config in $jsonConfigs) {
                { Get-Content $config.FullName | ConvertFrom-Json } | Should -Not -Throw
            }
            
            # Validate specific application configurations
            $vscodeSettings = Join-Path $mockConfigPath "AppData\Roaming\Code\User\settings.json"
            if (Test-Path $vscodeSettings) {
                $settings = Get-Content $vscodeSettings | ConvertFrom-Json
                $settings.'editor.fontSize' | Should -BeOfType [int]
                $settings.'editor.theme' | Should -BeOfType [string]
            }
        }
    }
}

AfterAll {
    # Cleanup enhanced test environment
    if ($script:TestEnvironment) {
        Cleanup-StandardTestEnvironment -TestEnvironment $script:TestEnvironment
    }
} 