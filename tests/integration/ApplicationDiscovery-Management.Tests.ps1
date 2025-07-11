# Tests for Application Discovery and Management (Task 7.2)
# Tests unmanaged application discovery, installation documentation, user-editable lists, and configuration selection

BeforeAll {
    # Import the module
    Import-Module (Resolve-Path "$PSScriptRoot/../../WindowsMelodyRecovery.psd1") -Force

    # Source the setup scripts
    . "$PSScriptRoot/../../Private/setup/setup-application-discovery.ps1"
    . "$PSScriptRoot/../../Private/setup/setup-configuration-selection.ps1"

    # Create test environment
    $script:TestBackupRoot = Join-Path $TestDrive "TestBackup"
    $script:TestMachineName = "TestMachine"
    $script:TestApplicationDiscoveryPath = Join-Path $TestBackupRoot $TestMachineName "ApplicationDiscovery"
    $script:TestConfigurationProfilesPath = Join-Path $TestBackupRoot $TestMachineName "ConfigurationProfiles"

    # Create test directories
    New-Item -ItemType Directory -Path $TestBackupRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $TestApplicationDiscoveryPath -Force | Out-Null
    New-Item -ItemType Directory -Path $TestConfigurationProfilesPath -Force | Out-Null

    # Mock WindowsMelodyRecovery configuration
    $script:MockConfig = @{
        IsInitialized = $true
        BackupRoot = $TestBackupRoot
        MachineName = $TestMachineName
    }

    # Mock Get-WindowsMelodyRecovery function
    Mock Get-WindowsMelodyRecovery { return $script:MockConfig }

    # Create mock unmanaged applications data
    $script:MockUnmanagedApps = @(
        @{
            Name = "TestApp1"
            Version = "1.0.0"
            Publisher = "Test Publisher"
            Source = "manual"
            Priority = "medium"
            Category = "productivity"
            InstallDate = "2024-01-01"
            UninstallString = "uninstall.exe"
        },
        @{
            Name = "TestApp2"
            Version = "2.0.0"
            Publisher = "Another Publisher"
            Source = "manual"
            Priority = "low"
            Category = "utility"
            InstallDate = "2024-01-02"
            UninstallString = "remove.exe"
        }
    )

    # Create mock available setup scripts
    $script:MockSetupScripts = @(
        @{
            Name = "Initialize-PackageManagers"
            FileName = "Initialize-PackageManagers.ps1"
            Description = "Install and configure package managers"
            Category = "System"
            RequiresAdmin = $true
            Dependencies = @()
        },
        @{
            Name = "Initialize-WSL"
            FileName = "Initialize-WSL.ps1"
            Description = "Configure Windows Subsystem for Linux"
            Category = "Development"
            RequiresAdmin = $true
            Dependencies = @()
        },
        @{
            Name = "setup-steam-games"
            FileName = "setup-steam-games.ps1"
            Description = "Configure Steam gaming platform"
            Category = "Gaming"
            RequiresAdmin = $false
            Dependencies = @()
        }
    )
}

Describe "Application Discovery and Management Tests" {

    Context "Unmanaged Application Discovery" {

        It "Should discover unmanaged applications in Quick mode" {
            # Mock the analyze-unmanaged script
            Mock Invoke-UnmanagedApplicationDiscovery { return $script:MockUnmanagedApps }

            $result = Invoke-UnmanagedApplicationDiscovery -Mode "Quick"

            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -Be 2
            $result[0].Name | Should -Be "TestApp1"
            $result[1].Name | Should -Be "TestApp2"
        }

        It "Should discover unmanaged applications in Full mode" {
            # Mock the analyze-unmanaged script
            Mock Invoke-UnmanagedApplicationDiscovery { return $script:MockUnmanagedApps }

            $result = Invoke-UnmanagedApplicationDiscovery -Mode "Full"

            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -Be 2
        }

        It "Should handle empty discovery results gracefully" {
            # Mock empty results
            Mock Invoke-UnmanagedApplicationDiscovery { return @() }

            $result = Invoke-UnmanagedApplicationDiscovery -Mode "Quick"

            $result | Should -Not -BeNull
            $result.Count | Should -Be 0
        }

        It "Should handle discovery errors gracefully" {
            # Mock error in discovery
            Mock Invoke-UnmanagedApplicationDiscovery { throw "Discovery failed" }

            $result = Invoke-UnmanagedApplicationDiscovery -Mode "Quick"

            $result | Should -Not -BeNull
            $result.Count | Should -Be 0
        }

        It "Should support WhatIf mode for discovery" {
            $result = Invoke-UnmanagedApplicationDiscovery -Mode "Quick" -WhatIf

            $result | Should -Not -BeNull
            $result.Count | Should -Be 0
        }
    }

    Context "Application List Management" {

        It "Should save application list in JSON format" {
            $testPath = Join-Path $TestDrive "test-apps.json"

            Save-ApplicationList -Applications $script:MockUnmanagedApps -Path $testPath -Format "JSON"

            $testPath | Should -Exist
            $content = Get-Content $testPath | ConvertFrom-Json
            $content.Count | Should -Be 2
            $content[0].Name | Should -Be "TestApp1"
        }

        It "Should save application list in CSV format" {
            $testPath = Join-Path $TestDrive "test-apps.csv"

            Save-ApplicationList -Applications $script:MockUnmanagedApps -Path $testPath -Format "CSV"

            $testPath | Should -Exist
            $content = Import-Csv $testPath
            $content.Count | Should -Be 2
            $content[0].Name | Should -Be "TestApp1"
        }

        It "Should save application list in YAML format" {
            $testPath = Join-Path $TestDrive "test-apps.yaml"

            Save-ApplicationList -Applications $script:MockUnmanagedApps -Path $testPath -Format "YAML"

            $testPath | Should -Exist
            $content = Get-Content $testPath -Raw
            $content | Should -Match "applications:"
            $content | Should -Match "TestApp1"
        }

        It "Should support WhatIf mode for saving" {
            $testPath = Join-Path $TestDrive "test-apps-whatif.json"

            Save-ApplicationList -Applications $script:MockUnmanagedApps -Path $testPath -Format "JSON" -WhatIf

            $testPath | Should -Not -Exist
        }
    }

    Context "Installation Documentation" {

        It "Should create installation documentation for applications" {
            $documentation = New-InstallationDocumentation -Applications $script:MockUnmanagedApps

            $documentation | Should -Not -BeNullOrEmpty
            $documentation.Count | Should -Be 2
            $documentation[0].Name | Should -Be "TestApp1"
            $documentation[0].InstallationMethods | Should -Not -BeNullOrEmpty
            $documentation[0].DownloadSources | Should -Not -BeNullOrEmpty
            $documentation[0].ManualSteps | Should -Not -BeNullOrEmpty
        }

        It "Should handle Microsoft applications specially" {
            $microsoftApp = @{
                Name = "Microsoft Office"
                Version = "2021"
                Publisher = "Microsoft Corporation"
                Source = "manual"
                Priority = "high"
                Category = "productivity"
            }

            $documentation = New-InstallationDocumentation -Applications @($microsoftApp)

            $documentation[0].InstallationMethods | Should -Contain "Windows Store"
            $documentation[0].InstallationMethods | Should -Contain "Microsoft Store"
            $documentation[0].DownloadSources | Should -Contain "https://www.microsoft.com"
        }

        It "Should save installation documentation in JSON format" {
            $testPath = Join-Path $TestDrive "test-docs.json"
            $documentation = New-InstallationDocumentation -Applications $script:MockUnmanagedApps

            Save-InstallationDocumentation -Documentation $documentation -Path $testPath -Format "JSON"

            $testPath | Should -Exist
            $content = Get-Content $testPath | ConvertFrom-Json
            $content.Count | Should -Be 2
            $content[0].Name | Should -Be "TestApp1"
        }

        It "Should save installation documentation in CSV format" {
            $testPath = Join-Path $TestDrive "test-docs.csv"
            $documentation = New-InstallationDocumentation -Applications $script:MockUnmanagedApps

            Save-InstallationDocumentation -Documentation $documentation -Path $testPath -Format "CSV"

            $testPath | Should -Exist
            $content = Import-Csv $testPath
            $content.Count | Should -Be 2
            $content[0].Name | Should -Be "TestApp1"
        }

        It "Should support WhatIf mode for documentation" {
            $documentation = New-InstallationDocumentation -Applications $script:MockUnmanagedApps -WhatIf

            $documentation | Should -Not -BeNull
            $documentation.Count | Should -Be 0
        }
    }

    Context "User-Editable Application Lists" {

        It "Should create user-editable application lists" {
            New-UserEditableApplicationLists -OutputPath $TestApplicationDiscoveryPath -Format "JSON"

            $appsPath = Join-Path $TestApplicationDiscoveryPath "user-editable-apps.json"
            $gamesPath = Join-Path $TestApplicationDiscoveryPath "user-editable-games.json"
            $instructionsPath = Join-Path $TestApplicationDiscoveryPath "user-lists-instructions.txt"

            $appsPath | Should -Exist
            $gamesPath | Should -Exist
            $instructionsPath | Should -Exist

            # Verify content structure
            $appsContent = Get-Content $appsPath | ConvertFrom-Json
            $appsContent.metadata | Should -Not -BeNullOrEmpty
            $appsContent.categories | Should -Not -BeNullOrEmpty
            $appsContent.categories.essential | Should -Not -BeNullOrEmpty
            $appsContent.categories.productivity | Should -Not -BeNullOrEmpty
            $appsContent.categories.development | Should -Not -BeNullOrEmpty
            $appsContent.categories.gaming | Should -Not -BeNullOrEmpty
            $appsContent.categories.optional | Should -Not -BeNullOrEmpty

            $gamesContent = Get-Content $gamesPath | ConvertFrom-Json
            $gamesContent.metadata | Should -Not -BeNullOrEmpty
            $gamesContent.platforms | Should -Not -BeNullOrEmpty
            $gamesContent.platforms.steam | Should -Not -BeNullOrEmpty
            $gamesContent.platforms.epic | Should -Not -BeNullOrEmpty
            $gamesContent.platforms.gog | Should -Not -BeNullOrEmpty
            $gamesContent.platforms.xbox | Should -Not -BeNullOrEmpty
            $gamesContent.platforms.other | Should -Not -BeNullOrEmpty
        }

        It "Should create user-editable lists in CSV format" {
            New-UserEditableApplicationLists -OutputPath $TestApplicationDiscoveryPath -Format "CSV"

            $appsPath = Join-Path $TestApplicationDiscoveryPath "user-editable-apps.csv"
            $gamesPath = Join-Path $TestApplicationDiscoveryPath "user-editable-games.csv"

            $appsPath | Should -Exist
            $gamesPath | Should -Exist
        }

        It "Should create user-editable lists in YAML format" {
            New-UserEditableApplicationLists -OutputPath $TestApplicationDiscoveryPath -Format "YAML"

            $appsPath = Join-Path $TestApplicationDiscoveryPath "user-editable-apps.yaml"
            $gamesPath = Join-Path $TestApplicationDiscoveryPath "user-editable-games.yaml"

            $appsPath | Should -Exist
            $gamesPath | Should -Exist
        }

        It "Should support WhatIf mode for user lists" {
            New-UserEditableApplicationLists -OutputPath $TestApplicationDiscoveryPath -Format "JSON" -WhatIf

            $appsPath = Join-Path $TestApplicationDiscoveryPath "user-editable-apps.json"
            $gamesPath = Join-Path $TestApplicationDiscoveryPath "user-editable-games.json"

            $appsPath | Should -Not -Exist
            $gamesPath | Should -Not -Exist
        }
    }

    Context "Application Decision Workflows" {

        It "Should initialize application decision workflows" {
            Initialize-ApplicationDecisionWorkflows -OutputPath $TestApplicationDiscoveryPath

            $workflowPath = Join-Path $TestApplicationDiscoveryPath "application-decision-workflows.json"
            $workflowPath | Should -Exist

            $content = Get-Content $workflowPath | ConvertFrom-Json
            $content.metadata | Should -Not -BeNullOrEmpty
            $content.workflows | Should -Not -BeNullOrEmpty
            $content.workflows.install_decisions | Should -Not -BeNullOrEmpty
            $content.workflows.uninstall_decisions | Should -Not -BeNullOrEmpty

            # Verify workflow rules
            $content.workflows.install_decisions.rules.Count | Should -BeGreaterThan 0
            $content.workflows.uninstall_decisions.rules.Count | Should -BeGreaterThan 0
        }

        It "Should support WhatIf mode for workflow initialization" {
            Initialize-ApplicationDecisionWorkflows -OutputPath $TestApplicationDiscoveryPath -WhatIf

            $workflowPath = Join-Path $TestApplicationDiscoveryPath "application-decision-workflows.json"
            $workflowPath | Should -Not -Exist
        }
    }

    Context "Application Discovery Status" {

        It "Should check application discovery status correctly" {
            # Create some test files
            New-Item -Path (Join-Path $TestApplicationDiscoveryPath "unmanaged-applications.json") -ItemType File -Force | Out-Null
            New-Item -Path (Join-Path $TestApplicationDiscoveryPath "installation-documentation.json") -ItemType File -Force | Out-Null
            New-Item -Path (Join-Path $TestApplicationDiscoveryPath "user-editable-apps.json") -ItemType File -Force | Out-Null
            New-Item -Path (Join-Path $TestApplicationDiscoveryPath "user-editable-games.json") -ItemType File -Force | Out-Null
            New-Item -Path (Join-Path $TestApplicationDiscoveryPath "application-decision-workflows.json") -ItemType File -Force | Out-Null

            $status = Test-ApplicationDiscoveryStatus -OutputPath $TestApplicationDiscoveryPath

            $status.ApplicationDiscoveryConfigured | Should -Be $true
            $status.UnmanagedAppsDiscovered | Should -Be $true
            $status.InstallationDocumented | Should -Be $true
            $status.UserListsCreated | Should -Be $true
            $status.WorkflowsInitialized | Should -Be $true
        }

        It "Should handle missing application discovery directory" {
            $nonExistentPath = Join-Path $TestDrive "NonExistent"

            $status = Test-ApplicationDiscoveryStatus -OutputPath $nonExistentPath

            $status.ApplicationDiscoveryConfigured | Should -Be $false
            $status.UnmanagedAppsDiscovered | Should -Be $false
            $status.InstallationDocumented | Should -Be $false
            $status.UserListsCreated | Should -Be $false
            $status.WorkflowsInitialized | Should -Be $false
        }
    }

    Context "Setup-ApplicationDiscovery Integration" {

        It "Should run complete application discovery setup" {
            Mock Invoke-UnmanagedApplicationDiscovery { return $script:MockUnmanagedApps }

            $result = Setup-ApplicationDiscovery -DiscoveryMode "Quick" -OutputFormat "JSON" -CreateUserLists -DocumentInstallation

            $result | Should -Be $true

            # Verify files were created
            $unmanagedPath = Join-Path $TestApplicationDiscoveryPath "unmanaged-applications.json"
            $docsPath = Join-Path $TestApplicationDiscoveryPath "installation-documentation.json"
            $appsPath = Join-Path $TestApplicationDiscoveryPath "user-editable-apps.json"
            $gamesPath = Join-Path $TestApplicationDiscoveryPath "user-editable-games.json"
            $workflowPath = Join-Path $TestApplicationDiscoveryPath "application-decision-workflows.json"

            $unmanagedPath | Should -Exist
            $docsPath | Should -Exist
            $appsPath | Should -Exist
            $gamesPath | Should -Exist
            $workflowPath | Should -Exist
        }

        It "Should support WhatIf mode for complete setup" {
            Mock Invoke-UnmanagedApplicationDiscovery { return $script:MockUnmanagedApps }

            $result = Setup-ApplicationDiscovery -DiscoveryMode "Quick" -OutputFormat "JSON" -CreateUserLists -DocumentInstallation -WhatIf

            $result | Should -Be $true

            # Verify files were NOT created
            $unmanagedPath = Join-Path $TestApplicationDiscoveryPath "unmanaged-applications.json"
            $docsPath = Join-Path $TestApplicationDiscoveryPath "installation-documentation.json"

            $unmanagedPath | Should -Not -Exist
            $docsPath | Should -Not -Exist
        }
    }
}

Describe "Configuration Selection Tests" {

    Context "Available Setup Scripts Discovery" {

        It "Should discover available setup scripts" {
            # Mock setup scripts directory
            $mockSetupPath = Join-Path $TestDrive "MockSetup"
            New-Item -ItemType Directory -Path $mockSetupPath -Force | Out-Null

            # Create mock script files
            $script1 = Join-Path $mockSetupPath "setup-test1.ps1"
            $script2 = Join-Path $mockSetupPath "setup-test2.ps1"

            "# Test script 1 - Configure test feature 1" | Out-File $script1
            "# Test script 2 - Configure test feature 2" | Out-File $script2

            $scripts = Get-AvailableSetupScripts -SetupPath $mockSetupPath

            $scripts.Count | Should -Be 2
            $scripts[0].Name | Should -Be "setup-test1"
            $scripts[1].Name | Should -Be "setup-test2"
            $scripts[0].Description | Should -Match "Test script 1"
            $scripts[1].Description | Should -Match "Test script 2"
        }

        It "Should categorize setup scripts correctly" {
            $category1 = Get-SetupScriptCategory -ScriptName "Initialize-WSL"
            $category2 = Get-SetupScriptCategory -ScriptName "setup-defender"
            $category3 = Get-SetupScriptCategory -ScriptName "setup-steam-games"
            $category4 = Get-SetupScriptCategory -ScriptName "setup-unknown"

            $category1 | Should -Be "Development"
            $category2 | Should -Be "Security"
            $category3 | Should -Be "Gaming"
            $category4 | Should -Be "Unknown"
        }

        It "Should handle empty setup scripts directory" {
            $emptyPath = Join-Path $TestDrive "EmptySetup"
            New-Item -ItemType Directory -Path $emptyPath -Force | Out-Null

            $scripts = Get-AvailableSetupScripts -SetupPath $emptyPath

            $scripts.Count | Should -Be 0
        }
    }

    Context "Configuration Profile Management" {

        It "Should create new configuration profile" {
            $profile = New-ConfigurationProfile -ProfileName "TestProfile" -OutputPath $TestConfigurationProfilesPath -AvailableScripts $script:MockSetupScripts

            $profile | Should -Not -BeNullOrEmpty
            $profile.metadata.name | Should -Be "TestProfile"
            $profile.setup_scripts | Should -Not -BeNullOrEmpty
            $profile.categories | Should -Not -BeNullOrEmpty
        }

        It "Should create developer profile with appropriate scripts" {
            $profile = New-ConfigurationProfile -ProfileName "Developer" -OutputPath $TestConfigurationProfilesPath -AvailableScripts $script:MockSetupScripts

            $profile.categories.Development.enabled | Should -Be $true
            $profile.setup_scripts | Should -Contain "Initialize-WSL"
        }

        It "Should create gamer profile with appropriate scripts" {
            $profile = New-ConfigurationProfile -ProfileName "Gamer" -OutputPath $TestConfigurationProfilesPath -AvailableScripts $script:MockSetupScripts

            $profile.categories.Gaming.enabled | Should -Be $true
            $profile.setup_scripts | Should -Contain "setup-steam-games"
        }

        It "Should save and load configuration profile" {
            $profile = New-ConfigurationProfile -ProfileName "TestProfile" -OutputPath $TestConfigurationProfilesPath -AvailableScripts $script:MockSetupScripts

            Save-ConfigurationProfile -Profile $profile -ProfileName "TestProfile" -OutputPath $TestConfigurationProfilesPath

            $profilePath = Join-Path $TestConfigurationProfilesPath "TestProfile-profile.json"
            $profilePath | Should -Exist

            $loadedProfile = Get-ConfigurationProfile -ProfileName "TestProfile" -OutputPath $TestConfigurationProfilesPath
            $loadedProfile.metadata.name | Should -Be "TestProfile"
        }

        It "Should test configuration profile existence" {
            $profile = New-ConfigurationProfile -ProfileName "TestProfile" -OutputPath $TestConfigurationProfilesPath -AvailableScripts $script:MockSetupScripts
            Save-ConfigurationProfile -Profile $profile -ProfileName "TestProfile" -OutputPath $TestConfigurationProfilesPath

            $exists = Test-ConfigurationProfile -ProfileName "TestProfile" -OutputPath $TestConfigurationProfilesPath
            $notExists = Test-ConfigurationProfile -ProfileName "NonExistent" -OutputPath $TestConfigurationProfilesPath

            $exists | Should -Be $true
            $notExists | Should -Be $false
        }
    }

    Context "Script Selection Methods" {

        It "Should handle automatic script selection" {
            Mock Get-SystemInfo {
                return @{
                    HasDevelopmentTools = $true
                    HasGamingPlatforms = $true
                    HasWSL = $true
                    HasGit = $true
                }
            }

            $selectedScripts = Invoke-AutomaticScriptSelection -AvailableScripts $script:MockSetupScripts

            $selectedScripts | Should -Not -BeNullOrEmpty
            $selectedScripts | Should -Contain "Initialize-PackageManagers"
            $selectedScripts | Should -Contain "Initialize-WSL"
            $selectedScripts | Should -Contain "setup-steam-games"
        }

        It "Should handle profile-based script selection" {
            $profile = @{
                setup_scripts = @("Initialize-PackageManagers", "Initialize-WSL")
            }

            $selectedScripts = Get-ProfileScriptSelection -Profile $profile

            $selectedScripts | Should -Not -BeNullOrEmpty
            $selectedScripts.Count | Should -Be 2
            $selectedScripts | Should -Contain "Initialize-PackageManagers"
            $selectedScripts | Should -Contain "Initialize-WSL"
        }

        It "Should support WhatIf mode for script selection" {
            $selectedScripts = Invoke-AutomaticScriptSelection -AvailableScripts $script:MockSetupScripts -WhatIf

            $selectedScripts | Should -Not -BeNull
            $selectedScripts.Count | Should -Be 0
        }
    }

    Context "Setup Execution Plan" {

        It "Should create setup execution plan" {
            $profile = @{
                metadata = @{ name = "TestProfile" }
                setup_scripts = @("Initialize-PackageManagers", "Initialize-WSL", "setup-steam-games")
            }

            $executionPlan = New-SetupExecutionPlan -Profile $profile -AvailableScripts $script:MockSetupScripts

            $executionPlan | Should -Not -BeNullOrEmpty
            $executionPlan.metadata.profile | Should -Be "TestProfile"
            $executionPlan.execution_phases | Should -Not -BeNullOrEmpty
            $executionPlan.execution_phases.phase1_system | Should -Not -BeNullOrEmpty
            $executionPlan.execution_phases.phase2_applications | Should -Not -BeNullOrEmpty
            $executionPlan.execution_phases.phase3_development | Should -Not -BeNullOrEmpty
            $executionPlan.execution_phases.phase4_gaming | Should -Not -BeNullOrEmpty
        }

        It "Should organize scripts by execution phase" {
            $profile = @{
                metadata = @{ name = "TestProfile" }
                setup_scripts = @("Initialize-PackageManagers", "Initialize-WSL", "setup-steam-games")
            }

            $executionPlan = New-SetupExecutionPlan -Profile $profile -AvailableScripts $script:MockSetupScripts

            # Check that scripts are in appropriate phases
            $phase1Scripts = $executionPlan.execution_phases.phase1_system.scripts
            $phase3Scripts = $executionPlan.execution_phases.phase3_development.scripts
            $phase4Scripts = $executionPlan.execution_phases.phase4_gaming.scripts

            $phase1Scripts | Should -Not -BeNullOrEmpty
            $phase3Scripts | Should -Not -BeNullOrEmpty
            $phase4Scripts | Should -Not -BeNullOrEmpty
        }

        It "Should save execution plan" {
            $executionPlan = @{
                metadata = @{ name = "Test Plan" }
                execution_phases = @{}
            }

            $planPath = Join-Path $TestConfigurationProfilesPath "test-plan.json"

            Save-ExecutionPlan -ExecutionPlan $executionPlan -Path $planPath

            $planPath | Should -Exist
            $content = Get-Content $planPath | ConvertFrom-Json
            $content.metadata.name | Should -Be "Test Plan"
        }
    }

    Context "Configuration Selection Status" {

        It "Should check configuration selection status correctly" {
            # Create test profile and execution plan
            $profile = New-ConfigurationProfile -ProfileName "TestProfile" -OutputPath $TestConfigurationProfilesPath -AvailableScripts $script:MockSetupScripts
            Save-ConfigurationProfile -Profile $profile -ProfileName "TestProfile" -OutputPath $TestConfigurationProfilesPath

            $executionPlan = New-SetupExecutionPlan -Profile $profile -AvailableScripts $script:MockSetupScripts
            $planPath = Join-Path $TestConfigurationProfilesPath "TestProfile-execution-plan.json"
            Save-ExecutionPlan -ExecutionPlan $executionPlan -Path $planPath

            $status = Test-ConfigurationSelectionStatus -OutputPath $TestConfigurationProfilesPath -ProfileName "TestProfile"

            $status.ConfigurationSelectionConfigured | Should -Be $true
            $status.ProfileExists | Should -Be $true
            $status.ExecutionPlanExists | Should -Be $true
            $status.ScriptCount | Should -BeGreaterThan 0
        }

        It "Should handle missing configuration selection directory" {
            $nonExistentPath = Join-Path $TestDrive "NonExistent"

            $status = Test-ConfigurationSelectionStatus -OutputPath $nonExistentPath -ProfileName "TestProfile"

            $status.ConfigurationSelectionConfigured | Should -Be $false
            $status.ProfileExists | Should -Be $false
            $status.ExecutionPlanExists | Should -Be $false
        }
    }

    Context "Setup-ConfigurationSelection Integration" {

        It "Should run complete configuration selection setup" {
            Mock Get-AvailableSetupScripts { return $script:MockSetupScripts }

            $result = Setup-ConfigurationSelection -ProfileName "TestProfile" -ConfigurationMode "Profile" -CreateProfile -OutputPath $TestConfigurationProfilesPath

            $result | Should -Be $true

            # Verify files were created
            $profilePath = Join-Path $TestConfigurationProfilesPath "TestProfile-profile.json"
            $planPath = Join-Path $TestConfigurationProfilesPath "TestProfile-execution-plan.json"

            $profilePath | Should -Exist
            $planPath | Should -Exist
        }

        It "Should support WhatIf mode for complete setup" {
            Mock Get-AvailableSetupScripts { return $script:MockSetupScripts }

            $result = Setup-ConfigurationSelection -ProfileName "TestProfile" -ConfigurationMode "Profile" -CreateProfile -OutputPath $TestConfigurationProfilesPath -WhatIf

            $result | Should -Be $true

            # Verify files were NOT created
            $profilePath = Join-Path $TestConfigurationProfilesPath "TestProfile-profile.json"
            $planPath = Join-Path $TestConfigurationProfilesPath "TestProfile-execution-plan.json"

            $profilePath | Should -Not -Exist
            $planPath | Should -Not -Exist
        }
    }
}

Describe "Integration Tests - Application Discovery and Configuration Selection" {

    Context "End-to-End Application Management Workflow" {

        It "Should complete full application discovery and configuration workflow" {
            # Mock dependencies
            Mock Invoke-UnmanagedApplicationDiscovery { return $script:MockUnmanagedApps }
            Mock Get-AvailableSetupScripts { return $script:MockSetupScripts }

            # Step 1: Setup application discovery
            $discoveryResult = Setup-ApplicationDiscovery -DiscoveryMode "Quick" -OutputFormat "JSON" -CreateUserLists -DocumentInstallation
            $discoveryResult | Should -Be $true

            # Step 2: Setup configuration selection
            $configResult = Setup-ConfigurationSelection -ProfileName "TestProfile" -ConfigurationMode "Profile" -CreateProfile -OutputPath $TestConfigurationProfilesPath
            $configResult | Should -Be $true

            # Step 3: Verify complete setup
            $discoveryStatus = Test-ApplicationDiscoveryStatus -OutputPath $TestApplicationDiscoveryPath
            $configStatus = Test-ConfigurationSelectionStatus -OutputPath $TestConfigurationProfilesPath -ProfileName "TestProfile"

            $discoveryStatus.ApplicationDiscoveryConfigured | Should -Be $true
            $discoveryStatus.UnmanagedAppsDiscovered | Should -Be $true
            $discoveryStatus.UserListsCreated | Should -Be $true
            $discoveryStatus.WorkflowsInitialized | Should -Be $true

            $configStatus.ConfigurationSelectionConfigured | Should -Be $true
            $configStatus.ProfileExists | Should -Be $true
            $configStatus.ExecutionPlanExists | Should -Be $true
        }

        It "Should handle initialization testing correctly" {
            # Mock module initialization
            Mock Get-WindowsMelodyRecovery { return $script:MockConfig }

            # Test that both components can initialize with module configuration
            $discoveryResult = Setup-ApplicationDiscovery -DiscoveryMode "Manual" -OutputFormat "JSON"
            $configResult = Setup-ConfigurationSelection -ProfileName "Default" -ConfigurationMode "Automatic"

            $discoveryResult | Should -Be $true
            $configResult | Should -Be $true
        }
    }

    Context "Error Handling and Edge Cases" {

        It "Should handle module not initialized gracefully" {
            Mock Get-WindowsMelodyRecovery { throw "Module not initialized" }

            # Should fall back to defaults and continue
            $result = Setup-ApplicationDiscovery -DiscoveryMode "Quick" -OutputFormat "JSON"
            $result | Should -Be $true
        }

        It "Should handle missing setup scripts directory" {
            $nonExistentPath = Join-Path $TestDrive "NonExistentSetup"

            $scripts = Get-AvailableSetupScripts -SetupPath $nonExistentPath
            $scripts.Count | Should -Be 0
        }

        It "Should handle corrupt configuration files" {
            # Create corrupt profile file
            $corruptPath = Join-Path $TestConfigurationProfilesPath "Corrupt-profile.json"
            "{ invalid json" | Out-File $corruptPath

            $profile = Get-ConfigurationProfile -ProfileName "Corrupt" -OutputPath $TestConfigurationProfilesPath
            $profile.Count | Should -Be 0
        }
    }
}

AfterAll {
    # Clean up test environment
    if (Test-Path $TestDrive) {
        Remove-Item -Path $TestDrive -Recurse -Force -ErrorAction SilentlyContinue
    }
}






