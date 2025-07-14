# Tests the entire user journey from installation to backup to restore
# Functions are now defined in BeforeAll block for proper scoping

BeforeDiscovery {
}

BeforeAll {
    # Import the unified test environment library and initialize it for End-to-End tests.
    . (Join-Path $PSScriptRoot "..\utilities\Test-Environment.ps1")
    $script:TestEnvironment = Initialize-WmrTestEnvironment -SuiteName 'E2E'

    # Import the main module to make functions available for testing.
    Import-Module (Join-Path $script:TestEnvironment.ModuleRoot "WindowsMelodyRecovery.psd1") -Force

    # Test configuration using paths from the initialized environment
    $script:InstallPath = Join-Path $script:TestEnvironment.TestRoot "Installation"
    $script:BackupRoot = $script:TestEnvironment.TestBackup
    $script:RestoreRoot = $script:TestEnvironment.TestRestore
    $script:SourceSystem = Join-Path $script:TestEnvironment.Temp "SourceSystem"
    $script:TargetSystem = Join-Path $script:TestEnvironment.Temp "TargetSystem"

    Write-Information -MessageData "Setting up test environment:" -InformationAction Continue
    Write-Information -MessageData "  TestRoot: $($script:TestEnvironment.TestRoot)" -InformationAction Continue
    Write-Information -MessageData "  InstallPath: $script:InstallPath" -InformationAction Continue
    Write-Information -MessageData "  Docker test: $($script:TestEnvironment.IsDocker)" -InformationAction Continue

    # Create additional test-specific directory structure
    @($script:InstallPath, $script:SourceSystem, $script:TargetSystem) | ForEach-Object {
        if (-not (Test-Path $_)) {
            Write-Verbose -Message "Creating directory: $_"
            try {
                New-Item -Path $_ -ItemType Directory -Force | Out-Null
            }
            catch {
                throw "Failed to create directory '$_': $($_.Exception.Message)"
            }
        }
    }

    # Set up test environment variables (some are handled by initializer, some are specific)
    $env:WMR_CONFIG_PATH = $script:InstallPath
    $env:WMR_STATE_PATH = $script:SourceSystem
    $env:COMPUTERNAME = "TEST-MACHINE-E2E"
    $env:USERPROFILE = $script:SourceSystem

    # Force the module to use the correct backup root by explicitly setting it
    Set-Item -Path "HKLM:\Software\WindowsMelodyRecovery" -Name "BackupRoot" -Value $script:BackupRoot -Force
    Set-Item -Path "HKLM:\Software\WindowsMelodyRecovery" -Name "RestoreRoot" -Value $script:RestoreRoot -Force

    # Initialize mock data
    Initialize-BasicMockData
}

AfterAll {
    # Clean up the test environment created in BeforeAll.
    Remove-WmrTestEnvironment
}

Describe "Windows Melody Recovery - End-to-End Workflow" {
    BeforeAll {
        # Initialize the mock source system for all tests in this describe block
        Initialize-MockSourceSystem -Path $script:SourceSystem
        Initialize-MockTargetSystem -Path $script:TargetSystem
    }

    It "Installs Windows Melody Recovery" {
        # Install the module
        Install-WmrModule -Path $script:InstallPath
        # Verify installation
        Test-WmrModule -Path $script:InstallPath
    }

    It "Backs up the source system" {
        # Create a dummy file in the source system
        $dummyFile = Join-Path $script:SourceSystem "dummy.txt"
        "Dummy content" | Out-File -FilePath $dummyFile -Force

        # Perform backup
        Backup-WmrSystem -SourcePath $script:SourceSystem -BackupPath $script:BackupRoot

        # Verify backup
        Test-WmrBackup -BackupPath $script:BackupRoot
    }

    It "Restores the target system" {
        # Create a dummy file in the target system
        $dummyFile = Join-Path $script:TargetSystem "dummy.txt"
        "Dummy content" | Out-File -FilePath $dummyFile -Force

        # Perform restore
        Restore-WmrSystem -BackupPath $script:BackupRoot -RestorePath $script:RestoreRoot

        # Verify restore
        Test-WmrRestore -RestorePath $script:RestoreRoot
    }
}
