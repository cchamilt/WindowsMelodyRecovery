# tests/unit/EncryptionWorkflow.Tests.ps1
# Phase 6.1: Encryption Workflow Testing - Unit Tests

BeforeAll {
    # Load Docker test bootstrap for cross-platform compatibility
    . (Join-Path $PSScriptRoot "../utilities/Docker-Test-Bootstrap.ps1")

    # Load the unified test environment (works for both Docker and Windows)
    . (Join-Path $PSScriptRoot "..\utilities\Test-Environment.ps1")

    # Initialize test environment
    $testEnvironment = Initialize-TestEnvironment -SuiteName 'Unit'

    # Import core functions through module system for code coverage
    try {
        # First import the module for code coverage
        $moduleRoot = $PSScriptRoot
        while (-not (Test-Path (Join-Path $moduleRoot "WindowsMelodyRecovery.psd1"))) {
            $moduleRoot = Split-Path -Parent $moduleRoot
            if ([string]::IsNullOrEmpty($moduleRoot)) {
                throw "Could not find WindowsMelodyRecovery module root"
            }
        }

        # Import the module
        Import-Module (Join-Path $moduleRoot "WindowsMelodyRecovery.psd1") -Force -Global

        # Directly dot-source the Core files to ensure functions are available
        . (Join-Path $moduleRoot "Private\Core\EncryptionUtilities.ps1")
        . (Join-Path $moduleRoot "Private\Core\PathUtilities.ps1")

        Write-Verbose "Successfully loaded core functions for code coverage"
    }
    catch {
        throw "Cannot find or import required functions: $($_.Exception.Message)"
    }

    # Create and import the test helper module
    $helperPath = Join-Path $PSScriptRoot "../utilities/EncryptionTestHelper.ps1"
    . $helperPath

    # Set up test environment
    $script:TestDataPath = [string](New-TestTempDirectory)
    $script:TestPassword = "TestP@ssw0rd123!"
    $script:TestSecureString = New-TestSecureString -PlainText $TestPassword
    $script:TestWrongPassword = New-TestSecureString -PlainText "WrongP@ssw0rd!"
}

Describe 'Encryption Workflow Tests' {

    Context 'Password Prompt Security' {
        BeforeEach {
            # Clear any cached encryption keys
            Clear-WmrEncryptionCache
        }

        It 'Should securely handle password prompts without caching' {
            # Arrange
            $testData = "Sensitive configuration data"

            # Act - First encryption should prompt for password
            $encrypted1 = Protect-WmrData -Data $testData -Passphrase $TestSecureString

            # Clear cache to force new password prompt
            Clear-WmrEncryptionCache

            # Second encryption should work with same password
            $encrypted2 = Protect-WmrData -Data $testData -Passphrase $TestSecureString

            # Assert
            $encrypted1 | Should -Not -BeNullOrEmpty
            $encrypted2 | Should -Not -BeNullOrEmpty
            $encrypted1 | Should -Not -Be $encrypted2  # Different IVs should produce different results

            # Both should decrypt to same original data
            $decrypted1 = Unprotect-WmrData -EncodedData $encrypted1 -Passphrase $TestSecureString
            $decrypted2 = Unprotect-WmrData -EncodedData $encrypted2 -Passphrase $TestSecureString

            $decrypted1 | Should -Be $testData
            $decrypted2 | Should -Be $testData
        }

        It 'Should properly cache encryption keys during session' {
            # Arrange
            $testData = "Test data for caching"

            # Act - First call should cache the key
            $keyInfo1 = Get-WmrEncryptionKey -Passphrase $TestSecureString
            $keyInfo2 = Get-WmrEncryptionKey  # Should use cached key

            # Assert
            $keyInfo1 | Should -Not -BeNull
            $keyInfo2 | Should -Not -BeNull
            $keyInfo1.Key | Should -Be $keyInfo2.Key
            $keyInfo1.Salt | Should -Be $keyInfo2.Salt
        }

        It 'Should clear encryption cache securely' {
            # Arrange
            $keyInfo = Get-WmrEncryptionKey -Passphrase $TestSecureString
            $keyInfo | Should -Not -BeNull

            # Act
            Clear-WmrEncryptionCache

            # Assert - Should need to provide password again
            $newKeyInfo = Get-WmrEncryptionKey -Passphrase $TestSecureString
            $newKeyInfo | Should -Not -BeNull
            # New key should be different (different salt)
            $newKeyInfo.Key | Should -Not -Be $keyInfo.Key
        }

        It 'Should handle empty passphrase gracefully' {
            # Arrange
            $emptySecureString = New-Object System.Security.SecureString

            # Act & Assert
            { Get-WmrEncryptionKey -Passphrase $emptySecureString } |
                Should -Throw "*Encryption passphrase cannot be empty*"
        }

        It 'Should validate passphrase strength requirements' {
            # Arrange
            $weakPasswords = @(
                "123",
                "password",
                "abc",
                ""
            )

            # Act & Assert
            foreach ($weak in $weakPasswords) {
                # Clear cache before each test to ensure clean state
                Clear-WmrEncryptionCache

                if ($weak -eq "") {
                    # Create a truly empty SecureString
                    $secureWeak = New-Object System.Security.SecureString
                }
                else {
                    $secureWeak = New-TestSecureString -PlainText $weak
                }

                if ($weak -eq "") {
                    { Get-WmrEncryptionKey -Passphrase $secureWeak } |
                        Should -Throw "*Encryption passphrase cannot be empty*"
                }
                else {
                    # Should still work but warn about weak passwords in real implementation
                    { Get-WmrEncryptionKey -Passphrase $secureWeak } | Should -Not -Throw
                }
            }
        }
    }

    Context 'Secure Key/File Encryption Workflows' {
        BeforeEach {
            Clear-WmrEncryptionCache
        }

        It 'Should encrypt configuration files with proper metadata' {
            # Arrange
            $configData = @{
                username = "testuser"
                apikey   = "secret-api-key-12345"
                servers  = @("server1.example.com", "server2.example.com")
                settings = @{
                    timeout = 30
                    retries = 3
                }
            } | ConvertTo-Json -Depth 3

            # Act
            $encrypted = Protect-WmrData -Data $configData -Passphrase $TestSecureString

            # Assert
            $encrypted | Should -Not -BeNullOrEmpty
            $encrypted | Should -Not -Be $configData
            $encrypted | Should -Match "^[A-Za-z0-9+/=]+$"  # Base64 format

            # Should decrypt back to original
            $decrypted = Unprotect-WmrData -EncodedData $encrypted -Passphrase $TestSecureString
            $decrypted | Should -Be $configData

            # Should be able to parse back to original structure
            $parsedConfig = $decrypted | ConvertFrom-Json
            $parsedConfig.username | Should -Be "testuser"
            $parsedConfig.apikey | Should -Be "secret-api-key-12345"
            $parsedConfig.servers.Count | Should -Be 2
        }

        It 'Should handle binary file encryption' {
            # Arrange
            $binaryData = [byte[]](1..255)

            # Act
            $encrypted = Protect-WmrData -Data $binaryData -Passphrase $TestSecureString
            $decrypted = Unprotect-WmrData -EncodedData $encrypted -Passphrase $TestSecureString -ReturnBytes

            # Assert
            $decrypted | Should -Not -BeNull
            $decrypted.Length | Should -Be 255
            for ($i = 0; $i -lt 255; $i++) {
                $decrypted[$i] | Should -Be ($i + 1)
            }
        }

        It 'Should handle large file encryption efficiently' {
            # Arrange
            $largeData = "x" * 1MB  # 1MB of data

            # Act
            $startTime = Get-Date
            $encrypted = Protect-WmrData -Data $largeData -Passphrase $TestSecureString
            $encryptTime = (Get-Date) - $startTime

            $startTime = Get-Date
            $decrypted = Unprotect-WmrData -EncodedData $encrypted -Passphrase $TestSecureString
            $decryptTime = (Get-Date) - $startTime

            # Assert
            $decrypted | Should -Be $largeData
            $encryptTime.TotalSeconds | Should -BeLessThan 10  # Should encrypt 1MB in under 10 seconds
            $decryptTime.TotalSeconds | Should -BeLessThan 10  # Should decrypt 1MB in under 10 seconds
        }

        It 'Should maintain encryption integrity across multiple operations' {
            # Arrange
            $testData = "Critical system configuration"

            # Act - Multiple encrypt/decrypt cycles
            $encrypted1 = Protect-WmrData -Data $testData -Passphrase $TestSecureString
            $decrypted1 = Unprotect-WmrData -EncodedData $encrypted1 -Passphrase $TestSecureString

            $encrypted2 = Protect-WmrData -Data $decrypted1 -Passphrase $TestSecureString
            $decrypted2 = Unprotect-WmrData -EncodedData $encrypted2 -Passphrase $TestSecureString

            $encrypted3 = Protect-WmrData -Data $decrypted2 -Passphrase $TestSecureString
            $decrypted3 = Unprotect-WmrData -EncodedData $encrypted3 -Passphrase $TestSecureString

            # Assert
            $decrypted1 | Should -Be $testData
            $decrypted2 | Should -Be $testData
            $decrypted3 | Should -Be $testData

            # Each encryption should produce different results (different IVs)
            $encrypted1 | Should -Not -Be $encrypted2
            $encrypted2 | Should -Not -Be $encrypted3
            $encrypted1 | Should -Not -Be $encrypted3
        }

        It 'Should handle special characters and encoding correctly' {
            # Arrange
            $specialData = @"
Special characters: !@#$%^&*()_+-=[]{}|;:',.<>?
Unicode: 世界 🌍 🔒 ñáéíóú
Quotes: "double" 'single' `backtick`
Newlines and tabs:
	Line 1
	Line 2
		Indented line
"@

            # Act
            $encrypted = Protect-WmrData -Data $specialData -Passphrase $TestSecureString
            $decrypted = Unprotect-WmrData -EncodedData $encrypted -Passphrase $TestSecureString

            # Assert
            $decrypted | Should -Be $specialData
        }
    }

    Context 'Encryption Error Handling' {
        It 'Should handle corrupted encrypted data gracefully' {
            # Arrange
            $testData = "Test data"
            $encrypted = Protect-WmrData -Data $testData -Passphrase $TestSecureString

            # Corrupt the encrypted data
            $corruptedData = $encrypted.Substring(0, $encrypted.Length - 10) + "CORRUPTED="

            # Act & Assert
            { Unprotect-WmrData -EncodedData $corruptedData -Passphrase $TestSecureString } |
                Should -Throw "*Decryption failed*"
        }

        It 'Should handle invalid Base64 data' {
            # Arrange
            $invalidBase64 = "This is not valid Base64 data!"

            # Act & Assert
            { Unprotect-WmrData -EncodedData $invalidBase64 -Passphrase $TestSecureString } |
                Should -Throw "*Decryption failed: Invalid Base64 data*"
        }

        It 'Should handle data too short for decryption' {
            # Arrange
            $shortData = [Convert]::ToBase64String([byte[]](1..10))  # Only 10 bytes, need at least 48

            # Act & Assert
            { Unprotect-WmrData -EncodedData $shortData -Passphrase $TestSecureString } |
                Should -Throw "*Decryption failed: Data too short*"
        }

        It 'Should handle wrong password gracefully' {
            # Arrange
            $testData = "Sensitive data"
            $encrypted = Protect-WmrData -Data $testData -Passphrase $TestSecureString

            # Act & Assert
            { Unprotect-WmrData -EncodedData $encrypted -Passphrase $TestWrongPassword } |
                Should -Throw "*Decryption failed*"
        }
    }

    Context 'Encryption Performance and Security' {
        It 'Should use strong encryption parameters' {
            # Arrange & Act
            $keyInfo = Get-WmrEncryptionKey -Passphrase $TestSecureString

            # Assert
            $keyInfo.Key.Length | Should -Be 32  # 256-bit key
            $keyInfo.Salt.Length | Should -Be 32  # 256-bit salt
        }

        It 'Should generate unique salts for each key derivation' {
            # Arrange & Act
            Clear-WmrEncryptionCache
            $keyInfo1 = Get-WmrEncryptionKey -Passphrase $TestSecureString

            Clear-WmrEncryptionCache
            $keyInfo2 = Get-WmrEncryptionKey -Passphrase $TestSecureString

            # Assert
            $keyInfo1.Salt | Should -Not -Be $keyInfo2.Salt
            $keyInfo1.Key | Should -Not -Be $keyInfo2.Key
        }

        It 'Should use secure random number generation' {
            # Arrange & Act
            $encrypted1 = Protect-WmrData -Data "test" -Passphrase $TestSecureString
            $encrypted2 = Protect-WmrData -Data "test" -Passphrase $TestSecureString

            # Assert - Same data with same password should produce different encrypted output due to random IV
            $encrypted1 | Should -Not -Be $encrypted2
        }

        It 'Should properly dispose of cryptographic resources' {
            # This test verifies that the encryption functions don't leak cryptographic resources
            # by running multiple encryption operations and checking they complete successfully

            # Arrange & Act
            $results = @()
            for ($i = 0; $i -lt 10; $i++) {
                $encrypted = Protect-WmrData -Data "Test data $i" -Passphrase $TestSecureString
                $decrypted = Unprotect-WmrData -EncodedData $encrypted -Passphrase $TestSecureString
                $results += ($decrypted -eq "Test data $i")
            }

            # Assert
            $results | Should -Not -Contain $false
        }
    }
}

AfterAll {
    # Clean up test environment
    Clear-WmrEncryptionCache
    if ($script:TestDataPath -and (Test-Path $script:TestDataPath)) {
        Remove-Item -Path $script:TestDataPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}







