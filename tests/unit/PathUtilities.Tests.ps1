#!/usr/bin/env pwsh

BeforeAll {
    # Load Docker test bootstrap for cross-platform compatibility
    . (Join-Path $PSScriptRoot "../utilities/Docker-Test-Bootstrap.ps1")

    # Import only the PathUtilities script directly to avoid TUI dependencies
    try {
        $PathUtilitiesScript = Resolve-Path "$PSScriptRoot/../../Private/Core/PathUtilities.ps1"
        . $PathUtilitiesScript

        # Also need the test environment path function
        $TestEnvironmentScript = Resolve-Path "$PSScriptRoot/../utilities/Test-Environment.ps1"
        . $TestEnvironmentScript

        # Initialize test environment for path redirection
        Initialize-TestEnvironment -SuiteName 'Unit' | Out-Null
    }
    catch {
        throw "Cannot find or import PathUtilities script: $($_.Exception.Message)"
    }
}

Describe "Convert-WmrPath" {

    It "should correctly expand environment variables for Windows paths" {
        $env:TEST_VAR = "TestFolder"
        $windowsPath = "C:\Users\$env:USERNAME\$env:TEST_VAR\file.txt"
        $result = Convert-WmrPath -Path $windowsPath
        $result.PathType | Should -Be "File"
        $result.Path | Should -Be $windowsPath
        $env:TEST_VAR = $null
    }

    It "should correctly handle file:// URIs" {
        $path = "file://C:/Program Files/App/app.exe"
        $result = Convert-WmrPath -Path $path
        $result.PathType | Should -Be "File"
        $result.Path | Should -Be "C:\Program Files\App\app.exe"
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








