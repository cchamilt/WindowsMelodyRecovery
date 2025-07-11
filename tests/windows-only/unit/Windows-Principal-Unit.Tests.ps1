# Windows-Only Unit Tests for Windows Principal Functionality
# These tests MUST run on Windows CI/CD systems only

# Skip all tests if not on Windows
if (-not $IsWindows) {
    Write-Warning "Windows-only tests skipped on non-Windows platform"
    return
}

# Skip if not in CI/CD environment (safety check)
if (-not $env:CI -and -not $env:GITHUB_ACTIONS) {
    Write-Warning "Windows-only tests skipped outside CI/CD environment for safety"
    return
}

BeforeAll {
    # Import the module
    Import-Module (Resolve-Path "$PSScriptRoot/../../../WindowsMelodyRecovery.psd1") -Force

    # Set up test environment
    $script:TestTempDir = Join-Path $env:TEMP "WMR-WindowsPrincipal-Tests"
    if (Test-Path $script:TestTempDir) {
        Remove-Item $script:TestTempDir -Recurse -Force
    }
    New-Item -Path $script:TestTempDir -ItemType Directory -Force | Out-Null
}

AfterAll {
    # Clean up test environment
    if (Test-Path $script:TestTempDir) {
        Remove-Item $script:TestTempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "Windows Principal Unit Tests" -Tag "Windows", "Unit", "Principal" {

    Context "Administrative Privilege Detection" {
        It "Should detect current user's administrative status" {
            $result = Test-WmrAdminPrivilege
            $result | Should -BeOfType [bool]
        }

        It "Should return consistent results across multiple calls" {
            $result1 = Test-WmrAdminPrivilege
            $result2 = Test-WmrAdminPrivilege
            $result1 | Should -Be $result2
        }

        It "Should match PowerShell's built-in principal check" {
            $wmrResult = Test-WmrAdminPrivilege
            $builtinResult = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
            $wmrResult | Should -Be $builtinResult
        }
    }

    Context "Privilege Requirements Analysis" {
        It "Should analyze template privilege requirements correctly" {
            $template = @{
                metadata = @{
                    name = "test-template"
                    version = "1.0"
                }
                registry = @(
                    @{
                        path = "HKLM:\SOFTWARE\Test"
                        values = @()
                    }
                )
            }

            $requirements = Get-WmrPrivilegeRequirements -Template $template
            $requirements | Should -Not -BeNullOrEmpty
            $requirements.RequiresAdmin | Should -BeOfType [bool]
            $requirements.RequiresElevation | Should -BeOfType [bool]
        }

        It "Should identify admin requirements for HKLM registry operations" {
            $template = @{
                metadata = @{ name = "hklm-test" }
                registry = @(
                    @{ path = "HKLM:\SOFTWARE\Test" }
                )
            }

            $requirements = Get-WmrPrivilegeRequirements -Template $template
            $requirements.RequiresAdmin | Should -Be $true
        }

        It "Should not require admin for HKCU registry operations" {
            $template = @{
                metadata = @{ name = "hkcu-test" }
                registry = @(
                    @{ path = "HKCU:\SOFTWARE\Test" }
                )
            }

            $requirements = Get-WmrPrivilegeRequirements -Template $template
            $requirements.RequiresAdmin | Should -Be $false
        }

        It "Should identify Windows features as requiring admin" {
            $template = @{
                metadata = @{ name = "windows-features-test" }
                windows_features = @(
                    @{ name = "IIS-WebServerRole" }
                )
            }

            $requirements = Get-WmrPrivilegeRequirements -Template $template
            $requirements.RequiresAdmin | Should -Be $true
        }
    }

    Context "Safe Admin Operation Execution" {
        It "Should execute main operation when privileges are sufficient" {
            $mainCalled = $false
            $fallbackCalled = $false

            $mainOperation = { $script:mainCalled = $true; return "main-result" }
            $fallbackOperation = { $script:fallbackCalled = $true; return "fallback-result" }

            $result = Invoke-WmrSafeAdminOperation -MainOperation $mainOperation -FallbackOperation $fallbackOperation -OperationType "User"

            $result | Should -Be "main-result"
            $mainCalled | Should -Be $true
            $fallbackCalled | Should -Be $false
        }

        It "Should execute fallback when admin required but not available" {
            # This test only runs if current user is NOT admin
            if (-not (Test-WmrAdminPrivilege)) {
                $mainCalled = $false
                $fallbackCalled = $false

                $mainOperation = { $script:mainCalled = $true; return "main-result" }
                $fallbackOperation = { $script:fallbackCalled = $true; return "fallback-result" }

                $result = Invoke-WmrSafeAdminOperation -MainOperation $mainOperation -FallbackOperation $fallbackOperation -OperationType "Admin"

                $result | Should -Be "fallback-result"
                $mainCalled | Should -Be $false
                $fallbackCalled | Should -Be $true
            } else {
                Set-ItResult -Skipped -Because "Current user has admin privileges"
            }
        }

        It "Should throw when admin required, not available, and no fallback" {
            # This test only runs if current user is NOT admin
            if (-not (Test-WmrAdminPrivilege)) {
                $mainOperation = { return "main-result" }

                { Invoke-WmrSafeAdminOperation -MainOperation $mainOperation -OperationType "Admin" } | Should -Throw "*Administrative privileges required*"
            } else {
                Set-ItResult -Skipped -Because "Current user has admin privileges"
            }
        }
    }

    Context "Elevation Handling" {
        It "Should execute directly when already elevated" {
            if (Test-WmrAdminPrivilege) {
                $executed = $false
                $scriptBlock = { $script:executed = $true; return "elevated-result" }

                $result = Invoke-WmrWithElevation -ScriptBlock $scriptBlock

                $result | Should -Be "elevated-result"
                $executed | Should -Be $true
            } else {
                Set-ItResult -Skipped -Because "Current user does not have admin privileges"
            }
        }

        It "Should handle WhatIf parameter correctly" {
            $executed = $false
            $scriptBlock = { $script:executed = $true; return "result" }

            $result = Invoke-WmrWithElevation -ScriptBlock $scriptBlock -WhatIf

            $executed | Should -Be $false
            $result | Should -BeNullOrEmpty
        }

        It "Should throw when elevation needed but NoPrompt specified" {
            if (-not (Test-WmrAdminPrivilege)) {
                $scriptBlock = { return "result" }

                { Invoke-WmrWithElevation -ScriptBlock $scriptBlock -NoPrompt } | Should -Throw "*Elevation required*"
            } else {
                Set-ItResult -Skipped -Because "Current user already has admin privileges"
            }
        }
    }

    Context "Windows Registry Access" {
        It "Should validate registry paths correctly" {
            Test-WmrRegistryPath -Path "HKLM:\SOFTWARE\Test" | Should -Be $true
            Test-WmrRegistryPath -Path "HKCU:\SOFTWARE\Test" | Should -Be $true
            Test-WmrRegistryPath -Path "HKCR:\Test" | Should -Be $true
            Test-WmrRegistryPath -Path "HKU:\.DEFAULT\Test" | Should -Be $true
            Test-WmrRegistryPath -Path "HKCC:\Test" | Should -Be $true
            Test-WmrRegistryPath -Path "C:\Invalid\Path" | Should -Be $false
        }

        It "Should handle registry state operations" {
            $registryConfig = @{
                path = "HKCU:\SOFTWARE\WMR-Test"
                values = @{
                    "TestValue" = "TestData"
                }
            }

            $stateDir = Join-Path $script:TestTempDir "registry-state"
            New-Item -Path $stateDir -ItemType Directory -Force | Out-Null

            $result = Get-WmrRegistryState -RegistryConfig $registryConfig -StateFilesDirectory $stateDir

            $result | Should -Not -BeNullOrEmpty
            $result.Path | Should -Be $registryConfig.path
            $result.StateFilePath | Should -Not -BeNullOrEmpty
        }
    }

    Context "Windows Scheduled Tasks" {
        It "Should detect scheduled task capability" {
            $taskCmdlet = Get-Command "Get-ScheduledTask" -ErrorAction SilentlyContinue
            $taskCmdlet | Should -Not -BeNullOrEmpty
        }

        It "Should handle scheduled task operations" {
            # This is a safe read-only test
            $result = Get-ScheduledTask -TaskName "NonExistentTask" -ErrorAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }
    }

    Context "Windows File System Operations" {
        It "Should handle Windows file paths correctly" {
            $testPath = Join-Path $script:TestTempDir "test-file.txt"
            "test content" | Out-File -FilePath $testPath -Encoding UTF8

            $fileConfig = @{
                path = $testPath
                encrypt = $false
            }

            $result = Get-WmrFileState -FileConfig $fileConfig -StateFilesDirectory $script:TestTempDir

            $result | Should -Not -BeNullOrEmpty
            $result.Path | Should -Be $testPath
        }

        It "Should handle Windows directory paths correctly" {
            $testDir = Join-Path $script:TestTempDir "test-directory"
            New-Item -Path $testDir -ItemType Directory -Force | Out-Null

            $dirConfig = @{
                path = $testDir
                encrypt = $false
            }

            $result = Get-WmrFileState -FileConfig $dirConfig -StateFilesDirectory $script:TestTempDir

            $result | Should -Not -BeNullOrEmpty
            $result.Path | Should -Be $testDir
        }
    }
}

Describe "Windows Environment Integration" -Tag "Windows", "Unit", "Environment" {

    Context "Windows Environment Variables" {
        It "Should access Windows-specific environment variables" {
            $env:USERPROFILE | Should -Not -BeNullOrEmpty
            $env:PROGRAMFILES | Should -Not -BeNullOrEmpty
            $env:PROGRAMDATA | Should -Not -BeNullOrEmpty
            $env:COMPUTERNAME | Should -Not -BeNullOrEmpty
        }

        It "Should handle Windows path separators correctly" {
            $testPath = Join-Path $env:TEMP "wmr-test"
            $testPath | Should -Match '\\'
        }
    }

    Context "Windows Module Operations" {
        It "Should get correct module path on Windows" {
            $modulePath = Get-WmrModulePath
            $modulePath | Should -Not -BeNullOrEmpty
            $modulePath | Should -Match '^[A-Za-z]:'
        }

        It "Should handle Windows-specific module loading" {
            $module = Get-Module WindowsMelodyRecovery
            $module | Should -Not -BeNullOrEmpty
            $module.ModuleBase | Should -Match '^[A-Za-z]:'
        }
    }
}






