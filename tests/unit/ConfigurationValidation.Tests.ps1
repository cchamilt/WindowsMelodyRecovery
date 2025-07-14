BeforeAll {
    # Load Docker test bootstrap for cross-platform compatibility
    . (Join-Path $PSScriptRoot "../utilities/Docker-Test-Bootstrap.ps1")

    # Import required modules and functions
    $script:ModuleRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent

    # Import only the specific scripts needed to avoid TUI dependencies
    . (Join-Path $script:ModuleRoot "Private\Core\ConfigurationValidation.ps1")
    . (Join-Path $script:ModuleRoot "Private\Core\ConfigurationMerging.ps1")
    . (Join-Path $script:ModuleRoot "Private\Core\WindowsMelodyRecovery.Initialization.ps1")

    # Initialize test environment
    . (Join-Path $PSScriptRoot "../utilities/Test-Environment.ps1")
    Initialize-TestEnvironment -SuiteName 'Unit' | Out-Null

    # Mock or define missing functions if not available
    if (-not (Get-Command Merge-Configurations -ErrorAction SilentlyContinue)) {
        function Merge-Configuration {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $true)]
                [hashtable]$Base,

                [Parameter(Mandatory = $true)]
                [hashtable]$Override
            )

            $merged = $Base.Clone()

            foreach ($key in $Override.Keys) {
                if ($Override[$key] -is [hashtable] -and $merged[$key] -is [hashtable]) {
                    $merged[$key] = Merge-Configurations -Base $merged[$key] -Override $Override[$key]
                }
                else {
                    $merged[$key] = $Override[$key]
                }
            }

            return $merged
        }
    }
}

Describe "ConfigurationValidation Unit Tests" -Tag "Unit", "Logic", "Configuration", "Validation" {

    Context "Test-ConfigurationConsistency Function" {

        It "Should validate consistent configurations successfully" {
            $machineConfig = @{
                BackupRoot    = (Get-WmrTestPath -WindowsPath "C:\MachineBackups")
                CloudProvider = "OneDrive"
                EmailSettings = @{
                    FromAddress = "machine@example.com"
                    SmtpPort    = 587
                }
            }

            $sharedConfig = @{
                BackupRoot    = (Get-WmrTestPath -WindowsPath "C:\SharedBackups")
                CloudProvider = "GoogleDrive"
                EmailSettings = @{
                    FromAddress = "shared@example.com"
                    SmtpPort    = 465
                }
            }

            $result = Test-ConfigurationConsistency -MachineConfig $machineConfig -SharedConfig $sharedConfig

            $result.Success | Should -Be $true
            $result.Errors.Count | Should -Be 0
            $result.ValidationDetails.MachineConfigKeys | Should -Contain "BackupRoot"
            $result.ValidationDetails.SharedConfigKeys | Should -Contain "CloudProvider"
        }

        It "Should detect missing required keys" {
            $machineConfig = @{
                BackupRoot = (Get-WmrTestPath -WindowsPath "C:\MachineBackups")
                # Missing CloudProvider
            }

            $sharedConfig = @{
                BackupRoot = (Get-WmrTestPath -WindowsPath "C:\SharedBackups")
                # Missing CloudProvider
            }

            $requiredKeys = @("BackupRoot", "CloudProvider")
            $result = Test-ConfigurationConsistency -MachineConfig $machineConfig -SharedConfig $sharedConfig -RequiredKeys $requiredKeys

            $result.Success | Should -Be $false
            $result.Errors | Should -Contain "Required key 'CloudProvider' is missing from both machine and shared configurations"
            $result.ValidationDetails.MissingRequiredKeys | Should -Contain "CloudProvider"
        }

        It "Should detect type mismatches" {
            $machineConfig = @{
                BackupRoot    = (Get-WmrTestPath -WindowsPath "C:\MachineBackups")
                RetentionDays = 30  # Integer
            }

            $sharedConfig = @{
                BackupRoot    = (Get-WmrTestPath -WindowsPath "C:\SharedBackups")
                RetentionDays = @("30", "60")  # Array - incompatible type
            }

            $result = Test-ConfigurationConsistency -MachineConfig $machineConfig -SharedConfig $sharedConfig

            $result.Success | Should -Be $false
            $result.Errors | Should -Match "Type mismatch for key 'RetentionDays'"
            $result.ValidationDetails.TypeMismatches.Count | Should -BeGreaterThan 0
        }

        It "Should handle nested structure validation" {
            $machineConfig = @{
                EmailSettings = @{
                    FromAddress    = "machine@example.com"
                    SmtpPort       = 587
                    Authentication = @{
                        Type     = "OAuth"
                        ClientId = "machine-client"
                    }
                }
            }

            $sharedConfig = @{
                EmailSettings = @{
                    FromAddress    = "shared@example.com"
                    SmtpPort       = 465
                    Authentication = @{
                        Type     = "Basic"
                        Username = "shared-user"
                    }
                }
            }

            $result = Test-ConfigurationConsistency -MachineConfig $machineConfig -SharedConfig $sharedConfig

            $result.Success | Should -Be $true
            $result.Errors.Count | Should -Be 0
        }

        It "Should apply custom validation rules" {
            $machineConfig = @{
                BackupRoot    = (Get-WmrTestPath -WindowsPath "C:\MachineBackups")
                CloudProvider = "OneDrive"
            }

            $sharedConfig = @{
                BackupRoot    = (Get-WmrTestPath -WindowsPath "C:\SharedBackups")
                CloudProvider = "GoogleDrive"
            }

            $validationRules = @{
                "CloudProviderCompatibility" = {
                    param($MachineConfig, $SharedConfig)

                    $compatibleProviders = @("OneDrive", "GoogleDrive", "Dropbox")
                    $machineProvider = $MachineConfig.CloudProvider
                    $sharedProvider = $SharedConfig.CloudProvider

                    if ($machineProvider -notin $compatibleProviders -or $sharedProvider -notin $compatibleProviders) {
                        return @{ Success = $false; Message = "Incompatible cloud providers" }
                    }

                    return @{ Success = $true; Message = "Cloud providers are compatible" }
                }
            }

            $result = Test-ConfigurationConsistency -MachineConfig $machineConfig -SharedConfig $sharedConfig -ValidationRules $validationRules

            $result.Success | Should -Be $true
            $result.ValidationDetails.ValidationRuleResults.Count | Should -Be 1
            $result.ValidationDetails.ValidationRuleResults[0].RuleName | Should -Be "CloudProviderCompatibility"
            $result.ValidationDetails.ValidationRuleResults[0].Success | Should -Be $true
        }

        It "Should handle empty configurations" {
            $machineConfig = @{}
            $sharedConfig = @{}

            $result = Test-ConfigurationConsistency -MachineConfig $machineConfig -SharedConfig $sharedConfig

            $result.Success | Should -Be $true
            $result.Errors.Count | Should -Be 0
            $result.ValidationDetails.MachineConfigKeys.Count | Should -Be 0
            $result.ValidationDetails.SharedConfigKeys.Count | Should -Be 0
        }
    }

    Context "Test-SharedConfigurationMerging Function" {
        It "Should merge configurations correctly" {
            # Arrange
            $baseConfig = @{
                Key1 = "Value1"
                Key2 = @{
                    SubKey1 = "SubValue1"
                    SubKey2 = "SubValue2"
                }
                Key3 = "Value3"
            }

            $overrideConfig = @{
                Key1 = "OverrideValue1"
                Key2 = @{
                    SubKey2 = "OverrideSubValue2"
                    SubKey3 = "NewSubValue3"
                }
                Key4 = "NewValue4"
            }

            # Act
            $result = Test-SharedConfigurationMerging -BaseConfig $baseConfig -OverrideConfig $overrideConfig

            # Assert
            $result.Success | Should -Be $true
            $result.MergedConfig.Key1 | Should -Be "OverrideValue1"
            $result.MergedConfig.Key2.SubKey1 | Should -Be "SubValue1"
            $result.MergedConfig.Key2.SubKey2 | Should -Be "OverrideSubValue2"
            $result.MergedConfig.Key2.SubKey3 | Should -Be "NewSubValue3"
            $result.MergedConfig.Key3 | Should -Be "Value3"
            $result.MergedConfig.Key4 | Should -Be "NewValue4"
        }

        It "Should validate expected keys" {
            # Arrange
            $baseConfig = @{ Key1 = "Value1" }
            $overrideConfig = @{ Key2 = "Value2" }
            $expectedKeys = @("Key1", "Key2", "Key3")

            # Act
            $result = Test-SharedConfigurationMerging -BaseConfig $baseConfig -OverrideConfig $overrideConfig -ExpectedKeys $expectedKeys

            # Assert
            $result.Success | Should -Be $false
            $result.Errors | Should -Contain "Expected key 'Key3' is missing from merged configuration"
        }

        It "Should apply custom merging rules" {
            # Arrange
            $baseConfig = @{ Key1 = "Value1" }
            $overrideConfig = @{ Key2 = "Value2" }
            $mergingRules = @{
                "TestRule" = {
                    param($base, $override, $merged)
                    return @{ Success = $false; Message = "Test rule failed" }
                }
            }

            # Act
            $result = Test-SharedConfigurationMerging -BaseConfig $baseConfig -OverrideConfig $overrideConfig -MergingRules $mergingRules

            # Assert
            $result.Success | Should -Be $false
            $result.Errors | Should -Contain "Test rule failed"
        }

        It "Should handle empty configurations" {
            # Arrange
            $baseConfig = @{}
            $overrideConfig = @{}

            # Act
            $result = Test-SharedConfigurationMerging -BaseConfig $baseConfig -OverrideConfig $overrideConfig

            # Assert
            $result.Success | Should -Be $true
            $result.MergedConfig.Count | Should -Be 0
        }
    }

    Context "Test-ConfigurationInheritance Function" {

        It "Should validate simple inheritance hierarchy" {
            $level1 = @{
                Setting1 = "Level1Value1"
                Setting2 = "Level1Value2"
            }

            $level2 = @{
                Setting2 = "Level2Value2"
                Setting3 = "Level2Value3"
            }

            $level3 = @{
                Setting3 = "Level3Value3"
                Setting4 = "Level3Value4"
            }

            $hierarchy = @($level1, $level2, $level3)
            $result = Test-ConfigurationInheritance -ConfigurationHierarchy $hierarchy

            $result.Success | Should -Be $true
            $result.Errors.Count | Should -Be 0
            $result.FinalConfiguration | Should -Not -Be $null

            # Verify inheritance
            $result.FinalConfiguration.Setting1 | Should -Be "Level1Value1"  # From level 1
            $result.FinalConfiguration.Setting2 | Should -Be "Level2Value2"  # Overridden by level 2
            $result.FinalConfiguration.Setting3 | Should -Be "Level3Value3"  # Overridden by level 3
            $result.FinalConfiguration.Setting4 | Should -Be "Level3Value4"  # From level 3

            # Verify analysis
            $result.InheritanceAnalysis.LevelCount | Should -Be 3
            $result.InheritanceAnalysis.InheritanceChain.Count | Should -Be 3
        }

        It "Should track key origins and override history" {
            $level1 = @{
                Setting1 = "Original"
                Setting2 = "Original"
            }

            $level2 = @{
                Setting1 = "Override1"
                Setting3 = "New"
            }

            $level3 = @{
                Setting1 = "Override2"
            }

            $hierarchy = @($level1, $level2, $level3)
            $result = Test-ConfigurationInheritance -ConfigurationHierarchy $hierarchy

            $result.Success | Should -Be $true

            # Verify key origins
            $result.InheritanceAnalysis.KeyOrigins.ContainsKey("Setting1") | Should -Be $true
            $result.InheritanceAnalysis.KeyOrigins.ContainsKey("Setting2") | Should -Be $true
            $result.InheritanceAnalysis.KeyOrigins.ContainsKey("Setting3") | Should -Be $true

            # Verify override history for Setting1 (overridden twice)
            $setting1History = $result.InheritanceAnalysis.KeyOrigins["Setting1"].OverrideHistory
            $setting1History.Count | Should -Be 2
            $setting1History[0].OldValue | Should -Be "Original"
            $setting1History[0].NewValue | Should -Be "Override1"
            $setting1History[1].OldValue | Should -Be "Override1"
            $setting1History[1].NewValue | Should -Be "Override2"
        }

        It "Should apply inheritance rules" {
            $level1 = @{
                Arrays  = @("base1", "base2")
                Strings = "BaseString"
            }

            $level2 = @{
                Arrays  = @("override1", "override2")
                Strings = "OverrideString"
            }

            $inheritanceRules = @{
                "ArrayConcatenationRule" = {
                    param($CurrentConfig, $OverrideConfig, $Level)

                    # Custom rule to concatenate arrays instead of replacing
                    $modifiedConfig = $OverrideConfig.Clone()

                    if ($CurrentConfig.ContainsKey("Arrays") -and $OverrideConfig.ContainsKey("Arrays")) {
                        $modifiedConfig["Arrays"] = $CurrentConfig["Arrays"] + $OverrideConfig["Arrays"]
                    }

                    return @{
                        Success        = $true
                        Message        = "Array concatenation applied"
                        ModifiedConfig = $modifiedConfig
                    }
                }
            }

            $hierarchy = @($level1, $level2)
            $result = Test-ConfigurationInheritance -ConfigurationHierarchy $hierarchy -InheritanceRules $inheritanceRules

            $result.Success | Should -Be $true
            $result.FinalConfiguration.Arrays | Should -Be @("base1", "base2", "override1", "override2")
        }

        It "Should validate against schema" {
            $level1 = @{
                RequiredString = "Value"
                RequiredInt    = 42
                OptionalBool   = $true
            }

            $level2 = @{
                RequiredInt = 99
            }

            $schema = @{
                "RequiredString"  = @{
                    Required = $true
                    Type     = "String"
                }
                "RequiredInt"     = @{
                    Required  = $true
                    Type      = "Int32"
                    Validator = { param($Value) $Value -gt 0 }
                }
                "OptionalBool"    = @{
                    Required = $false
                    Type     = "Boolean"
                }
                "MissingRequired" = @{
                    Required = $true
                    Type     = "String"
                }
            }

            $hierarchy = @($level1, $level2)
            $result = Test-ConfigurationInheritance -ConfigurationHierarchy $hierarchy -ValidationSchema $schema

            $result.Success | Should -Be $false
            $result.Errors | Should -Contain "Required key 'MissingRequired' is missing from final configuration"

            # Verify schema validation results
            $schemaValidation = $result.InheritanceAnalysis.SchemaValidation
            $schemaValidation.Count | Should -Be 4

            $requiredStringValidation = $schemaValidation | Where-Object { $_.Key -eq "RequiredString" }
            $requiredStringValidation.Present | Should -Be $true
            $requiredStringValidation.TypeValid | Should -Be $true
        }

        It "Should handle empty hierarchy" {
            $hierarchy = @()
            $result = Test-ConfigurationInheritance -ConfigurationHierarchy $hierarchy

            $result.Success | Should -Be $false
            $result.Errors | Should -Contain "Configuration hierarchy is empty"
        }

        It "Should handle single level hierarchy" {
            $level1 = @{
                Setting1 = "Value1"
                Setting2 = "Value2"
            }

            $hierarchy = @($level1)
            $result = Test-ConfigurationInheritance -ConfigurationHierarchy $hierarchy

            $result.Success | Should -Be $true
            $result.FinalConfiguration.Setting1 | Should -Be "Value1"
            $result.FinalConfiguration.Setting2 | Should -Be "Value2"
            $result.InheritanceAnalysis.LevelCount | Should -Be 1
        }
    }

    Context "Test-ConfigurationFilePath Function" {

        BeforeEach {
            # Create temporary test files - handle Docker environment properly
            $tempPath = if ($env:TEMP) { $env:TEMP } elseif ($env:TMP) { $env:TMP } else { "/tmp" }
            $script:TempDir = Join-Path $tempPath "WMR-ConfigValidation-Tests"

            # Ensure TempDir is not null and create directory
            if ([string]::IsNullOrEmpty($script:TempDir)) {
                $script:TempDir = "/tmp/WMR-ConfigValidation-Tests"
            }

            New-Item -ItemType Directory -Path $script:TempDir -Force | Out-Null

            $script:ValidJsonFile = Join-Path $script:TempDir "valid.json"
            $script:InvalidJsonFile = Join-Path $script:TempDir "invalid.json"
            $script:EmptyFile = Join-Path $script:TempDir "empty.json"
            $script:NonExistentFile = Join-Path $script:TempDir "nonexistent.json"

            # Create test files
            @{ test = "value" } | ConvertTo-Json | Out-File $script:ValidJsonFile -Encoding UTF8
            "{ invalid json" | Out-File $script:InvalidJsonFile -Encoding UTF8
            # Create truly empty file with 0 bytes
            New-Item -ItemType File -Path $script:EmptyFile -Force | Out-Null
        }

        AfterEach {
            # Clean up temporary files
            if (Test-Path $script:TempDir) {
                Remove-Item $script:TempDir -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
            }
        }

        It "Should validate existing valid files" {
            $paths = @($script:ValidJsonFile)
            $result = Test-ConfigurationFilePath -ConfigurationPaths $paths -AccessibilityChecks $true -ContentValidation $true

            $result.Success | Should -Be $true
            $result.Errors.Count | Should -Be 0
            $result.PathAnalysis.Count | Should -Be 1

            $pathResult = $result.PathAnalysis[0]
            $pathResult.Exists | Should -Be $true
            $pathResult.Accessible | Should -Be $true
            $pathResult.ValidContent | Should -Be $true
            $pathResult.Extension | Should -Be ".json"
        }

        It "Should detect invalid JSON content" {
            $paths = @($script:InvalidJsonFile)
            $result = Test-ConfigurationFilePath -ConfigurationPaths $paths -AccessibilityChecks $true -ContentValidation $true

            $result.Success | Should -Be $false
            $result.Errors.Count | Should -BeGreaterThan 0
            $result.Errors[0] | Should -Match "Invalid JSON"

            $pathResult = $result.PathAnalysis[0]
            $pathResult.Exists | Should -Be $true
            $pathResult.Accessible | Should -Be $true
            $pathResult.ValidContent | Should -Be $false
        }

        It "Should detect empty files" {
            $paths = @($script:EmptyFile)
            $result = Test-ConfigurationFilePath -ConfigurationPaths $paths -AccessibilityChecks $true -ContentValidation $true

            $result.Success | Should -Be $true
            $result.Warnings.Count | Should -BeGreaterThan 0
            $result.Warnings[0] | Should -Match "empty"

            $pathResult = $result.PathAnalysis[0]
            $pathResult.Exists | Should -Be $true
            $pathResult.Size | Should -Be 0
        }

        It "Should detect non-existent files" {
            $paths = @($script:NonExistentFile)
            $result = Test-ConfigurationFilePath -ConfigurationPaths $paths -AccessibilityChecks $true -ContentValidation $true

            $result.Success | Should -Be $true
            $result.Warnings.Count | Should -BeGreaterThan 0
            $result.Warnings[0] | Should -Match "does not exist"

            $pathResult = $result.PathAnalysis[0]
            $pathResult.Exists | Should -Be $false
            $pathResult.Accessible | Should -Be $false
        }

        It "Should handle multiple files with mixed results" {
            $paths = @($script:ValidJsonFile, $script:InvalidJsonFile, $script:NonExistentFile)
            $result = Test-ConfigurationFilePath -ConfigurationPaths $paths -AccessibilityChecks $true -ContentValidation $true

            $result.Success | Should -Be $false  # Due to invalid JSON
            $result.PathAnalysis.Count | Should -Be 3

            # Valid file
            $validResult = $result.PathAnalysis | Where-Object { $_.Path -eq $script:ValidJsonFile }
            $validResult.Exists | Should -Be $true
            $validResult.ValidContent | Should -Be $true

            # Invalid file
            $invalidResult = $result.PathAnalysis | Where-Object { $_.Path -eq $script:InvalidJsonFile }
            $invalidResult.Exists | Should -Be $true
            $invalidResult.ValidContent | Should -Be $false

            # Non-existent file
            $nonExistentResult = $result.PathAnalysis | Where-Object { $_.Path -eq $script:NonExistentFile }
            $nonExistentResult.Exists | Should -Be $false
        }

        It "Should skip accessibility checks when disabled" {
            $paths = @($script:ValidJsonFile)
            $result = Test-ConfigurationFilePath -ConfigurationPaths $paths -AccessibilityChecks $false -ContentValidation $false

            $result.Success | Should -Be $true
            $pathResult = $result.PathAnalysis[0]
            $pathResult.Exists | Should -Be $true
            $pathResult.Accessible | Should -Be $false  # Not checked
            $pathResult.ValidContent | Should -Be $false  # Not checked
        }
    }
}








