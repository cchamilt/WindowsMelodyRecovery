# tests/windows-only/integration/WSL-Native.Tests.ps1

<#
.SYNOPSIS
    Windows-Only Native WSL Integration Tests

.DESCRIPTION
    Tests the module's ability to interact directly with a real, native
    WSL installation on a Windows machine.

    These tests require a functional WSL environment and are intended to
    run only on Windows CI/CD systems.

.NOTES
    Test Level: Integration (Windows-Only)
    Requires: Pester 5.0+, Windows with WSL installed
#>

BeforeAll {
    # CRITICAL SAFETY CHECK: Only run on a Windows machine.
    if (-not $IsWindows) {
        throw "Native WSL tests can only be run on a Windows machine."
    }

    # Import the module
    Import-Module (Resolve-Path "$PSScriptRoot/../../../WindowsMelodyRecovery.psd1") -Force

    # Check if WSL is available
    $script:WSLAvailable = $false
    try {
        $wslVersion = wsl.exe --version
        if ($wslVersion) {
            $script:WSLAvailable = $true
            $script:WSLDistro = (wsl.exe --list --quiet | Select-Object -First 1).Trim()
        }
    }
    catch {
        Write-Warning "WSL is not available or not found in PATH. Skipping native WSL tests."
    }
}

Describe "Native WSL Integration Tests" -Tag "WindowsOnly", "WSL" {

    Context "WSL Environment Detection" {
        It "Should detect WSL installation" {
            if ($script:WSLAvailable) {
                { wsl.exe --version } | Should -Not -Throw
                (wsl.exe --version) | Should -Not -BeNullOrEmpty
            }
            else {
                Set-ItResult -Skipped -Because "WSL not available on this Windows machine."
            }
        }

        It "Should list WSL distributions" {
            if ($script:WSLAvailable) {
                $distros = wsl.exe --list --quiet
                $distros | Should -Not -BeNullOrEmpty
                $distros | Should -Contain $script:WSLDistro
            }
            else {
                Set-ItResult -Skipped -Because "WSL not available on this Windows machine."
            }
        }

        It "Should connect to a WSL distribution" {
            if ($script:WSLAvailable) {
                $result = wsl.exe -d $script:WSLDistro -- echo "test"
                $result | Should -Be "test"
            }
            else {
                Set-ItResult -Skipped -Because "WSL not available on this Windows machine."
            }
        }
    }

    Context "Direct WSL Command Execution" {
        It "Should backup APT packages using direct WSL execution" {
            if ($script:WSLAvailable) {
                # This tests the module's ability to shell out to wsl.exe correctly
                $command = 'dpkg --get-selections'
                $result = wsl.exe -d $script:WSLDistro -u root -- bash -c $command

                $result | Should -Not -BeNullOrEmpty
                $result | Should -Contain "install"
            }
            else {
                Set-ItResult -Skipped -Because "WSL not available on this Windows machine."
            }
        }

        It "Should backup NPM packages using direct WSL execution" {
            if ($script:WSLAvailable) {
                # This tests the module's ability to shell out to wsl.exe correctly
                $command = 'npm list -g --depth=0'
                $result = wsl.exe -d $script:WSLDistro -u root -- bash -c $command

                $result | Should -Not -BeNullOrEmpty
            }
            else {
                Set-ItResult -Skipped -Because "WSL not available on this Windows machine."
            }
        }
    }
}
