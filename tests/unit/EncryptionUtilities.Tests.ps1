# tests/unit/EncryptionUtilities.Tests.ps1

BeforeAll {
    # Import the WindowsMelodyRecovery module to make functions available
    $ModulePath = if (Test-Path "./WindowsMelodyRecovery.psm1") {
        "./WindowsMelodyRecovery.psm1"
    } elseif (Test-Path "/workspace/WindowsMelodyRecovery.psm1") {
        "/workspace/WindowsMelodyRecovery.psm1"
    } else {
        throw "Cannot find WindowsMelodyRecovery.psm1 module"
    }
    Import-Module $ModulePath -Force
    
    # Create a test passphrase for consistent testing
    $script:TestPassphrase = ConvertTo-SecureString "TestPassphrase123!" -AsPlainText -Force
}

AfterAll {
    # Clean up encryption cache after all tests
    Clear-WmrEncryptionCache
}

AfterEach {
    # Clean up encryption cache after each test
    Clear-WmrEncryptionCache
}

Describe "AES-256 Encryption Utilities" {

    Context "Protect-WmrData and Unprotect-WmrData" {

        It "should correctly encrypt and decrypt string data with passphrase" {
            $originalString = "This is a secret message for AES-256 encryption."
            $originalBytes = [System.Text.Encoding]::UTF8.GetBytes($originalString)

            $encryptedString = Protect-WmrData -DataBytes $originalBytes -Passphrase $script:TestPassphrase
            $encryptedString | Should -Not -BeNullOrEmpty
            $encryptedString | Should -Not -Be $originalString
            $encryptedString | Should -Match '^[A-Za-z0-9+/]+=*$'  # Base64 pattern

            $decryptedBytes = Unprotect-WmrData -EncodedData $encryptedString -Passphrase $script:TestPassphrase
            $decryptedBytes | Should -Not -BeNullOrEmpty

            $decryptedString = [System.Text.Encoding]::UTF8.GetString($decryptedBytes)
            $decryptedString | Should -Be $originalString
        }

        It "should handle empty string data" {
            $originalString = ""
            $originalBytes = [System.Text.Encoding]::UTF8.GetBytes($originalString)

            $encryptedString = Protect-WmrData -DataBytes $originalBytes -Passphrase $script:TestPassphrase
            $encryptedString | Should -Not -BeNullOrEmpty  # Even empty data creates encrypted output due to salt+IV

            $decryptedBytes = Unprotect-WmrData -EncodedData $encryptedString -Passphrase $script:TestPassphrase
            $decryptedBytes | Should -Not -BeNull

            $decryptedString = [System.Text.Encoding]::UTF8.GetString($decryptedBytes)
            $decryptedString | Should -Be $originalString
        }

        It "should handle string with special characters and Unicode" {
            $originalString = "!@#$%^&*()_+-={}[]|\:;'.?/ 🔐 密码 العربية"
            $originalBytes = [System.Text.Encoding]::UTF8.GetBytes($originalString)

            $encryptedString = Protect-WmrData -DataBytes $originalBytes -Passphrase $script:TestPassphrase
            $decryptedBytes = Unprotect-WmrData -EncodedData $encryptedString -Passphrase $script:TestPassphrase
            $decryptedString = [System.Text.Encoding]::UTF8.GetString($decryptedBytes)

            $decryptedString | Should -Be $originalString
        }

        It "should handle large binary data" {
            # Create 1KB of random data
            $originalBytes = New-Object byte[] 1024
            [System.Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($originalBytes)

            $encryptedString = Protect-WmrData -DataBytes $originalBytes -Passphrase $script:TestPassphrase
            $decryptedBytes = Unprotect-WmrData -EncodedData $encryptedString -Passphrase $script:TestPassphrase

            $decryptedBytes.Length | Should -Be $originalBytes.Length
            
            # Compare byte arrays
            $bytesMatch = $true
            for ($i = 0; $i -lt $originalBytes.Length; $i++) {
                if ($originalBytes[$i] -ne $decryptedBytes[$i]) {
                    $bytesMatch = $false
                    break
                }
            }
            $bytesMatch | Should -Be $true
        }

        It "should fail with wrong passphrase" {
            $originalString = "Secret data"
            $originalBytes = [System.Text.Encoding]::UTF8.GetBytes($originalString)
            $wrongPassphrase = ConvertTo-SecureString "WrongPassphrase!" -AsPlainText -Force

            $encryptedString = Protect-WmrData -DataBytes $originalBytes -Passphrase $script:TestPassphrase
            
            { Unprotect-WmrData -EncodedData $encryptedString -Passphrase $wrongPassphrase } | Should -Throw
        }

        It "should produce different encrypted output for same input (different IVs)" {
            $originalString = "Same input data"
            $originalBytes = [System.Text.Encoding]::UTF8.GetBytes($originalString)

            $encrypted1 = Protect-WmrData -DataBytes $originalBytes -Passphrase $script:TestPassphrase
            Clear-WmrEncryptionCache  # Clear cache to force new salt/IV
            $encrypted2 = Protect-WmrData -DataBytes $originalBytes -Passphrase $script:TestPassphrase

            $encrypted1 | Should -Not -Be $encrypted2  # Different due to different IVs
            
            # But both should decrypt to the same data
            $decrypted1 = Unprotect-WmrData -EncodedData $encrypted1 -Passphrase $script:TestPassphrase
            $decrypted2 = Unprotect-WmrData -EncodedData $encrypted2 -Passphrase $script:TestPassphrase
            
            $decryptedString1 = [System.Text.Encoding]::UTF8.GetString($decrypted1)
            $decryptedString2 = [System.Text.Encoding]::UTF8.GetString($decrypted2)
            
            $decryptedString1 | Should -Be $originalString
            $decryptedString2 | Should -Be $originalString
        }
    }

    Context "Get-WmrEncryptionKey" {

        It "should generate consistent key for same passphrase and salt" {
            $salt = New-Object byte[] 32
            [System.Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($salt)

            $keyInfo1 = Get-WmrEncryptionKey -Passphrase $script:TestPassphrase -Salt $salt
            Clear-WmrEncryptionCache
            $keyInfo2 = Get-WmrEncryptionKey -Passphrase $script:TestPassphrase -Salt $salt

            $keyInfo1.Key.Length | Should -Be 32  # 256-bit key
            $keyInfo2.Key.Length | Should -Be 32

            # Keys should be identical for same passphrase and salt
            $keysMatch = $true
            for ($i = 0; $i -lt $keyInfo1.Key.Length; $i++) {
                if ($keyInfo1.Key[$i] -ne $keyInfo2.Key[$i]) {
                    $keysMatch = $false
                    break
                }
            }
            $keysMatch | Should -Be $true
        }

        It "should cache key during session" {
            $keyInfo1 = Get-WmrEncryptionKey -Passphrase $script:TestPassphrase
            $keyInfo2 = Get-WmrEncryptionKey  # Should use cached key

            # Should return same key reference when cached
            $keyInfo1.Key.Length | Should -Be $keyInfo2.Key.Length
        }
    }

    Context "Clear-WmrEncryptionCache" {

        It "should clear cached encryption key" {
            # Create a key to cache
            $keyInfo = Get-WmrEncryptionKey -Passphrase $script:TestPassphrase
            $keyInfo.Key | Should -Not -BeNull

            # Clear cache
            Clear-WmrEncryptionCache

            # Verify cache is cleared by checking that script variables are null
            $script:CachedEncryptionKey | Should -BeNull
            $script:CachedKeySalt | Should -BeNull
        }
    }

    Context "Test-WmrEncryption" {

        It "should pass encryption round-trip test" {
            Mock Read-Host { return $script:TestPassphrase } -ParameterFilter { $AsSecureString }
            
            $result = Test-WmrEncryption -TestData "Test encryption functionality"
            $result | Should -Be $true
        }

        It "should handle custom test data" {
            Mock Read-Host { return $script:TestPassphrase } -ParameterFilter { $AsSecureString }
            
            $customData = "Custom test data with special chars: 🔒🗝️"
            $result = Test-WmrEncryption -TestData $customData
            $result | Should -Be $true
        }
    }

    Context "Error Handling" {

        It "should handle corrupted encrypted data" {
            $corruptedData = "InvalidBase64Data!@#"
            
            { Unprotect-WmrData -EncodedData $corruptedData -Passphrase $script:TestPassphrase } | Should -Throw
        }

        It "should handle encrypted data that is too short" {
            $tooShortData = [System.Convert]::ToBase64String([byte[]](1..10))  # Less than 48 bytes
            
            { Unprotect-WmrData -EncodedData $tooShortData -Passphrase $script:TestPassphrase } | Should -Throw
        }
    }
} 