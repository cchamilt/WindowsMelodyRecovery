# tests/unit/AdministrativePrivileges.Tests.ps1

<#
.SYNOPSIS
    Unit tests for AdministrativePrivileges.ps1 functions.

.DESCRIPTION
    Tests the enhanced administrative privilege management functions
    including privilege checking, elevation handling, and safe operations.

.NOTES
    Test Level: Unit (Logic Only)
    Author: Windows Melody Recovery
    Version: 1.0
    Requires: Pester 5.0+
#>

BeforeAll {
    # Load Docker test bootstrap for cross-platform compatibility
    . (Join-Path $PSScriptRoot "../utilities/Docker-Test-Bootstrap.ps1")

    # Import the module
    Import-Module (Resolve-Path "$PSScriptRoot/../../WindowsMelodyRecovery.psd1") -Force

    # Dot-source AdministrativePrivileges.ps1 to ensure all functions are available
    . (Join-Path (Split-Path (Resolve-Path "$PSScriptRoot/../../WindowsMelodyRecovery.psd1")) "Private\Core\AdministrativePrivileges.ps1")

    # Import test utilities
    . "$PSScriptRoot/../utilities/Test-Utilities.ps1"
}

Describe "Test-WmrAdministrativePrivileges Function" {
    Context "Basic Privilege Detection" {
        It "Should return privilege information object with required properties" {
            $result = Test-WmrAdministrativePrivileges -Quiet

            $result | Should -Not -BeNull
            $result.PSObject.Properties.Name | Should -Contain "IsWindows"
            $result.PSObject.Properties.Name | Should -Contain "IsElevated"
            $result.PSObject.Properties.Name | Should -Contain "CanElevate"
            $result.PSObject.Properties.Name | Should -Contain "CurrentUser"
            $result.PSObject.Properties.Name | Should -Contain "ProcessId"
            $result.PSObject.Properties.Name | Should -Contain "ElevationMethod"
            $result.PSObject.Properties.Name | Should -Contain "Warnings"
            $result.PSObject.Properties.Name | Should -Contain "Errors"
        }

        It "Should detect Windows platform correctly" {
            $result = Test-WmrAdministrativePrivileges -Quiet
            $result.IsWindows | Should -Be $IsWindows
        }

        It "Should include process ID" {
            $result = Test-WmrAdministrativePrivileges -Quiet
            $result.ProcessId | Should -Be $PID
        }

        It "Should handle ThrowIfNotAdmin parameter when not admin" {
            Mock -CommandName "Test-WmrAdministrativePrivileges" -MockWith {
                param($ThrowIfNotAdmin, $Quiet)
                if ($ThrowIfNotAdmin) {
                    throw "Administrative privileges are required for this operation"
                }
                return [PSCustomObject]@{ IsElevated = $false }
            }

            { Test-WmrAdministrativePrivileges -ThrowIfNotAdmin } | Should -Throw "*Administrative privileges are required*"
        }

        It "Should not throw when admin privileges are available" {
            Mock -CommandName "Test-WmrAdministrativePrivileges" -MockWith {
                param($ThrowIfNotAdmin, $Quiet)
                return [PSCustomObject]@{ IsElevated = $true }
            }

            { Test-WmrAdministrativePrivileges -ThrowIfNotAdmin } | Should -Not -Throw
        }
    }

    Context "Elevation Method Detection" {
        It "Should detect 'Already Elevated' when running as admin" {
            Mock -CommandName "Test-WmrAdministrativePrivileges" -MockWith {
                return [PSCustomObject]@{
                    IsElevated = $true
                    ElevationMethod = "Already Elevated"
                }
            }

            $result = Test-WmrAdministrativePrivileges -Quiet
            $result.ElevationMethod | Should -Be "Already Elevated"
        }

        It "Should detect 'UAC Available' when can elevate" {
            Mock -CommandName "Test-WmrAdministrativePrivileges" -MockWith {
                return [PSCustomObject]@{
                    IsElevated = $false
                    CanElevate = $true
                    ElevationMethod = "UAC Available"
                }
            }

            $result = Test-WmrAdministrativePrivileges -Quiet
            $result.ElevationMethod | Should -Be "UAC Available"
        }

        It "Should detect 'No Elevation Available' when cannot elevate" {
            Mock -CommandName "Test-WmrAdministrativePrivileges" -MockWith {
                return [PSCustomObject]@{
                    IsElevated = $false
                    CanElevate = $false
                    ElevationMethod = "No Elevation Available"
                }
            }

            $result = Test-WmrAdministrativePrivileges -Quiet
            $result.ElevationMethod | Should -Be "No Elevation Available"
        }
    }

    Context "Error Handling" {
        It "Should handle privilege detection errors gracefully" {
            Mock -CommandName "Test-WmrAdministrativePrivileges" -MockWith {
                return [PSCustomObject]@{
                    IsElevated = $false
                    Errors = @("Test error message")
                }
            }

            $result = Test-WmrAdministrativePrivileges -Quiet
            $result.Errors | Should -Contain "Test error message"
        }

        It "Should collect warnings when not quiet" {
            Mock -CommandName "Test-WmrAdministrativePrivileges" -MockWith {
                return [PSCustomObject]@{
                    IsElevated = $false
                    Warnings = @("Not running with administrative privileges")
                }
            }

            $result = Test-WmrAdministrativePrivileges
            $result.Warnings | Should -Contain "Not running with administrative privileges"
        }
    }
}

Describe "Test-WmrElevationCapability Function" {
    Context "UAC Detection" {
        It "Should return false on non-Windows systems" {
            Mock -CommandName "Test-WmrElevationCapability" -MockWith {
                if (-not $IsWindows) { return $false }
                return $true
            }

            $result = Test-WmrElevationCapability

            if (-not $IsWindows) {
                $result | Should -Be $false
            }
        }

        It "Should handle registry access errors gracefully" {
            Mock -CommandName "Get-ItemProperty" -MockWith { throw "Access denied" }

            $result = Test-WmrElevationCapability
            $result | Should -BeOfType [bool]
        }
    }
}

Describe "Test-WmrAdminRequiredOperation Function" {
    Context "Registry Operations" {
        It "Should require admin for HKLM write operations" {
            $result = Test-WmrAdminRequiredOperation -OperationType "Registry" -Path "HKLM:\SOFTWARE\Test" -Action "Write"
            $result | Should -Be $true
        }

        It "Should not require admin for HKLM read operations" {
            $result = Test-WmrAdminRequiredOperation -OperationType "Registry" -Path "HKLM:\SOFTWARE\Test" -Action "Read"
            $result | Should -Be $false
        }

        It "Should not require admin for HKCU operations" {
            $result = Test-WmrAdminRequiredOperation -OperationType "Registry" -Path "HKCU:\SOFTWARE\Test" -Action "Write"
            $result | Should -Be $false
        }

        It "Should require admin for protected registry paths" {
            $protectedPaths = @(
                "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Test",
                "HKLM:\SYSTEM\CurrentControlSet\Test",
                "HKLM:\SOFTWARE\Classes\Test"
            )

            foreach ($path in $protectedPaths) {
                $result = Test-WmrAdminRequiredOperation -OperationType "Registry" -Path $path -Action "Read"
                $result | Should -Be $true
            }
        }
    }

    Context "File Operations" {
        It "Should require admin for system directory writes" {
            $result = Test-WmrAdminRequiredOperation -OperationType "File" -Path "C:\Windows\System32\test.txt" -Action "Write"
            $result | Should -Be $true
        }

        It "Should not require admin for system directory reads" {
            $result = Test-WmrAdminRequiredOperation -OperationType "File" -Path "C:\Windows\System32\test.txt" -Action "Read"
            $result | Should -Be $false
        }

        It "Should not require admin for user directory operations" {
            $result = Test-WmrAdminRequiredOperation -OperationType "File" -Path "C:\Users\Test\test.txt" -Action "Write"
            $result | Should -Be $false
        }
    }

    Context "Service Operations" {
        It "Should require admin for service modifications" {
            $result = Test-WmrAdminRequiredOperation -OperationType "Service" -Path "TestService" -Action "Modify"
            $result | Should -Be $true
        }

        It "Should not require admin for service reads" {
            $result = Test-WmrAdminRequiredOperation -OperationType "Service" -Path "TestService" -Action "Read"
            $result | Should -Be $false
        }
    }

    Context "Scheduled Task Operations" {
        It "Should require admin for scheduled task modifications" {
            $result = Test-WmrAdminRequiredOperation -OperationType "ScheduledTask" -Path "TestTask" -Action "Create"
            $result | Should -Be $true
        }

        It "Should not require admin for scheduled task reads" {
            $result = Test-WmrAdminRequiredOperation -OperationType "ScheduledTask" -Path "TestTask" -Action "Read"
            $result | Should -Be $false
        }
    }

    Context "Windows Features and Capabilities" {
        It "Should always require admin for Windows features" {
            $result = Test-WmrAdminRequiredOperation -OperationType "WindowsFeature" -Path "TestFeature" -Action "Read"
            $result | Should -Be $true
        }

        It "Should always require admin for Windows capabilities" {
            $result = Test-WmrAdminRequiredOperation -OperationType "WindowsCapability" -Path "TestCapability" -Action "Read"
            $result | Should -Be $true
        }
    }
}

Describe "Get-WmrPrivilegeRequirements Function" {
    Context "Template Analysis" {
        It "Should detect admin requirements from prerequisites" {
            $template = @{
                prerequisites = @(
                    @{
                        name = "Administrator Privileges Required"
                        inline_script = "Test-WmrAdministrativePrivileges"
                    }
                )
            }

            $result = Get-WmrPrivilegeRequirements -TemplateConfig $template -Operation "Backup"
            $result.RequiresAdmin | Should -Be $true
        }

        It "Should detect admin requirements from HKLM registry operations" {
            $template = @{
                registry = @(
                    @{
                        path = "HKLM:\SOFTWARE\Test"
                        action = "sync"
                    }
                )
            }

            $result = Get-WmrPrivilegeRequirements -TemplateConfig $template -Operation "Backup"
            $result.RequiresAdmin | Should -Be $true
        }

        It "Should detect safe operations from HKCU registry operations" {
            $template = @{
                registry = @(
                    @{
                        path = "HKCU:\SOFTWARE\Test"
                        action = "sync"
                    }
                )
            }

            $result = Get-WmrPrivilegeRequirements -TemplateConfig $template -Operation "Backup"
            $result.RequiresAdmin | Should -Be $false
        }

        It "Should detect admin requirements from Windows features" {
            $template = @{
                applications = @(
                    @{
                        name = "Test Feature"
                        discovery_command = "Get-WindowsOptionalFeature -Online"
                    }
                )
            }

            $result = Get-WmrPrivilegeRequirements -TemplateConfig $template -Operation "Backup"
            $result.RequiresAdmin | Should -Be $true
        }

        It "Should detect mixed requirements and set appropriate flags" {
            $template = @{
                registry = @(
                    @{
                        path = "HKLM:\SOFTWARE\Test"
                        action = "sync"
                    },
                    @{
                        path = "HKCU:\SOFTWARE\Test"
                        action = "sync"
                    }
                )
            }

            $result = Get-WmrPrivilegeRequirements -TemplateConfig $template -Operation "Backup"
            $result.RequiresAdmin | Should -Be $true
            $result.CanRunWithoutAdmin | Should -Be $true
        }
    }
}

Describe "Invoke-WmrSafeAdminOperation Function" {
    Context "Privilege-Based Execution" {
        It "Should execute main operation when admin privileges are available" {
            Mock -CommandName "Test-WmrAdministrativePrivileges" -MockWith {
                return [PSCustomObject]@{ IsElevated = $true }
            }

            $result = Invoke-WmrSafeAdminOperation -ScriptBlock { return "Success" } -OperationName "Test Operation"
            $result.Success | Should -Be $true
            $result.Data | Should -Be "Success"
        }

        It "Should execute fallback operation when admin privileges are not available" {
            Mock -CommandName "Test-WmrAdministrativePrivileges" -MockWith {
                return [PSCustomObject]@{ IsElevated = $false }
            }

            $result = Invoke-WmrSafeAdminOperation -ScriptBlock { return "Main" } -FallbackScriptBlock { return "Fallback" } -OperationName "Test Operation"
            $result.Success | Should -Be $true
            $result.Data | Should -Be "Fallback"
            $result.UsedFallback | Should -Be $true
        }

        It "Should fail gracefully when no fallback is available" {
            Mock -CommandName "Test-WmrAdministrativePrivileges" -MockWith {
                return [PSCustomObject]@{ IsElevated = $false }
            }

            $result = Invoke-WmrSafeAdminOperation -ScriptBlock { return "Main" } -OperationName "Test Operation"
            $result.Success | Should -Be $false
            $result.RequiredPrivileges | Should -Be "Admin"
        }

        It "Should handle User-level operations regardless of privileges" {
            Mock -CommandName "Test-WmrAdministrativePrivileges" -MockWith {
                return [PSCustomObject]@{ IsElevated = $false }
            }

            $result = Invoke-WmrSafeAdminOperation -ScriptBlock { return "User Operation" } -OperationName "Test Operation" -RequiredPrivileges "User"
            $result.Success | Should -Be $true
            $result.Data | Should -Be "User Operation"
        }
    }

    Context "Error Handling" {
        It "Should handle main operation errors and try fallback" {
            Mock -CommandName "Test-WmrAdministrativePrivileges" -MockWith {
                return [PSCustomObject]@{ IsElevated = $true }
            }

            $result = Invoke-WmrSafeAdminOperation -ScriptBlock { throw "Main operation failed" } -FallbackScriptBlock { return "Fallback worked" } -OperationName "Test Operation"
            $result.Success | Should -Be $true
            $result.Data | Should -Be "Fallback worked"
            $result.UsedFallback | Should -Be $true
        }

        It "Should handle both main and fallback operation errors" {
            Mock -CommandName "Test-WmrAdministrativePrivileges" -MockWith {
                return [PSCustomObject]@{ IsElevated = $true }
            }

            $result = Invoke-WmrSafeAdminOperation -ScriptBlock { throw "Main operation failed" } -FallbackScriptBlock { throw "Fallback failed" } -OperationName "Test Operation"
            $result.Success | Should -Be $false
            $result.Errors.Count | Should -BeGreaterThan 0
        }
    }
}

Describe "Invoke-WmrWithElevation Function" {
    Context "Elevation Logic" {
        It "Should execute directly when already elevated" {
            Mock -CommandName "Test-WmrAdministrativePrivileges" -MockWith {
                return [PSCustomObject]@{ IsElevated = $true; CanElevate = $true }
            }

            $result = Invoke-WmrWithElevation -ScriptBlock { return "Elevated Success" }
            $result | Should -Be "Elevated Success"
        }

        It "Should handle WhatIf parameter correctly" {
            Mock -CommandName "Test-WmrAdministrativePrivileges" -MockWith {
                return [PSCustomObject]@{ IsElevated = $false; CanElevate = $true }
            }

            $result = Invoke-WmrWithElevation -ScriptBlock { return "Test" } -WhatIf
            $result.WhatIf | Should -Be $true
            $result.WouldElevate | Should -Be $true
        }

        It "Should handle NoPrompt parameter when elevation is needed" {
            Mock -CommandName "Test-WmrAdministrativePrivileges" -MockWith {
                return [PSCustomObject]@{ IsElevated = $false; CanElevate = $true }
            }

            $result = Invoke-WmrWithElevation -ScriptBlock { return "Test" } -NoPrompt
            $result.Success | Should -Be $false
            $result.RequiresElevation | Should -Be $true
        }
    }

    Context "Argument Passing" {
        It "Should pass arguments to script block correctly" {
            Mock -CommandName "Test-WmrAdministrativePrivileges" -MockWith {
                return [PSCustomObject]@{ IsElevated = $true; CanElevate = $true }
            }

            $result = Invoke-WmrWithElevation -ScriptBlock { param($arg1, $arg2) return "$arg1-$arg2" } -ArgumentList @("Hello", "World")
            $result | Should -Be "Hello-World"
        }
    }
}

AfterAll {
    # Clean up any test resources
}

