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
            $result | Should -HaveProperty "IsWindows"
            $result | Should -HaveProperty "IsElevated"
            $result | Should -HaveProperty "CanElevate"
            $result | Should -HaveProperty "CurrentUser"
            $result | Should -HaveProperty "ProcessId"
            $result | Should -HaveProperty "ElevationMethod"
            $result | Should -HaveProperty "Warnings"
            $result | Should -HaveProperty "Errors"
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
            
            { Test-WmrAdministrativePrivileges -ThrowIfNotAdmin } | Should -Throw "Administrative privileges are required"
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
            $systemPaths = @(
                (Get-WmrTestPath -WindowsPath "C:\Windows\test.txt"),
                (Get-WmrTestPath -WindowsPath "C:\Program Files\test.txt"),
                (Get-WmrTestPath -WindowsPath "C:\Program Files (x86)\test.txt")
            )
            
            foreach ($path in $systemPaths) {
                $result = Test-WmrAdminRequiredOperation -OperationType "File" -Path $path -Action "Write"
                $result | Should -Be $true
            }
        }
        
        It "Should not require admin for system directory reads" {
            $result = Test-WmrAdminRequiredOperation -OperationType "File" -Path (Get-WmrTestPath -WindowsPath "C:\Windows\test.txt") -Action "Read"
            $result | Should -Be $false
        }
        
        It "Should not require admin for user directory operations" {
            $userPath = Join-Path $env:USERPROFILE "test.txt"
            $result = Test-WmrAdminRequiredOperation -OperationType "File" -Path $userPath -Action "Write"
            $result | Should -Be $false
        }
    }
    
    Context "Service Operations" {
        It "Should require admin for service modifications" {
            $modifyActions = @("Write", "Create", "Delete", "Modify", "Execute")
            
            foreach ($action in $modifyActions) {
                $result = Test-WmrAdminRequiredOperation -OperationType "Service" -Path "TestService" -Action $action
                $result | Should -Be $true
            }
        }
        
        It "Should not require admin for service reads" {
            $result = Test-WmrAdminRequiredOperation -OperationType "Service" -Path "TestService" -Action "Read"
            $result | Should -Be $false
        }
    }
    
    Context "Scheduled Task Operations" {
        It "Should require admin for scheduled task modifications" {
            $modifyActions = @("Create", "Delete", "Modify")
            
            foreach ($action in $modifyActions) {
                $result = Test-WmrAdminRequiredOperation -OperationType "ScheduledTask" -Path "TestTask" -Action $action
                $result | Should -Be $true
            }
        }
        
        It "Should not require admin for scheduled task reads" {
            $result = Test-WmrAdminRequiredOperation -OperationType "ScheduledTask" -Path "TestTask" -Action "Read"
            $result | Should -Be $false
        }
    }
    
    Context "Windows Features and Capabilities" {
        It "Should always require admin for Windows features" {
            $actions = @("Read", "Write", "Create", "Delete", "Modify", "Execute")
            
            foreach ($action in $actions) {
                $result = Test-WmrAdminRequiredOperation -OperationType "WindowsFeature" -Path "TestFeature" -Action $action
                $result | Should -Be $true
            }
        }
        
        It "Should always require admin for Windows capabilities" {
            $actions = @("Read", "Write", "Create", "Delete", "Modify", "Execute")
            
            foreach ($action in $actions) {
                $result = Test-WmrAdminRequiredOperation -OperationType "WindowsCapability" -Path "TestCapability" -Action $action
                $result | Should -Be $true
            }
        }
    }
}

Describe "Get-WmrPrivilegeRequirements Function" {
    Context "Template Analysis" {
        It "Should detect admin requirements from prerequisites" {
            $templateConfig = @{
                metadata = @{ name = "Test Template" }
                prerequisites = @(
                    @{
                        name = "Administrative Privileges Required"
                        inline_script = "Test-WmrAdminPrivilege"
                    }
                )
            }
            
            $result = Get-WmrPrivilegeRequirements -TemplateConfig $templateConfig -Operation "Backup"
            $result.RequiresAdmin | Should -Be $true
            $result.AdminOperations | Should -Contain "Prerequisite: Administrative Privileges Required"
        }
        
        It "Should detect admin requirements from HKLM registry operations" {
            $templateConfig = @{
                metadata = @{ name = "Test Template" }
                registry = @(
                    @{
                        name = "Test Registry"
                        path = "HKLM:\SOFTWARE\Test"
                        action = "sync"
                    }
                )
            }
            
            $result = Get-WmrPrivilegeRequirements -TemplateConfig $templateConfig -Operation "Backup"
            $result.RequiresAdmin | Should -Be $true
            $result.AdminOperations | Should -Contain "Registry: HKLM:\SOFTWARE\Test"
        }
        
        It "Should detect safe operations from HKCU registry operations" {
            $templateConfig = @{
                metadata = @{ name = "Test Template" }
                registry = @(
                    @{
                        name = "Test Registry"
                        path = "HKCU:\SOFTWARE\Test"
                        action = "sync"
                    }
                )
            }
            
            $result = Get-WmrPrivilegeRequirements -TemplateConfig $templateConfig -Operation "Backup"
            $result.RequiresAdmin | Should -Be $false
            $result.SafeOperations | Should -Contain "Registry: HKCU:\SOFTWARE\Test"
        }
        
        It "Should detect admin requirements from Windows features" {
            $templateConfig = @{
                metadata = @{ name = "Test Template" }
                applications = @(
                    @{
                        name = "Windows Features"
                        discovery_command = "Get-WindowsOptionalFeature -Online"
                    }
                )
            }
            
            $result = Get-WmrPrivilegeRequirements -TemplateConfig $templateConfig -Operation "Backup"
            $result.RequiresAdmin | Should -Be $true
            $result.AdminOperations | Should -Contain "Windows Feature/Capability: Windows Features"
        }
        
        It "Should detect mixed requirements and set appropriate flags" {
            $templateConfig = @{
                metadata = @{ name = "Test Template" }
                registry = @(
                    @{
                        name = "Admin Registry"
                        path = "HKLM:\SOFTWARE\Test"
                        action = "sync"
                    },
                    @{
                        name = "User Registry"
                        path = "HKCU:\SOFTWARE\Test"
                        action = "sync"
                    }
                )
            }
            
            $result = Get-WmrPrivilegeRequirements -TemplateConfig $templateConfig -Operation "Backup"
            $result.RequiresAdmin | Should -Be $true
            $result.CanRunWithoutAdmin | Should -Be $true
            $result.AdminOperations | Should -Contain "Registry: HKLM:\SOFTWARE\Test"
            $result.SafeOperations | Should -Contain "Registry: HKCU:\SOFTWARE\Test"
            $result.Warnings.Count | Should -BeGreaterThan 0
        }
    }
}

Describe "Invoke-WmrSafeAdminOperation Function" {
    Context "Privilege-Based Execution" {
        It "Should execute main operation when admin privileges are available" {
            Mock -CommandName "Test-WmrAdministrativePrivileges" -MockWith {
                return [PSCustomObject]@{ IsElevated = $true }
            }
            
            $testResult = "Admin operation executed"
            $result = Invoke-WmrSafeAdminOperation -ScriptBlock { $testResult } -OperationName "Test Operation" -RequiredPrivileges "Admin"
            
            $result.Success | Should -Be $true
            $result.Data | Should -Be $testResult
            $result.UsedFallback | Should -Be $false
            $result.ActualPrivileges | Should -Be "Admin"
        }
        
        It "Should execute fallback operation when admin privileges are not available" {
            Mock -CommandName "Test-WmrAdministrativePrivileges" -MockWith {
                return [PSCustomObject]@{ IsElevated = $false }
            }
            
            $fallbackResult = "Fallback operation executed"
            $result = Invoke-WmrSafeAdminOperation -ScriptBlock { "Should not execute" } -FallbackScriptBlock { $fallbackResult } -OperationName "Test Operation" -RequiredPrivileges "Admin"
            
            $result.Success | Should -Be $true
            $result.Data | Should -Be $fallbackResult
            $result.UsedFallback | Should -Be $true
            $result.ActualPrivileges | Should -Be "User"
        }
        
        It "Should fail gracefully when no fallback is available" {
            Mock -CommandName "Test-WmrAdministrativePrivileges" -MockWith {
                return [PSCustomObject]@{ IsElevated = $false }
            }
            
            $result = Invoke-WmrSafeAdminOperation -ScriptBlock { "Should not execute" } -OperationName "Test Operation" -RequiredPrivileges "Admin"
            
            $result.Success | Should -Be $false
            $result.RequiresElevation | Should -Be $true
            $result.Errors.Count | Should -BeGreaterThan 0
        }
        
        It "Should handle User-level operations regardless of privileges" {
            Mock -CommandName "Test-WmrAdministrativePrivileges" -MockWith {
                return [PSCustomObject]@{ IsElevated = $false }
            }
            
            $testResult = "User operation executed"
            $result = Invoke-WmrSafeAdminOperation -ScriptBlock { $testResult } -OperationName "Test Operation" -RequiredPrivileges "User"
            
            $result.Success | Should -Be $true
            $result.Data | Should -Be $testResult
            $result.UsedFallback | Should -Be $false
        }
    }
    
    Context "Error Handling" {
        It "Should handle main operation errors and try fallback" {
            Mock -CommandName "Test-WmrAdministrativePrivileges" -MockWith {
                return [PSCustomObject]@{ IsElevated = $true }
            }
            
            $fallbackResult = "Fallback after error"
            $result = Invoke-WmrSafeAdminOperation -ScriptBlock { throw "Main operation failed" } -FallbackScriptBlock { $fallbackResult } -OperationName "Test Operation" -RequiredPrivileges "Admin"
            
            $result.Success | Should -Be $true
            $result.Data | Should -Be $fallbackResult
            $result.UsedFallback | Should -Be $true
            $result.Errors.Count | Should -BeGreaterThan 0
        }
        
        It "Should handle both main and fallback operation errors" {
            Mock -CommandName "Test-WmrAdministrativePrivileges" -MockWith {
                return [PSCustomObject]@{ IsElevated = $true }
            }
            
            $result = Invoke-WmrSafeAdminOperation -ScriptBlock { throw "Main operation failed" } -FallbackScriptBlock { throw "Fallback failed" } -OperationName "Test Operation" -RequiredPrivileges "Admin"
            
            $result.Success | Should -Be $false
            $result.Errors.Count | Should -BeGreaterThan 1
        }
    }
}

Describe "Invoke-WmrWithElevation Function" {
    Context "Elevation Logic" {
        It "Should execute directly when already elevated" {
            Mock -CommandName "Test-WmrAdministrativePrivileges" -MockWith {
                return [PSCustomObject]@{ IsElevated = $true; CanElevate = $false }
            }
            
            $testResult = "Elevated execution"
            $result = Invoke-WmrWithElevation -ScriptBlock { $testResult }
            
            $result | Should -Be $testResult
        }
        
        It "Should handle WhatIf parameter correctly" {
            Mock -CommandName "Test-WmrAdministrativePrivileges" -MockWith {
                return [PSCustomObject]@{ IsElevated = $false; CanElevate = $true }
            }
            
            $result = Invoke-WmrWithElevation -ScriptBlock { "Test" } -WhatIf
            
            $result | Should -HaveProperty "WhatIf"
            $result.WhatIf | Should -Be $true
            $result.WouldElevate | Should -Be $true
        }
        
        It "Should handle NoPrompt parameter when elevation is needed" {
            Mock -CommandName "Test-WmrAdministrativePrivileges" -MockWith {
                return [PSCustomObject]@{ IsElevated = $false; CanElevate = $true }
            }
            
            $result = Invoke-WmrWithElevation -ScriptBlock { "Test" } -NoPrompt
            
            $result | Should -HaveProperty "Success"
            $result.Success | Should -Be $false
            $result.RequiresElevation | Should -Be $true
        }
    }
    
    Context "Argument Passing" {
        It "Should pass arguments to script block correctly" {
            Mock -CommandName "Test-WmrAdministrativePrivileges" -MockWith {
                return [PSCustomObject]@{ IsElevated = $true }
            }
            
            $result = Invoke-WmrWithElevation -ScriptBlock { param($arg1, $arg2) "$arg1-$arg2" } -ArgumentList @("test", "value")
            
            $result | Should -Be "test-value"
        }
    }
}

AfterAll {
    # Clean up any test resources
} 

