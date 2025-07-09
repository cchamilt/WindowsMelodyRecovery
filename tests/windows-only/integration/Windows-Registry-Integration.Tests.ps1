# Windows-Only Integration Tests for Windows Registry Functionality
# These tests MUST run on Windows CI/CD systems only

# Skip all tests if not on Windows
if (-not $IsWindows) {
    Write-Warning "Windows-only integration tests skipped on non-Windows platform"
    return
}

# Skip if not in CI/CD environment (safety check)
if (-not $env:CI -and -not $env:GITHUB_ACTIONS) {
    Write-Warning "Windows-only integration tests skipped outside CI/CD environment for safety"
    return
}

BeforeAll {
    # Import the module
    Import-Module (Resolve-Path "$PSScriptRoot/../../../WindowsMelodyRecovery.psd1") -Force
    
    # Set up test environment
    $script:TestTempDir = Join-Path $env:TEMP "WMR-WindowsRegistry-Integration-Tests"
    if (Test-Path $script:TestTempDir) {
        Remove-Item $script:TestTempDir -Recurse -Force
    }
    New-Item -Path $script:TestTempDir -ItemType Directory -Force | Out-Null
    
    # Create test registry key (safe location in HKCU)
    $script:TestRegistryPath = "HKCU:\SOFTWARE\WMR-Integration-Test"
    if (Test-Path $script:TestRegistryPath) {
        Remove-Item $script:TestRegistryPath -Recurse -Force
    }
    New-Item -Path $script:TestRegistryPath -Force | Out-Null
}

AfterAll {
    # Clean up test environment
    if (Test-Path $script:TestTempDir) {
        Remove-Item $script:TestTempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    # Clean up test registry key
    if (Test-Path $script:TestRegistryPath) {
        Remove-Item $script:TestRegistryPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "Windows Registry Integration Tests" -Tag "Windows", "Integration", "Registry" {
    
    Context "Registry State Backup and Restore" {
        It "Should backup registry values correctly" {
            # Set up test registry values
            Set-ItemProperty -Path $script:TestRegistryPath -Name "TestString" -Value "TestValue"
            Set-ItemProperty -Path $script:TestRegistryPath -Name "TestDWord" -Value 42
            
            $registryConfig = @{
                path = $script:TestRegistryPath
                values = @{
                    "TestString" = "String"
                    "TestDWord" = "DWord"
                }
            }
            
            $result = Get-WmrRegistryState -RegistryConfig $registryConfig -StateFilesDirectory $script:TestTempDir
            
            $result | Should -Not -BeNullOrEmpty
            $result.Path | Should -Be $script:TestRegistryPath
            $result.StateFilePath | Should -Exist
            
            # Verify state file contains expected data
            $stateContent = Get-Content $result.StateFilePath | ConvertFrom-Json
            $stateContent.values.TestString | Should -Be "TestValue"
            $stateContent.values.TestDWord | Should -Be 42
        }
        
        It "Should restore registry values correctly" {
            # Create state file with test data
            $stateData = @{
                path = $script:TestRegistryPath
                values = @{
                    "RestoreString" = "RestoreValue"
                    "RestoreDWord" = 123
                }
            }
            
            $stateFile = Join-Path $script:TestTempDir "registry_restore_test.json"
            $stateData | ConvertTo-Json | Out-File -FilePath $stateFile -Encoding UTF8
            
            $registryConfig = @{
                path = $script:TestRegistryPath
                values = @{
                    "RestoreString" = "String"
                    "RestoreDWord" = "DWord"
                }
            }
            
            Set-WmrRegistryState -RegistryConfig $registryConfig -StateFilesDirectory $script:TestTempDir
            
            # Verify values were restored
            $restoredString = Get-ItemProperty -Path $script:TestRegistryPath -Name "RestoreString" -ErrorAction SilentlyContinue
            $restoredDWord = Get-ItemProperty -Path $script:TestRegistryPath -Name "RestoreDWord" -ErrorAction SilentlyContinue
            
            $restoredString.RestoreString | Should -Be "RestoreValue"
            $restoredDWord.RestoreDWord | Should -Be 123
        }
        
        It "Should handle missing registry keys gracefully" {
            $nonExistentPath = "HKCU:\SOFTWARE\WMR-NonExistent-Test"
            
            $registryConfig = @{
                path = $nonExistentPath
                values = @{
                    "TestValue" = "String"
                }
            }
            
            { Get-WmrRegistryState -RegistryConfig $registryConfig -StateFilesDirectory $script:TestTempDir } | Should -Not -Throw
        }
    }
    
    Context "Registry Template Processing" {
        It "Should process registry template correctly" {
            $template = @{
                metadata = @{
                    name = "registry-test-template"
                    version = "1.0"
                }
                registry = @(
                    @{
                        path = $script:TestRegistryPath
                        values = @{
                            "TemplateString" = "TemplateValue"
                            "TemplateDWord" = 456
                        }
                    }
                )
            }
            
            # Set up initial values
            Set-ItemProperty -Path $script:TestRegistryPath -Name "TemplateString" -Value "TemplateValue"
            Set-ItemProperty -Path $script:TestRegistryPath -Name "TemplateDWord" -Value 456
            
            $result = Invoke-WmrTemplate -Template $template -Action "Backup" -StateFilesDirectory $script:TestTempDir
            
            $result | Should -Not -BeNullOrEmpty
            $result.Success | Should -Be $true
            
            # Verify registry state file was created
            $stateFiles = Get-ChildItem -Path $script:TestTempDir -Filter "registry_*.json"
            $stateFiles | Should -Not -BeNullOrEmpty
        }
        
        It "Should handle registry template restore" {
            # Create state file first
            $stateData = @{
                path = $script:TestRegistryPath
                values = @{
                    "RestoreTemplateString" = "RestoreTemplateValue"
                    "RestoreTemplateDWord" = 789
                }
            }
            
            $stateFile = Join-Path $script:TestTempDir "registry_restore_template_test.json"
            $stateData | ConvertTo-Json | Out-File -FilePath $stateFile -Encoding UTF8
            
            $template = @{
                metadata = @{
                    name = "registry-restore-template"
                    version = "1.0"
                }
                registry = @(
                    @{
                        path = $script:TestRegistryPath
                        values = @{
                            "RestoreTemplateString" = "String"
                            "RestoreTemplateDWord" = "DWord"
                        }
                    }
                )
            }
            
            $result = Invoke-WmrTemplate -Template $template -Action "Restore" -StateFilesDirectory $script:TestTempDir
            
            $result | Should -Not -BeNullOrEmpty
            $result.Success | Should -Be $true
            
            # Verify values were restored
            $restoredString = Get-ItemProperty -Path $script:TestRegistryPath -Name "RestoreTemplateString" -ErrorAction SilentlyContinue
            $restoredDWord = Get-ItemProperty -Path $script:TestRegistryPath -Name "RestoreTemplateDWord" -ErrorAction SilentlyContinue
            
            $restoredString.RestoreTemplateString | Should -Be "RestoreTemplateValue"
            $restoredDWord.RestoreTemplateDWord | Should -Be 789
        }
    }
    
    Context "Registry Privilege Requirements" {
        It "Should identify HKLM operations as requiring admin privileges" {
            $template = @{
                metadata = @{
                    name = "hklm-privilege-test"
                    version = "1.0"
                }
                registry = @(
                    @{
                        path = "HKLM:\SOFTWARE\Test"
                        values = @{
                            "TestValue" = "String"
                        }
                    }
                )
            }
            
            $requirements = Get-WmrPrivilegeRequirements -Template $template
            
            $requirements.RequiresAdmin | Should -Be $true
            $requirements.RegistryAccess | Should -Contain "HKLM"
        }
        
        It "Should identify HKCU operations as not requiring admin privileges" {
            $template = @{
                metadata = @{
                    name = "hkcu-privilege-test"
                    version = "1.0"
                }
                registry = @(
                    @{
                        path = "HKCU:\SOFTWARE\Test"
                        values = @{
                            "TestValue" = "String"
                        }
                    }
                )
            }
            
            $requirements = Get-WmrPrivilegeRequirements -Template $template
            
            $requirements.RequiresAdmin | Should -Be $false
            $requirements.RegistryAccess | Should -Contain "HKCU"
        }
    }
    
    Context "Registry Error Handling" {
        It "Should handle registry access denied gracefully" {
            # Try to access a restricted registry path (if not admin)
            if (-not (Test-WmrAdminPrivilege)) {
                $restrictedPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Test"
                
                $registryConfig = @{
                    path = $restrictedPath
                    values = @{
                        "TestValue" = "String"
                    }
                }
                
                { Get-WmrRegistryState -RegistryConfig $registryConfig -StateFilesDirectory $script:TestTempDir } | Should -Not -Throw
            } else {
                Set-ItResult -Skipped -Because "Current user has admin privileges"
            }
        }
        
        It "Should handle invalid registry paths gracefully" {
            $invalidPath = "HKXX:\Invalid\Path"
            
            $registryConfig = @{
                path = $invalidPath
                values = @{
                    "TestValue" = "String"
                }
            }
            
            { Get-WmrRegistryState -RegistryConfig $registryConfig -StateFilesDirectory $script:TestTempDir } | Should -Not -Throw
        }
    }
}

Describe "Windows Scheduled Tasks Integration Tests" -Tag "Windows", "Integration", "ScheduledTasks" {
    
    Context "Scheduled Task Operations" {
        It "Should detect scheduled task capability" {
            $taskCmdlet = Get-Command "Get-ScheduledTask" -ErrorAction SilentlyContinue
            $taskCmdlet | Should -Not -BeNullOrEmpty
        }
        
        It "Should handle scheduled task queries safely" {
            # This is a safe read-only test
            { Get-ScheduledTask -TaskName "NonExistentTask" -ErrorAction SilentlyContinue } | Should -Not -Throw
        }
        
        It "Should detect Windows Melody Recovery tasks" {
            $wmrTasks = Get-ScheduledTask -TaskPath "\WindowsMelodyRecovery\*" -ErrorAction SilentlyContinue
            # This may be empty if tasks haven't been installed, which is fine
            $wmrTasks | Should -BeOfType [System.Object[]] -Or -BeNullOrEmpty
        }
    }
    
    Context "Task Installation Integration" {
        It "Should handle task installation requirements" {
            # This test verifies the task installation logic without actually installing
            $taskConfig = @{
                name = "WMR-Test-Task"
                description = "Test task for Windows Melody Recovery"
                action = "powershell.exe"
                arguments = "-Command Write-Host 'Test'"
                trigger = @{
                    type = "Daily"
                    time = "02:00"
                }
            }
            
            # Mock the task installation (don't actually install)
            $requirements = Get-WmrPrivilegeRequirements -Template @{
                metadata = @{ name = "task-test" }
                scheduled_tasks = @($taskConfig)
            }
            
            $requirements.RequiresAdmin | Should -Be $true
        }
    }
}

Describe "Windows File System Integration Tests" -Tag "Windows", "Integration", "FileSystem" {
    
    Context "Windows-Specific File Operations" {
        It "Should handle Windows file attributes correctly" {
            $testFile = Join-Path $script:TestTempDir "windows-attributes-test.txt"
            "test content" | Out-File -FilePath $testFile -Encoding UTF8
            
            # Set Windows-specific attributes
            Set-ItemProperty -Path $testFile -Name Attributes -Value "ReadOnly,Hidden"
            
            $fileConfig = @{
                path = $testFile
                preserve_attributes = $true
                encrypt = $false
            }
            
            $result = Get-WmrFileState -FileConfig $fileConfig -StateFilesDirectory $script:TestTempDir
            
            $result | Should -Not -BeNullOrEmpty
            $result.Attributes | Should -Match "ReadOnly"
            $result.Attributes | Should -Match "Hidden"
        }
        
        It "Should handle Windows file permissions correctly" {
            $testFile = Join-Path $script:TestTempDir "windows-permissions-test.txt"
            "test content" | Out-File -FilePath $testFile -Encoding UTF8
            
            $fileConfig = @{
                path = $testFile
                preserve_permissions = $true
                encrypt = $false
            }
            
            $result = Get-WmrFileState -FileConfig $fileConfig -StateFilesDirectory $script:TestTempDir
            
            $result | Should -Not -BeNullOrEmpty
            $result.Permissions | Should -Not -BeNullOrEmpty
        }
        
        It "Should handle Windows junction points and symbolic links" {
            $sourceDir = Join-Path $script:TestTempDir "source-directory"
            $junctionDir = Join-Path $script:TestTempDir "junction-directory"
            
            New-Item -Path $sourceDir -ItemType Directory -Force | Out-Null
            "test content" | Out-File -FilePath (Join-Path $sourceDir "test.txt") -Encoding UTF8
            
            # Create junction point (requires admin on some systems)
            try {
                cmd /c mklink /J "$junctionDir" "$sourceDir" 2>$null
                
                if (Test-Path $junctionDir) {
                    $fileConfig = @{
                        path = $junctionDir
                        preserve_links = $true
                        encrypt = $false
                    }
                    
                    $result = Get-WmrFileState -FileConfig $fileConfig -StateFilesDirectory $script:TestTempDir
                    
                    $result | Should -Not -BeNullOrEmpty
                    $result.IsJunction | Should -Be $true
                }
            } catch {
                Set-ItResult -Skipped -Because "Could not create junction point (may require admin privileges)"
            }
        }
    }
    
    Context "Windows Path Handling" {
        It "Should handle Windows UNC paths correctly" {
            # Test UNC path handling (without actually accessing network)
            $uncPath = "\\localhost\C$\Windows"
            
            $pathInfo = Convert-WmrPath -Path $uncPath
            
            $pathInfo.Type | Should -Be "File"
            $pathInfo.Path | Should -Be $uncPath
        }
        
        It "Should handle Windows long paths correctly" {
            $longPath = "C:\" + ("a" * 200) + "\test.txt"
            
            $pathInfo = Convert-WmrPath -Path $longPath
            
            $pathInfo.Type | Should -Be "File"
            $pathInfo.Path | Should -Be $longPath
        }
        
        It "Should handle Windows drive letters correctly" {
            @("C:", "D:", "E:") | ForEach-Object {
                $drivePath = "$_\test\path"
                $pathInfo = Convert-WmrPath -Path $drivePath
                
                $pathInfo.Type | Should -Be "File"
                $pathInfo.Path | Should -Be $drivePath
            }
        }
    }
} 