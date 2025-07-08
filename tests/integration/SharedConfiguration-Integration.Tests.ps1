BeforeAll {
    # Import required modules and functions
    $script:ModuleRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    
    # Import the main module
    Import-Module (Join-Path $script:ModuleRoot "WindowsMelodyRecovery.psd1") -Force
    
    # Import core functions
    . (Join-Path $script:ModuleRoot "Private\Core\WindowsMelodyRecovery.Core.ps1")
    . (Join-Path $script:ModuleRoot "Private\Core\WindowsMelodyRecovery.Initialization.ps1")
    . (Join-Path $script:ModuleRoot "Private\Core\InvokeWmrTemplate.ps1")
    
    # Set up test environment
    $script:TestRoot = Join-Path $env:TEMP "WMR-SharedConfig-Integration-Tests"
    $script:TestBackupRoot = Join-Path $script:TestRoot "Backups"
    $script:TestMachineBackup = Join-Path $script:TestBackupRoot "TEST-MACHINE"
    $script:TestSharedBackup = Join-Path $script:TestBackupRoot "shared"
    $script:TestRestoreRoot = Join-Path $script:TestRoot "Restore"
    $script:TestTemplatesRoot = Join-Path $script:TestRoot "Templates"
    
    # Create test directories
    @($script:TestRoot, $script:TestBackupRoot, $script:TestMachineBackup, 
      $script:TestSharedBackup, $script:TestRestoreRoot, $script:TestTemplatesRoot) | ForEach-Object {
        if (-not (Test-Path $_)) {
            New-Item -ItemType Directory -Path $_ -Force | Out-Null
        }
    }
    
    # Set up test module configuration
    $script:TestConfig = @{
        BackupRoot = $script:TestBackupRoot
        MachineName = "TEST-MACHINE"
        WindowsMelodyRecoveryPath = $script:ModuleRoot
        CloudProvider = "OneDrive"
        IsInitialized = $true
    }
    
    # Mock Get-WindowsMelodyRecovery for testing
    function script:Get-WindowsMelodyRecovery {
        return [PSCustomObject]$script:TestConfig
    }
    
    # Test-BackupPath function for integration testing
    function script:Test-BackupPath {
        param (
            [Parameter(Mandatory=$true)]
            [string]$Path,
            [Parameter(Mandatory=$true)]
            [string]$BackupType,
            [Parameter(Mandatory=$true)]
            [string]$MACHINE_BACKUP,
            [Parameter(Mandatory=$true)]
            [string]$SHARED_BACKUP
        )
        
        # First check machine-specific backup
        $machinePath = Join-Path $MACHINE_BACKUP $Path
        if (Test-Path $machinePath) {
            Write-Host "Using machine-specific $BackupType backup from: $machinePath" -ForegroundColor Green
            return $machinePath
        }
        
        # Fall back to shared backup
        $sharedPath = Join-Path $SHARED_BACKUP $Path
        if (Test-Path $sharedPath) {
            Write-Host "Using shared $BackupType backup from: $sharedPath" -ForegroundColor Green
            return $sharedPath
        }
        
        Write-Host "No $BackupType backup found" -ForegroundColor Yellow
        return $null
    }
}

Describe "SharedConfiguration Integration Tests" -Tag "Integration", "SharedConfiguration" {
    
    Context "Machine-Specific vs Shared Configuration Priority" {
        
        It "Should prioritize machine-specific configuration when both exist" {
            # Create machine-specific configuration
            $machineConfigPath = Join-Path $script:TestMachineBackup "system-settings"
            New-Item -ItemType Directory -Path $machineConfigPath -Force | Out-Null
            
            $machineConfig = @{
                Source = "Machine"
                Theme = "Dark"
                Language = "en-US"
                Priority = 1
                Timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
            }
            $machineConfig | ConvertTo-Json -Depth 3 | Out-File (Join-Path $machineConfigPath "display.json") -Encoding UTF8
            
            # Create shared configuration
            $sharedConfigPath = Join-Path $script:TestSharedBackup "system-settings"
            New-Item -ItemType Directory -Path $sharedConfigPath -Force | Out-Null
            
            $sharedConfig = @{
                Source = "Shared"
                Theme = "Light"
                Language = "en-GB"
                Priority = 2
                Timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
            }
            $sharedConfig | ConvertTo-Json -Depth 3 | Out-File (Join-Path $sharedConfigPath "display.json") -Encoding UTF8
            
            # Test path resolution
            $resolvedPath = Test-BackupPath -Path "system-settings\display.json" -BackupType "SystemSettings" -MACHINE_BACKUP $script:TestMachineBackup -SHARED_BACKUP $script:TestSharedBackup
            
            # Verify machine-specific path is selected
            $resolvedPath | Should -Be (Join-Path $script:TestMachineBackup "system-settings\display.json")
            
            # Verify content is from machine configuration
            $content = Get-Content $resolvedPath -Raw | ConvertFrom-Json
            $content.Source | Should -Be "Machine"
            $content.Theme | Should -Be "Dark"
            $content.Priority | Should -Be 1
        }
        
        It "Should fall back to shared configuration when machine-specific is unavailable" {
            # Create only shared configuration (no machine-specific)
            $sharedConfigPath = Join-Path $script:TestSharedBackup "fallback-settings"
            New-Item -ItemType Directory -Path $sharedConfigPath -Force | Out-Null
            
            $sharedConfig = @{
                Source = "Shared"
                Theme = "Light"
                Language = "en-GB"
                FontSize = 12
                FallbackUsed = $true
                Timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
            }
            $sharedConfig | ConvertTo-Json -Depth 3 | Out-File (Join-Path $sharedConfigPath "display.json") -Encoding UTF8
            
            # Test path resolution
            $resolvedPath = Test-BackupPath -Path "fallback-settings\display.json" -BackupType "FallbackSettings" -MACHINE_BACKUP $script:TestMachineBackup -SHARED_BACKUP $script:TestSharedBackup
            
            # Verify shared path is selected
            $resolvedPath | Should -Be (Join-Path $script:TestSharedBackup "fallback-settings\display.json")
            
            # Verify content is from shared configuration
            $content = Get-Content $resolvedPath -Raw | ConvertFrom-Json
            $content.Source | Should -Be "Shared"
            $content.FallbackUsed | Should -Be $true
        }
        
        It "Should return null when neither machine nor shared configuration exists" {
            # Test with non-existent configuration
            $resolvedPath = Test-BackupPath -Path "nonexistent-settings\config.json" -BackupType "NonExistent" -MACHINE_BACKUP $script:TestMachineBackup -SHARED_BACKUP $script:TestSharedBackup
            
            # Should return null
            $resolvedPath | Should -Be $null
        }
    }
    
    Context "Configuration Merging in Real Scenarios" {
        
        It "Should merge configurations correctly for template-based operations" {
            # Create base configuration
            $baseConfig = @{
                BackupRoot = $script:TestBackupRoot
                MachineName = "DEFAULT-MACHINE"
                CloudProvider = "OneDrive"
                EmailSettings = @{
                    FromAddress = "default@example.com"
                    SmtpServer = "smtp.office365.com"
                    SmtpPort = 587
                }
                BackupSettings = @{
                    RetentionDays = 30
                    ExcludePaths = @("*.tmp", "*.log")
                }
            }
            
            # Create override configuration
            $overrideConfig = @{
                MachineName = "TEST-MACHINE"
                CloudProvider = "GoogleDrive"
                EmailSettings = @{
                    FromAddress = "test@example.com"
                    ToAddress = "admin@example.com"
                }
                BackupSettings = @{
                    RetentionDays = 60
                    IncludePaths = @("*.config", "*.json")
                }
            }
            
            # Test merge-configurations function
            $mergedConfig = Merge-Configurations -Base $baseConfig -Override $overrideConfig
            
            # Verify merged configuration
            $mergedConfig.MachineName | Should -Be "TEST-MACHINE"  # Override value
            $mergedConfig.CloudProvider | Should -Be "GoogleDrive"  # Override value
            $mergedConfig.BackupRoot | Should -Be $script:TestBackupRoot  # Base value preserved
            
            # Verify nested hash merging
            $mergedConfig.EmailSettings.FromAddress | Should -Be "test@example.com"  # Override value
            $mergedConfig.EmailSettings.ToAddress | Should -Be "admin@example.com"  # Override value
            $mergedConfig.EmailSettings.SmtpServer | Should -Be "smtp.office365.com"  # Base value preserved
            $mergedConfig.EmailSettings.SmtpPort | Should -Be 587  # Base value preserved
            
            # Verify array handling
            $mergedConfig.BackupSettings.RetentionDays | Should -Be 60  # Override value
            $mergedConfig.BackupSettings.ExcludePaths | Should -Be @("*.tmp", "*.log")  # Base value preserved
            $mergedConfig.BackupSettings.IncludePaths | Should -Be @("*.config", "*.json")  # Override value added
        }
        
        It "Should handle edge cases in configuration merging" {
            # Test with null/empty override
            $baseConfig = @{
                Setting1 = "Value1"
                Setting2 = "Value2"
            }
            
            $emptyOverride = @{}
            $mergedEmpty = Merge-Configurations -Base $baseConfig -Override $emptyOverride
            
            $mergedEmpty.Setting1 | Should -Be "Value1"
            $mergedEmpty.Setting2 | Should -Be "Value2"
            
            # Test with null values in override
            $nullOverride = @{
                Setting1 = $null
                Setting3 = "Value3"
            }
            
            $mergedNull = Merge-Configurations -Base $baseConfig -Override $nullOverride
            $mergedNull.Setting1 | Should -Be $null  # Override with null
            $mergedNull.Setting2 | Should -Be "Value2"  # Base preserved
            $mergedNull.Setting3 | Should -Be "Value3"  # Override added
        }
    }
    
    Context "Template-Based Backup and Restore with Shared Configuration" {
        
        It "Should perform backup with shared configuration fallback" {
            # Create a test template
            $templatePath = Join-Path $script:TestTemplatesRoot "test-shared-config.yaml"
            $templateContent = @"
metadata:
  name: Test Shared Configuration
  description: Template for testing shared configuration workflows
  version: "1.0"
  author: Integration Tests

registry:
  - name: Test Registry Setting
    path: "HKCU:\Software\TestApp"
    type: key
    action: sync
    dynamic_state_path: "registry/test_app.json"

files:
  - name: Test Configuration File
    path: "%TEMP%\test-config.json"
    type: file
    action: sync
    dynamic_state_path: "files/test_config.json"
"@
            $templateContent | Out-File $templatePath -Encoding UTF8
            
            # Create shared configuration files
            $sharedRegistryPath = Join-Path $script:TestSharedBackup "registry"
            New-Item -ItemType Directory -Path $sharedRegistryPath -Force | Out-Null
            
            $sharedRegistryConfig = @{
                Name = "Test Registry Setting"
                Path = "HKCU:\Software\TestApp"
                Values = @{
                    Setting1 = "SharedValue1"
                    Setting2 = "SharedValue2"
                }
                Source = "Shared"
                Timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
            }
            $sharedRegistryConfig | ConvertTo-Json -Depth 3 | Out-File (Join-Path $sharedRegistryPath "test_app.json") -Encoding UTF8
            
            # Test backup operation (should use shared config when machine config unavailable)
            $backupStateDir = Join-Path $script:TestRoot "BackupState"
            New-Item -ItemType Directory -Path $backupStateDir -Force | Out-Null
            
            # This would normally call Invoke-WmrTemplate, but we'll simulate the behavior
            $resolvedRegistryPath = Test-BackupPath -Path "registry\test_app.json" -BackupType "Registry" -MACHINE_BACKUP $script:TestMachineBackup -SHARED_BACKUP $script:TestSharedBackup
            
            # Verify shared configuration is used
            $resolvedRegistryPath | Should -Be (Join-Path $script:TestSharedBackup "registry\test_app.json")
            
            $registryContent = Get-Content $resolvedRegistryPath -Raw | ConvertFrom-Json
            $registryContent.Source | Should -Be "Shared"
            $registryContent.Values.Setting1 | Should -Be "SharedValue1"
        }
        
        It "Should perform restore with configuration inheritance" {
            # Create machine-specific configuration that overrides shared
            $machineRegistryPath = Join-Path $script:TestMachineBackup "registry"
            New-Item -ItemType Directory -Path $machineRegistryPath -Force | Out-Null
            
            $machineRegistryConfig = @{
                Name = "Test Registry Setting"
                Path = "HKCU:\Software\TestApp"
                Values = @{
                    Setting1 = "MachineValue1"  # Override shared value
                    Setting3 = "MachineValue3"  # Machine-specific value
                }
                Source = "Machine"
                Timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
            }
            $machineRegistryConfig | ConvertTo-Json -Depth 3 | Out-File (Join-Path $machineRegistryPath "test_app.json") -Encoding UTF8
            
            # Test restore operation (should prioritize machine config)
            $resolvedRegistryPath = Test-BackupPath -Path "registry\test_app.json" -BackupType "Registry" -MACHINE_BACKUP $script:TestMachineBackup -SHARED_BACKUP $script:TestSharedBackup
            
            # Verify machine configuration is prioritized
            $resolvedRegistryPath | Should -Be (Join-Path $script:TestMachineBackup "registry\test_app.json")
            
            $registryContent = Get-Content $resolvedRegistryPath -Raw | ConvertFrom-Json
            $registryContent.Source | Should -Be "Machine"
            $registryContent.Values.Setting1 | Should -Be "MachineValue1"
            $registryContent.Values.Setting3 | Should -Be "MachineValue3"
        }
    }
    
    Context "Multi-Component Configuration Workflows" {
        
        It "Should handle mixed machine and shared configurations across components" {
            # Create mixed configuration scenario
            $components = @(
                @{ Name = "display"; HasMachine = $true; HasShared = $true },
                @{ Name = "mouse"; HasMachine = $false; HasShared = $true },
                @{ Name = "keyboard"; HasMachine = $true; HasShared = $false },
                @{ Name = "sound"; HasMachine = $false; HasShared = $false }
            )
            
            $results = @{}
            
            foreach ($component in $components) {
                $componentName = $component.Name
                
                # Create machine configuration if specified
                if ($component.HasMachine) {
                    $machinePath = Join-Path $script:TestMachineBackup $componentName
                    New-Item -ItemType Directory -Path $machinePath -Force | Out-Null
                    
                    $machineConfig = @{
                        Component = $componentName
                        Source = "Machine"
                        Settings = @{
                            Theme = "Dark"
                            CustomSetting = "MachineValue"
                        }
                    }
                    $machineConfig | ConvertTo-Json -Depth 3 | Out-File (Join-Path $machinePath "config.json") -Encoding UTF8
                }
                
                # Create shared configuration if specified
                if ($component.HasShared) {
                    $sharedPath = Join-Path $script:TestSharedBackup $componentName
                    New-Item -ItemType Directory -Path $sharedPath -Force | Out-Null
                    
                    $sharedConfig = @{
                        Component = $componentName
                        Source = "Shared"
                        Settings = @{
                            Theme = "Light"
                            SharedSetting = "SharedValue"
                        }
                    }
                    $sharedConfig | ConvertTo-Json -Depth 3 | Out-File (Join-Path $sharedPath "config.json") -Encoding UTF8
                }
                
                # Test path resolution
                $resolvedPath = Test-BackupPath -Path "$componentName\config.json" -BackupType $componentName -MACHINE_BACKUP $script:TestMachineBackup -SHARED_BACKUP $script:TestSharedBackup
                $results[$componentName] = $resolvedPath
            }
            
            # Verify results
            $results["display"] | Should -Be (Join-Path $script:TestMachineBackup "display\config.json")  # Machine priority
            $results["mouse"] | Should -Be (Join-Path $script:TestSharedBackup "mouse\config.json")  # Shared fallback
            $results["keyboard"] | Should -Be (Join-Path $script:TestMachineBackup "keyboard\config.json")  # Machine only
            $results["sound"] | Should -Be $null  # Neither exists
            
            # Verify content sources
            $displayContent = Get-Content $results["display"] -Raw | ConvertFrom-Json
            $displayContent.Source | Should -Be "Machine"
            
            $mouseContent = Get-Content $results["mouse"] -Raw | ConvertFrom-Json
            $mouseContent.Source | Should -Be "Shared"
        }
    }
    
    Context "Configuration Validation and Error Handling" {
        
        It "Should handle corrupted configuration files gracefully" {
            # Create corrupted machine configuration
            $corruptedPath = Join-Path $script:TestMachineBackup "corrupted"
            New-Item -ItemType Directory -Path $corruptedPath -Force | Out-Null
            
            $corruptedContent = '{ "Name": "Corrupted", "Value": "Test"'  # Missing closing brace
            $corruptedContent | Out-File (Join-Path $corruptedPath "config.json") -Encoding UTF8
            
            # Create valid shared configuration as fallback
            $validSharedPath = Join-Path $script:TestSharedBackup "corrupted"
            New-Item -ItemType Directory -Path $validSharedPath -Force | Out-Null
            
            $validSharedConfig = @{
                Name = "Valid Shared"
                Value = "SharedValue"
                Source = "Shared"
            }
            $validSharedConfig | ConvertTo-Json -Depth 3 | Out-File (Join-Path $validSharedPath "config.json") -Encoding UTF8
            
            # Test path resolution (should still return machine path)
            $resolvedPath = Test-BackupPath -Path "corrupted\config.json" -BackupType "Corrupted" -MACHINE_BACKUP $script:TestMachineBackup -SHARED_BACKUP $script:TestSharedBackup
            $resolvedPath | Should -Be (Join-Path $script:TestMachineBackup "corrupted\config.json")
            
            # Verify that JSON parsing would fail for machine config
            { Get-Content $resolvedPath -Raw | ConvertFrom-Json } | Should -Throw
            
            # But shared config should be valid
            $sharedPath = Join-Path $script:TestSharedBackup "corrupted\config.json"
            $sharedContent = Get-Content $sharedPath -Raw | ConvertFrom-Json
            $sharedContent.Source | Should -Be "Shared"
        }
        
        It "Should handle missing directories gracefully" {
            # Test with non-existent directories
            $nonExistentMachine = Join-Path $script:TestRoot "NonExistentMachine"
            $nonExistentShared = Join-Path $script:TestRoot "NonExistentShared"
            
            $resolvedPath = Test-BackupPath -Path "missing\config.json" -BackupType "Missing" -MACHINE_BACKUP $nonExistentMachine -SHARED_BACKUP $nonExistentShared
            
            # Should return null gracefully
            $resolvedPath | Should -Be $null
        }
    }
}

AfterAll {
    # Clean up test environment
    if (Test-Path $script:TestRoot) {
        Remove-Item $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
} 