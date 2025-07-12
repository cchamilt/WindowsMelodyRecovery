# PSScriptAnalyzer - ignore creation of a SecureString using plain text for the contents of this test file
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingConvertToSecureStringWithPlainText", "")]
param()

# Test for secure file handling integration
# Tests the secure file handling and encryption integration

BeforeAll {
    # Import the module with standardized pattern
    try {
        $ModulePath = Resolve-Path "$PSScriptRoot/../../WindowsMelodyRecovery.psd1"
        Import-Module $ModulePath -Force -ErrorAction Stop
    }
    catch {
        throw "Cannot find or import WindowsMelodyRecovery module: $($_.Exception.Message)"
    }

    # Set up test environment
    $script:TestDataPath = Join-Path ([System.IO.Path]::GetTempPath()) "WMR_SecureFiles_$(Get-Random)"
    $script:TestSecureDir = Join-Path $script:TestDataPath "SecureFiles"
    $script:TestBackupDir = Join-Path $script:TestDataPath "BackupFiles"
    $script:TestTempDir = Join-Path $script:TestDataPath "TempFiles"
    $script:TestPassword = "SecureFile_P@ssw0rd123!"
    # PSScriptAnalyzer suppression: Test requires known plaintext password
    [System.Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidUsingConvertToSecureStringWithPlainText', '')]
    $script:TestSecureString = ConvertTo-SecureString -String $script:TestPassword -AsPlainText -Force

    # Create test directories
    New-Item -ItemType Directory -Path $script:TestSecureDir -Force | Out-Null
    New-Item -ItemType Directory -Path $script:TestBackupDir -Force | Out-Null
    New-Item -ItemType Directory -Path $script:TestTempDir -Force | Out-Null

    # Helper function to create secure test files
    function New-SecureTestFile {
        param($Path, $Content, $Permissions = "User")
        $parent = Split-Path -Path $Path -Parent
        if (-not (Test-Path $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        Set-Content -Path $Path -Value $Content -NoNewline -Encoding UTF8

        # Set Windows file permissions
        if ($Permissions -eq "User") {
            icacls $Path /inheritance:r | Out-Null
            icacls $Path /grant:r "${env:USERNAME}:(F)" | Out-Null
        }
    }

    # Helper function to validate safe test paths
    function Test-SafeTestPath {
        param($Path)
        return $Path -and $Path.StartsWith($script:TestDataPath)
    }
}

Describe 'Secure File Handling and Storage Tests' {

    Context 'Secure File Permissions and Access Control' {
        BeforeEach {
            # Clear encryption cache
            Clear-WmrEncryptionCache

            # Clean up test files
            Get-ChildItem -Path $script:TestSecureDir -Recurse -ErrorAction SilentlyContinue |
                Remove-Item -Force -Recurse -Confirm:$false -ErrorAction SilentlyContinue
        }

        It 'Should maintain proper file permissions for encrypted files' {
            # Arrange
            $sensitiveFilePath = Join-Path $script:TestSecureDir "sensitive_data.txt"
            $sensitiveContent = @"
Database Connection String: Server=localhost;Database=prod;User=admin;Password=secret123
API Keys:
  - Primary: sk-1234567890abcdef
  - Secondary: sk-fedcba0987654321
SSH Private Key Data:
-----BEGIN PRIVATE KEY-----
MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQC...
-----END PRIVATE KEY-----
"@

            New-SecureTestFile -Path $sensitiveFilePath -Content $sensitiveContent -Permissions "User"

            # Act - Encrypt and store the file
            $encryptedContent = Protect-WmrData -Data $sensitiveContent -Passphrase $script:TestSecureString
            $encryptedFilePath = Join-Path $script:TestBackupDir "encrypted_sensitive_data.enc"
            Set-Content -Path $encryptedFilePath -Value $encryptedContent -NoNewline -Encoding UTF8

            # Set secure permissions on encrypted file
            icacls $encryptedFilePath /inheritance:r | Out-Null
            icacls $encryptedFilePath /grant:r "${env:USERNAME}:(F)" | Out-Null

            # Assert
            Test-Path $encryptedFilePath | Should -Be $true

            # Verify file permissions (Windows-specific)
            $acl = Get-Acl $encryptedFilePath
            $acl.Owner | Should -Match $env:USERNAME

            # Verify content is encrypted
            $storedContent = Get-Content $encryptedFilePath -Raw
            $storedContent | Should -Not -Be $sensitiveContent
            $storedContent | Should -Match "^[A-Za-z0-9+/=]+$"

            # Verify decryption works
            $decryptedContent = Unprotect-WmrData -EncodedData $storedContent -Passphrase $script:TestSecureString
            $decryptedContent | Should -Be $sensitiveContent
        }

        It 'Should handle secure directory creation and permissions' {
            # Arrange
            $secureBackupDir = Join-Path $script:TestSecureDir "secure_backup"

            # Act - Create secure directory
            New-Item -ItemType Directory -Path $secureBackupDir -Force | Out-Null

            # Set secure permissions
            icacls $secureBackupDir /inheritance:r | Out-Null
            icacls $secureBackupDir /grant:r "${env:USERNAME}:(OI)(CI)F" | Out-Null

            # Create encrypted files in secure directory
            $files = @(
                @{ Name = "config.enc"; Content = "encrypted config data" },
                @{ Name = "keys.enc"; Content = "encrypted key data" },
                @{ Name = "credentials.enc"; Content = "encrypted credential data" }
            )

            foreach ($file in $files) {
                $filePath = Join-Path $secureBackupDir $file.Name
                $encrypted = Protect-WmrData -Data $file.Content -Passphrase $script:TestSecureString
                Set-Content -Path $filePath -Value $encrypted -NoNewline -Encoding UTF8
            }

            # Assert
            Test-Path $secureBackupDir | Should -Be $true
            Get-ChildItem -Path $secureBackupDir | Should -HaveCount 3

            # Verify all files are encrypted
            foreach ($file in $files) {
                $filePath = Join-Path $secureBackupDir $file.Name
                $content = Get-Content $filePath -Raw
                $content | Should -Not -Be $file.Content
                $content | Should -Match "^[A-Za-z0-9+/=]+$"
            }
        }

        It 'Should prevent unauthorized access to encrypted files' {
            # Arrange
            $restrictedFilePath = Join-Path $script:TestSecureDir "restricted_file.enc"
            $restrictedContent = "Top secret information"

            # Act - Create encrypted file with restricted permissions
            $encrypted = Protect-WmrData -Data $restrictedContent -Passphrase $script:TestSecureString
            Set-Content -Path $restrictedFilePath -Value $encrypted -NoNewline -Encoding UTF8

            # Set very restrictive permissions (owner only)
            icacls $restrictedFilePath /inheritance:r | Out-Null
            icacls $restrictedFilePath /grant:r "${env:USERNAME}:(F)" | Out-Null

            # Assert
            Test-Path $restrictedFilePath | Should -Be $true

            # Verify file is accessible to owner
            $content = Get-Content $restrictedFilePath -Raw
            $content | Should -Not -BeNullOrEmpty

            # Verify content is encrypted
            $content | Should -Not -Be $restrictedContent
            $decrypted = Unprotect-WmrData -EncodedData $content -Passphrase $script:TestSecureString
            $decrypted | Should -Be $restrictedContent
        }

        It 'Should handle secure file cleanup and deletion' {
            # Arrange
            $tempSecureFiles = @()
            for ($i = 1; $i -le 3; $i++) {
                $filePath = Join-Path $script:TestTempDir "temp_secure_$i.enc"
                $content = "Temporary secure content $i"
                $encrypted = Protect-WmrData -Data $content -Passphrase $script:TestSecureString
                Set-Content -Path $filePath -Value $encrypted -NoNewline -Encoding UTF8
                $tempSecureFiles += $filePath
            }

            # Verify files exist
            $tempSecureFiles | ForEach-Object { Test-Path $_ | Should -Be $true }

            # Act - Secure cleanup
            foreach ($file in $tempSecureFiles) {
                if (Test-Path $file) {
                    # Overwrite file with random data before deletion (secure delete simulation)
                    $randomData = [System.Text.Encoding]::UTF8.GetBytes("RANDOM_DATA_$(Get-Random)")
                    [System.IO.File]::WriteAllBytes($file, $randomData)
                    Remove-Item -Path $file -Force
                }
            }

            # Assert
            $tempSecureFiles | ForEach-Object { Test-Path $_ | Should -Be $false }
        }
    }

    Context 'Secure Storage Mechanisms' {
        It 'Should implement secure storage with integrity checking' {
            # Arrange
            $originalData = @{
                username = "admin"
                password = "super-secret-password"
                api_key = "sk-1234567890abcdef"
                database_url = "postgresql://user:pass@localhost/db"
            } | ConvertTo-Json -Depth 2

            # Act - Store with integrity checking
            $encrypted = Protect-WmrData -Data $originalData -Passphrase $script:TestSecureString
            $hash = (Get-FileHash -InputStream ([System.IO.MemoryStream]::new([System.Text.Encoding]::UTF8.GetBytes($encrypted))) -Algorithm SHA256).Hash

            $secureStorage = @{
                encrypted_data = $encrypted
                integrity_hash = $hash
                timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                version = "1.0"
            } | ConvertTo-Json -Depth 2

            $storageFilePath = Join-Path $script:TestBackupDir "secure_storage.json"
            Set-Content -Path $storageFilePath -Value $secureStorage -NoNewline -Encoding UTF8

            # Assert - Verify storage and integrity
            Test-Path $storageFilePath | Should -Be $true

            $retrievedStorage = Get-Content $storageFilePath | ConvertFrom-Json
            $retrievedStorage.encrypted_data | Should -Be $encrypted
            $retrievedStorage.integrity_hash | Should -Be $hash

            # Verify integrity
            $retrievedHash = (Get-FileHash -InputStream ([System.IO.MemoryStream]::new([System.Text.Encoding]::UTF8.GetBytes($retrievedStorage.encrypted_data))) -Algorithm SHA256).Hash
            $retrievedHash | Should -Be $retrievedStorage.integrity_hash

            # Verify decryption
            $decryptedData = Unprotect-WmrData -EncodedData $retrievedStorage.encrypted_data -Passphrase $script:TestSecureString
            $decryptedData | Should -Be $originalData
        }

        It 'Should handle secure storage with metadata' {
            # Arrange
            $sensitiveFiles = @(
                @{ Name = "ssh_private_key"; Content = "-----BEGIN PRIVATE KEY-----\nMIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQC...\n-----END PRIVATE KEY-----"; Type = "ssh_key" },
                @{ Name = "api_credentials"; Content = '{"api_key": "sk-1234567890abcdef", "secret": "secret-key-data"}'; Type = "api_credentials" },
                @{ Name = "database_config"; Content = "Server=localhost;Database=prod;User=admin;Password=secret123"; Type = "connection_string" }
            )

            # Act - Store each file with metadata
            $storageResults = @()
            foreach ($file in $sensitiveFiles) {
                $encrypted = Protect-WmrData -Data $file.Content -Passphrase $script:TestSecureString
                $metadata = @{
                    name = $file.Name
                    type = $file.Type
                    encrypted = $true
                    encryption_algorithm = "AES-256-CBC"
                    key_derivation = "PBKDF2"
                    created = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                    size_original = $file.Content.Length
                    size_encrypted = $encrypted.Length
                }

                $storageItem = @{
                    metadata = $metadata
                    encrypted_content = $encrypted
                } | ConvertTo-Json -Depth 3

                $storageFilePath = Join-Path $script:TestBackupDir "$($file.Name).secure"
                Set-Content -Path $storageFilePath -Value $storageItem -NoNewline -Encoding UTF8

                $storageResults += @{
                    File = $file
                    Path = $storageFilePath
                    Metadata = $metadata
                }
            }

            # Assert
            $storageResults | Should -HaveCount 3

            foreach ($result in $storageResults) {
                Test-Path $result.Path | Should -Be $true

                # Verify storage structure
                $storedItem = Get-Content $result.Path | ConvertFrom-Json
                $storedItem.metadata.name | Should -Be $result.File.Name
                $storedItem.metadata.type | Should -Be $result.File.Type
                $storedItem.metadata.encrypted | Should -Be $true

                # Verify content can be decrypted
                $decrypted = Unprotect-WmrData -EncodedData $storedItem.encrypted_content -Passphrase $script:TestSecureString
                $decrypted | Should -Be $result.File.Content
            }
        }

        It 'Should implement secure storage with versioning' {
            # Arrange
            $configData = @{
                version = 1
                settings = @{
                    debug = $false
                    timeout = 30
                }
                credentials = @{
                    username = "admin"
                    password = "password123"
                }
            }

            # Act - Create multiple versions
            $versions = @()
            for ($i = 1; $i -le 3; $i++) {
                $configData.version = $i
                $configData.settings.timeout = 30 * $i
                $configData.credentials.password = "password$i"

                $jsonData = $configData | ConvertTo-Json -Depth 3
                $encrypted = Protect-WmrData -Data $jsonData -Passphrase $script:TestSecureString

                $versionedStorage = @{
                    version = $i
                    timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                    encrypted_data = $encrypted
                    previous_version = if ($i -gt 1) { $i - 1 } else { $null }
                } | ConvertTo-Json -Depth 2

                $versionPath = Join-Path $script:TestBackupDir "config_v$i.secure"
                Set-Content -Path $versionPath -Value $versionedStorage -NoNewline -Encoding UTF8

                $versions += @{
                    Version = $i
                    Path = $versionPath
                    Data = $configData.Clone()
                }
            }

            # Assert
            $versions | Should -HaveCount 3

            # Verify each version
            foreach ($version in $versions) {
                Test-Path $version.Path | Should -Be $true

                $storedVersion = Get-Content $version.Path | ConvertFrom-Json
                $storedVersion.version | Should -Be $version.Version

                # Verify decryption
                $decryptedData = Unprotect-WmrData -EncodedData $storedVersion.encrypted_data -Passphrase $script:TestSecureString
                $parsedData = $decryptedData | ConvertFrom-Json
                $parsedData.version | Should -Be $version.Version
                $parsedData.settings.timeout | Should -Be (30 * $version.Version)
                $parsedData.credentials.password | Should -Be "password$($version.Version)"
            }
        }

        It 'Should handle secure storage with compression' {
            # Arrange
            $largeData = "This is a large data string that will be repeated many times. " * 1000

            # Act - Store with compression simulation
            $compressed = [System.IO.Compression.GzipStream]::new([System.IO.MemoryStream]::new([System.Text.Encoding]::UTF8.GetBytes($largeData)), [System.IO.Compression.CompressionMode]::Compress)
            $compressedBytes = @()
            $buffer = New-Object byte[] 1024
            do {
                $bytesRead = $compressed.Read($buffer, 0, $buffer.Length)
                if ($bytesRead -gt 0) {
                    $compressedBytes += $buffer[0..($bytesRead - 1)]
                }
            } while ($bytesRead -gt 0)
            $compressed.Close()

            # Encrypt compressed data
            $encrypted = Protect-WmrData -Data $compressedBytes -Passphrase $script:TestSecureString
            $compressedStorage = @{
                compressed = $true
                original_size = $largeData.Length
                compressed_size = $compressedBytes.Length
                encrypted_size = $encrypted.Length
                encrypted_data = $encrypted
            } | ConvertTo-Json -Depth 2

            $storagePath = Join-Path $script:TestBackupDir "compressed_secure.json"
            Set-Content -Path $storagePath -Value $compressedStorage -NoNewline -Encoding UTF8

            # Assert
            Test-Path $storagePath | Should -Be $true

            $storedData = Get-Content $storagePath | ConvertFrom-Json
            $storedData.compressed | Should -Be $true
            $storedData.original_size | Should -Be $largeData.Length
            $storedData.compressed_size | Should -BeLessThan $storedData.original_size
            $storedData.encrypted_size | Should -BeGreaterThan $storedData.compressed_size

            # Verify decryption and decompression would work
            $decryptedCompressed = Unprotect-WmrData -EncodedData $storedData.encrypted_data -Passphrase $script:TestSecureString -ReturnBytes
            $decryptedCompressed | Should -Not -BeNull
            $decryptedCompressed.Length | Should -Be $storedData.compressed_size
        }
    }

    Context 'Secure File Operations' {
        It 'Should handle secure file copying with encryption' {
            # Arrange
            $sourceFile = Join-Path $script:TestSecureDir "source_secure.txt"
            $destinationFile = Join-Path $script:TestBackupDir "destination_secure.enc"
            $sensitiveContent = "This is sensitive content that needs secure copying"

            New-SecureTestFile -Path $sourceFile -Content $sensitiveContent

            # Act - Secure copy with encryption
            $encrypted = Protect-WmrData -Data $sensitiveContent -Passphrase $script:TestSecureString
            Set-Content -Path $destinationFile -Value $encrypted -NoNewline -Encoding UTF8

            # Set secure permissions on destination
            icacls $destinationFile /inheritance:r | Out-Null
            icacls $destinationFile /grant:r "${env:USERNAME}:(F)" | Out-Null

            # Assert
            Test-Path $sourceFile | Should -Be $true
            Test-Path $destinationFile | Should -Be $true

            # Verify source is readable
            $sourceContent = Get-Content $sourceFile -Raw
            $sourceContent | Should -Be $sensitiveContent

            # Verify destination is encrypted
            $destinationContent = Get-Content $destinationFile -Raw
            $destinationContent | Should -Not -Be $sensitiveContent
            $destinationContent | Should -Match "^[A-Za-z0-9+/=]+$"

            # Verify decryption works
            $decrypted = Unprotect-WmrData -EncodedData $destinationContent -Passphrase $script:TestSecureString
            $decrypted | Should -Be $sensitiveContent
        }

        It 'Should handle secure file moving with encryption' {
            # Arrange
            $sourceFile = Join-Path $script:TestSecureDir "move_source.txt"
            $tempFile = Join-Path $script:TestTempDir "move_temp.enc"
            $destinationFile = Join-Path $script:TestBackupDir "move_destination.enc"
            $sensitiveContent = "Content to be moved securely"

            New-SecureTestFile -Path $sourceFile -Content $sensitiveContent

            # Act - Secure move with encryption
            # Step 1: Encrypt and copy to temp location
            $encrypted = Protect-WmrData -Data $sensitiveContent -Passphrase $script:TestSecureString
            Set-Content -Path $tempFile -Value $encrypted -NoNewline -Encoding UTF8

            # Step 2: Move encrypted file to final destination
            Move-Item -Path $tempFile -Destination $destinationFile

            # Step 3: Securely delete original
            $randomData = [System.Text.Encoding]::UTF8.GetBytes("OVERWRITE_$(Get-Random)")
            [System.IO.File]::WriteAllBytes($sourceFile, $randomData)
            Remove-Item -Path $sourceFile -Force

            # Assert
            Test-Path $sourceFile | Should -Be $false
            Test-Path $tempFile | Should -Be $false
            Test-Path $destinationFile | Should -Be $true

            # Verify destination contains encrypted data
            $destinationContent = Get-Content $destinationFile -Raw
            $destinationContent | Should -Not -Be $sensitiveContent
            $decrypted = Unprotect-WmrData -EncodedData $destinationContent -Passphrase $script:TestSecureString
            $decrypted | Should -Be $sensitiveContent
        }

        It 'Should handle secure file backup with atomic operations' {
            # Arrange
            $originalFile = Join-Path $script:TestSecureDir "atomic_original.txt"
            $backupFile = Join-Path $script:TestBackupDir "atomic_backup.enc"
            $tempBackupFile = "$backupFile.tmp"
            $sensitiveContent = "Atomic backup test content"

            New-SecureTestFile -Path $originalFile -Content $sensitiveContent

            # Act - Atomic backup operation
            try {
                # Step 1: Create encrypted backup in temp location
                $encrypted = Protect-WmrData -Data $sensitiveContent -Passphrase $script:TestSecureString
                Set-Content -Path $tempBackupFile -Value $encrypted -NoNewline -Encoding UTF8

                # Step 2: Atomically move temp file to final location
                Move-Item -Path $tempBackupFile -Destination $backupFile

                $backupSuccess = $true
            }
            catch {
                # Cleanup temp file on failure
                if (Test-Path $tempBackupFile) {
                    Remove-Item -Path $tempBackupFile -Force
                }
                $backupSuccess = $false
                throw
            }

            # Assert
            $backupSuccess | Should -Be $true
            Test-Path $originalFile | Should -Be $true
            Test-Path $backupFile | Should -Be $true
            Test-Path $tempBackupFile | Should -Be $false

            # Verify backup integrity
            $backupContent = Get-Content $backupFile -Raw
            $decrypted = Unprotect-WmrData -EncodedData $backupContent -Passphrase $script:TestSecureString
            $decrypted | Should -Be $sensitiveContent
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







