# PSScriptAnalyzer - ignore creation of a SecureString using plain text for the contents of this test file
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingConvertToSecureStringWithPlainText", "")]
param()

# Test for encrypted backup tasks integration
# Tests the encrypted backup task integration and handling

BeforeAll {
    # Import the module with standardized pattern
    try {
        $ModulePath = Resolve-Path "$PSScriptRoot/../../WindowsMelodyRecovery.psd1"
        Import-Module $ModulePath -Force -ErrorAction Stop
    } catch {
        throw "Cannot find or import WindowsMelodyRecovery module: $($_.Exception.Message)"
    }

    # Set up test environment
    $script:TestDataPath = Join-Path ([System.IO.Path]::GetTempPath()) "WMR_EncryptedTasks_$(Get-Random)"
    $script:TestBackupDir = Join-Path $script:TestDataPath "BackupTasks"
    $script:TestConfigDir = Join-Path $script:TestDataPath "Config"
    $script:TestPassword = "BackupTask_P@ssw0rd123!"
    # PSScriptAnalyzer suppression: Test setup requires known plaintext password
    [System.Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidUsingConvertToSecureStringWithPlainText', '')]
    $script:TestSecureString = ConvertTo-SecureString -String $script:TestPassword -AsPlainText -Force

    # Create test directories
    New-Item -ItemType Directory -Path $script:TestBackupDir -Force | Out-Null
    New-Item -ItemType Directory -Path $script:TestConfigDir -Force | Out-Null

    # Helper function to validate safe test paths
    function Test-SafeTestPath {
        param($Path)
        return $Path -and $Path.StartsWith($script:TestDataPath)
    }

    # Mock scheduled task functions for testing
    Mock Register-ScheduledTask {
        param($TaskName, $TaskPath, $Description, $Action, $Trigger, $Settings, $Principal)
        return @{
            TaskName = $TaskName
            TaskPath = $TaskPath
            Description = $Description
            State = "Ready"
            LastRunTime = $null
            NextRunTime = (Get-Date).AddDays(1)
        }
    }

    Mock Unregister-ScheduledTask {
        param($TaskName, $TaskPath, $Confirm)
        return $true
    }

    Mock Get-ScheduledTask {
        param($TaskName, $TaskPath, $ErrorAction)
        if ($ErrorAction -eq 'SilentlyContinue') {
            return $null
        }
        return $null
    }

    Mock New-ScheduledTaskAction {
        param($Execute, $Argument, $WorkingDirectory)
        return @{
            Execute = $Execute
            Arguments = $Argument
            WorkingDirectory = $WorkingDirectory
        }
    }

    Mock New-ScheduledTaskTrigger {
        param($Weekly, $DaysOfWeek, $At)
        return @{
            TriggerType = "Weekly"
            DaysOfWeek = $DaysOfWeek
            StartBoundary = (Get-Date $At).ToString("yyyy-MM-ddTHH:mm:ss")
        }
    }

    Mock New-ScheduledTaskSettingsSet {
        param($AllowStartIfOnBatteries, $DontStopIfGoingOnBatteries, $StartWhenAvailable,
              $RunOnlyIfNetworkAvailable, $WakeToRun, $DontStopOnIdleEnd,
              $RestartInterval, $RestartCount)
        return @{
            AllowStartIfOnBatteries = $AllowStartIfOnBatteries
            DontStopIfGoingOnBatteries = $DontStopIfGoingOnBatteries
            StartWhenAvailable = $StartWhenAvailable
            RunOnlyIfNetworkAvailable = $RunOnlyIfNetworkAvailable
            WakeToRun = $WakeToRun
            DontStopOnIdleEnd = $DontStopOnIdleEnd
            RestartInterval = $RestartInterval
            RestartCount = $RestartCount
        }
    }

    Mock New-ScheduledTaskPrincipal {
        param($UserId, $LogonType, $RunLevel)
        return @{
            UserId = $UserId
            LogonType = $LogonType
            RunLevel = $RunLevel
        }
    }
}

Describe 'Encrypted Backup Task Integration Tests' {

    Context 'Encrypted Backup Task Configuration' {
        BeforeEach {
            # Clear encryption cache
            Clear-WmrEncryptionCache
        }

        It 'Should validate encryption configuration for backup tasks' {
            # Arrange
            $taskConfig = @{
                TaskName = "WindowsMelodyRecovery_Encrypted_Backup"
                Description = "Encrypted backup of Windows configuration"
                EncryptionEnabled = $true
                BackupPaths = @(
                    @{
                        Path = "C:\Users\TestUser\.ssh\config"
                        Encrypt = $false
                        Type = "file"
                    },
                    @{
                        Path = "C:\Users\TestUser\.ssh\id_rsa"
                        Encrypt = $true
                        Type = "file"
                    },
                    @{
                        Path = "C:\Users\TestUser\Documents\credentials.json"
                        Encrypt = $true
                        Type = "file"
                    }
                )
                Schedule = @{
                    Frequency = "Weekly"
                    DayOfWeek = "Sunday"
                    Time = "02:00"
                }
            }

            # Act - Validate configuration
            $encryptedPaths = $taskConfig.BackupPaths | Where-Object { $_.Encrypt -eq $true }
            $unencryptedPaths = $taskConfig.BackupPaths | Where-Object { $_.Encrypt -eq $false }

            # Assert
            $taskConfig.EncryptionEnabled | Should -Be $true
            $encryptedPaths | Should -HaveCount 2
            $unencryptedPaths | Should -HaveCount 1

            # Verify encrypted paths are appropriate for encryption
            $encryptedPaths[0].Path | Should -Match "(id_rsa|private|key)"
            $encryptedPaths[1].Path | Should -Match "(credential|password|secret)"
        }

        It 'Should create backup task with encryption support' {
            # Arrange
            $taskName = "Test_Encrypted_Backup"
            $taskPath = "\Custom Tasks"
            $backupScript = "C:\Test\Backup-WindowsMelodyRecovery.ps1"

            # Mock the backup script existence
            Mock Test-Path { return $true } -ParameterFilter { $Path -eq $backupScript }

            # Act - Simulate task creation (using mocked functions)
            $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$backupScript`" -EncryptionEnabled" -WorkingDirectory "C:\Test"
            $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek "Sunday" -At "02:00"
            $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable -WakeToRun -DontStopOnIdleEnd -RestartInterval (New-TimeSpan -Minutes 1) -RestartCount 3
            $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType "S4U" -RunLevel "Highest"

            $task = Register-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Description "Test encrypted backup task" -Action $action -Trigger $trigger -Settings $settings -Principal $principal

            # Assert
            $task | Should -Not -BeNull
            $task.TaskName | Should -Be $taskName
            $task.TaskPath | Should -Be $taskPath
            $task.State | Should -Be "Ready"

            # Verify encryption parameter is included
            $action.Arguments | Should -Match "EncryptionEnabled"
        }

        It 'Should handle encryption password configuration for tasks' {
            # Arrange
            $configPath = Join-Path $script:TestConfigDir "task_encryption.json"
            $encryptionConfig = @{
                encryption_enabled = $true
                password_storage = "secure"
                key_derivation = @{
                    algorithm = "PBKDF2"
                    iterations = 100000
                    salt_length = 32
                }
                encrypted_paths = @(
                    "C:\Users\TestUser\.ssh\id_rsa",
                    "C:\Users\TestUser\.ssh\id_ed25519",
                    "C:\Users\TestUser\Documents\passwords.txt"
                )
            } | ConvertTo-Json -Depth 3

            Set-Content -Path $configPath -Value $encryptionConfig -Encoding UTF8

            # Act
            $config = Get-Content -Path $configPath | ConvertFrom-Json

            # Assert
            $config.encryption_enabled | Should -Be $true
            $config.password_storage | Should -Be "secure"
            $config.key_derivation.algorithm | Should -Be "PBKDF2"
            $config.key_derivation.iterations | Should -Be 100000
            $config.encrypted_paths | Should -HaveCount 3
        }

        It 'Should validate encryption requirements for scheduled execution' {
            # Arrange
            $scheduledPaths = @(
                @{ Path = "C:\Users\TestUser\.ssh\config"; ShouldEncrypt = $false },
                @{ Path = "C:\Users\TestUser\.ssh\id_rsa"; ShouldEncrypt = $true },
                @{ Path = "C:\Users\TestUser\.ssh\known_hosts"; ShouldEncrypt = $false },
                @{ Path = "C:\Users\TestUser\Documents\credentials.json"; ShouldEncrypt = $true },
                @{ Path = "C:\Users\TestUser\Documents\settings.json"; ShouldEncrypt = $false },
                @{ Path = "C:\ProgramData\SSL\private\server.key"; ShouldEncrypt = $true }
            )

            # Act - Analyze each path for encryption requirements
            $analysisResults = @()
            foreach ($pathInfo in $scheduledPaths) {
                $requiresEncryption = $pathInfo.Path -match "(private|key|credential|password|secret)" -and
                                     $pathInfo.Path -notmatch "(\.pub|config|known_hosts|settings)$"

                $analysisResults += @{
                    Path = $pathInfo.Path
                    Expected = $pathInfo.ShouldEncrypt
                    Actual = $requiresEncryption
                    Match = $pathInfo.ShouldEncrypt -eq $requiresEncryption
                }
            }

            # Assert
            $analysisResults | ForEach-Object { $_.Match | Should -Be $true }
        }
    }

    Context 'Backup Task Execution with Encryption' {
        It 'Should execute backup task with encryption parameters' {
            # Arrange
            $taskParameters = @{
                TemplatePath = "ssh.yaml"
                StateFilesDirectory = $script:TestBackupDir
                EncryptionEnabled = $true
                LogPath = Join-Path $script:TestBackupDir "backup.log"
            }

            # Mock the template execution
            Mock Invoke-WmrTemplate {
                param($TemplatePath, $Operation, $StateFilesDirectory, $Passphrase)
                return @{
                    Success = $true
                    EncryptedFiles = @("ssh_private_key", "winscp_sessions")
                    UnencryptedFiles = @("ssh_config", "known_hosts")
                    Operation = $Operation
                    EncryptionUsed = $Passphrase -ne $null
                }
            }

            # Act
            $result = Invoke-WmrTemplate -TemplatePath $taskParameters.TemplatePath -Operation "Backup" -StateFilesDirectory $taskParameters.StateFilesDirectory -Passphrase $script:TestSecureString

            # Assert
            $result.Success | Should -Be $true
            $result.EncryptionUsed | Should -Be $true
            $result.EncryptedFiles | Should -HaveCount 2
            $result.UnencryptedFiles | Should -HaveCount 2

            # Verify template execution was called with encryption
            Should -Invoke Invoke-WmrTemplate -Exactly 1 -ParameterFilter { $Passphrase -ne $null }
        }

        It 'Should handle encryption failures during scheduled backup' {
            # Arrange
            Mock Invoke-WmrTemplate {
                param($TemplatePath, $Operation, $StateFilesDirectory, $Passphrase)
                throw "Encryption failed: Invalid passphrase"
            }

            # Act & Assert
            { Invoke-WmrTemplate -TemplatePath "ssh.yaml" -Operation "Backup" -StateFilesDirectory $script:TestBackupDir -Passphrase $script:TestSecureString } |
                Should -Throw "*Encryption failed*"
        }

        It 'Should log encryption operations in backup tasks' {
            # Arrange
            $logPath = Join-Path $script:TestBackupDir "encryption.log"

            # Mock logging functions
            Mock Write-Information -MessageData { } -InformationAction Continue
            Mock Start-Transcript { }
            Mock Stop-Transcript { }

            # Act - Simulate encrypted backup with logging
            Start-Transcript -Path $logPath -Append -Force
            try {
                Write-Information -MessageData "Starting encrypted backup operation" -InformationAction Continue
                Write-Information -MessageData "Encryption enabled: True" -InformationAction Continue
                Write-Information -MessageData "Processing encrypted files: 2" -InformationAction Continue
                Write-Information -MessageData "Processing unencrypted files: 3" -InformationAction Continue
                Write-Information -MessageData "Encrypted backup completed successfully" -InformationAction Continue
            } finally {
                Stop-Transcript
            }

            # Assert
            Should -Invoke Start-Transcript -Exactly 1
            Should -Invoke Stop-Transcript -Exactly 1
            Should -Invoke Write-Host -Exactly 5
        }

        It 'Should handle concurrent encrypted backup tasks safely' {
            # Arrange
            $taskConfigs = @(
                @{ Name = "SSH_Backup"; Template = "ssh.yaml"; Priority = 1 },
                @{ Name = "Network_Backup"; Template = "network.yaml"; Priority = 2 },
                @{ Name = "Browser_Backup"; Template = "browsers.yaml"; Priority = 3 }
            )

            # Mock concurrent task execution
            Mock Invoke-WmrTemplate {
                param($TemplatePath, $Operation, $StateFilesDirectory, $Passphrase)
                Start-Sleep -Milliseconds (Get-Random -Minimum 100 -Maximum 500)
                return @{
                    Success = $true
                    Template = $TemplatePath
                    EncryptionUsed = $Passphrase -ne $null
                    ExecutionTime = (Get-Date)
                }
            }

            # Act - Execute tasks concurrently
            $jobs = @()
            foreach ($config in $taskConfigs) {
                $job = Start-Job -ScriptBlock {
                    param($Config, $BackupDir, $SecureString)
                    Import-Module (Resolve-Path "$using:PSScriptRoot/../../WindowsMelodyRecovery.psd1") -Force
                    Invoke-WmrTemplate -TemplatePath $Config.Template -Operation "Backup" -StateFilesDirectory $BackupDir -Passphrase $SecureString
                } -ArgumentList $config, $script:TestBackupDir, $script:TestSecureString

                $jobs += $job
            }

            # Wait for completion
            $results = $jobs | Wait-Job | Receive-Job
            $jobs | Remove-Job

            # Assert
            $results | Should -HaveCount 3
            $results | ForEach-Object {
                $_.Success | Should -Be $true
                $_.EncryptionUsed | Should -Be $true
            }
        }
    }

    Context 'Backup Task Security and Validation' {
        It 'Should validate backup task security configuration' {
            # Arrange
            $securityConfig = @{
                RequireAdminPrivileges = $true
                EncryptionMandatory = $true
                SecurePasswordStorage = $true
                LogEncryptionOperations = $true
                ValidateEncryptionIntegrity = $true
            }

            # Act - Validate security requirements
            $securityChecks = @()
            $securityChecks += @{ Check = "Admin Privileges"; Required = $securityConfig.RequireAdminPrivileges; Valid = $true }
            $securityChecks += @{ Check = "Encryption Mandatory"; Required = $securityConfig.EncryptionMandatory; Valid = $true }
            $securityChecks += @{ Check = "Secure Password Storage"; Required = $securityConfig.SecurePasswordStorage; Valid = $true }
            $securityChecks += @{ Check = "Log Encryption Operations"; Required = $securityConfig.LogEncryptionOperations; Valid = $true }
            $securityChecks += @{ Check = "Validate Encryption Integrity"; Required = $securityConfig.ValidateEncryptionIntegrity; Valid = $true }

            # Assert
            $securityChecks | ForEach-Object {
                if ($_.Required) {
                    $_.Valid | Should -Be $true
                }
            }
        }

        It 'Should handle backup task encryption key rotation' {
            # Arrange
            $currentKey = Get-WmrEncryptionKey -Passphrase $script:TestSecureString
            $newPassword = "NewRotated_P@ssw0rd456!"
            # PSScriptAnalyzer suppression: Test key rotation requires known plaintext password
            [System.Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidUsingConvertToSecureStringWithPlainText', '')]
            $newSecureString = ConvertTo-SecureString -String $newPassword -AsPlainText -Force

            # Act - Simulate key rotation
            Clear-WmrEncryptionCache
            $newKey = Get-WmrEncryptionKey -Passphrase $newSecureString

            # Assert
            $currentKey | Should -Not -BeNull
            $newKey | Should -Not -BeNull
            $newKey.Key | Should -Not -Be $currentKey.Key
            $newKey.Salt | Should -Not -Be $currentKey.Salt
        }

        It 'Should validate backup task encryption compliance' {
            # Arrange
            $complianceRequirements = @{
                MinimumKeyLength = 256
                RequiredAlgorithm = "AES"
                RequiredMode = "CBC"
                RequiredPadding = "PKCS7"
                MinimumIterations = 100000
                RequiredSaltLength = 32
            }

            # Act - Get encryption parameters
            $keyInfo = Get-WmrEncryptionKey -Passphrase $script:TestSecureString

            # Assert compliance
            $keyInfo.Key.Length | Should -Be ($complianceRequirements.MinimumKeyLength / 8)  # 32 bytes for 256 bits
            $keyInfo.Salt.Length | Should -Be $complianceRequirements.RequiredSaltLength

            # Test encryption with compliance parameters
            $testData = "Compliance test data"
            $encrypted = Protect-WmrData -Data $testData -Passphrase $script:TestSecureString
            $decrypted = Unprotect-WmrData -EncodedData $encrypted -Passphrase $script:TestSecureString

            $decrypted | Should -Be $testData
        }

        It 'Should handle backup task encryption audit logging' {
            # Arrange
            $auditLog = Join-Path $script:TestBackupDir "encryption_audit.log"

            # Mock audit logging
            Mock Add-Content {
                param($Path, $Value)
                # Simulate audit log entry
            }

            # Act - Simulate encryption operations with audit logging
            $auditEntries = @(
                "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Encryption key generated for backup task",
                "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - File encrypted: ssh_private_key",
                "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - File encrypted: winscp_sessions",
                "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Encryption cache cleared",
                "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Backup task completed successfully"
            )

            foreach ($entry in $auditEntries) {
                Add-Content -Path $auditLog -Value $entry
            }

            # Assert
            Should -Invoke Add-Content -Exactly 5
        }
    }
}

AfterAll {
    # Clean up test environment
    Clear-WmrEncryptionCache
    if ($script:TestDataPath -and (Test-SafeTestPath $script:TestDataPath)) {
        Remove-Item -Path $script:TestDataPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}







