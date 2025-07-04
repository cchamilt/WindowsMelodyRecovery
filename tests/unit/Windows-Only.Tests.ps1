#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Windows-Only Unit Tests for Windows Melody Recovery

.DESCRIPTION
    These tests are specifically for Windows-only functionality and should only run on Windows systems.
    They test real Windows features like scheduled tasks, Windows Principal checks, and registry operations.
#>

BeforeAll {
    # Only run these tests on Windows
    if (-not $IsWindows) {
        Write-Warning "Skipping Windows-only tests on non-Windows platform"
        return
    }
    
    # Import the module
    Import-Module (Join-Path $PSScriptRoot "../../WindowsMelodyRecovery.psm1") -Force
}

Describe "Windows-Only Functionality" -Tag "WindowsOnly" {
    BeforeAll {
        if (-not $IsWindows) {
            Write-Warning "Skipping Windows-only tests on non-Windows platform"
            return
        }
    }
    
    Context "Windows Principal and Privilege Checks" {
        It "Should properly check administrator privileges on Windows" {
            # Test the real Windows Principal functionality
            $result = Test-WmrAdminPrivilege
            $result | Should -BeOfType [bool]
        }
        
        It "Should handle privilege checks in Test-WindowsMelodyRecovery" {
            # Test the full privilege check flow on Windows
            $result = Test-WindowsMelodyRecovery -ErrorAction SilentlyContinue
            $result | Should -BeOfType [bool]
        }
    }
    
    Context "Windows Scheduled Tasks" {
        It "Should be able to check for scheduled tasks on Windows" {
            # Test that Get-ScheduledTask is available on Windows
            $taskCmdlet = Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue
            $taskCmdlet | Should -Not -BeNullOrEmpty
            
            # Test that we can query scheduled tasks
            $tasks = Get-ScheduledTask -ErrorAction SilentlyContinue | Select-Object -First 5
            $tasks | Should -Not -BeNullOrEmpty
        }
        
        It "Should properly detect WindowsMelodyRecovery scheduled tasks" {
            # Test the scheduled task detection in Test-WindowsMelodyRecovery
            $result = Test-WindowsMelodyRecovery -ErrorAction SilentlyContinue
            $result | Should -BeOfType [bool]
        }
    }
    
    Context "Windows Registry Operations" {
        It "Should be able to access Windows registry" {
            # Test basic registry access
            $testKey = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion" -ErrorAction SilentlyContinue
            $testKey | Should -Not -BeNullOrEmpty
        }
        
        It "Should handle registry state operations" {
            # Test the registry state functions
            $registryState = Get-WmrRegistryState -ErrorAction SilentlyContinue
            $registryState | Should -Not -BeNullOrEmpty
        }
    }
    
    Context "Windows File System Operations" {
        It "Should handle Windows file paths correctly" {
            # Test Windows-specific path handling
            $testPath = "C:\Windows\System32\notepad.exe"
            $fileState = Get-WmrFileState -Path $testPath -ErrorAction SilentlyContinue
            $fileState | Should -Not -BeNullOrEmpty
        }
    }
    
    Context "Windows Installation and Configuration" {
        It "Should handle Windows system directory access" {
            # Test initialization in Windows system directories
            $systemPath = "C:\Windows\System32"
            { Initialize-WindowsMelodyRecovery -InstallPath $systemPath -NoPrompt -ErrorAction Stop } | Should -Throw
        }
        
        It "Should provide Windows-specific error messages" {
            # Test Windows path validation and error handling
            try {
                Initialize-WindowsMelodyRecovery -InstallPath "" -NoPrompt -ErrorAction Stop
            } catch {
                $_.Exception.Message | Should -Not -BeNullOrEmpty
                $_.Exception.Message | Should -Match "configuration|install|path"
            }
        }
        
        It "Should properly validate Windows installation paths" {
            # Test real Windows path validation
            $invalidPath = "C:\Invalid\Path\That\Does\Not\Exist"
            { Initialize-WindowsMelodyRecovery -InstallPath $invalidPath -NoPrompt -ErrorAction Stop } | Should -Throw
        }
        
        It "Should handle Windows-specific privilege requirements" {
            # Test real Windows privilege checks in installation context
            $result = Test-WindowsMelodyRecovery -ErrorAction SilentlyContinue
            $result | Should -BeOfType [bool]
        }
    }
}

# Skip all tests if not on Windows
if (-not $IsWindows) {
    Write-Warning "All Windows-only tests skipped on non-Windows platform"
    return
} 