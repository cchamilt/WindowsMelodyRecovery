BeforeAll {
    # Import required modules and utilities
    . "$PSScriptRoot\..\utilities\Test-Utilities.ps1"
    . "$PSScriptRoot\..\utilities\Mock-Utilities.ps1"

    # Set up test environment
    $script:TestDataPath = "$PSScriptRoot\..\mock-data"
    $script:TempBackupPath = "$PSScriptRoot\..\test-backups\applications"
    $script:TempRestorePath = "$PSScriptRoot\..\test-restore\applications"

    # Ensure directories exist
    New-Item -Path $script:TempBackupPath -ItemType Directory -Force -ErrorAction SilentlyContinue
    New-Item -Path $script:TempRestorePath -ItemType Directory -Force -ErrorAction SilentlyContinue

    # Mock application detection functions
    function Get-MockWingetPackages {
        $wingetPath = "$script:TestDataPath\appdata\Users\TestUser\AppData\Local\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\winget_installed_packages.json"
        if (Test-Path $wingetPath) {
            return Get-Content $wingetPath | ConvertFrom-Json
        }
        return $null
    }

    function Get-MockChocolateyPackages {
        $chocoPath = "$script:TestDataPath\appdata\Users\TestUser\AppData\Roaming\chocolatey\chocolatey_installed_packages.json"
        if (Test-Path $chocoPath) {
            return Get-Content $chocoPath | ConvertFrom-Json
        }
        return $null
    }

    function Get-MockScoopPackages {
        $scoopPath = "$script:TestDataPath\appdata\Users\TestUser\scoop\apps\scoop_installed_packages.json"
        if (Test-Path $scoopPath) {
            return Get-Content $scoopPath | ConvertFrom-Json
        }
        return $null
    }

    function Get-MockSteamGames {
        $steamPath = "$script:TestDataPath\steam\userdata\123456789\config\localconfig.vdf"
        if (Test-Path $steamPath) {
            # Parse VDF format for Steam games
            $steamConfig = Get-Content $steamPath -Raw
            $games = @()

            # Extract game information from VDF using simpler regex
            if ($steamConfig -match '"730"') {
                $games += @{
                    AppId = "730"
                    LaunchOptions = "-novid -tickrate 128"
                    Name = "Counter-Strike 2"
                }
            }
            if ($steamConfig -match '"440"') {
                $games += @{
                    AppId = "440"
                    LaunchOptions = "-novid -autoconfig"
                    Name = "Team Fortress 2"
                }
            }
            if ($steamConfig -match '"570"') {
                $games += @{
                    AppId = "570"
                    LaunchOptions = "-console"
                    Name = "Dota 2"
                }
            }

            return $games
        }
        return @()
    }
}

Describe "Application Backup and Restore Integration Tests" {

    Context "Winget Package Manager" {
        It "Should backup winget installed packages to JSON" {
            $wingetData = Get-MockWingetPackages
            $wingetData | Should -Not -BeNullOrEmpty
            $wingetData.Sources | Should -Not -BeNullOrEmpty
            $wingetData.Sources[0].Packages.Count | Should -BeGreaterThan 0
        }

        It "Should validate winget package structure" {
            $wingetData = Get-MockWingetPackages
            $firstPackage = $wingetData.Sources[0].Packages[0]

            $firstPackage.PackageIdentifier | Should -Not -BeNullOrEmpty
            $firstPackage.PackageName | Should -Not -BeNullOrEmpty
            $firstPackage.Publisher | Should -Not -BeNullOrEmpty
            $firstPackage.Version | Should -Not -BeNullOrEmpty
            $firstPackage.InstallLocation | Should -Not -BeNullOrEmpty
        }

        It "Should backup and restore winget packages" {
            $wingetData = Get-MockWingetPackages
            $backupFile = "$script:TempBackupPath\winget_backup.json"

            # Simulate backup
            $wingetData | ConvertTo-Json -Depth 10 | Out-File -FilePath $backupFile -Encoding UTF8

            # Verify backup file exists and is valid
            Test-Path $backupFile | Should -Be $true
            $restoredData = Get-Content $backupFile | ConvertFrom-Json
            $restoredData.Sources[0].Packages.Count | Should -Be $wingetData.Sources[0].Packages.Count
        }

        It "Should handle winget package installation simulation" {
            $wingetData = Get-MockWingetPackages
            $packagesToInstall = $wingetData.Sources[0].Packages | Select-Object -First 3

            foreach ($package in $packagesToInstall) {
                # Simulate installation check
                $package.PackageIdentifier | Should -Match "^[A-Za-z0-9\.\-_]+$"
                $package.Version | Should -Match "^\d+\.\d+(\.\d+)?(\.\d+)?$"
            }
        }
    }

    Context "Chocolatey Package Manager" {
        It "Should backup chocolatey installed packages to JSON" {
            $chocoData = Get-MockChocolateyPackages
            $chocoData | Should -Not -BeNullOrEmpty
            $chocoData.packages | Should -Not -BeNullOrEmpty
            $chocoData.packages.Count | Should -BeGreaterThan 0
        }

        It "Should validate chocolatey package structure" {
            $chocoData = Get-MockChocolateyPackages
            $firstPackage = $chocoData.packages[0]

            $firstPackage.name | Should -Not -BeNullOrEmpty
            $firstPackage.version | Should -Not -BeNullOrEmpty
            $firstPackage.title | Should -Not -BeNullOrEmpty
            $firstPackage.install_location | Should -Not -BeNullOrEmpty
            $firstPackage.size | Should -Not -BeNullOrEmpty
        }

        It "Should backup and restore chocolatey packages" {
            $chocoData = Get-MockChocolateyPackages
            $backupFile = "$script:TempBackupPath\chocolatey_backup.json"

            # Simulate backup
            $chocoData | ConvertTo-Json -Depth 10 | Out-File -FilePath $backupFile -Encoding UTF8

            # Verify backup file exists and is valid
            Test-Path $backupFile | Should -Be $true
            $restoredData = Get-Content $backupFile | ConvertFrom-Json
            $restoredData.packages.Count | Should -Be $chocoData.packages.Count
        }

        It "Should handle chocolatey package installation simulation" {
            $chocoData = Get-MockChocolateyPackages
            $packagesToInstall = $chocoData.packages | Select-Object -First 3

            foreach ($package in $packagesToInstall) {
                # Simulate installation check
                $package.name | Should -Match "^[a-zA-Z0-9\.\-_]+$"
                $package.version | Should -Not -BeNullOrEmpty
                $package.install_location | Should -Match "^[C-Z]:\\"
            }
        }
    }

    Context "Scoop Package Manager" {
        It "Should backup scoop installed packages to JSON" {
            $scoopData = Get-MockScoopPackages
            $scoopData | Should -Not -BeNullOrEmpty
            $scoopData.installed_apps | Should -Not -BeNullOrEmpty
            $scoopData.installed_apps.Count | Should -BeGreaterThan 0
        }

        It "Should validate scoop package structure" {
            $scoopData = Get-MockScoopPackages
            $firstApp = $scoopData.installed_apps[0]

            $firstApp.name | Should -Not -BeNullOrEmpty
            $firstApp.version | Should -Not -BeNullOrEmpty
            $firstApp.bucket | Should -Not -BeNullOrEmpty
            $firstApp.install_path | Should -Not -BeNullOrEmpty
            $firstApp.size | Should -Not -BeNullOrEmpty
        }

        It "Should backup and restore scoop packages" {
            $scoopData = Get-MockScoopPackages
            $backupFile = "$script:TempBackupPath\scoop_backup.json"

            # Simulate backup
            $scoopData | ConvertTo-Json -Depth 10 | Out-File -FilePath $backupFile -Encoding UTF8

            # Verify backup file exists and is valid
            Test-Path $backupFile | Should -Be $true
            $restoredData = Get-Content $backupFile | ConvertFrom-Json
            $restoredData.installed_apps.Count | Should -Be $scoopData.installed_apps.Count
        }

        It "Should handle scoop bucket management" {
            $scoopData = Get-MockScoopPackages
            $scoopData.buckets | Should -Not -BeNullOrEmpty
            $scoopData.buckets.Count | Should -BeGreaterThan 0

            foreach ($bucket in $scoopData.buckets) {
                $bucket.name | Should -Not -BeNullOrEmpty
                $bucket.source | Should -Match "^https?://"
                $bucket.updated | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context "Gaming Platform Integration" {
        It "Should backup Steam game library" {
            $steamGames = Get-MockSteamGames
            $steamGames | Should -Not -BeNullOrEmpty
            $steamGames.Count | Should -BeGreaterThan 0

            if ($steamGames.Count -gt 0) {
                $steamGames[0].AppId | Should -Not -BeNullOrEmpty
                $steamGames[0].Name | Should -Not -BeNullOrEmpty
            }
        }

        It "Should validate Steam configuration backup" {
            $steamConfigPath = "$script:TestDataPath\steam\userdata\123456789\config\localconfig.vdf"
            Test-Path $steamConfigPath | Should -Be $true

            $steamConfig = Get-Content $steamConfigPath -Raw
            $steamConfig | Should -Match "UserLocalConfigStore"
            $steamConfig | Should -Match "friends"
            $steamConfig | Should -Match "games"
        }

        It "Should backup Epic Games library" {
            $epicManifestPath = "$script:TestDataPath\epic\Manifest\Manifests\epic_games_library.json"
            Test-Path $epicManifestPath | Should -Be $true

            $epicData = Get-Content $epicManifestPath | ConvertFrom-Json
            $epicData.AppName | Should -Not -BeNullOrEmpty
            $epicData.DisplayName | Should -Not -BeNullOrEmpty
            $epicData.InstallLocation | Should -Not -BeNullOrEmpty
        }

        It "Should backup GOG Galaxy configuration" {
            $gogConfigPath = "$script:TestDataPath\gog\config.cfg"
            Test-Path $gogConfigPath | Should -Be $true

            $gogConfig = Get-Content $gogConfigPath -Raw
            $gogConfig | Should -Match "\[General\]"
            $gogConfig | Should -Match "\[InstalledGames\]"
            $gogConfig | Should -Match "\[UserProfile\]"
        }

        It "Should backup EA App configuration" {
            $eaConfigPath = "$script:TestDataPath\ea\config.xml"
            Test-Path $eaConfigPath | Should -Be $true

            $eaConfig = Get-Content $eaConfigPath -Raw
            $eaConfig | Should -Match "<EADesktopConfig>"
            $eaConfig | Should -Match "<InstalledGames>"
            $eaConfig | Should -Match "<UserProfile>"
        }
    }

    Context "Cross-Platform Package Management" {
        It "Should handle multiple package managers simultaneously" {
            $wingetData = Get-MockWingetPackages
            $chocoData = Get-MockChocolateyPackages
            $scoopData = Get-MockScoopPackages

            # All package managers should have data
            $wingetData | Should -Not -BeNullOrEmpty
            $chocoData | Should -Not -BeNullOrEmpty
            $scoopData | Should -Not -BeNullOrEmpty

            # Total package count should be reasonable
            $totalPackages = $wingetData.Sources[0].Packages.Count + $chocoData.packages.Count + $scoopData.installed_apps.Count
            $totalPackages | Should -BeGreaterThan 20
        }

        It "Should detect package conflicts and duplicates" {
            $wingetData = Get-MockWingetPackages
            $chocoData = Get-MockChocolateyPackages
            $scoopData = Get-MockScoopPackages

            # Check for common applications across package managers
            $wingetApps = $wingetData.Sources[0].Packages | ForEach-Object { $_.PackageName.ToLower() }
            $chocoApps = $chocoData.packages | ForEach-Object { $_.title.ToLower() }
            $scoopApps = $scoopData.installed_apps | ForEach-Object { $_.name.ToLower() }

            # Should find some common applications (like Git, VS Code, Node.js)
            $commonApps = @()
            foreach ($app in $wingetApps) {
                if ($app -like "*git*" -or $app -like "*visual studio code*" -or $app -like "*node*") {
                    $commonApps += $app
                }
            }
            foreach ($app in $chocoApps) {
                if ($app -like "*git*" -or $app -like "*visual studio code*" -or $app -like "*node*") {
                    $commonApps += $app
                }
            }
            foreach ($app in $scoopApps) {
                if ($app -like "*git*" -or $app -like "*visual studio code*" -or $app -like "*node*") {
                    $commonApps += $app
                }
            }

            $commonApps.Count | Should -BeGreaterThan 0
        }

        It "Should create unified application backup" {
            $unifiedBackup = @{
                timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
                computer_name = $env:COMPUTERNAME
                user_name = $env:USERNAME
                package_managers = @{
                    winget = Get-MockWingetPackages
                    chocolatey = Get-MockChocolateyPackages
                    scoop = Get-MockScoopPackages
                }
                gaming_platforms = @{
                    steam = @{
                        config_path = "$script:TestDataPath\steam\userdata\123456789\config\localconfig.vdf"
                        library_path = "$script:TestDataPath\steam\steamapps\libraryfolders.vdf"
                    }
                    epic = @{
                        manifest_path = "$script:TestDataPath\epic\Manifest\Manifests\epic_games_library.json"
                    }
                    gog = @{
                        config_path = "$script:TestDataPath\gog\config.cfg"
                    }
                    ea = @{
                        config_path = "$script:TestDataPath\ea\config.xml"
                    }
                }
            }

            $backupFile = "$script:TempBackupPath\unified_application_backup.json"
            $unifiedBackup | ConvertTo-Json -Depth 10 | Out-File -FilePath $backupFile -Encoding UTF8

            Test-Path $backupFile | Should -Be $true
            $backupSize = (Get-Item $backupFile).Length
            $backupSize | Should -BeGreaterThan 10KB
        }
    }
}

AfterAll {
    # Clean up test files
    if (Test-Path $script:TempBackupPath) {
        Remove-Item -Path $script:TempBackupPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $script:TempRestorePath) {
        Remove-Item -Path $script:TempRestorePath -Recurse -Force -ErrorAction SilentlyContinue
    }
}





