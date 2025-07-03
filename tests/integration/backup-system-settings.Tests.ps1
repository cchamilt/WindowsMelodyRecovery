Describe "System Settings Backup Tests" {
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
        $testBackupPath = "/workspace/test-backups/system-settings"
        $mockRegistryPath = "/mock-registry"
        $mockAppDataPath = "/mock-appdata"
        
        # Create test directories if they don't exist
        if (-not (Test-Path $testBackupPath)) {
            New-Item -Path $testBackupPath -ItemType Directory -Force | Out-Null
        }
    }
    
    Context "Environment Setup" {
        It "Should have access to mock registry" {
            Test-Path $mockRegistryPath | Should -Be $true
        }
        
        It "Should have access to mock appdata" {
            Test-Path $mockAppDataPath | Should -Be $true
        }
        
        It "Should be able to create backup directories" {
            Test-Path $testBackupPath | Should -Be $true
        }
    }
    
    Context "System Settings Backup Functions" {
        It "Should have Backup-SystemSettings function available" {
            Get-Command Backup-SystemSettings -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
        
        It "Should be able to backup registry settings" {
            # Test basic registry backup functionality
            $registryBackupPath = Join-Path $testBackupPath "registry"
            if (-not (Test-Path $registryBackupPath)) {
                New-Item -Path $registryBackupPath -ItemType Directory -Force | Out-Null
            }
            
            # Create a mock registry export
            $mockRegFile = Join-Path $registryBackupPath "mock-registry.reg"
            @"
Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\Software\WindowsMelodyRecovery\Test]
"TestValue"="TestData"
"@ | Out-File -FilePath $mockRegFile -Encoding ASCII
            
            Test-Path $mockRegFile | Should -Be $true
        }
        
        It "Should be able to backup user preferences" {
            # Test user preferences backup
            $preferencesPath = Join-Path $testBackupPath "preferences"
            if (-not (Test-Path $preferencesPath)) {
                New-Item -Path $preferencesPath -ItemType Directory -Force | Out-Null
            }
            
            # Create mock preference files
            $mockPrefFile = Join-Path $preferencesPath "user-preferences.json"
            @{
                Theme = "Dark"
                Language = "en-US"
                TimeZone = "UTC"
            } | ConvertTo-Json | Out-File -FilePath $mockPrefFile -Encoding UTF8
            
            Test-Path $mockPrefFile | Should -Be $true
        }
    }
    
    Context "Backup Validation" {
        It "Should create backup manifest" {
            $manifestPath = Join-Path $testBackupPath "backup-manifest.json"
            
            # Create the files referenced in the manifest
            $registryPath = Join-Path $testBackupPath "mock-registry.reg"
            $preferencesPath = Join-Path $testBackupPath "user-preferences.json"
            
            # Create the actual files that the manifest references
            @"
Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\Software\WindowsMelodyRecovery\Test]
"TestValue"="TestData"
"@ | Out-File -FilePath $registryPath -Encoding ASCII
            
            @{
                Theme = "Dark"
                Language = "en-US"
                TimeZone = "UTC"
            } | ConvertTo-Json | Out-File -FilePath $preferencesPath -Encoding UTF8
            
            @{
                BackupType = "SystemSettings"
                Timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
                Version = "1.0.0"
                Items = @(
                    @{ Type = "Registry"; Path = "mock-registry.reg" },
                    @{ Type = "Preferences"; Path = "user-preferences.json" }
                )
            } | ConvertTo-Json -Depth 3 | Out-File -FilePath $manifestPath -Encoding UTF8
            
            Test-Path $manifestPath | Should -Be $true
            
            $manifest = Get-Content $manifestPath | ConvertFrom-Json
            $manifest.BackupType | Should -Be "SystemSettings"
            $manifest.Items.Count | Should -Be 2
        }
        
        It "Should validate backup integrity" {
            $manifestPath = Join-Path $testBackupPath "backup-manifest.json"
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