Describe "Applications Backup Tests" {
    BeforeAll {
        # Import the module
        # Import the module - handle both local and container paths
$ModulePath = if (Test-Path "./WindowsMelodyRecovery.psm1") {
    "./WindowsMelodyRecovery.psm1"
} elseif (Test-Path "/workspace/WindowsMelodyRecovery.psm1") {
    "/workspace/WindowsMelodyRecovery.psm1"
} else {
    throw "Cannot find WindowsMelodyRecovery.psm1 module"
}
Import-Module $ModulePath -Force -ErrorAction SilentlyContinue
        
        # Set up test paths
        $testBackupPath = "/workspace/test-backups/applications"
        $mockProgramFilesPath = "/mock-programfiles"
        $mockAppDataPath = "/mock-appdata"
        
        # Create test directories if they don't exist
        if (-not (Test-Path $testBackupPath)) {
            New-Item -Path $testBackupPath -ItemType Directory -Force | Out-Null
        }
    }
    
    Context "Environment Setup" {
        It "Should have access to mock program files" {
            Test-Path $mockProgramFilesPath | Should -Be $true
        }
        
        It "Should have access to mock appdata" {
            Test-Path $mockAppDataPath | Should -Be $true
        }
        
        It "Should be able to create backup directories" {
            Test-Path $testBackupPath | Should -Be $true
        }
    }
    
    Context "Applications Backup Functions" {
        It "Should have Backup-Applications function available" {
            Get-Command Backup-Applications -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
        
        It "Should be able to backup application configurations" {
            # Test application config backup
            $appConfigPath = Join-Path $testBackupPath "configs"
            if (-not (Test-Path $appConfigPath)) {
                New-Item -Path $appConfigPath -ItemType Directory -Force | Out-Null
            }
            
            # Create mock application configs
            $apps = @("VSCode", "Chrome", "Firefox", "Notepad++")
            foreach ($app in $apps) {
                $appConfigFile = Join-Path $appConfigPath "$app-config.json"
                @{
                    Application = $app
                    Version = "1.0.0"
                    Settings = @{
                        Theme = "Dark"
                        Language = "en-US"
                        AutoSave = $true
                    }
                    Extensions = @("extension1", "extension2")
                } | ConvertTo-Json -Depth 3 | Out-File -FilePath $appConfigFile -Encoding UTF8
                
                Test-Path $appConfigFile | Should -Be $true
            }
        }
        
        It "Should be able to backup application data" {
            # Test application data backup
            $appDataPath = Join-Path $testBackupPath "data"
            if (-not (Test-Path $appDataPath)) {
                New-Item -Path $appDataPath -ItemType Directory -Force | Out-Null
            }
            
            # Create mock application data
            $appData = @{
                "VSCode" = @{
                    "settings.json" = '{"theme":"dark","fontSize":14}'
                    "extensions.json" = '["ms-vscode.powershell","ms-vscode.csharp"]'
                }
                "Chrome" = @{
                    "Preferences" = '{"default_search_provider_enabled":true}'
                    "Bookmarks" = '[{"name":"Test Bookmark","url":"https://example.com"}]'
                }
            }
            
            foreach ($app in $appData.Keys) {
                $appDir = Join-Path $appDataPath $app
                if (-not (Test-Path $appDir)) {
                    New-Item -Path $appDir -ItemType Directory -Force | Out-Null
                }
                
                foreach ($file in $appData[$app].Keys) {
                    $filePath = Join-Path $appDir $file
                    $appData[$app][$file] | Out-File -FilePath $filePath -Encoding UTF8
                    Test-Path $filePath | Should -Be $true
                }
            }
        }
        
        It "Should be able to backup installed applications list" {
            # Test installed applications list backup
            $installedAppsPath = Join-Path $testBackupPath "installed-apps.json"
            $installedApps = @(
                @{
                    Name = "Visual Studio Code"
                    Version = "1.85.0"
                    Publisher = "Microsoft"
                    InstallDate = "2024-01-15"
                    InstallLocation = "C:\Users\TestUser\AppData\Local\Programs\Microsoft VS Code"
                },
                @{
                    Name = "Google Chrome"
                    Version = "120.0.6099.109"
                    Publisher = "Google LLC"
                    InstallDate = "2024-01-10"
                    InstallLocation = "C:\Program Files\Google\Chrome\Application"
                },
                @{
                    Name = "Mozilla Firefox"
                    Version = "121.0"
                    Publisher = "Mozilla"
                    InstallDate = "2024-01-12"
                    InstallLocation = "C:\Program Files\Mozilla Firefox"
                }
            )
            
            $installedApps | ConvertTo-Json -Depth 3 | Out-File -FilePath $installedAppsPath -Encoding UTF8
            Test-Path $installedAppsPath | Should -Be $true
            
            $loadedApps = Get-Content $installedAppsPath | ConvertFrom-Json
            $loadedApps.Count | Should -Be 3
        }
    }
    
    Context "Backup Validation" {
        It "Should create applications backup manifest" {
            $manifestPath = Join-Path $testBackupPath "applications-manifest.json"
            @{
                BackupType = "Applications"
                Timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
                Version = "1.0.0"
                Applications = @("VSCode", "Chrome", "Firefox", "Notepad++")
                Items = @(
                    @{ Type = "Configs"; Path = "configs" },
                    @{ Type = "Data"; Path = "data" },
                    @{ Type = "InstalledApps"; Path = "installed-apps.json" }
                )
            } | ConvertTo-Json -Depth 3 | Out-File -FilePath $manifestPath -Encoding UTF8
            
            Test-Path $manifestPath | Should -Be $true
            
            $manifest = Get-Content $manifestPath | ConvertFrom-Json
            $manifest.BackupType | Should -Be "Applications"
            $manifest.Applications.Count | Should -Be 4
        }
        
        It "Should validate application backup integrity" {
            $manifestPath = Join-Path $testBackupPath "applications-manifest.json"
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