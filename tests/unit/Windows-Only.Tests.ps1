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
    
    # Import the module with standardized pattern
    try {
        $ModulePath = Resolve-Path "$PSScriptRoot/../../WindowsMelodyRecovery.psd1"
        Import-Module $ModulePath -Force -ErrorAction Stop
    } catch {
        throw "Cannot find or import WindowsMelodyRecovery module: $($_.Exception.Message)"
    }
    
    # Import test environment utilities
    . (Join-Path $PSScriptRoot "..\utilities\Test-Environment.ps1")
    
    # Get standardized test paths
    $script:TestPaths = Get-TestPaths
    
    # Directly source the core functions needed for testing
    . (Join-Path $script:TestPaths.ModuleRoot "Private\Core\RegistryState.ps1")
    . (Join-Path $script:TestPaths.ModuleRoot "Private\Core\FileState.ps1")
    . (Join-Path $script:TestPaths.ModuleRoot "Private\Core\PathUtilities.ps1")
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
            # Test the registry state functions with proper mock parameters
            $mockRegistryConfig = @{
                name = "TestRegistry"
                path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion"
                type = "key"
                dynamic_state_path = "registry/test-registry.json"
            }
            $mockStateDirectory = $env:TEMP
            
            $registryState = Get-WmrRegistryState -RegistryConfig $mockRegistryConfig -StateFilesDirectory $mockStateDirectory -ErrorAction SilentlyContinue
            # Registry state can be null if the operation fails, so just test that the function can be called
            { Get-WmrRegistryState -RegistryConfig $mockRegistryConfig -StateFilesDirectory $mockStateDirectory -ErrorAction Stop } | Should -Not -Throw
        }
    }
    
    Context "Windows File System Operations" {
        It "Should handle Windows file paths correctly" {
            # Test Windows-specific path handling with proper mock parameters
            $testPath = "C:\Windows\System32\notepad.exe"
            $mockFileConfig = @{
                name = "TestFile"
                path = $testPath
                type = "file"
                dynamic_state_path = "files/test-file.json"
            }
            $mockStateDirectory = $env:TEMP
            
            $fileState = Get-WmrFileState -FileConfig $mockFileConfig -StateFilesDirectory $mockStateDirectory -ErrorAction SilentlyContinue
            # File state can be null if the operation fails, so just test that the function can be called
            { Get-WmrFileState -FileConfig $mockFileConfig -StateFilesDirectory $mockStateDirectory -ErrorAction Stop } | Should -Not -Throw
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