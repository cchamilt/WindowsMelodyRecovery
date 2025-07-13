# TemplateInheritance.Tests.ps1
# Tests for template inheritance functionality in Windows Melody Recovery

# Import required modules and test utilities
BeforeAll {
    # Load test environment
    . "$PSScriptRoot\..\utilities\Test-Utilities.ps1"

    # Load the main module
    Import-Module $PSScriptRoot\..\..\WindowsMelodyRecovery.psd1 -Force

    # Load template inheritance functions
    . "$PSScriptRoot\..\..\Private\Core\TemplateInheritance.ps1"

    # Create test machine context
    $script:TestMachineContext = @{
        MachineName          = "TEST-MACHINE"
        UserName             = "TestUser"
        UserProfile          = "C:\Users\TestUser"
        OSVersion            = "10.0.19045"
        Architecture         = "AMD64"
        Domain               = "WORKGROUP"
        EnvironmentVariables = @{
            COMPUTERNAME           = "TEST-MACHINE"
            USERNAME               = "TestUser"
            USERPROFILE            = "C:\Users\TestUser"
            PROCESSOR_ARCHITECTURE = "AMD64"
            USERDOMAIN             = "WORKGROUP"
        }
        HardwareInfo         = @{
            Processors       = @(@{
                    Name                      = "Intel(R) Core(TM) i7-9700K CPU @ 3.60GHz"
                    NumberOfCores             = 8
                    NumberOfLogicalProcessors = 8
                })
            Memory           = 17179869184  # 16 GB
            VideoControllers = @(@{
                    Name       = "NVIDIA GeForce RTX 3070"
                    AdapterRAM = 8589934592  # 8 GB
                })
        }
        SoftwareInfo         = @{
            PowerShellVersion = "5.1.19041.1682"
            DotNetVersion     = ".NET Framework 4.8.4515.0"
        }
        Timestamp            = Get-Date
    }

    # Create test inheritance template
    $script:InheritanceTemplate = @{
        metadata             = @{
            name        = "Test Inheritance Template"
            version     = "1.0"
            description = "Test template for inheritance functionality"
        }
        inheritance_mode     = "merge"
        machine_precedence   = $true
        shared               = @{
            files    = @(
                @{
                    name             = "Shared Configuration"
                    path             = (Get-WmrTestPath -WindowsPath "C:\Shared\config.txt")
                    inheritance_tags = @("shared", "config")
                }
            )
            registry = @(
                @{
                    name             = "Shared Registry"
                    path             = "HKCU:\Software\TestApp"
                    inheritance_tags = @("shared", "registry")
                }
            )
        }
        machine_specific     = @(
            @{
                name              = "Test Machine Configuration"
                priority          = 90
                machine_selectors = @(
                    @{
                        type           = "machine_name"
                        value          = "TEST-MACHINE"
                        operator       = "equals"
                        case_sensitive = $false
                    }
                )
                files             = @(
                    @{
                        name             = "Machine File"
                        path             = (Get-WmrTestPath -WindowsPath "C:\Machine\config.txt")
                        inheritance_tags = @("machine", "config")
                    }
                )
                registry          = @(
                    @{
                        name             = "Machine Registry"
                        path             = "HKLM:\SOFTWARE\TestApp"
                        inheritance_tags = @("machine", "registry")
                    }
                )
            }
        )
        inheritance_rules    = @(
            @{
                name       = "Registry Merge Rule"
                applies_to = @("registry")
                action     = "merge"
                condition  = @{
                    inheritance_tags = @{
                        contains = @("registry")
                    }
                }
            }
        )
        conditional_sections = @(
            @{
                name       = "High Resolution Display"
                conditions = @(
                    @{
                        type            = "custom_script"
                        check           = "return 'success'"
                        expected_result = "success"
                    }
                )
                files      = @(
                    @{
                        name             = "High Res Display File"
                        path             = (Get-WmrTestPath -WindowsPath "C:\HighRes\display.txt")
                        inheritance_tags = @("display", "conditional")
                    }
                )
            }
        )
    }
}

Describe "Template Inheritance Core Functions" {
    Context "Get-WmrInheritanceConfiguration" {
        It "Should return default configuration when no template configuration exists" {
            $templateConfig = @{
                metadata      = @{ name = "Test" }
                configuration = @{}
            }

            $result = Get-WmrInheritanceConfiguration -TemplateConfig $templateConfig
            $result.inheritance_mode | Should -Be "merge"
            $result.machine_precedence | Should -Be $true
            $result.validation_level | Should -Be "moderate"
        }

        It "Should merge template configuration with defaults" {
            $templateConfig = @{
                metadata           = @{ name = "Test" }
                configuration      = @{}
                inheritance_mode   = "override"
                machine_precedence = $false
                validation_level   = "strict"
            }

            $result = Get-WmrInheritanceConfiguration -TemplateConfig $templateConfig
            $result.inheritance_mode | Should -Be "override"
            $result.machine_precedence | Should -Be $false
            $result.validation_level | Should -Be "strict"
        }
    }

    Context "Get-WmrMachineContext" {
        It "Should collect basic machine context information" {
            $context = Get-WmrMachineContext
            $context.MachineName | Should -Not -BeNullOrEmpty
            $context.UserName | Should -Not -BeNullOrEmpty
            $context.OSVersion | Should -Not -BeNullOrEmpty
            $context.Architecture | Should -Not -BeNullOrEmpty
        }

        It "Should include hardware and software information" {
            $context = Get-WmrMachineContext
            $context.HardwareInfo | Should -Not -BeNull
            $context.SoftwareInfo | Should -Not -BeNull
            $context.EnvironmentVariables | Should -Not -BeNull
        }
    }
}

Describe "Machine Selector Testing" {
    Context "Test-WmrMachineSelector" {
        It "Should match machine name selector" {
            $selectors = @(
                @{
                    type           = "machine_name"
                    value          = "TEST-MACHINE"
                    operator       = "equals"
                    case_sensitive = $false
                }
            )

            $result = Test-WmrMachineSelector -MachineSelectors $selectors -MachineContext $script:TestMachineContext
            $result | Should -Be $true
        }

        It "Should not match incorrect machine name" {
            $selectors = @(
                @{
                    type           = "machine_name"
                    value          = "WRONG-MACHINE"
                    operator       = "equals"
                    case_sensitive = $false
                }
            )

            $result = Test-WmrMachineSelector -MachineSelectors $selectors -MachineContext $script:TestMachineContext
            $result | Should -Be $false
        }

        It "Should match hostname pattern selector" {
            $selectors = @(
                @{
                    type           = "hostname_pattern"
                    value          = "TEST-.*"
                    operator       = "matches"
                    case_sensitive = $false
                }
            )

            $result = Test-WmrMachineSelector -MachineSelectors $selectors -MachineContext $script:TestMachineContext
            $result | Should -Be $true
        }

        It "Should match environment variable selector" {
            $selectors = @(
                @{
                    type           = "environment_variable"
                    value          = "USERNAME"
                    expected_value = "TestUser"
                    operator       = "equals"
                    case_sensitive = $false
                }
            )

            $result = Test-WmrMachineSelector -MachineSelectors $selectors -MachineContext $script:TestMachineContext
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
    Context "Get-WmrApplicableMachineConfiguration" {
        It "Should return configurations that match machine selectors" {
            $machineConfigs = $script:InheritanceTemplate.machine_specific

            $result = Get-WmrApplicableMachineConfiguration -MachineSpecificConfigs $machineConfigs -MachineContext $script:TestMachineContext

            # The function should return all applicable configurations
            $result.Count | Should -BeGreaterThan 0
            # Check that at least one configuration matches
            $testMachineConfig = $result | Where-Object { $_.name -eq "Test Machine Configuration" }
            $testMachineConfig | Should -Not -BeNull
        }

        It "Should return configurations sorted by priority" {
            $machineConfigs = @(
                @{
                    machine_selectors = @(@{ type = "machine_name"; value = "TEST-MACHINE"; operator = "equals" })
                    name              = "Low Priority"
                    priority          = 50
                },
                @{
                    machine_selectors = @(@{ type = "machine_name"; value = "TEST-MACHINE"; operator = "equals" })
                    name              = "High Priority"
                    priority          = 90
                }
            )

            $result = Get-WmrApplicableMachineConfiguration -MachineSpecificConfigs $machineConfigs -MachineContext $script:TestMachineContext

            $result.Count | Should -Be 2
            $result[0].name | Should -Be "High Priority"
            $result[1].name | Should -Be "Low Priority"
        }
    }

    Context "Merge-WmrSharedConfiguration" {
        It "Should merge shared configuration into resolved configuration" {
            $resolvedConfig = [PSCustomObject]@{ metadata = @{ name = "Test" } }
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
            $resolvedConfig = [PSCustomObject]@{
                metadata = @{ name = "Test" }
                files    = @(
                    @{
                        name                 = "Existing File"
                        path                 = (Get-WmrTestPath -WindowsPath "C:\Existing\file.txt")
                        inheritance_source   = "shared"
                        inheritance_priority = 50
                    }
                )
            }

            $machineConfig = $script:InheritanceTemplate.machine_specific[0]
            $inheritanceConfig = @{ inheritance_mode = "merge"; machine_precedence = $true }

            $result = Merge-WmrMachineSpecificConfiguration -ResolvedConfig $resolvedConfig -MachineConfig $machineConfig -InheritanceConfig $inheritanceConfig

            $result.files.Count | Should -Be 2  # Original + machine-specific
            $result.registry | Should -Not -BeNull  # Machine-specific registry should exist
            $result.registry.Count | Should -BeGreaterThan 0  # Should have at least some registry items

            # Check that machine-specific items have correct inheritance metadata
            $machineFile = $result.files | Where-Object { $_.inheritance_source -eq "machine_specific" }
            $machineFile | Should -Not -BeNull
            $machineFile.inheritance_priority | Should -Be 90
        }
    }
}

Describe "Inheritance Rules Application" {
    Context "Invoke-WmrInheritanceRule" {
        It "Should apply inheritance rules to matching sections" {
            $resolvedConfig = [PSCustomObject]@{
                registry = @(
                    @{
                        name               = "Test Registry"
                        path               = "HKCU:\Software\Test"
                        inheritance_tags   = @("registry")
                        inheritance_source = "shared"
                    }
                )
            }

            $inheritanceRules = $script:InheritanceTemplate.inheritance_rules

            $result = Invoke-WmrInheritanceRule -ResolvedConfig $resolvedConfig -InheritanceRules $inheritanceRules -MachineContext $script:TestMachineContext

            $result.registry | Should -Not -BeNull
            $result.registry.Count | Should -BeGreaterThan 0  # Should have at least some registry items
        }
    }

    Context "Test-WmrInheritanceRuleCondition" {
        It "Should return true when rule has no conditions" {
            $rule = @{
                name       = "Test Rule"
                applies_to = @("registry")
                action     = "merge"
            }

            $result = Test-WmrInheritanceRuleCondition -Rule $rule -ResolvedConfig ([PSCustomObject]@{}) -MachineContext $script:TestMachineContext
            $result | Should -Be $true
        }

        It "Should check inheritance tags condition" {
            $rule = @{
                name       = "Test Rule"
                applies_to = @("registry")
                condition  = @{
                    inheritance_tags = @{
                        contains = @("registry")
                    }
                }
                action     = "merge"
            }

            $resolvedConfig = [PSCustomObject]@{
                registry = @(
                    @{
                        name             = "Test"
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
    Context "Invoke-WmrConditionalSection" {
        It "Should apply conditional sections when conditions are met" {
            $resolvedConfig = [PSCustomObject]@{ metadata = @{ name = "Test" } }
            $conditionalSections = $script:InheritanceTemplate.conditional_sections

            $result = Invoke-WmrConditionalSection -ResolvedConfig $resolvedConfig -ConditionalSections $conditionalSections -MachineContext $script:TestMachineContext

            $result.files | Should -Not -BeNull
            $result.files.Count | Should -Be 1
            $result.files[0].inheritance_source | Should -Be "conditional"
            $result.files[0].conditional_section | Should -Be "High Resolution Display"
        }
    }

    Context "Test-WmrConditionalSectionCondition" {
        It "Should evaluate custom script conditions" {
            $conditionalSection = @{
                name       = "Test Section"
                conditions = @(
                    @{
                        type            = "custom_script"
                        check           = "return 'success'"
                        expected_result = "success"
                    }
                )
            }

            $result = Test-WmrConditionalSectionCondition -ConditionalSection $conditionalSection -MachineContext $script:TestMachineContext
            $result | Should -Be $true
        }

        It "Should evaluate machine name conditions" {
            $conditionalSection = @{
                name       = "Test Section"
                conditions = @(
                    @{
                        type           = "environment_variable"
                        variable       = "COMPUTERNAME"
                        expected_value = "TEST-MACHINE"
                        operator       = "equals"
                    }
                )
            }

            $result = Test-WmrConditionalSectionCondition -ConditionalSection $conditionalSection -MachineContext $script:TestMachineContext
            $result | Should -Be $true
        }

        It "Should handle condition failures with skip action" {
            $conditionalSection = @{
                name       = "Test Section"
                conditions = @(
                    @{
                        type            = "custom_script"
                        check           = "return 'failure'"
                        expected_result = "success"
                    }
                )
            }

            $result = Test-WmrConditionalSectionCondition -ConditionalSection $conditionalSection -MachineContext $script:TestMachineContext
            $result | Should -Be $false
        }
    }
}

Describe "Configuration Validation" {
    Context "Test-WmrResolvedConfiguration" {
        It "Should validate configuration with moderate validation level" {
            $resolvedConfig = [PSCustomObject]@{
                metadata = @{ name = "Test"; version = "1.0" }
                files    = @(
                    @{
                        name               = "Test File"
                        path               = (Get-WmrTestPath -WindowsPath "C:\Test\file.txt")
                        inheritance_source = "shared"
                    }
                )
            }

            $result = Test-WmrResolvedConfiguration -ResolvedConfig $resolvedConfig -ValidationLevel "moderate"
            $result | Should -Be $true
        }
    }

    Context "Test-WmrStrictConfigurationValidation" {
        It "Should detect duplicate names in strict validation" {
            $resolvedConfig = [PSCustomObject]@{
                metadata = @{ name = "Test"; version = "1.0" }
                files    = @(
                    @{
                        name               = "Duplicate"
                        path               = (Get-WmrTestPath -WindowsPath "C:\Test1\file.txt")
                        inheritance_source = "shared"
                    },
                    @{
                        name               = "Duplicate"
                        path               = (Get-WmrTestPath -WindowsPath "C:\Test2\file.txt")
                        inheritance_source = "machine_specific"
                    }
                )
            }

            { Test-WmrStrictConfigurationValidation -ResolvedConfig $resolvedConfig } | Should -Throw "*Duplicate names found*"
        }

        It "Should detect missing required properties" {
            $resolvedConfig = [PSCustomObject]@{
                metadata = @{ version = "1.0" }  # Missing name
                files    = @(
                    @{
                        path               = (Get-WmrTestPath -WindowsPath "C:\Test\file.txt")
                        inheritance_source = "shared"
                    }
                )
            }

            { Test-WmrStrictConfigurationValidation -ResolvedConfig $resolvedConfig } | Should -Throw "*Missing required 'name' property*"
        }
    }
}

Describe "Full Template Inheritance Resolution" {
    Context "Resolve-WmrTemplateInheritance" {
        It "Should resolve template inheritance for basic template without inheritance features" {
            $templateConfig = @{
                metadata      = @{ name = "Basic Template"; version = "1.0" }
                configuration = @{
                    files = @(
                        @{
                            name = "Basic File"
                            path = (Get-WmrTestPath -WindowsPath "C:\Basic\file.txt")
                        }
                    )
                }
            }

            $result = Resolve-WmrTemplateInheritance -TemplateConfig $templateConfig -MachineContext $script:TestMachineContext
            $result.files.Count | Should -Be 1
            $result.files[0].name | Should -Be "Basic File"
        }

        It "Should resolve template inheritance for template with all inheritance features" {
            $result = Resolve-WmrTemplateInheritance -TemplateConfig $script:InheritanceTemplate -MachineContext $script:TestMachineContext
            $result.files.Count | Should -BeGreaterThan 0
            $result.registry.Count | Should -BeGreaterThan 0
        }

        It "Should handle template with no applicable machine-specific configurations" {
            $templateConfig = @{
                metadata             = @{ name = "Test Template"; version = "1.0" }
                configuration        = @{
                    files = @(
                        @{
                            name = "Basic File"
                            path = (Get-WmrTestPath -WindowsPath "C:\Basic\file.txt")
                        }
                    )
                }
                inheritance_rules    = @()
                shared               = @{}
                conditional_sections = @()
                machine_specific     = @(
                    @{
                        name              = "Different Machine"
                        machine_selectors = @(
                            @{
                                type     = "machine_name"
                                value    = "DIFFERENT-MACHINE"
                                operator = "equals"
                            }
                        )
                        files             = @(
                            @{
                                name = "Machine File"
                                path = (Get-WmrTestPath -WindowsPath "C:\Machine\file.txt")
                            }
                        )
                    }
                )
            }

            $result = Resolve-WmrTemplateInheritance -TemplateConfig $templateConfig -MachineContext $script:TestMachineContext
            $result.files.Count | Should -Be 1  # Only basic file, no machine-specific
        }
    }

    Context "Configuration Merging Edge Cases" {
        It "Should handle conflicting configurations with machine precedence" {
            $templateConfig = @{
                metadata           = @{ name = "Conflict Test"; version = "1.0" }
                configuration      = @{}
                machine_precedence = $true
                shared             = @{
                    files = @(
                        @{
                            name             = "Conflict File"
                            path             = (Get-WmrTestPath -WindowsPath "C:\Shared\file.txt")
                            inheritance_tags = @("shared")
                            value            = "shared_value"
                        }
                    )
                }
                machine_specific   = @(
                    @{
                        name              = "Machine Config"
                        machine_selectors = @(
                            @{
                                type     = "machine_name"
                                value    = "TEST-MACHINE"
                                operator = "equals"
                            }
                        )
                        files             = @(
                            @{
                                name             = "Conflict File"
                                path             = (Get-WmrTestPath -WindowsPath "C:\Machine\file.txt")
                                inheritance_tags = @("machine")
                                value            = "machine_value"
                            }
                        )
                    }
                )
            }

            $result = Resolve-WmrTemplateInheritance -TemplateConfig $templateConfig -MachineContext $script:TestMachineContext
            $result.files.Count | Should -BeGreaterThan 0
            # In machine precedence mode, machine-specific should win
            $conflictFile = $result.files | Where-Object { $_.name -eq "Conflict File" -and $_.value -eq "machine_value" }
            $conflictFile | Should -Not -BeNull
        }
    }
}

AfterAll {
    # Clean up any test resources
    # Test cleanup is handled by the test framework
}








