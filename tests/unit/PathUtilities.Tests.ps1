#!/usr/bin/env pwsh

BeforeAll {
    # Import the unified test environment library and initialize it.
    . (Join-Path $PSScriptRoot "..\utilities\Test-Environment.ps1")
    $script:TestEnvironment = Initialize-WmrTestEnvironment -SuiteName 'Unit'

    # Import the main module to make functions available for testing.
    Import-Module (Join-Path $script:TestEnvironment.ModuleRoot "WindowsMelodyRecovery.psd1") -Force
}

AfterAll {
    # Clean up the test environment created in BeforeAll.
    Remove-WmrTestEnvironment
}

Describe "Convert-WmrPath" {

    It "should correctly expand environment variables for Windows paths" {
        # Temporarily disable test mode for this logic test
        $originalTestMode = $env:WMR_TEST_MODE
        $env:WMR_TEST_MODE = $null

        try {
            $env:TEST_VAR = "TestFolder"
            $windowsPath = "C:\Users\$env:USERNAME\$env:TEST_VAR\file.txt"
            $result = Convert-WmrPath -Path $windowsPath
            $result.PathType | Should -Be "File"
            $result.Path | Should -Be $windowsPath
            $env:TEST_VAR = $null
        }
        finally {
            # Restore test mode
            $env:WMR_TEST_MODE = $originalTestMode
        }
    }

    It "should correctly handle file:// URIs" {
        # Temporarily disable test mode for this logic test
        $originalTestMode = $env:WMR_TEST_MODE
        $env:WMR_TEST_MODE = $null

        try {
            $path = "file://C:/Program Files/App/app.exe"
            $result = Convert-WmrPath -Path $path
            $result.PathType | Should -Be "File"
            $result.Path | Should -Be "C:\Program Files\App\app.exe"
        }
        finally {
            # Restore test mode
            $env:WMR_TEST_MODE = $originalTestMode
        }
    }

    It "should correctly handle winreg:// HKLM paths" {
        $path = "winreg://HKLM/SOFTWARE/Microsoft"
        $result = Convert-WmrPath -Path $path
        $result.PathType | Should -Be "Registry"
        $result.Path | Should -Be "HKLM:\SOFTWARE\Microsoft"
    }

    It "should correctly handle winreg:// HKCU paths" {
        $path = "winreg://HKCU/Software/MyApp"
        $result = Convert-WmrPath -Path $path
        $result.PathType | Should -Be "Registry"
        $result.Path | Should -Be "HKCU:\Software\MyApp"
    }

    It "should correctly handle wsl:/// paths (default distribution)" {
        $path = "wsl:///home/$user/.bashrc"
        $result = Convert-WmrPath -Path $path
        $result.PathType | Should -Be "WSL"
        $result.Distribution | Should -Be ""
        # Placeholder assumes $user is replaced by Windows username; in a real WSL env this might be $USER
        $result.Path | Should -Be "/home/$env:USERNAME/.bashrc"
    }

    It "should correctly handle wsl://WSLVM/ paths (specific distribution)" {
        $path = "wsl://Ubuntu/home/$user/.zshrc"
        $result = Convert-WmrPath -Path $path
        $result.PathType | Should -Be "WSL"
        $result.Distribution | Should -Be "Ubuntu"
        # Placeholder assumes $user is replaced by Windows username
        $result.Path | Should -Be "/home/$env:USERNAME/.zshrc"
    }

    It "should return original path for unrecognized URIs as File type" {
        $path = "customuri://something/data"
        $result = Convert-WmrPath -Path $path
        $result.PathType | Should -Be "File"
        $result.Path | Should -Be "customuri://something/data"
    }
}








