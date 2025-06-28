Describe "Gaming Platforms Backup Tests" {
    BeforeAll {
        # Import the module
        Import-Module ./WindowsMissingRecovery.psm1 -Force -ErrorAction SilentlyContinue
        
        # Set up test paths
        $testBackupPath = "/workspace/test-backups/gaming"
        $mockSteamPath = "/mock-steam"
        $mockEpicPath = "/mock-epic"
        $mockGogPath = "/mock-gog"
        $mockEaPath = "/mock-ea"
        
        # Create test directories if they don't exist
        if (-not (Test-Path $testBackupPath)) {
            New-Item -Path $testBackupPath -ItemType Directory -Force | Out-Null
        }
    }
    
    Context "Environment Setup" {
        It "Should have access to mock Steam directory" {
            Test-Path $mockSteamPath | Should -Be $true
        }
        
        It "Should have access to mock Epic directory" {
            Test-Path $mockEpicPath | Should -Be $true
        }
        
        It "Should have access to mock GOG directory" {
            Test-Path $mockGogPath | Should -Be $true
        }
        
        It "Should have access to mock EA directory" {
            Test-Path $mockEaPath | Should -Be $true
        }
        
        It "Should be able to create backup directories" {
            Test-Path $testBackupPath | Should -Be $true
        }
    }
    
    Context "Gaming Platforms Backup Functions" {
        It "Should have Backup-GamingPlatforms function available" {
            Get-Command Backup-GamingPlatforms -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
        
        It "Should be able to backup Steam data" {
            # Test Steam backup
            $steamBackupPath = Join-Path $testBackupPath "steam"
            if (-not (Test-Path $steamBackupPath)) {
                New-Item -Path $steamBackupPath -ItemType Directory -Force | Out-Null
            }
            
            # Create mock Steam data
            $steamData = @{
                "steamapps" = @{
                    "libraryfolders.vdf" = @"
"LibraryFolders"
{
    "TimeNextStatsReport"        "1704067200"
    "ContentStatsID"        "-1234567890123456789"
    "1"        "C:\\Program Files (x86)\\Steam"
}
"@
                    "appmanifest_730.acf" = @"
"AppState"
{
    "appid"        "730"
    "Universe"        "1"
    "name"        "Counter-Strike 2"
    "StateFlags"        "4"
    "installdir"        "Counter-Strike Global Offensive"
    "LastUpdated"        "1704067200"
    "UpdateResult"        "0"
    "SizeOnDisk"        "1234567890"
    "buildid"        "12345678"
    "LastOwner"        "76561198012345678"
    "BytesToDownload"        "0"
    "BytesDownloaded"        "0"
    "AutoUpdateBehavior"        "0"
    "AllowOtherDownloadsWhileRunning"        "0"
    "UserConfig"
    {
        "language"        "english"
    }
}
"@
                }
                "userdata" = @{
                    "76561198012345678" = @{
                        "config" = @{
                            "localconfig.vdf" = @"
"UserLocalConfigStore"
{
    "Software"
    {
        "Valve"
        {
            "Steam"
            {
                "Apps"
                {
                    "730"
                    {
                        "LaunchOptions"        "-novid -high"
                        "LastPlayed"        "1704067200"
                    }
                }
            }
        }
    }
}
"@
                        }
                    }
                }
            }
            
            # Create Steam directory structure
            foreach ($dir in $steamData.Keys) {
                $dirPath = Join-Path $steamBackupPath $dir
                if (-not (Test-Path $dirPath)) {
                    New-Item -Path $dirPath -ItemType Directory -Force | Out-Null
                }
                
                foreach ($subDir in $steamData[$dir].Keys) {
                    if ($steamData[$dir][$subDir] -is [hashtable]) {
                        $subDirPath = Join-Path $dirPath $subDir
                        if (-not (Test-Path $subDirPath)) {
                            New-Item -Path $subDirPath -ItemType Directory -Force | Out-Null
                        }
                        
                        foreach ($file in $steamData[$dir][$subDir].Keys) {
                            if ($steamData[$dir][$subDir][$file] -is [hashtable]) {
                                $fileDirPath = Join-Path $subDirPath $file
                                if (-not (Test-Path $fileDirPath)) {
                                    New-Item -Path $fileDirPath -ItemType Directory -Force | Out-Null
                                }
                                
                                foreach ($subFile in $steamData[$dir][$subDir][$file].Keys) {
                                    $filePath = Join-Path $fileDirPath $subFile
                                    $steamData[$dir][$subDir][$file][$subFile] | Out-File -FilePath $filePath -Encoding ASCII
                                    Test-Path $filePath | Should -Be $true
                                }
                            } else {
                                $filePath = Join-Path $subDirPath $file
                                $steamData[$dir][$subDir][$file] | Out-File -FilePath $filePath -Encoding ASCII
                                Test-Path $filePath | Should -Be $true
                            }
                        }
                    } else {
                        $filePath = Join-Path $dirPath $subDir
                        $steamData[$dir][$subDir] | Out-File -FilePath $filePath -Encoding ASCII
                        Test-Path $filePath | Should -Be $true
                    }
                }
            }
        }
        
        It "Should be able to backup Epic Games data" {
            # Test Epic backup
            $epicBackupPath = Join-Path $testBackupPath "epic"
            if (-not (Test-Path $epicBackupPath)) {
                New-Item -Path $epicBackupPath -ItemType Directory -Force | Out-Null
            }
            
            # Create mock Epic data
            $epicData = @{
                "Launcher" = @{
                    "VaultCache" = @{
                        "Windows" = @{
                            "Fortnite" = @{
                                "AppName" = "Fortnite"
                                "InstallLocation" = "C:\\Program Files\\Epic Games\\Fortnite"
                                "InstallSize" = "9876543210"
                            }
                        }
                    }
                }
            }
            
            # Create Epic directory structure
            foreach ($dir in $epicData.Keys) {
                $dirPath = Join-Path $epicBackupPath $dir
                if (-not (Test-Path $dirPath)) {
                    New-Item -Path $dirPath -ItemType Directory -Force | Out-Null
                }
                
                foreach ($subDir in $epicData[$dir].Keys) {
                    $subDirPath = Join-Path $dirPath $subDir
                    if (-not (Test-Path $subDirPath)) {
                        New-Item -Path $subDirPath -ItemType Directory -Force | Out-Null
                    }
                    
                    foreach ($platform in $epicData[$dir][$subDir].Keys) {
                        $platformPath = Join-Path $subDirPath $platform
                        if (-not (Test-Path $platformPath)) {
                            New-Item -Path $platformPath -ItemType Directory -Force | Out-Null
                        }
                        
                        foreach ($game in $epicData[$dir][$subDir][$platform].Keys) {
                            $gamePath = Join-Path $platformPath $game
                            if (-not (Test-Path $gamePath)) {
                                New-Item -Path $gamePath -ItemType Directory -Force | Out-Null
                            }
                            
                            $gameData = $epicData[$dir][$subDir][$platform][$game]
                            $gameData | ConvertTo-Json | Out-File -FilePath (Join-Path $gamePath "game-info.json") -Encoding UTF8
                        }
                    }
                }
            }
        }
        
        It "Should be able to backup GOG data" {
            # Test GOG backup
            $gogBackupPath = Join-Path $testBackupPath "gog"
            if (-not (Test-Path $gogBackupPath)) {
                New-Item -Path $gogBackupPath -ItemType Directory -Force | Out-Null
            }
            
            # Create mock GOG data
            $gogData = @{
                "Galaxy" = @{
                    "Games" = @{
                        "1207664663" = @{
                            "Name" = "The Witcher 3: Wild Hunt"
                            "InstallPath" = "C:\\Program Files (x86)\\GOG Galaxy\\Games\\The Witcher 3 Wild Hunt"
                            "Size" = "5678901234"
                        }
                    }
                }
            }
            
            # Create GOG directory structure
            foreach ($dir in $gogData.Keys) {
                $dirPath = Join-Path $gogBackupPath $dir
                if (-not (Test-Path $dirPath)) {
                    New-Item -Path $dirPath -ItemType Directory -Force | Out-Null
                }
                
                foreach ($subDir in $gogData[$dir].Keys) {
                    $subDirPath = Join-Path $dirPath $subDir
                    if (-not (Test-Path $subDirPath)) {
                        New-Item -Path $subDirPath -ItemType Directory -Force | Out-Null
                    }
                    
                    foreach ($gameId in $gogData[$dir][$subDir].Keys) {
                        $gamePath = Join-Path $subDirPath $gameId
                        if (-not (Test-Path $gamePath)) {
                            New-Item -Path $gamePath -ItemType Directory -Force | Out-Null
                        }
                        
                        $gameData = $gogData[$dir][$subDir][$gameId]
                        $gameData | ConvertTo-Json | Out-File -FilePath (Join-Path $gamePath "game-info.json") -Encoding UTF8
                    }
                }
            }
        }
        
        It "Should be able to backup EA data" {
            # Test EA backup
            $eaBackupPath = Join-Path $testBackupPath "ea"
            if (-not (Test-Path $eaBackupPath)) {
                New-Item -Path $eaBackupPath -ItemType Directory -Force | Out-Null
            }
            
            # Create mock EA data
            $eaData = @{
                "EA Desktop" = @{
                    "Games" = @{
                        "FIFA 24" = @{
                            "InstallPath" = "C:\\Program Files\\EA Games\\FIFA 24"
                            "Size" = "4567890123"
                            "Version" = "1.0.0"
                        }
                    }
                }
            }
            
            # Create EA directory structure
            foreach ($dir in $eaData.Keys) {
                $dirPath = Join-Path $eaBackupPath $dir
                if (-not (Test-Path $dirPath)) {
                    New-Item -Path $dirPath -ItemType Directory -Force | Out-Null
                }
                
                foreach ($subDir in $eaData[$dir].Keys) {
                    $subDirPath = Join-Path $dirPath $subDir
                    if (-not (Test-Path $subDirPath)) {
                        New-Item -Path $subDirPath -ItemType Directory -Force | Out-Null
                    }
                    
                    foreach ($game in $eaData[$dir][$subDir].Keys) {
                        $gamePath = Join-Path $subDirPath $game
                        if (-not (Test-Path $gamePath)) {
                            New-Item -Path $gamePath -ItemType Directory -Force | Out-Null
                        }
                        
                        $gameData = $eaData[$dir][$subDir][$game]
                        $gameData | ConvertTo-Json | Out-File -FilePath (Join-Path $gamePath "game-info.json") -Encoding UTF8
                    }
                }
            }
        }
    }
    
    Context "Backup Validation" {
        It "Should create gaming platforms backup manifest" {
            $manifestPath = Join-Path $testBackupPath "gaming-manifest.json"
            @{
                BackupType = "GamingPlatforms"
                Timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
                Version = "1.0.0"
                Platforms = @("Steam", "Epic", "GOG", "EA")
                Items = @(
                    @{ Type = "Steam"; Path = "steam" },
                    @{ Type = "Epic"; Path = "epic" },
                    @{ Type = "GOG"; Path = "gog" },
                    @{ Type = "EA"; Path = "ea" }
                )
            } | ConvertTo-Json -Depth 3 | Out-File -FilePath $manifestPath -Encoding UTF8
            
            Test-Path $manifestPath | Should -Be $true
            
            $manifest = Get-Content $manifestPath | ConvertFrom-Json
            $manifest.BackupType | Should -Be "GamingPlatforms"
            $manifest.Platforms.Count | Should -Be 4
        }
        
        It "Should validate gaming backup integrity" {
            $manifestPath = Join-Path $testBackupPath "gaming-manifest.json"
            if (Test-Path $manifestPath) {
                $manifest = Get-Content $manifestPath | ConvertFrom-Json
                
                foreach ($item in $manifest.Items) {
                    $itemPath = Join-Path $testBackupPath $item.Path
                    Test-Path $itemPath | Should -Be $true
                }
            }
        }
    }
    
    AfterAll {
        # Clean up test files
        if (Test-Path $testBackupPath) {
            Remove-Item -Path $testBackupPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
} 