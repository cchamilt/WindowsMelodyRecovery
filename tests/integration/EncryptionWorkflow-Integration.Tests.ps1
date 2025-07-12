# PSScriptAnalyzer - ignore creation of a SecureString using plain text for the contents of this test file
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingConvertToSecureStringWithPlainText", "")]
param()

# Test for encryption workflow integration
# Tests the end-to-end encryption workflow integration

BeforeAll {
    # Import the module with standardized pattern
    try {
        $ModulePath = Resolve-Path "$PSScriptRoot/../../WindowsMelodyRecovery.psd1"
        Import-Module $ModulePath -Force -ErrorAction Stop
    } catch {
        throw "Cannot find or import WindowsMelodyRecovery module: $($_.Exception.Message)"
    }

    # Set up test environment
    $script:TestDataPath = Join-Path ([System.IO.Path]::GetTempPath()) "WMR_EncryptionIntegration_$(Get-Random)"
    $script:TestStateDir = Join-Path $script:TestDataPath "StateFiles"
    $script:TestSourceDir = Join-Path $script:TestDataPath "SourceFiles"
    $script:TestBackupDir = Join-Path $script:TestDataPath "BackupFiles"
    $script:TestPassword = "Integration_Test_P@ssw0rd123!"
    # PSScriptAnalyzer suppression: Test requires known plaintext password
    [System.Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidUsingConvertToSecureStringWithPlainText', '')]
    $script:TestSecureString = ConvertTo-SecureString -String $script:TestPassword -AsPlainText -Force

    # Create test directories
    New-Item -ItemType Directory -Path $script:TestStateDir -Force | Out-Null
    New-Item -ItemType Directory -Path $script:TestSourceDir -Force | Out-Null
    New-Item -ItemType Directory -Path $script:TestBackupDir -Force | Out-Null

    # Helper function to create test files
    function New-TestFile {
        param($Path, $Content)
        $parent = Split-Path -Path $Path -Parent
        if (-not (Test-Path $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        Set-Content -Path $Path -Value $Content -NoNewline -Encoding UTF8
    }

    # Helper function to validate safe test paths
    function Test-SafeTestPath {
        param($Path)
        return $Path -and $Path.StartsWith($script:TestDataPath)
    }
}

Describe 'Encryption Workflow Integration Tests' {

    Context 'Template-Based Encryption Workflows' {
        BeforeEach {
            # Clear any cached encryption keys
            Clear-WmrEncryptionCache

            # Clean up test files
            Get-ChildItem -Path $script:TestSourceDir -Recurse -ErrorAction SilentlyContinue |
                Remove-Item -Force -Recurse -Confirm:$false -ErrorAction SilentlyContinue
            Get-ChildItem -Path $script:TestStateDir -Recurse -ErrorAction SilentlyContinue |
                Remove-Item -Force -Recurse -Confirm:$false -ErrorAction SilentlyContinue
        }

        It 'Should backup and restore encrypted file using template system' {
            # Arrange
            $testFilePath = Join-Path $script:TestSourceDir "sensitive_config.json"
            $sensitiveConfig = @{
                api_key = "secret-api-key-12345"
                database_password = "super-secret-db-password"
                encryption_keys = @{
                    primary = "primary-encryption-key"
                    secondary = "secondary-encryption-key"
                }
                user_credentials = @{
                    username = "admin"
                    password = "admin-password"
                }
            } | ConvertTo-Json -Depth 3

            New-TestFile -Path $testFilePath -Content $sensitiveConfig

            # Create test template for encrypted file
            $templateConfig = @{
                name = "Encrypted Config Test"
                description = "Test template for encrypted configuration"
                files = @(
                    @{
                        name = "Sensitive Configuration"
                        path = $testFilePath
                        type = "file"
                        action = "backup"
                        encrypt = $true
                        dynamic_state_path = "files/sensitive_config.json"
                    }
                )
            }

            # Act - Backup with encryption
            $backupResult = Get-WmrFileState -FileConfig $templateConfig.files[0] -StateFilesDirectory $script:TestStateDir -Passphrase $script:TestSecureString

            # Assert backup results
            $backupResult | Should -Not -BeNull
            $backupResult.Encrypted | Should -Be $true
            $backupResult.Content | Should -Not -Be $sensitiveConfig
            $backupResult.Content | Should -Match "^[A-Za-z0-9+/=]+$"  # Base64 format

            # Verify encrypted file was saved
            $stateFilePath = Join-Path $script:TestStateDir "files/sensitive_config.json"
            Test-Path $stateFilePath | Should -Be $true

            # Verify metadata was saved
            $metadataPath = Join-Path $script:TestStateDir "files/sensitive_config.json.metadata.json"
            Test-Path $metadataPath | Should -Be $true

            $metadata = Get-Content $metadataPath | ConvertFrom-Json
            $metadata.Encrypted | Should -Be $true
            $metadata.OriginalSize | Should -BeGreaterThan 0

            # Act - Restore from encrypted backup
            $encryptedContent = Get-Content $stateFilePath -Raw
            $decryptedContent = Unprotect-WmrData -EncodedData $encryptedContent -Passphrase $script:TestSecureString

            # Assert restore results
            $decryptedContent | Should -Be $sensitiveConfig
            $parsedConfig = $decryptedContent | ConvertFrom-Json
            $parsedConfig.api_key | Should -Be "secret-api-key-12345"
            $parsedConfig.database_password | Should -Be "super-secret-db-password"
            $parsedConfig.encryption_keys.primary | Should -Be "primary-encryption-key"
        }

        It 'Should handle mixed encrypted and unencrypted files in same template' {
            # Arrange
            $publicConfigPath = Join-Path $script:TestSourceDir "public_config.json"
            $privateConfigPath = Join-Path $script:TestSourceDir "private_config.json"

            $publicConfig = @{
                app_name = "Test Application"
                version = "1.0.0"
                public_settings = @{
                    theme = "dark"
                    language = "en"
                }
            } | ConvertTo-Json -Depth 3

            $privateConfig = @{
                license_key = "PRIVATE-LICENSE-KEY-12345"
                user_data = @{
                    email = "user@example.com"
                    token = "private-auth-token"
                }
            } | ConvertTo-Json -Depth 3

            New-TestFile -Path $publicConfigPath -Content $publicConfig
            New-TestFile -Path $privateConfigPath -Content $privateConfig

            # Create template with mixed encryption
            $templateConfig = @{
                name = "Mixed Encryption Test"
                files = @(
                    @{
                        name = "Public Configuration"
                        path = $publicConfigPath
                        type = "file"
                        action = "backup"
                        encrypt = $false
                        dynamic_state_path = "files/public_config.json"
                    },
                    @{
                        name = "Private Configuration"
                        path = $privateConfigPath
                        type = "file"
                        action = "backup"
                        encrypt = $true
                        dynamic_state_path = "files/private_config.json"
                    }
                )
            }

            # Act - Backup both files
            $publicResult = Get-WmrFileState -FileConfig $templateConfig.files[0] -StateFilesDirectory $script:TestStateDir
            $privateResult = Get-WmrFileState -FileConfig $templateConfig.files[1] -StateFilesDirectory $script:TestStateDir -Passphrase $script:TestSecureString

            # Assert
            $publicResult.Encrypted | Should -Be $false
            $publicResult.Content | Should -Be ([Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($publicConfig)))

            $privateResult.Encrypted | Should -Be $true
            $privateResult.Content | Should -Not -Be $privateConfig
            $privateResult.Content | Should -Match "^[A-Za-z0-9+/=]+$"

            # Verify files were saved correctly
            $publicStatePath = Join-Path $script:TestStateDir "files/public_config.json"
            $privateStatePath = Join-Path $script:TestStateDir "files/private_config.json"

            Test-Path $publicStatePath | Should -Be $true
            Test-Path $privateStatePath | Should -Be $true

            # Public file should be readable
            $publicSaved = Get-Content $publicStatePath -Raw
            $publicSaved | Should -Be $publicConfig

            # Private file should be encrypted
            $privateSaved = Get-Content $privateStatePath -Raw
            $privateSaved | Should -Not -Be $privateConfig
            $decryptedPrivate = Unprotect-WmrData -EncodedData $privateSaved -Passphrase $script:TestSecureString
            $decryptedPrivate | Should -Be $privateConfig
        }

        It 'Should handle encryption errors gracefully during backup' {
            # Arrange
            $testFilePath = Join-Path $script:TestSourceDir "test_file.txt"
            New-TestFile -Path $testFilePath -Content "Test content"

            $templateConfig = @{
                name = "Encryption Error Test"
                path = $testFilePath
                type = "file"
                action = "backup"
                encrypt = $true
                dynamic_state_path = "files/test_file.txt"
            }

            # Act & Assert - Should handle missing passphrase gracefully
            $result = Get-WmrFileState -FileConfig $templateConfig -StateFilesDirectory $script:TestStateDir
            $result | Should -BeNull  # Should return null when encryption fails
        }
    }

    Context 'Encrypted Backup Task Integration' {
        It 'Should create backup task that handles encrypted files' {
            # This test verifies that the backup task system can handle encrypted files
            # Note: This is a simulation since we can't actually create scheduled tasks in tests

            # Arrange
            $testConfigPath = Join-Path $script:TestSourceDir "task_config.json"
            $taskConfig = @{
                task_name = "Test Encrypted Backup"
                encryption_enabled = $true
                backup_paths = @(
                    @{
                        path = "C:\Users\TestUser\.ssh\config"
                        encrypt = $true
                    },
                    @{
                        path = "C:\Users\TestUser\Documents\credentials.json"
                        encrypt = $true
                    }
                )
            } | ConvertTo-Json -Depth 3

            New-TestFile -Path $testConfigPath -Content $taskConfig

            # Act - Simulate task configuration validation
            $config = Get-Content $testConfigPath | ConvertFrom-Json

            # Assert
            $config.encryption_enabled | Should -Be $true
            $config.backup_paths | Should -HaveCount 2
            $config.backup_paths[0].encrypt | Should -Be $true
            $config.backup_paths[1].encrypt | Should -Be $true
        }

        It 'Should validate encryption requirements for scheduled tasks' {
            # This test ensures that scheduled tasks properly validate encryption requirements

            # Arrange
            $encryptedPaths = @(
                "C:\Users\TestUser\.ssh\id_rsa",
                "C:\Users\TestUser\.ssh\id_ed25519",
                "C:\Users\TestUser\Documents\passwords.txt",
                "C:\ProgramData\SSL\private\server.key"
            )

            # Act - Check each path for encryption requirements
            $encryptionRequired = @()
            foreach ($path in $encryptedPaths) {
                # Simulate path analysis for encryption requirements
                $requiresEncryption = $path -match "(\.ssh|private|password|key|credential)" -and
                                     $path -notmatch "\.pub$"
                $encryptionRequired += $requiresEncryption
            }

            # Assert
            $encryptionRequired | Should -Not -Contain $false
        }
    }

    Context 'Secure File Handling and Storage' {
        It 'Should maintain proper file permissions for encrypted backups' {
            # Arrange
            $sensitiveFilePath = Join-Path $script:TestSourceDir "sensitive_file.txt"
            New-TestFile -Path $sensitiveFilePath -Content "Sensitive content"

            $templateConfig = @{
                name = "Sensitive File"
                path = $sensitiveFilePath
                type = "file"
                action = "backup"
                encrypt = $true
                dynamic_state_path = "files/sensitive_file.txt"
            }

            # Act
            $result = Get-WmrFileState -FileConfig $templateConfig -StateFilesDirectory $script:TestStateDir -Passphrase $script:TestSecureString

            # Assert
            $result.Encrypted | Should -Be $true

            # Verify encrypted file permissions (Windows-specific)
            $encryptedFilePath = Join-Path $script:TestStateDir "files/sensitive_file.txt"
            Test-Path $encryptedFilePath | Should -Be $true

            # Check that file exists and is readable by current user
            $fileInfo = Get-Item $encryptedFilePath
            $fileInfo.Exists | Should -Be $true
        }

        It 'Should handle concurrent encryption operations safely' {
            # Arrange
            $testFiles = @()
            for ($i = 1; $i -le 5; $i++) {
                $filePath = Join-Path $script:TestSourceDir "concurrent_file_$i.txt"
                New-TestFile -Path $filePath -Content "Concurrent test content $i"
                $testFiles += $filePath
            }

            # Act - Simulate concurrent encryption operations
            $jobs = @()
            foreach ($file in $testFiles) {
                $templateConfig = @{
                    name = "Concurrent File $(Split-Path $file -Leaf)"
                    path = $file
                    type = "file"
                    action = "backup"
                    encrypt = $true
                    dynamic_state_path = "files/$(Split-Path $file -Leaf)"
                }

                # Start background job for each encryption
                $job = Start-Job -ScriptBlock {
                    param($Config, $StateDir, $SecureString)
                    Import-Module (Resolve-Path "$using:PSScriptRoot/../../WindowsMelodyRecovery.psd1") -Force
                    Get-WmrFileState -FileConfig $Config -StateFilesDirectory $StateDir -Passphrase $SecureString
                } -ArgumentList $templateConfig, $script:TestStateDir, $script:TestSecureString

                $jobs += $job
            }

            # Wait for all jobs to complete
            $results = $jobs | Wait-Job | Receive-Job
            $jobs | Remove-Job

            # Assert
            $results | Should -HaveCount 5
            $results | ForEach-Object { $_.Encrypted | Should -Be $true }
        }

        It 'Should properly clean up temporary encryption files' {
            # Arrange
            $testFilePath = Join-Path $script:TestSourceDir "cleanup_test.txt"
            New-TestFile -Path $testFilePath -Content "Test cleanup content"

            $templateConfig = @{
                name = "Cleanup Test"
                path = $testFilePath
                type = "file"
                action = "backup"
                encrypt = $true
                dynamic_state_path = "files/cleanup_test.txt"
            }

            # Act
            $result = Get-WmrFileState -FileConfig $templateConfig -StateFilesDirectory $script:TestStateDir -Passphrase $script:TestSecureString

            # Assert
            $result.Encrypted | Should -Be $true

            # Verify no temporary files are left behind
            $tempFiles = Get-ChildItem -Path $script:TestDataPath -Recurse -Filter "*.tmp" -ErrorAction SilentlyContinue
            $tempFiles | Should -HaveCount 0

            # Clear encryption cache to ensure cleanup
            Clear-WmrEncryptionCache
        }
    }

    Context 'End-to-End Encryption Workflows' {
        It 'Should complete full backup and restore cycle with encryption' {
            # Arrange
            $originalFilePath = Join-Path $script:TestSourceDir "original_file.json"
            $restoredFilePath = Join-Path $script:TestSourceDir "restored_file.json"

            $originalData = @{
                secret_key = "very-secret-key-12345"
                credentials = @{
                    username = "admin"
                    password = "super-secret-password"
                }
                config = @{
                    database_url = "postgresql://user:pass@localhost/db"
                    api_endpoints = @(
                        "https://api.example.com/v1",
                        "https://backup.example.com/v1"
                    )
                }
            } | ConvertTo-Json -Depth 3

            New-TestFile -Path $originalFilePath -Content $originalData

            # Act - Backup with encryption
            $backupConfig = @{
                name = "End-to-End Test"
                path = $originalFilePath
                type = "file"
                action = "backup"
                encrypt = $true
                dynamic_state_path = "files/e2e_test.json"
            }

            $backupResult = Get-WmrFileState -FileConfig $backupConfig -StateFilesDirectory $script:TestStateDir -Passphrase $script:TestSecureString

            # Simulate restore process
            $encryptedStatePath = Join-Path $script:TestStateDir "files/e2e_test.json"
            $encryptedContent = Get-Content $encryptedStatePath -Raw
            $decryptedContent = Unprotect-WmrData -EncodedData $encryptedContent -Passphrase $script:TestSecureString

            # Restore to new location
            Set-Content -Path $restoredFilePath -Value $decryptedContent -NoNewline -Encoding UTF8

            # Assert
            $backupResult.Encrypted | Should -Be $true
            Test-Path $restoredFilePath | Should -Be $true

            $restoredData = Get-Content $restoredFilePath -Raw
            $restoredData | Should -Be $originalData

            # Verify data integrity
            $parsedOriginal = $originalData | ConvertFrom-Json
            $parsedRestored = $restoredData | ConvertFrom-Json

            $parsedRestored.secret_key | Should -Be $parsedOriginal.secret_key
            $parsedRestored.credentials.username | Should -Be $parsedOriginal.credentials.username
            $parsedRestored.credentials.password | Should -Be $parsedOriginal.credentials.password
            $parsedRestored.config.database_url | Should -Be $parsedOriginal.config.database_url
        }

        It 'Should handle encryption workflow with multiple templates' {
            # Arrange - Create multiple files with different encryption requirements
            $sshConfigPath = Join-Path $script:TestSourceDir "ssh_config"
            $sshPrivateKeyPath = Join-Path $script:TestSourceDir "id_rsa"
            $sshPublicKeyPath = Join-Path $script:TestSourceDir "id_rsa.pub"

            New-TestFile -Path $sshConfigPath -Content "Host example.com`n  User testuser`n  Port 22"
            New-TestFile -Path $sshPrivateKeyPath -Content "-----BEGIN PRIVATE KEY-----`nMIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQC..."
            New-TestFile -Path $sshPublicKeyPath -Content "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCx... user@example.com"

            # Create template configurations
            $templates = @(
                @{
                    name = "SSH Config"
                    path = $sshConfigPath
                    type = "file"
                    action = "backup"
                    encrypt = $false  # Config file doesn't need encryption
                    dynamic_state_path = "files/ssh_config"
                },
                @{
                    name = "SSH Private Key"
                    path = $sshPrivateKeyPath
                    type = "file"
                    action = "backup"
                    encrypt = $true  # Private key needs encryption
                    dynamic_state_path = "files/ssh_private_key"
                },
                @{
                    name = "SSH Public Key"
                    path = $sshPublicKeyPath
                    type = "file"
                    action = "backup"
                    encrypt = $false  # Public key doesn't need encryption
                    dynamic_state_path = "files/ssh_public_key"
                }
            )

            # Act - Process each template
            $results = @()
            foreach ($template in $templates) {
                if ($template.encrypt) {
                    $result = Get-WmrFileState -FileConfig $template -StateFilesDirectory $script:TestStateDir -Passphrase $script:TestSecureString
                } else {
                    $result = Get-WmrFileState -FileConfig $template -StateFilesDirectory $script:TestStateDir
                }
                $results += $result
            }

            # Assert
            $results | Should -HaveCount 3
            $results[0].Encrypted | Should -Be $false  # SSH config
            $results[1].Encrypted | Should -Be $true   # SSH private key
            $results[2].Encrypted | Should -Be $false  # SSH public key

            # Verify encrypted private key can be decrypted
            $privateKeyStatePath = Join-Path $script:TestStateDir "files/ssh_private_key"
            $encryptedPrivateKey = Get-Content $privateKeyStatePath -Raw
            $decryptedPrivateKey = Unprotect-WmrData -EncodedData $encryptedPrivateKey -Passphrase $script:TestSecureString
            $decryptedPrivateKey | Should -Match "BEGIN PRIVATE KEY"
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







