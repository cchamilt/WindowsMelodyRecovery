# tests/integration/TemplateIntegration.Tests.ps1

Describe "Template Integration Tests" {

    BeforeAll {
        # Import the module with standardized pattern
        try {
            $ModulePath = Resolve-Path "$PSScriptRoot/../../WindowsMelodyRecovery.psd1"
            Import-Module $ModulePath -Force -ErrorAction Stop
        } catch {
            throw "Cannot find or import WindowsMelodyRecovery module: $($_.Exception.Message)"
        }

        # Define paths
        $script:ProjectPath = (Get-Item -Path $PSScriptRoot).Parent.Parent.FullName
        $script:InvokeTemplatePath = Join-Path $script:ProjectPath "Private\Core\InvokeWmrTemplate.ps1"
        $script:DisplayTemplatePath = Join-Path $script:ProjectPath "Templates\System\display.yaml"
        $script:WingetAppsTemplatePath = Join-Path $script:ProjectPath "Templates\System\winget-apps.yaml"
        $script:BackupBaseDir = Join-Path $script:ProjectPath "test-backups\integration"
        $script:RestoreBaseDir = Join-Path $script:ProjectPath "test-restore\integration"
        $script:TempInstalledAppsDir = Join-Path $script:ProjectPath "Temp\InstalledAppsSimulation"

        # Clean up previous test runs
        Remove-Item -Path $script:BackupBaseDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $script:RestoreBaseDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $script:TempInstalledAppsDir -Recurse -Force -ErrorAction SilentlyContinue

        # Ensure directories exist
        New-Item -ItemType Directory -Path $script:BackupBaseDir -Force | Out-Null
        New-Item -ItemType Directory -Path $script:RestoreBaseDir -Force | Out-Null
        New-Item -ItemType Directory -Path $script:TempInstalledAppsDir -Force | Out-Null

        # Dot-source the main InvokeWmrTemplate function
        . $script:InvokeTemplatePath

        # Mock external commands for application tests
        Mock Invoke-Expression {
            param($Command)
            if ($Command -match "^winget list") {
                return @"
Name                 Id               Version
------------------------------------------------
Microsoft Edge       Microsoft.Edge   100.0.1
Windows Terminal     Microsoft.WindowsTerminal 1.0.0
MyDummyApp           Test.DummyApp    9.9.9
"@
            } elseif ($Command -match "^winget install") {
                # Simulate installation by creating a dummy file
                $idMatch = $Command | Select-String -Pattern '--id "(?<Id>[^"]+)"' | Select-Object -ExpandProperty Matches | Select-Object -ExpandProperty Groups | Where-Object Name -eq "Id"
                if ($idMatch) {
                    Set-Content -Path (Join-Path $script:TempInstalledAppsDir "$($idMatch.Value).installed") -Value "Installed" -Force
                }
                return "Installation successful"
            } elseif ($Command -match "^winget uninstall") {
                 # Simulate uninstallation by removing a dummy file
                $idMatch = $Command | Select-String -Pattern '--id "(?<Id>[^"]+)"' | Select-Object -ExpandProperty Matches | Select-Object -ExpandProperty Groups | Where-Object Name -eq "Id"
                if ($idMatch) {
                    Remove-Item -Path (Join-Path $script:TempInstalledAppsDir "$($idMatch.Value).installed") -ErrorAction SilentlyContinue
                }
                return "Uninstallation successful"
            }
             # Mock for Get-DisplayResolution from display.yaml prerequisite
            elseif ($Command -like "Get-Command Get-DisplayResolution*") {
                # Simulate that the module/command exists for the prerequisite check to pass
                return ""
            }
             elseif ($Command -match "Get-DisplayResolution") {
                return "1920x1080"
            }
             else {
                throw "Unexpected mocked command: $Command"
            }
        }
    }

    AfterAll {
        # Unmock functions
        [Pester.Mocking.Mock]::UnmockAll()
        # Clean up after all tests
        Remove-Item -Path $script:BackupBaseDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $script:RestoreBaseDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $script:TempInstalledAppsDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path (Join-Path $script:ProjectPath "Temp") -Recurse -Force -ErrorAction SilentlyContinue

        # Revert registry changes made during tests
        Remove-Item -Path "HKCU:\Control Panel\Desktop\Test" -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context "Backup Operations" {
        It "should successfully backup display settings" {
            $timestamp = (Get-Date -Format "yyyyMMdd_HHmmss")
            $currentBackupDir = Join-Path $script:BackupBaseDir "display_backup_$timestamp"

            # Ensure a dummy registry value exists before backup
            Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "DisplayOrientation" -Value "99" -Force | Out-Null
            Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "ResolutionHeight" -Value "1080" -Force | Out-Null
            Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "ResolutionWidth" -Value "1920" -Force | Out-Null

            { Invoke-WmrTemplate -TemplatePath $script:DisplayTemplatePath -Operation "Backup" -StateFilesDirectory $currentBackupDir } | Should -Not -Throw

            # Verify state files are created
            (Test-Path (Join-Path $currentBackupDir "system_settings\display_orientation.json")) | Should -Be $true
            (Test-Path (Join-Path $currentBackupDir "system_settings\resolution_height.json")) | Should -Be $true
            (Test-Path (Join-Path $currentBackupDir "system_settings\resolution_width.json")) | Should -Be $true

            # Verify content of state files
            $orientationState = (Get-Content -Path (Join-Path $currentBackupDir "system_settings\display_orientation.json") -Raw | ConvertFrom-Json)
            $orientationState.Value | Should -Be "99"
        }

        It "should successfully backup winget application list" {
            $timestamp = (Get-Date -Format "yyyyMMdd_HHmmss")
            $currentBackupDir = Join-Path $script:BackupBaseDir "winget_backup_$timestamp"

            { Invoke-WmrTemplate -TemplatePath $script:WingetAppsTemplatePath -Operation "Backup" -StateFilesDirectory $currentBackupDir } | Should -Not -Throw

            # Verify state file is created
            (Test-Path (Join-Path $currentBackupDir "applications\winget-installed.json")) | Should -Be $true

            # Verify content of state file
            $appList = (Get-Content -Path (Join-Path $currentBackupDir "applications\winget-installed.json") -Raw | ConvertFrom-Json)
            $appList.Count | Should -Be 3
            $appList | Where-Object Id -eq "Microsoft.Edge" | Should -Not -BeNull
            $appList | Where-Object Id -eq "Test.DummyApp" | Should -Not -BeNull
        }
    }

    Context "Restore Operations" {
        It "should successfully restore display settings" {
            # Simulate a backup first
            $backupTimestamp = (Get-Date -Format "yyyyMMdd_HHmmss")
            $mockBackupDir = Join-Path $script:BackupBaseDir "restore_display_mock_$backupTimestamp"
            New-Item -ItemType Directory -Path $mockBackupDir -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $mockBackupDir "system_settings") -Force | Out-Null

            # Create dummy state files that would have been generated by backup
            @{
                Name = "Display Orientation"
                Path = "HKCU:\Control Panel\Desktop"
                KeyName = "DisplayOrientation"
                Value = "1"
            } | ConvertTo-Json -Compress | Set-Content -Path (Join-Path $mockBackupDir "system_settings\display_orientation.json") -Encoding Utf8

            @{
                Name = "Resolution Height"
                Path = "HKCU:\Control Panel\Desktop"
                KeyName = "ResolutionHeight"
                Value = "1024"
            } | ConvertTo-Json -Compress | Set-Content -Path (Join-Path $mockBackupDir "system_settings\resolution_height.json") -Encoding Utf8

            @{
                Name = "Resolution Width"
                Path = "HKCU:\Control Panel\Desktop"
                KeyName = "ResolutionWidth"
                Value = "768"
            } | ConvertTo-Json -Compress | Set-Content -Path (Join-Path $mockBackupDir "system_settings\resolution_width.json") -Encoding Utf8

            # Ensure the registry values are different before restore
            Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "DisplayOrientation" -Value "999" -Force | Out-Null
            Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "ResolutionHeight" -Value "1111" -Force | Out-Null
            Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "ResolutionWidth" -Value "2222" -Force | Out-Null

            # Perform restore
            { Invoke-WmrTemplate -TemplatePath $script:DisplayTemplatePath -Operation "Restore" -StateFilesDirectory $mockBackupDir } | Should -Not -Throw

            # Verify registry values are restored
            (Get-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "DisplayOrientation").DisplayOrientation | Should -Be "1"
            (Get-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "ResolutionHeight").ResolutionHeight | Should -Be "1024"
            (Get-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "ResolutionWidth").ResolutionWidth | Should -Be "768"
        }

        It "should successfully restore winget applications" {
            # Simulate a backup first by creating the state file
            $backupTimestamp = (Get-Date -Format "yyyyMMdd_HHmmss")
            $mockBackupDir = Join-Path $script:BackupBaseDir "restore_winget_mock_$backupTimestamp"
            New-Item -ItemType Directory -Path $mockBackupDir -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $mockBackupDir "applications") -Force | Out-Null

            $appListJson = '[{"Name":"TestApp1","Id":"Test.App1","Version":"1.0.0"},{"Name":"TestApp2","Id":"Test.App2","Version":"2.0.0"}]'
            $appListJson | Set-Content -Path (Join-Path $mockBackupDir "applications\winget-installed.json") -Encoding Utf8

            # Ensure no dummy app files exist before restore
            Remove-Item -Path (Join-Path $script:TempInstalledAppsDir "Test.App1.installed") -ErrorAction SilentlyContinue
            Remove-Item -Path (Join-Path $script:TempInstalledAppsDir "Test.App2.installed") -ErrorAction SilentlyContinue

            # Perform restore
            { Invoke-WmrTemplate -TemplatePath $script:WingetAppsTemplatePath -Operation "Restore" -StateFilesDirectory $mockBackupDir } | Should -Not -Throw

            # Verify simulation of installation
            (Test-Path (Join-Path $script:TempInstalledAppsDir "Test.App1.installed")) | Should -Be $true
            (Test-Path (Join-Path $script:TempInstalledAppsDir "Test.App2.installed")) | Should -Be $true
        }
    }

    Context "Prerequisite Failures" {
        It "should fail backup if a fail_backup prerequisite is not met" {
            # Temporarily modify display.yaml to have a failing prerequisite
            $originalDisplayTemplate = Get-Content -Path $script:DisplayTemplatePath -Raw
            $failingPrereqTemplateContent = $originalDisplayTemplate -replace 'expected_output: "Module exists"' , 'expected_output: "NonExistentOutput"'
            $failingPrereqTemplateContent | Set-Content -Path $script:DisplayTemplatePath -Encoding Utf8

            $timestamp = (Get-Date -Format "yyyyMMdd_HHmmss")
            $currentBackupDir = Join-Path $script:BackupBaseDir "failing_prereq_backup_$timestamp"

            { Invoke-WmrTemplate -TemplatePath $script:DisplayTemplatePath -Operation "Backup" -StateFilesDirectory $currentBackupDir } | Should -Throw "Prerequisites not met for Backup operation. Aborting."

            # Revert template changes
            $originalDisplayTemplate | Set-Content -Path $script:DisplayTemplatePath -Encoding Utf8
        }
    }
}





