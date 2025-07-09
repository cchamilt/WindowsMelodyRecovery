# tests/unit/TemplateInheritance.Tests.ps1

<#
.SYNOPSIS
    Unit tests for template inheritance functionality.

.DESCRIPTION
    Tests the template inheritance system including shared configurations,
    machine-specific overrides, conditional sections, and inheritance rules.

.NOTES
    Test Level: Unit
    Author: Windows Melody Recovery
    Version: 2.0
    Requires: Pester 5.0+
#>

BeforeAll {
    # Load Docker test bootstrap for cross-platform compatibility
    . (Join-Path $PSScriptRoot "../utilities/Docker-Test-Bootstrap.ps1")

    # Import the module
    Import-Module (Resolve-Path "$PSScriptRoot/../../WindowsMelodyRecovery.psd1") -Force
    
    # Load TemplateInheritance.ps1 content without Export-ModuleMember
    $templateInheritancePath = Join-Path (Split-Path (Resolve-Path "$PSScriptRoot/../../WindowsMelodyRecovery.psd1")) "Private\Core\TemplateInheritance.ps1"
    $templateInheritanceLines = Get-Content $templateInheritancePath
    # Remove the Export-ModuleMember section
    $filteredLines = @()
    $skipExport = $false
    foreach ($line in $templateInheritanceLines) {
        if ($line -match "^# Export functions for module use" -or $line -match "^Export-ModuleMember") {
            $skipExport = $true
        }
        if (-not $skipExport) {
            $filteredLines += $line
        }
    }
    $templateInheritanceContent = $filteredLines -join "`n"
    Invoke-Expression $templateInheritanceContent
    
    # Import test utilities
    . "$PSScriptRoot/../utilities/Test-Utilities.ps1"
    
    # Test data directory
    $script:TestDataPath = Join-Path $PSScriptRoot "../mock-data"
    
    # Create test template configurations
    $script:BasicTemplate = @{
        metadata = @{
            name = "Basic Template"
            description = "Basic template without inheritance"
            version = "1.0"
        }
        files = @(
            @{
                name = "Basic File"
                path = (Get-WmrTestPath -WindowsPath "C:\Test\basic.txt")
                type = "file"
                action = "sync"
                dynamic_state_path = "files/basic.txt"
            }
        )
    }
    
    $script:InheritanceTemplate = @{
        metadata = @{
            name = "Inheritance Template"
            description = "Template with inheritance features"
            version = "2.0"
        }
        configuration = @{
            inheritance_mode = "merge"
            machine_precedence = $true
            validation_level = "moderate"
            fallback_strategy = "use_shared"
        }
        shared = @{
            name = "Shared Configuration"
            description = "Shared settings for all machines"
            priority = 60
            override_policy = "merge"
            files = @(
                @{
                    name = "Shared File"
                    path = (Get-WmrTestPath -WindowsPath "C:\Shared\config.txt")
                    type = "file"
                    action = "sync"
                    dynamic_state_path = "shared/files/config.txt"
                    inheritance_tags = @("config", "shared")
                    inheritance_priority = 50
                }
            )
            registry = @(
                @{
                    name = "Shared Registry"
                    path = "HKCU:\Software\TestApp"
                    type = "key"
                    action = "sync"
                    dynamic_state_path = "shared/registry/testapp.json"
                    inheritance_tags = @("registry", "shared")
                    inheritance_priority = 50
                }
            )
        }
        machine_specific = @(
            @{
                machine_selectors = @(
                    @{
                        type = "machine_name"
                        value = "TEST-MACHINE"
                        operator = "equals"
                        case_sensitive = $false
                    }
                )
                name = "Test Machine Configuration"
                priority = 90
                merge_strategy = "deep_merge"
                files = @(
                    @{
                        name = "Machine File"
                        path = (Get-WmrTestPath -WindowsPath "C:\Machine\config.txt")
                        type = "file"
                        action = "sync"
                        dynamic_state_path = "machine/files/config.txt"
                        inheritance_tags = @("config", "machine")
                        inheritance_priority = 90
                    }
                )
                registry = @(
                    @{
                        name = "Machine Registry"
                        path = "HKCU:\Software\TestApp"
                        type = "key"
                        action = "sync"
                        dynamic_state_path = "machine/registry/testapp.json"
                        inheritance_tags = @("registry", "machine")
                        inheritance_priority = 90
                        conflict_resolution = "machine_wins"
                    }
                )
            }
        )
        inheritance_rules = @(
            @{
                name = "Registry Merge Rule"
                description = "Merge registry values instead of replacing"
                applies_to = @("registry")
                condition = @{
                    inheritance_tags = @{
                        contains = @("registry")
                    }
                }
                action = "merge"
                parameters = @{
                    merge_level = "value"
                    conflict_resolution = "machine_wins"
                }
            }
        )
        conditional_sections = @(
            @{
                name = "High Resolution Display"
                description = "Settings for high resolution displays"
                conditions = @(
                    @{
                        type = "custom_script"
                        check = "return 'high_res'"
                        expected_result = "high_res"
                        on_failure = "skip"
                    }
                )
                logic = "and"
                files = @(
                    @{
                        name = "High Resolution File"
                        path = (Get-WmrTestPath -WindowsPath "C:\HighRes\display.txt")
                        type = "file"
                        action = "sync"
                        dynamic_state_path = "conditional/files/display.txt"
                        inheritance_tags = @("display", "conditional")
                    }
                )
            }
        )
    }
    
    $script:TestMachineContext = @{
        MachineName = "TEST-MACHINE"
        UserName = "TestUser"
        UserProfile = (Get-WmrTestPath -WindowsPath "C:\Users\TestUser")
        OSVersion = "10.0.19041.0"
        Architecture = "AMD64"
        Domain = "WORKGROUP"
        EnvironmentVariables = @{
            COMPUTERNAME = "TEST-MACHINE"
            USERNAME = "TestUser"
            USERPROFILE = (Get-WmrTestPath -WindowsPath "C:\Users\TestUser")
        }
        HardwareInfo = @{
            Processors = @(@{ Name = "Intel Core i7"; NumberOfCores = 4 })
            Memory = 16GB
        }
        SoftwareInfo = @{
            PowerShellVersion = "5.1.19041.1"
        }
        Timestamp = Get-Date
    }
}

Describe "Template Inheritance Core Functions" {
    Context "Get-WmrInheritanceConfiguration" {
        It "Should return default configuration when no template configuration exists" {
            $template = @{ metadata = @{ name = "Test" } }
            $result = Get-WmrInheritanceConfiguration -TemplateConfig $template
            
            $result.inheritance_mode | Should -Be "merge"
            $result.machine_precedence | Should -Be $true
            $result.validation_level | Should -Be "moderate"
            $result.fallback_strategy | Should -Be "use_shared"
        }
        
        It "Should merge template configuration with defaults" {
            $template = @{
                metadata = @{ name = "Test" }
                configuration = @{
                    inheritance_mode = "override"
                    validation_level = "strict"
                }
            }
            $result = Get-WmrInheritanceConfiguration -TemplateConfig $template
            
            $result.inheritance_mode | Should -Be "override"
            $result.machine_precedence | Should -Be $true  # Default
            $result.validation_level | Should -Be "strict"
            $result.fallback_strategy | Should -Be "use_shared"  # Default
        }
    }
    
    Context "Get-WmrMachineContext" {
        It "Should collect basic machine context information" {
            $context = Get-WmrMachineContext
            
            $context.MachineName | Should -Not -BeNullOrEmpty
            $context.UserName | Should -Not -BeNullOrEmpty
            $context.OSVersion | Should -Not -BeNullOrEmpty
            $context.Architecture | Should -Not -BeNullOrEmpty
            $context.EnvironmentVariables | Should -Not -BeNull
            $context.Timestamp | Should -BeOfType [DateTime]
        }
        
        It "Should include hardware and software information" {
            $context = Get-WmrMachineContext
            
            $context.HardwareInfo | Should -Not -BeNull
            $context.SoftwareInfo | Should -Not -BeNull
            $context.SoftwareInfo.PowerShellVersion | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "Machine Selector Testing" {
    Context "Test-WmrMachineSelectors" {
        It "Should match machine name selector" {
            $selectors = @(
                @{
                    type = "machine_name"
                    value = "TEST-MACHINE"
                    operator = "equals"
                    case_sensitive = $false
                }
            )
            
            $result = Test-WmrMachineSelectors -MachineSelectors $selectors -MachineContext $script:TestMachineContext
            $result | Should -Be $true
        }
        
        It "Should not match incorrect machine name" {
            $selectors = @(
                @{
                    type = "machine_name"
                    value = "WRONG-MACHINE"
                    operator = "equals"
                    case_sensitive = $false
                }
            )
            
            $result = Test-WmrMachineSelectors -MachineSelectors $selectors -MachineContext $script:TestMachineContext
            $result | Should -Be $false
        }
        
        It "Should match hostname pattern selector" {
            $selectors = @(
                @{
                    type = "hostname_pattern"
                    value = "TEST-.*"
                    operator = "matches"
                    case_sensitive = $false
                }
            )
            
            $result = Test-WmrMachineSelectors -MachineSelectors $selectors -MachineContext $script:TestMachineContext
            $result | Should -Be $true
        }
        
        It "Should match environment variable selector" {
            $selectors = @(
                @{
                    type = "environment_variable"
                    value = "USERNAME"
                    expected_value = "TestUser"
                    operator = "equals"
                    case_sensitive = $false
                }
            )
            
            $result = Test-WmrMachineSelectors -MachineSelectors $selectors -MachineContext $script:TestMachineContext
            $result | Should -Be $true
        }
    }
    
    Context "Test-WmrStringComparison" {
        It "Should perform case-insensitive equals comparison" {
            $result = Test-WmrStringComparison -Value "TEST" -Expected "test" -Operator "equals" -CaseSensitive $false
            $result | Should -Be $true
        }
        
        It "Should perform case-sensitive equals comparison" {
            $result = Test-WmrStringComparison -Value "TEST" -Expected "test" -Operator "equals" -CaseSensitive $true
            $result | Should -Be $false
        }
        
        It "Should perform contains comparison" {
            $result = Test-WmrStringComparison -Value "TEST-MACHINE" -Expected "MACHINE" -Operator "contains" -CaseSensitive $false
            $result | Should -Be $true
        }
        
        It "Should perform regex matches comparison" {
            $result = Test-WmrStringComparison -Value "TEST-MACHINE-01" -Expected "TEST-.*-\d+" -Operator "matches" -CaseSensitive $false
            $result | Should -Be $true
        }
    }
}

Describe "Configuration Merging" {
    Context "Get-WmrApplicableMachineConfigurations" {
        It "Should return configurations that match machine selectors" {
            $machineConfigs = $script:InheritanceTemplate.machine_specific
            
            $result = Get-WmrApplicableMachineConfigurations -MachineSpecificConfigs $machineConfigs -MachineContext $script:TestMachineContext
            
            $result.Count | Should -Be 1
            $result[0].name | Should -Be "Test Machine Configuration"
        }
        
        It "Should return configurations sorted by priority" {
            $machineConfigs = @(
                @{
                    machine_selectors = @(@{ type = "machine_name"; value = "TEST-MACHINE"; operator = "equals" })
                    name = "Low Priority"
                    priority = 50
                },
                @{
                    machine_selectors = @(@{ type = "machine_name"; value = "TEST-MACHINE"; operator = "equals" })
                    name = "High Priority"
                    priority = 90
                }
            )
            
            $result = Get-WmrApplicableMachineConfigurations -MachineSpecificConfigs $machineConfigs -MachineContext $script:TestMachineContext
            
            $result.Count | Should -Be 2
            $result[0].name | Should -Be "High Priority"
            $result[1].name | Should -Be "Low Priority"
        }
    }
    
    Context "Merge-WmrSharedConfiguration" {
        It "Should merge shared configuration into resolved configuration" {
            $resolvedConfig = @{ metadata = @{ name = "Test" } }
            $sharedConfig = $script:InheritanceTemplate.shared
            $inheritanceConfig = @{ inheritance_mode = "merge"; machine_precedence = $true }
            
            $result = Merge-WmrSharedConfiguration -ResolvedConfig $resolvedConfig -SharedConfig $sharedConfig -InheritanceConfig $inheritanceConfig
            
            $result.files | Should -Not -BeNull
            $result.registry | Should -Not -BeNull
            $result.files.Count | Should -Be 1
            $result.registry.Count | Should -Be 1
            $result.files[0].inheritance_source | Should -Be "shared"
            $result.registry[0].inheritance_source | Should -Be "shared"
        }
    }
    
    Context "Merge-WmrMachineSpecificConfiguration" {
        It "Should merge machine-specific configuration with deep merge strategy" {
            $resolvedConfig = @{
                metadata = @{ name = "Test" }
                files = @(
                    @{
                        name = "Existing File"
                        path = (Get-WmrTestPath -WindowsPath "C:\Existing\file.txt")
                        inheritance_source = "shared"
                        inheritance_priority = 50
                    }
                )
            }
            
            $machineConfig = $script:InheritanceTemplate.machine_specific[0]
            $inheritanceConfig = @{ inheritance_mode = "merge"; machine_precedence = $true }
            
            $result = Merge-WmrMachineSpecificConfiguration -ResolvedConfig $resolvedConfig -MachineConfig $machineConfig -InheritanceConfig $inheritanceConfig
            
            $result.files.Count | Should -Be 2  # Original + machine-specific
            $result.registry.Count | Should -Be 1  # Machine-specific
            
            # Check that machine-specific items have correct inheritance metadata
            $machineFile = $result.files | Where-Object { $_.inheritance_source -eq "machine_specific" }
            $machineFile | Should -Not -BeNull
            $machineFile.inheritance_priority | Should -Be 90
        }
    }
}

Describe "Inheritance Rules Application" {
    Context "Apply-WmrInheritanceRules" {
        It "Should apply inheritance rules to matching sections" {
            $resolvedConfig = @{
                registry = @(
                    @{
                        name = "Test Registry"
                        path = "HKCU:\Software\Test"
                        inheritance_tags = @("registry")
                        inheritance_source = "shared"
                    }
                )
            }
            
            $inheritanceRules = $script:InheritanceTemplate.inheritance_rules
            
            $result = Apply-WmrInheritanceRules -ResolvedConfig $resolvedConfig -InheritanceRules $inheritanceRules -MachineContext $script:TestMachineContext
            
            $result.registry | Should -Not -BeNull
            $result.registry.Count | Should -Be 1
        }
    }
    
    Context "Test-WmrInheritanceRuleCondition" {
        It "Should return true when rule has no conditions" {
            $rule = @{
                name = "Test Rule"
                applies_to = @("registry")
                action = "merge"
            }
            
            $result = Test-WmrInheritanceRuleCondition -Rule $rule -ResolvedConfig @{} -MachineContext $script:TestMachineContext
            $result | Should -Be $true
        }
        
        It "Should check inheritance tags condition" {
            $rule = @{
                name = "Test Rule"
                applies_to = @("registry")
                condition = @{
                    inheritance_tags = @{
                        contains = @("registry")
                    }
                }
                action = "merge"
            }
            
            $resolvedConfig = @{
                registry = @(
                    @{
                        name = "Test"
                        inheritance_tags = @("registry", "shared")
                    }
                )
            }
            
            $result = Test-WmrInheritanceRuleCondition -Rule $rule -ResolvedConfig $resolvedConfig -MachineContext $script:TestMachineContext
            $result | Should -Be $true
        }
    }
}

Describe "Conditional Sections" {
    Context "Apply-WmrConditionalSections" {
        It "Should apply conditional sections when conditions are met" {
            $resolvedConfig = @{ metadata = @{ name = "Test" } }
            $conditionalSections = $script:InheritanceTemplate.conditional_sections
            
            $result = Apply-WmrConditionalSections -ResolvedConfig $resolvedConfig -ConditionalSections $conditionalSections -MachineContext $script:TestMachineContext
            
            $result.files | Should -Not -BeNull
            $result.files.Count | Should -Be 1
            $result.files[0].inheritance_source | Should -Be "conditional"
            $result.files[0].conditional_section | Should -Be "High Resolution Display"
        }
    }
    
    Context "Test-WmrConditionalSectionConditions" {
        It "Should evaluate custom script conditions" {
            $conditionalSection = @{
                name = "Test Section"
                conditions = @(
                    @{
                        type = "custom_script"
                        check = "return 'success'"
                        expected_result = "success"
                        on_failure = "skip"
                    }
                )
                logic = "and"
            }
            
            $result = Test-WmrConditionalSectionConditions -ConditionalSection $conditionalSection -MachineContext $script:TestMachineContext
            $result | Should -Be $true
        }
        
        It "Should evaluate machine name conditions" {
            $conditionalSection = @{
                name = "Test Section"
                conditions = @(
                    @{
                        type = "machine_name"
                        check = "TEST-MACHINE"
                        expected_result = "TEST-MACHINE"
                        on_failure = "skip"
                    }
                )
                logic = "and"
            }
            
            $result = Test-WmrConditionalSectionConditions -ConditionalSection $conditionalSection -MachineContext $script:TestMachineContext
            $result | Should -Be $true
        }
        
        It "Should handle condition failures with skip action" {
            $conditionalSection = @{
                name = "Test Section"
                conditions = @(
                    @{
                        type = "custom_script"
                        check = "throw 'Test error'"
                        expected_result = "success"
                        on_failure = "skip"
                    }
                )
                logic = "and"
            }
            
            $result = Test-WmrConditionalSectionConditions -ConditionalSection $conditionalSection -MachineContext $script:TestMachineContext
            $result | Should -Be $false
        }
    }
}

Describe "Configuration Validation" {
    Context "Test-WmrResolvedConfiguration" {
        It "Should validate configuration with moderate validation level" {
            $resolvedConfig = @{
                metadata = @{ name = "Test" }
                files = @(
                    @{
                        name = "Test File"
                        path = (Get-WmrTestPath -WindowsPath "C:\Test\file.txt")
                        type = "file"
                        action = "sync"
                    }
                )
            }
            
            $inheritanceConfig = @{ validation_level = "moderate" }
            
            { Test-WmrResolvedConfiguration -ResolvedConfig $resolvedConfig -InheritanceConfig $inheritanceConfig } | Should -Not -Throw
        }
    }
    
    Context "Test-WmrStrictConfigurationValidation" {
        It "Should detect duplicate names in strict validation" {
            $resolvedConfig = @{
                files = @(
                    @{ name = "Duplicate"; path = (Get-WmrTestPath -WindowsPath "C:\Test1\file.txt") },
                    @{ name = "Duplicate"; path = (Get-WmrTestPath -WindowsPath "C:\Test2\file.txt") }
                )
            }
            
            { Test-WmrStrictConfigurationValidation -ResolvedConfig $resolvedConfig } | Should -Throw "*Duplicate names found*"
        }
        
        It "Should detect missing required properties" {
            $resolvedConfig = @{
                files = @(
                    @{ path = (Get-WmrTestPath -WindowsPath "C:\Test\file.txt") }  # Missing name
                )
            }
            
            { Test-WmrStrictConfigurationValidation -ResolvedConfig $resolvedConfig } | Should -Throw "*Missing required 'name' property*"
        }
    }
}

Describe "Full Template Inheritance Resolution" {
    Context "Resolve-WmrTemplateInheritance" {
        It "Should resolve template inheritance for basic template without inheritance features" {
            $result = Resolve-WmrTemplateInheritance -TemplateConfig $script:BasicTemplate -MachineContext $script:TestMachineContext
            
            $result.metadata.name | Should -Be "Basic Template"
            $result.files.Count | Should -Be 1
            $result.files[0].name | Should -Be "Basic File"
        }
        
        It "Should resolve template inheritance for template with all inheritance features" {
            $result = Resolve-WmrTemplateInheritance -TemplateConfig $script:InheritanceTemplate -MachineContext $script:TestMachineContext
            
            $result.metadata.name | Should -Be "Inheritance Template"
            $result.files | Should -Not -BeNull
            $result.registry | Should -Not -BeNull
            
            # Should have shared + machine-specific + conditional files
            $result.files.Count | Should -Be 3
            
            # Check inheritance sources
            $sharedFile = $result.files | Where-Object { $_.inheritance_source -eq "shared" }
            $machineFile = $result.files | Where-Object { $_.inheritance_source -eq "machine_specific" }
            $conditionalFile = $result.files | Where-Object { $_.inheritance_source -eq "conditional" }
            
            $sharedFile | Should -Not -BeNull
            $machineFile | Should -Not -BeNull
            $conditionalFile | Should -Not -BeNull
        }
        
        It "Should handle template with no applicable machine-specific configurations" {
            $template = $script:InheritanceTemplate | ConvertTo-Json -Depth 100 | ConvertFrom-Json
            $template.machine_specific[0].machine_selectors[0].value = "DIFFERENT-MACHINE"
            
            $result = Resolve-WmrTemplateInheritance -TemplateConfig $template -MachineContext $script:TestMachineContext
            
            # Should only have shared + conditional files (no machine-specific)
            $result.files.Count | Should -Be 2
            
            $machineFile = $result.files | Where-Object { $_.inheritance_source -eq "machine_specific" }
            $machineFile | Should -BeNull
        }
    }
    
    Context "Configuration Merging Edge Cases" {
        It "Should handle conflicting configurations with machine precedence" {
            $template = @{
                metadata = @{ name = "Conflict Test" }
                configuration = @{
                    inheritance_mode = "merge"
                    machine_precedence = $true
                }
                shared = @{
                    files = @(
                        @{
                            name = "Conflict File"
                            path = (Get-WmrTestPath -WindowsPath "C:\Shared\file.txt")
                            inheritance_tags = @("config")
                            inheritance_priority = 50
                        }
                    )
                }
                machine_specific = @(
                    @{
                        machine_selectors = @(@{ type = "machine_name"; value = "TEST-MACHINE"; operator = "equals" })
                        files = @(
                            @{
                                name = "Conflict File"
                                path = (Get-WmrTestPath -WindowsPath "C:\Machine\file.txt")
                                inheritance_tags = @("config")
                                inheritance_priority = 90
                                conflict_resolution = "machine_wins"
                            }
                        )
                    }
                )
            }
            
            $result = Resolve-WmrTemplateInheritance -TemplateConfig $template -MachineContext $script:TestMachineContext
            
            $result.files.Count | Should -Be 1
            $result.files[0].path | Should -Be (Get-WmrTestPath -WindowsPath "C:\Machine\file.txt")  # Machine should win
        }
    }
}

AfterAll {
    # Clean up any test resources
    if (Test-Path $script:TestDataPath) {
        # Clean up test data if needed
    }
} 

