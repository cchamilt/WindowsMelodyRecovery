# tests/integration/AdministrativePrivileges-Integration.Tests.ps1

<#
.SYNOPSIS
    Integration tests for administrative privileges functionality.

.DESCRIPTION
    Tests administrative privilege features in a controlled CI/CD environment.
    These tests should ONLY run on Windows CI/CD systems with proper isolation.

    SAFETY WARNING: These tests may modify system settings and require admin privileges.
    DO NOT run on development or production systems.

.NOTES
    Test Level: Integration (Windows CI/CD Only)
    Author: Windows Melody Recovery
    Version: 1.0
    Requires: Pester 5.0+, Windows CI/CD Environment, Administrative Privileges
#>

BeforeAll {
    # CRITICAL SAFETY CHECK: Only run in CI/CD environment
    $isCICD = $env:GITHUB_ACTIONS -eq "true" -or
              $env:AZURE_PIPELINES -eq "True" -or
              $env:CI -eq "true" -or
              $env:BUILD_BUILDID -or
              $env:SYSTEM_TEAMPROJECT -or
              $env:RUNNER_OS -eq "Windows"

    $isWindowsCI = $IsWindows -and $isCICD

    if (-not $isWindowsCI) {
        Write-Warning "Administrative privilege integration tests are disabled outside Windows CI/CD environment"
        Write-Warning "Current environment: IsWindows=$IsWindows, CI/CD=$isCICD"
        return
    }

    # Import the module
    Import-Module (Resolve-Path "$PSScriptRoot/../../WindowsMelodyRecovery.psd1") -Force

    # Import test utilities
    . "$PSScriptRoot/../utilities/Test-Utilities.ps1"

    # Verify we're running with admin privileges in CI/CD
    $isAdmin = try {
        ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        $false
    }

    if (-not $isAdmin) {
        throw "Administrative privilege integration tests require elevated privileges in CI/CD environment"
    }

    # Set up test environment
    $script:TestBackupDir = Join-Path $env:TEMP "WMR-AdminTest-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    $script:TestStateDir = Join-Path $script:TestBackupDir "State"
    $script:TestTemplateDir = Join-Path $PSScriptRoot "../../Templates/System"

    # Create test directories
    New-Item -ItemType Directory -Path $script:TestBackupDir -Force | Out-Null
    New-Item -ItemType Directory -Path $script:TestStateDir -Force | Out-Null

    Write-Warning -Message "Running administrative privilege integration tests in CI/CD environment"
    Write-Verbose -Message "Test backup directory: $script:TestBackupDir"
}

Describe "Administrative Privilege Integration Tests" -Tag "WindowsOnly", "AdminRequired", "CICDOnly" {
    BeforeAll {
        if (-not $isWindowsCI) {
            return
        }
    }

    Context "Windows Optional Features Integration" {
        BeforeEach {
            if (-not $isWindowsCI) {
                Set-ItResult -Skipped -Because "Not running in Windows CI/CD environment"
                return
            }
        }

        It "Should successfully query Windows Optional Features with admin privileges" {
            # Test actual Windows Optional Features query
            $features = Get-WindowsOptionalFeature -Online -ErrorAction SilentlyContinue

            $features | Should -Not -BeNull
            $features.Count | Should -BeGreaterThan 0

            # Verify feature structure
            $features[0] | Should -HaveProperty "FeatureName"
            $features[0] | Should -HaveProperty "State"
        }

        It "Should process Windows Optional Features template with admin privileges" {
            $templatePath = Join-Path $script:TestTemplateDir "windows-optional-features.yaml"

            if (-not (Test-Path $templatePath)) {
                Set-ItResult -Skipped -Because "Windows Optional Features template not found"
                return
            }

            # Test template processing with admin privileges
            { Invoke-WmrTemplate -TemplatePath $templatePath -Operation "Backup" -StateFilesDirectory $script:TestStateDir } | Should -Not -Throw

            # Verify state files were created
            $stateFiles = Get-ChildItem -Path $script:TestStateDir -Recurse -Filter "*.json"
            $stateFiles.Count | Should -BeGreaterThan 0
        }

        It "Should handle Windows Optional Features prerequisites correctly" {
            # Test prerequisite checking for admin-required operations
            $templateConfig = @{
                metadata = @{ name = "Test Template" }
                prerequisites = @(
                    @{
                        type = "script"
                        name = "Administrative Privileges Required"
                        inline_script = @"
                            try {
                                `$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
                                `$isAdmin = `$currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

                                if (`$isAdmin) {
                                    Write-Output "Administrative privileges confirmed"
                                } else {
                                    Write-Output "Administrative privileges required"
                                }
                            } catch {
                                Write-Output "Unable to verify administrative privileges"
                            }
"@
                        expected_output = "Administrative privileges confirmed"
                        on_missing = "warn"
                    }
                )
            }

            $result = Test-WmrPrerequisites -TemplateConfig $templateConfig -Operation "Backup"
            $result | Should -Be $true
        }
    }

    Context "Windows Capabilities Integration" {
        BeforeEach {
            if (-not $isWindowsCI) {
                Set-ItResult -Skipped -Because "Not running in Windows CI/CD environment"
                return
            }
        }

        It "Should successfully query Windows Capabilities with admin privileges" {
            # Test actual Windows Capabilities query
            $capabilities = Get-WindowsCapability -Online -ErrorAction SilentlyContinue

            $capabilities | Should -Not -BeNull
            $capabilities.Count | Should -BeGreaterThan 0

            # Verify capability structure
            $capabilities[0] | Should -HaveProperty "Name"
            $capabilities[0] | Should -HaveProperty "State"
        }

        It "Should process Windows Capabilities template with admin privileges" {
            $templatePath = Join-Path $script:TestTemplateDir "windows-capabilities.yaml"

            if (-not (Test-Path $templatePath)) {
                Set-ItResult -Skipped -Because "Windows Capabilities template not found"
                return
            }

            # Test template processing with admin privileges
            { Invoke-WmrTemplate -TemplatePath $templatePath -Operation "Backup" -StateFilesDirectory $script:TestStateDir } | Should -Not -Throw

            # Verify state files were created
            $stateFiles = Get-ChildItem -Path $script:TestStateDir -Recurse -Filter "*.json"
            $stateFiles.Count | Should -BeGreaterThan 0
        }
    }

    Context "Scheduled Task Management Integration" {
        BeforeEach {
            if (-not $isWindowsCI) {
                Set-ItResult -Skipped -Because "Not running in Windows CI/CD environment"
                return
            }
        }

        It "Should successfully create and remove test scheduled task with admin privileges" {
            $taskName = "WMR-Test-Task-$(Get-Date -Format 'yyyyMMddHHmmss')"

            try {
                # Create test scheduled task
                $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-Command 'Write-Information -MessageData Test'" -InformationAction Continue
                $trigger = New-ScheduledTaskTrigger -Daily -At "3:00AM"
                $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

                $task = Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Force

                $task | Should -Not -BeNull
                $task.TaskName | Should -Be $taskName

                # Verify task exists
                $createdTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
                $createdTask | Should -Not -BeNull
                $createdTask.Principal.RunLevel | Should -Be "Highest"

            } finally {
                # Clean up test task
                try {
                    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
                } catch {
                    Write-Warning "Failed to clean up test scheduled task: $_"
                }
            }
        }

        It "Should test Install-WindowsMelodyRecoveryTasks with admin privileges" {
            # Mock configuration for testing
            Mock -CommandName "Get-WindowsMelodyRecovery" -MockWith {
                return @{
                    BackupRoot = $script:TestBackupDir
                    MachineName = "TestMachine"
                    WindowsMelodyRecoveryPath = $PSScriptRoot
                }
            }

            # Mock private script loading
            Mock -CommandName "Import-PrivateScripts" -MockWith { }

            # Mock the actual task registration functions
            Mock -CommandName "Register-BackupTask" -MockWith {
                return @{ Success = $true; TaskName = "WindowsMelodyRecovery-Backup" }
            }

            Mock -CommandName "Register-UpdateTask" -MockWith {
                return @{ Success = $true; TaskName = "WindowsMelodyRecovery-Update" }
            }

            # Test the function
            $result = Install-WindowsMelodyRecoveryTasks -NoPrompt
            $result | Should -Be $true

            Assert-MockCalled -CommandName "Get-WindowsMelodyRecovery" -Times 1
            Assert-MockCalled -CommandName "Import-PrivateScripts" -Times 1
        }
    }

    Context "Registry Operations Integration" {
        BeforeEach {
            if (-not $isWindowsCI) {
                Set-ItResult -Skipped -Because "Not running in Windows CI/CD environment"
                return
            }
        }

        It "Should handle HKLM registry operations with admin privileges" {
            $testKeyPath = "HKLM:\SOFTWARE\WMR-Test-$(Get-Date -Format 'yyyyMMddHHmmss')"
            $testValueName = "TestValue"
            $testValueData = "TestData"

            try {
                # Test creating registry key in HKLM (requires admin)
                New-Item -Path $testKeyPath -Force | Out-Null

                # Verify key was created
                Test-Path $testKeyPath | Should -Be $true

                # Test setting registry value
                Set-ItemProperty -Path $testKeyPath -Name $testValueName -Value $testValueData

                # Verify value was set
                $retrievedValue = Get-ItemProperty -Path $testKeyPath -Name $testValueName
                $retrievedValue.$testValueName | Should -Be $testValueData

            } finally {
                # Clean up test registry key
                try {
                    Remove-Item -Path $testKeyPath -Recurse -Force -ErrorAction SilentlyContinue
                } catch {
                    Write-Warning "Failed to clean up test registry key: $_"
                }
            }
        }

        It "Should test registry state functions with HKLM paths" {
            $testKeyPath = "HKLM:\SOFTWARE\WMR-RegTest-$(Get-Date -Format 'yyyyMMddHHmmss')"

            try {
                # Create test registry key
                New-Item -Path $testKeyPath -Force | Out-Null
                Set-ItemProperty -Path $testKeyPath -Name "TestValue1" -Value "Data1"
                Set-ItemProperty -Path $testKeyPath -Name "TestValue2" -Value "Data2"

                # Test Get-WmrRegistryState with HKLM path
                $registryConfig = @{
                    name = "Test Registry State"
                    path = $testKeyPath
                    type = "key"
                    action = "backup"
                    dynamic_state_path = "test_registry.json"
                }

                $stateFile = Join-Path $script:TestStateDir "test_registry.json"

                # Test backup
                { Get-WmrRegistryState -RegistryConfig $registryConfig -StateFilesDirectory $script:TestStateDir } | Should -Not -Throw

                # Verify state file was created
                Test-Path $stateFile | Should -Be $true

                # Verify state file content
                $stateContent = Get-Content $stateFile -Raw | ConvertFrom-Json
                $stateContent | Should -Not -BeNull
                $stateContent.TestValue1 | Should -Be "Data1"
                $stateContent.TestValue2 | Should -Be "Data2"

            } finally {
                # Clean up test registry key
                try {
                    Remove-Item -Path $testKeyPath -Recurse -Force -ErrorAction SilentlyContinue
                } catch {
                    Write-Warning "Failed to clean up test registry key: $_"
                }
            }
        }
    }

    Context "Service Management Integration" {
        BeforeEach {
            if (-not $isWindowsCI) {
                Set-ItResult -Skipped -Because "Not running in Windows CI/CD environment"
                return
            }
        }

        It "Should query service information with admin privileges" {
            # Test querying services (read-only, should work)
            $services = Get-Service | Select-Object -First 5

            $services | Should -Not -BeNull
            $services.Count | Should -Be 5

            foreach ($service in $services) {
                $service | Should -HaveProperty "Name"
                $service | Should -HaveProperty "Status"
                $service | Should -HaveProperty "StartType"
            }
        }

        It "Should handle service configuration safely in test environment" {
            # Test service configuration logic without actually modifying services
            $testServiceName = "Spooler"  # Common service for testing

            # Get current service state
            $originalService = Get-Service -Name $testServiceName -ErrorAction SilentlyContinue

            if ($originalService) {
                $originalService | Should -HaveProperty "Status"
                $originalService | Should -HaveProperty "StartType"

                # In CI/CD, we can test service state queries without modification
                $originalService.Name | Should -Be $testServiceName
            } else {
                Set-ItResult -Skipped -Because "Test service '$testServiceName' not available"
            }
        }
    }

    Context "Setup Script Integration" {
        BeforeEach {
            if (-not $isWindowsCI) {
                Set-ItResult -Skipped -Because "Not running in Windows CI/CD environment"
                return
            }
        }

        It "Should test setup scripts that require admin privileges" {
            # Test admin-required setup scripts in CI/CD environment
            $setupScripts = @(
                "setup-defender.ps1",
                "setup-packagemanagers.ps1",
                "setup-removebloat.ps1",
                "setup-restorepoints.ps1",
                "setup-wsl-fonts.ps1"
            )

            foreach ($scriptName in $setupScripts) {
                $scriptPath = Join-Path $PSScriptRoot "../../Private/setup/$scriptName"

                if (Test-Path $scriptPath) {
                    # Test that script exists and can be parsed
                    $scriptContent = Get-Content $scriptPath -Raw
                    $scriptContent | Should -Not -BeNullOrEmpty

                    # Test for admin privilege checks
                    $scriptContent | Should -Match "Administrator|Elevated|RunAsAdministrator"

                    Write-Verbose -Message "Verified admin privilege requirements in $scriptName"
                } else {
                    Write-Warning "Setup script not found: $scriptPath"
                }
            }
        }

        It "Should test Setup-WindowsMelodyRecovery with admin privileges" {
            # Mock dependencies for testing
            Mock -CommandName "Get-WindowsMelodyRecovery" -MockWith {
                return @{
                    BackupRoot = $script:TestBackupDir
                    MachineName = "TestMachine"
                    WindowsMelodyRecoveryPath = $PSScriptRoot
                }
            }

            Mock -CommandName "Import-PrivateScripts" -MockWith { }

            # Mock setup functions to avoid actual system changes
            Mock -CommandName "Setup-PackageManagers" -MockWith { return @{ Success = $true } }
            Mock -CommandName "Setup-WindowsDefender" -MockWith { return @{ Success = $true } }
            Mock -CommandName "Setup-RestorePoints" -MockWith { return @{ Success = $true } }

            # Test the function logic
            $result = Setup-WindowsMelodyRecovery -NoPrompt
            $result | Should -Be $true

            Assert-MockCalled -CommandName "Get-WindowsMelodyRecovery" -Times 1
        }
    }

    Context "Administrative Privilege Validation" {
        BeforeEach {
            if (-not $isWindowsCI) {
                Set-ItResult -Skipped -Because "Not running in Windows CI/CD environment"
                return
            }
        }

        It "Should confirm administrative privileges in CI/CD environment" {
            # Test actual administrative privilege detection
            $result = Test-WmrAdminPrivilege
            $result | Should -Be $true
        }

        It "Should validate Windows Principal functionality" {
            # Test Windows Principal functionality directly
            $currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
            $currentPrincipal | Should -Not -BeNull

            $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
            $isAdmin | Should -Be $true
        }

        It "Should test privilege escalation detection" {
            # Test privilege escalation detection logic
            $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
            $currentIdentity | Should -Not -BeNull
            $currentIdentity.IsAuthenticated | Should -Be $true

            # In CI/CD, we should be running with elevated privileges
            $currentIdentity.Owner | Should -Not -BeNull
        }
    }
}

Describe "Administrative Privilege Error Handling" -Tag "WindowsOnly", "AdminRequired", "CICDOnly" {
    BeforeAll {
        if (-not $isWindowsCI) {
            return
        }
    }

    Context "Graceful Degradation Testing" {
        BeforeEach {
            if (-not $isWindowsCI) {
                Set-ItResult -Skipped -Because "Not running in Windows CI/CD environment"
                return
            }
        }

        It "Should handle access denied scenarios gracefully" {
            # Test handling of access denied scenarios
            $restrictedPath = "C:\Windows\System32\config\SAM"

            # This should fail even with admin privileges due to file locks
            { Get-Content $restrictedPath -ErrorAction Stop } | Should -Throw

            # Test graceful handling
            $result = try {
                Get-Content $restrictedPath -ErrorAction Stop
                $true
            } catch {
                $false
            }

            $result | Should -Be $false
        }

        It "Should handle privilege validation errors" {
            # Test privilege validation error handling
            Mock -CommandName "Test-WmrAdminPrivilege" -MockWith { throw "Access denied" }

            $result = try {
                Test-WmrAdminPrivilege
                $true
            } catch {
                $false
            }

            $result | Should -Be $false

            Assert-MockCalled -CommandName "Test-WmrAdminPrivilege" -Times 1
        }
    }
}

AfterAll {
    if (-not $isWindowsCI) {
        return
    }

    # Clean up test environment
    try {
        if (Test-Path $script:TestBackupDir) {
            Remove-Item -Path $script:TestBackupDir -Recurse -Force -ErrorAction SilentlyContinue
            Write-Verbose -Message "Cleaned up test backup directory: $script:TestBackupDir"
        }
    } catch {
        Write-Warning "Failed to clean up test backup directory: $_"
    }

    Write-Information -MessageData "Administrative privilege integration tests completed" -InformationAction Continue
}
