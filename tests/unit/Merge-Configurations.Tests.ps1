BeforeAll {
    # Import required modules and functions
    $script:ModuleRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    
    # Import the main module
    Import-Module (Join-Path $script:ModuleRoot "WindowsMelodyRecovery.psd1") -Force
    
    # Import the initialization module that contains Merge-Configurations
    . (Join-Path $script:ModuleRoot "Private\Core\WindowsMelodyRecovery.Initialization.ps1")
}

Describe "Merge-Configurations Unit Tests" -Tag "Unit", "Logic", "Configuration" {
    
    Context "Basic Configuration Merging" {
        
        It "Should merge simple configurations correctly" {
            $baseConfig = @{
                Setting1 = "BaseValue1"
                Setting2 = "BaseValue2"
                Setting3 = "BaseValue3"
            }
            
            $overrideConfig = @{
                Setting2 = "OverrideValue2"
                Setting4 = "OverrideValue4"
            }
            
            $result = Merge-Configurations -Base $baseConfig -Override $overrideConfig
            
            # Base values should be preserved when not overridden
            $result.Setting1 | Should -Be "BaseValue1"
            $result.Setting3 | Should -Be "BaseValue3"
            
            # Override values should replace base values
            $result.Setting2 | Should -Be "OverrideValue2"
            
            # New values from override should be added
            $result.Setting4 | Should -Be "OverrideValue4"
        }
        
        It "Should handle empty base configuration" {
            $baseConfig = @{}
            $overrideConfig = @{
                Setting1 = "Value1"
                Setting2 = "Value2"
            }
            
            $result = Merge-Configurations -Base $baseConfig -Override $overrideConfig
            
            $result.Setting1 | Should -Be "Value1"
            $result.Setting2 | Should -Be "Value2"
        }
        
        It "Should handle empty override configuration" {
            $baseConfig = @{
                Setting1 = "Value1"
                Setting2 = "Value2"
            }
            $overrideConfig = @{}
            
            $result = Merge-Configurations -Base $baseConfig -Override $overrideConfig
            
            $result.Setting1 | Should -Be "Value1"
            $result.Setting2 | Should -Be "Value2"
        }
        
        It "Should handle both configurations being empty" {
            $baseConfig = @{}
            $overrideConfig = @{}
            
            $result = Merge-Configurations -Base $baseConfig -Override $overrideConfig
            
            $result.Count | Should -Be 0
        }
    }
    
    Context "Deep Nested Configuration Merging" {
        
        It "Should merge nested hashtables correctly" {
            $baseConfig = @{
                EmailSettings = @{
                    FromAddress = "default@example.com"
                    SmtpServer = "smtp.office365.com"
                    SmtpPort = 587
                    EnableSsl = $true
                }
                BackupSettings = @{
                    RetentionDays = 30
                    ExcludePaths = @("*.tmp", "*.log")
                }
            }
            
            $overrideConfig = @{
                EmailSettings = @{
                    FromAddress = "override@example.com"
                    ToAddress = "admin@example.com"
                    SmtpPort = 465
                }
                BackupSettings = @{
                    RetentionDays = 60
                    IncludePaths = @("*.config", "*.json")
                }
            }
            
            $result = Merge-Configurations -Base $baseConfig -Override $overrideConfig
            
            # Email settings should be merged
            $result.EmailSettings.FromAddress | Should -Be "override@example.com"  # Override
            $result.EmailSettings.ToAddress | Should -Be "admin@example.com"      # New from override
            $result.EmailSettings.SmtpServer | Should -Be "smtp.office365.com"   # Preserved from base
            $result.EmailSettings.SmtpPort | Should -Be 465                       # Override
            $result.EmailSettings.EnableSsl | Should -Be $true                    # Preserved from base
            
            # Backup settings should be merged
            $result.BackupSettings.RetentionDays | Should -Be 60                  # Override
            $result.BackupSettings.ExcludePaths | Should -Be @("*.tmp", "*.log")  # Preserved from base
            $result.BackupSettings.IncludePaths | Should -Be @("*.config", "*.json") # New from override
        }
        
        It "Should handle deeply nested structures" {
            $baseConfig = @{
                Level1 = @{
                    Level2 = @{
                        Level3 = @{
                            Setting1 = "BaseValue"
                            Setting2 = "BaseValue2"
                        }
                        OtherSetting = "BaseOther"
                    }
                }
            }
            
            $overrideConfig = @{
                Level1 = @{
                    Level2 = @{
                        Level3 = @{
                            Setting1 = "OverrideValue"
                            Setting3 = "NewValue"
                        }
                        NewSetting = "OverrideNew"
                    }
                }
            }
            
            $result = Merge-Configurations -Base $baseConfig -Override $overrideConfig
            
            # Deep nested override
            $result.Level1.Level2.Level3.Setting1 | Should -Be "OverrideValue"
            # Deep nested preservation
            $result.Level1.Level2.Level3.Setting2 | Should -Be "BaseValue2"
            # Deep nested addition
            $result.Level1.Level2.Level3.Setting3 | Should -Be "NewValue"
            # Mid-level preservation
            $result.Level1.Level2.OtherSetting | Should -Be "BaseOther"
            # Mid-level addition
            $result.Level1.Level2.NewSetting | Should -Be "OverrideNew"
        }
        
        It "Should handle mixed nested and flat structures" {
            $baseConfig = @{
                FlatSetting = "FlatValue"
                NestedSetting = @{
                    SubSetting1 = "SubValue1"
                    SubSetting2 = "SubValue2"
                }
            }
            
            $overrideConfig = @{
                FlatSetting = "OverrideFlatValue"
                NestedSetting = @{
                    SubSetting2 = "OverrideSubValue2"
                    SubSetting3 = "NewSubValue3"
                }
                NewFlatSetting = "NewFlatValue"
            }
            
            $result = Merge-Configurations -Base $baseConfig -Override $overrideConfig
            
            # Flat settings
            $result.FlatSetting | Should -Be "OverrideFlatValue"
            $result.NewFlatSetting | Should -Be "NewFlatValue"
            
            # Nested settings
            $result.NestedSetting.SubSetting1 | Should -Be "SubValue1"         # Preserved
            $result.NestedSetting.SubSetting2 | Should -Be "OverrideSubValue2" # Override
            $result.NestedSetting.SubSetting3 | Should -Be "NewSubValue3"      # New
        }
    }
    
    Context "Edge Cases and Error Conditions" {
        
        It "Should handle null values in override" {
            $baseConfig = @{
                Setting1 = "Value1"
                Setting2 = "Value2"
                Setting3 = "Value3"
            }
            
            $overrideConfig = @{
                Setting2 = $null
                Setting4 = "Value4"
            }
            
            $result = Merge-Configurations -Base $baseConfig -Override $overrideConfig
            
            $result.Setting1 | Should -Be "Value1"
            $result.Setting2 | Should -Be $null      # Explicitly overridden with null
            $result.Setting3 | Should -Be "Value3"
            $result.Setting4 | Should -Be "Value4"
        }
        
        It "Should handle null values in base" {
            $baseConfig = @{
                Setting1 = $null
                Setting2 = "Value2"
            }
            
            $overrideConfig = @{
                Setting1 = "OverrideValue1"
                Setting3 = "Value3"
            }
            
            $result = Merge-Configurations -Base $baseConfig -Override $overrideConfig
            
            $result.Setting1 | Should -Be "OverrideValue1"  # Override null base
            $result.Setting2 | Should -Be "Value2"
            $result.Setting3 | Should -Be "Value3"
        }
        
        It "Should handle array values correctly" {
            $baseConfig = @{
                ArraySetting = @("item1", "item2", "item3")
                StringSetting = "string"
            }
            
            $overrideConfig = @{
                ArraySetting = @("override1", "override2")
                StringSetting = "overrideString"
            }
            
            $result = Merge-Configurations -Base $baseConfig -Override $overrideConfig
            
            # Arrays should be replaced, not merged
            $result.ArraySetting | Should -Be @("override1", "override2")
            $result.StringSetting | Should -Be "overrideString"
        }
        
        It "Should handle different value types" {
            $baseConfig = @{
                StringValue = "string"
                IntValue = 42
                BoolValue = $true
                ArrayValue = @("a", "b", "c")
                HashValue = @{ Key = "Value" }
            }
            
            $overrideConfig = @{
                StringValue = "overrideString"
                IntValue = 99
                BoolValue = $false
                ArrayValue = @("x", "y")
                HashValue = @{ Key = "OverrideValue"; NewKey = "NewValue" }
            }
            
            $result = Merge-Configurations -Base $baseConfig -Override $overrideConfig
            
            $result.StringValue | Should -Be "overrideString"
            $result.IntValue | Should -Be 99
            $result.BoolValue | Should -Be $false
            $result.ArrayValue | Should -Be @("x", "y")
            $result.HashValue.Key | Should -Be "OverrideValue"
            $result.HashValue.NewKey | Should -Be "NewValue"
        }
        
        It "Should handle type conflicts gracefully" {
            $baseConfig = @{
                Setting1 = "string"
                Setting2 = @{ Key = "Value" }
            }
            
            $overrideConfig = @{
                Setting1 = 42                    # String -> Int
                Setting2 = "replacedWithString"  # Hash -> String
            }
            
            $result = Merge-Configurations -Base $baseConfig -Override $overrideConfig
            
            # Type changes should be allowed (override wins)
            $result.Setting1 | Should -Be 42
            $result.Setting2 | Should -Be "replacedWithString"
        }
    }
    
    Context "Configuration Conflict Resolution" {
        
        It "Should prioritize override values in all conflicts" {
            $baseConfig = @{
                ConflictSetting1 = "BaseValue1"
                ConflictSetting2 = @{
                    SubConflict = "BaseSubValue"
                    NoConflict = "BaseNoConflict"
                }
                NoConflictSetting = "BaseNoConflict"
            }
            
            $overrideConfig = @{
                ConflictSetting1 = "OverrideValue1"
                ConflictSetting2 = @{
                    SubConflict = "OverrideSubValue"
                    NewSubSetting = "NewValue"
                }
                NewSetting = "NewValue"
            }
            
            $result = Merge-Configurations -Base $baseConfig -Override $overrideConfig
            
            # All conflicts should be resolved in favor of override
            $result.ConflictSetting1 | Should -Be "OverrideValue1"
            $result.ConflictSetting2.SubConflict | Should -Be "OverrideSubValue"
            
            # Non-conflicting values should be preserved
            $result.ConflictSetting2.NoConflict | Should -Be "BaseNoConflict"
            $result.NoConflictSetting | Should -Be "BaseNoConflict"
            
            # New values should be added
            $result.ConflictSetting2.NewSubSetting | Should -Be "NewValue"
            $result.NewSetting | Should -Be "NewValue"
        }
        
        It "Should handle nested conflict resolution" {
            $baseConfig = @{
                System = @{
                    Display = @{
                        Theme = "Light"
                        Resolution = "1920x1080"
                        RefreshRate = 60
                    }
                    Audio = @{
                        Volume = 50
                        Muted = $false
                    }
                }
            }
            
            $overrideConfig = @{
                System = @{
                    Display = @{
                        Theme = "Dark"           # Conflict - override wins
                        Brightness = 80          # New setting
                        # Resolution preserved from base
                    }
                    Network = @{                 # New section
                        Wifi = $true
                        Ethernet = $false
                    }
                    # Audio preserved from base
                }
            }
            
            $result = Merge-Configurations -Base $baseConfig -Override $overrideConfig
            
            # Conflicts resolved in favor of override
            $result.System.Display.Theme | Should -Be "Dark"
            
            # New settings added
            $result.System.Display.Brightness | Should -Be 80
            $result.System.Network.Wifi | Should -Be $true
            $result.System.Network.Ethernet | Should -Be $false
            
            # Non-conflicting settings preserved
            $result.System.Display.Resolution | Should -Be "1920x1080"
            $result.System.Display.RefreshRate | Should -Be 60
            $result.System.Audio.Volume | Should -Be 50
            $result.System.Audio.Muted | Should -Be $false
        }
    }
    
    Context "Shared Configuration Fallback Scenarios" {
        
        It "Should merge shared configuration when machine configuration is incomplete" {
            # Simulate machine config with missing settings
            $machineConfig = @{
                Source = "Machine"
                MachineName = "SPECIFIC-MACHINE"
                CloudProvider = "OneDrive"
                # Missing email and backup settings
            }
            
            # Shared config provides defaults
            $sharedConfig = @{
                Source = "Shared"
                MachineName = "DEFAULT-MACHINE"  # Should be overridden
                CloudProvider = "GoogleDrive"    # Should be overridden
                EmailSettings = @{
                    FromAddress = "shared@example.com"
                    SmtpServer = "smtp.gmail.com"
                    SmtpPort = 587
                }
                BackupSettings = @{
                    RetentionDays = 30
                    ExcludePaths = @("*.tmp", "*.log")
                }
            }
            
            $result = Merge-Configurations -Base $sharedConfig -Override $machineConfig
            
            # Machine-specific settings should override shared
            $result.Source | Should -Be "Machine"
            $result.MachineName | Should -Be "SPECIFIC-MACHINE"
            $result.CloudProvider | Should -Be "OneDrive"
            
            # Shared settings should be used when machine config is incomplete
            $result.EmailSettings.FromAddress | Should -Be "shared@example.com"
            $result.EmailSettings.SmtpServer | Should -Be "smtp.gmail.com"
            $result.EmailSettings.SmtpPort | Should -Be 587
            $result.BackupSettings.RetentionDays | Should -Be 30
            $result.BackupSettings.ExcludePaths | Should -Be @("*.tmp", "*.log")
        }
        
        It "Should handle partial machine configuration overrides" {
            $sharedConfig = @{
                Source = "Shared"
                EmailSettings = @{
                    FromAddress = "shared@example.com"
                    ToAddress = "admin@example.com"
                    SmtpServer = "smtp.gmail.com"
                    SmtpPort = 587
                    EnableSsl = $true
                }
                BackupSettings = @{
                    RetentionDays = 30
                    ExcludePaths = @("*.tmp", "*.log")
                    CompressBackups = $true
                }
            }
            
            $machineConfig = @{
                Source = "Machine"
                EmailSettings = @{
                    FromAddress = "machine@example.com"  # Override
                    SmtpPort = 465                       # Override
                    # Other email settings inherited from shared
                }
                BackupSettings = @{
                    RetentionDays = 60                   # Override
                    IncludePaths = @("*.config")         # New setting
                    # Other backup settings inherited from shared
                }
            }
            
            $result = Merge-Configurations -Base $sharedConfig -Override $machineConfig
            
            # Machine overrides should take precedence
            $result.Source | Should -Be "Machine"
            $result.EmailSettings.FromAddress | Should -Be "machine@example.com"
            $result.EmailSettings.SmtpPort | Should -Be 465
            $result.BackupSettings.RetentionDays | Should -Be 60
            $result.BackupSettings.IncludePaths | Should -Be @("*.config")
            
            # Shared settings should be preserved when not overridden
            $result.EmailSettings.ToAddress | Should -Be "admin@example.com"
            $result.EmailSettings.SmtpServer | Should -Be "smtp.gmail.com"
            $result.EmailSettings.EnableSsl | Should -Be $true
            $result.BackupSettings.ExcludePaths | Should -Be @("*.tmp", "*.log")
            $result.BackupSettings.CompressBackups | Should -Be $true
        }
    }
    
    Context "Error Handling and Validation" {
        
        It "Should require non-null base configuration" {
            $overrideConfig = @{
                Setting1 = "Value1"
                Setting2 = "Value2"
            }
            
            { Merge-Configurations -Base $null -Override $overrideConfig } | Should -Throw "*Cannot bind argument to parameter 'Base' because it is null*"
        }
        
        It "Should require non-null override configuration" {
            $baseConfig = @{
                Setting1 = "Value1"
                Setting2 = "Value2"
            }
            
            { Merge-Configurations -Base $baseConfig -Override $null } | Should -Throw "*Cannot bind argument to parameter 'Override' because it is null*"
        }
        
        It "Should require both configurations to be non-null" {
            { Merge-Configurations -Base $null -Override $null } | Should -Throw "*Cannot bind argument to parameter 'Base' because it is null*"
        }
        
        It "Should preserve object references correctly" {
            $sharedObject = @{ Key = "SharedValue" }
            $baseConfig = @{
                SharedRef = $sharedObject
                OtherSetting = "Base"
            }
            
            $overrideConfig = @{
                NewSetting = "Override"
            }
            
            $result = Merge-Configurations -Base $baseConfig -Override $overrideConfig
            
            # Object reference should be preserved
            $result.SharedRef | Should -Be $sharedObject
            $result.SharedRef.Key | Should -Be "SharedValue"
            $result.OtherSetting | Should -Be "Base"
            $result.NewSetting | Should -Be "Override"
        }
    }
} 