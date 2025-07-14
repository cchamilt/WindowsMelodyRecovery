# tests/unit/EncryptionUtilities.Tests.ps1

BeforeAll {
    # Load Docker test bootstrap for cross-platform compatibility
    . (Join-Path $PSScriptRoot "../utilities/Docker-Test-Bootstrap.ps1")

    # Import only the specific script needed to avoid TUI dependencies
    try {
        $EncryptionUtilitiesScript = Resolve-Path "$PSScriptRoot/../../Private/Core/EncryptionUtilities.ps1"
        . $EncryptionUtilitiesScript

        # Initialize test environment
        $TestEnvironmentScript = Resolve-Path "$PSScriptRoot/../utilities/Test-Environment.ps1"
        . $TestEnvironmentScript
        Initialize-TestEnvironment -SuiteName 'Unit' | Out-Null
    }
    catch {
        throw "Cannot find or import EncryptionUtilities script: $($_.Exception.Message)"
    }

    # Create and import the test helper module
    $helperPath = Join-Path $PSScriptRoot "../utilities/EncryptionTestHelper.ps1"
    . $helperPath

    # Set up test environment
    $script:TestDataPath = [string](New-TestTempDirectory)
}

Describe 'EncryptionUtilities' {
    BeforeAll {
        # Load Docker test bootstrap for cross-platform compatibility
        . (Join-Path $PSScriptRoot "../utilities/Docker-Test-Bootstrap.ps1")

        $script:TestPassword = "TestP@ssw0rd!"
        $script:TestSecureString = New-TestSecureString -PlainText $TestPassword
        $script:TestSalt = New-Object byte[] 32
        for ($i = 0; $i -lt 32; $i++) {
            $script:TestSalt[$i] = $i
        }
        $script:TestKey = New-TestEncryptionKey -Password $TestSecureString -Salt $TestSalt
        $script:TestInitializationVector = New-TestInitializationVector
    }

    Context 'Protect-WmrData' {
        It 'Should encrypt string data correctly' {
            # Arrange
            $plainText = "Sensitive test data"

            # Act
            $encryptedData = Protect-WmrData -Data $plainText -Passphrase $TestSecureString

            # Assert
            $encryptedData | Should -Not -BeNullOrEmpty
            $encryptedData | Should -Not -Be $plainText
            $encryptedData.GetType().Name | Should -Be 'String'
        }

        It 'Should handle empty strings' {
            # Act & Assert
            { Protect-WmrData -Data "" -Passphrase $TestSecureString } | Should -Not -Throw
        }

        It 'Should throw on null data' {
            # Act & Assert
            { Protect-WmrData -Data $null -Passphrase $TestSecureString } |
                Should -Throw -ExpectedMessage "*Cannot validate argument on parameter 'Data'. The argument is null*"
        }

        It 'Should throw on null password' {
            # Act & Assert
            { Protect-WmrData -Data "test" -Passphrase $null } |
                Should -Throw -ExpectedMessage "*Cannot validate argument on parameter 'Passphrase'. The argument is null*"
        }
    }

    Context 'Unprotect-WmrData' {
        It 'Should decrypt data correctly' {
            # Arrange
            $plainText = "Test data for decryption"
            $encodedData = Protect-WmrData -Data $plainText -Passphrase $TestSecureString

            # Act
            $decryptedData = Unprotect-WmrData -EncodedData $encodedData -Passphrase $TestSecureString

            # Assert
            $decryptedData | Should -Not -BeNullOrEmpty
            $decryptedData | Should -Be $plainText
        }

        It 'Should handle empty encrypted data' {
            # Arrange
            $encodedEmpty = Protect-WmrData -Data "" -Passphrase $TestSecureString

            # Act
            $decrypted = Unprotect-WmrData -EncodedData $encodedEmpty -Passphrase $TestSecureString

            # Assert
            $decrypted | Should -Be ""
        }

        It 'Should throw on corrupted data' {
            # Arrange
            $encodedData = Protect-WmrData -Data "Test" -Passphrase $TestSecureString
            $encryptedData = [Convert]::FromBase64String($encodedData)
            $corruptedData = $encryptedData[0..($encryptedData.Length - 2)]  # Remove last byte
            $encodedCorrupted = [Convert]::ToBase64String($corruptedData)

            # Act & Assert
            { Unprotect-WmrData -EncodedData $encodedCorrupted -Passphrase $TestSecureString } |
                Should -Throw -ExpectedMessage "*Decryption failed*"
        }

        It 'Should throw on incorrect password' {
            # Arrange
            $plainText = "Test data"
            $encodedData = Protect-WmrData -Data $plainText -Passphrase $TestSecureString
            $wrongPassword = New-TestSecureString -PlainText "WrongP@ssw0rd!"

            # Act & Assert
            { Unprotect-WmrData -EncodedData $encodedData -Passphrase $wrongPassword } |
                Should -Throw -ExpectedMessage "*Decryption failed*"
        }
    }

    Context 'End-to-End Encryption' {
        It 'Should successfully encrypt and decrypt data' {
            # Arrange
            $testData = @{
                'String' = "Test string"
                'Number' = 42
                'Array'  = @(1, 2, 3)
                'Nested' = @{
                    'Key' = 'Value'
                }
            } | ConvertTo-Json

            # Act
            # First encrypt with a known salt
            $salt = New-Object byte[] 32
            for ($i = 0; $i -lt 32; $i++) {
                $salt[$i] = $i
            }

            # Get the key info with our known salt
            $keyInfo = Get-WmrEncryptionKey -Passphrase $TestSecureString -Salt $salt

            # Create AES provider
            $aes = [System.Security.Cryptography.AesCryptoServiceProvider]::new()
            $aes.KeySize = 256
            $aes.BlockSize = 128
            $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
            $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
            $aes.Key = $keyInfo.Key
            $aes.GenerateIV()

            # Encrypt the data
            $encryptor = $aes.CreateEncryptor()
            $dataBytes = [System.Text.Encoding]::UTF8.GetBytes($testData)
            $encryptedBytes = $encryptor.TransformFinalBlock($dataBytes, 0, $dataBytes.Length)

            # Combine salt + IV + encrypted data
            $combinedData = New-Object byte[] ($salt.Length + $aes.IV.Length + $encryptedBytes.Length)
            [Array]::Copy($salt, 0, $combinedData, 0, $salt.Length)
            [Array]::Copy($aes.IV, 0, $combinedData, $salt.Length, $aes.IV.Length)
            [Array]::Copy($encryptedBytes, 0, $combinedData, $salt.Length + $aes.IV.Length, $encryptedBytes.Length)

            # Convert to Base64
            $encrypted = [System.Convert]::ToBase64String($combinedData)

            # Clean up
            $encryptor.Dispose()
            $aes.Dispose()

            # Now decrypt
            $decrypted = Unprotect-WmrData -EncodedData $encrypted -Passphrase $TestSecureString

            # Assert
            $decrypted | Should -Be $testData
            ($decrypted | ConvertFrom-Json).String | Should -Be "Test string"
            ($decrypted | ConvertFrom-Json).Number | Should -Be 42
        }

        It 'Should handle special characters correctly' {
            # Arrange
            $specialChars = "!@#$%^&*()_+-=[]{}|;:',.<>?`~"

            # Act
            $encrypted = Protect-WmrData -Data $specialChars -Passphrase $TestSecureString
            $decrypted = Unprotect-WmrData -EncodedData $encrypted -Passphrase $TestSecureString

            # Assert
            $decrypted | Should -Be $specialChars
        }

        It 'Should handle Unicode characters' {
            # Arrange
            $unicodeText = "Hello 世界 🌍"

            # Act
            $encrypted = Protect-WmrData -Data $unicodeText -Passphrase $TestSecureString
            $decrypted = Unprotect-WmrData -EncodedData $encrypted -Passphrase $TestSecureString

            # Assert
            $decrypted | Should -Be $unicodeText
        }
    }
}

AfterAll {
    # Clean up test environment
    if ($script:TestDataPath) {
        Remove-TestTempDirectory -Path $script:TestDataPath
    }
}







