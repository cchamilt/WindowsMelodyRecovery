# Private/Core/EncryptionUtilities.ps1

# AES-256 symmetric encryption utilities for Windows Melody Recovery
# Uses PBKDF2 for key derivation from passphrase with salt
# Stores salt and IV with encrypted data for proper decryption

Add-Type -AssemblyName System.Security

# Global variable to cache the encryption key during a session to avoid repeated passphrase prompts
$script:CachedEncryptionKey = $null
$script:CachedKeySalt = $null

function Get-WmrEncryptionKey {
    <#
    .SYNOPSIS
    Gets or creates an AES-256 encryption key from a passphrase.
    
    .DESCRIPTION
    Derives an AES-256 key from a user-provided passphrase using PBKDF2.
    Caches the key during the session to avoid repeated passphrase prompts.
    
    .PARAMETER Passphrase
    Optional passphrase. If not provided, prompts the user securely.
    
    .PARAMETER Salt
    Optional salt for key derivation. If not provided, generates a new random salt.
    
    .OUTPUTS
    Hashtable with 'Key' and 'Salt' properties
    #>
    param(
        [Parameter(Mandatory=$false)]
        [SecureString]$Passphrase,
        
        [Parameter(Mandatory=$false)]
        [byte[]]$Salt
    )

    # If we have a cached key and salt, and no specific salt is requested, use cached
    if ($script:CachedEncryptionKey -and $script:CachedKeySalt -and -not $Salt) {
        return @{
            Key = $script:CachedEncryptionKey
            Salt = $script:CachedKeySalt
        }
    }

    # Get passphrase if not provided
    if (-not $Passphrase) {
        $Passphrase = Read-Host -AsSecureString -Prompt "Enter encryption passphrase for Windows Melody Recovery"
        if ($Passphrase.Length -eq 0) {
            throw "Encryption passphrase cannot be empty"
        }
    }

    # Generate salt if not provided
    if (-not $Salt) {
        $Salt = New-Object byte[] 32  # 256-bit salt
        [System.Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($Salt)
    }

    # Convert SecureString to plain text for key derivation
    $passphrasePtr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Passphrase)
    try {
        $passphraseText = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($passphrasePtr)
        
        # Derive key using PBKDF2 (100,000 iterations for security)
        $pbkdf2 = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($passphraseText, $Salt, 100000)
        $key = $pbkdf2.GetBytes(32)  # 256-bit key
        $pbkdf2.Dispose()
        
        # Cache the key and salt for this session
        $script:CachedEncryptionKey = $key
        $script:CachedKeySalt = $Salt
        
        return @{
            Key = $key
            Salt = $Salt
        }
    }
    finally {
        # Securely clear the passphrase from memory
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passphrasePtr)
        if ($passphraseText) {
            $passphraseText = $null
        }
    }
}

function Clear-WmrEncryptionCache {
    <#
    .SYNOPSIS
    Clears the cached encryption key from memory.
    
    .DESCRIPTION
    Securely clears the cached encryption key and salt from memory.
    Call this when finished with encryption operations.
    #>
    if ($script:CachedEncryptionKey) {
        # Zero out the key bytes
        for ($i = 0; $i -lt $script:CachedEncryptionKey.Length; $i++) {
            $script:CachedEncryptionKey[$i] = 0
        }
        $script:CachedEncryptionKey = $null
    }
    if ($script:CachedKeySalt) {
        # Zero out the salt bytes
        for ($i = 0; $i -lt $script:CachedKeySalt.Length; $i++) {
            $script:CachedKeySalt[$i] = 0
        }
        $script:CachedKeySalt = $null
    }
}

function Protect-WmrData {
    <#
    .SYNOPSIS
    Encrypts data using AES-256 symmetric encryption.
    
    .DESCRIPTION
    Encrypts the provided data using AES-256-CBC with a key derived from a passphrase.
    The output includes the salt, IV, and encrypted data as a Base64-encoded string.
    
    .PARAMETER Data
    The data to encrypt. Can be either a string or byte array.
    
    .PARAMETER Passphrase
    Optional passphrase for encryption. If not provided, prompts the user.
    
    .OUTPUTS
    Base64-encoded string containing salt, IV, and encrypted data
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [AllowEmptyString()]
        [AllowEmptyCollection()]
        [ValidateNotNull()]
        [object]$Data,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        [SecureString]$Passphrase
    )

    Write-Verbose "Encrypting data using AES-256-CBC encryption"
    
    try {
        # Convert input to bytes if it's a string
        $dataBytes = if ($Data -is [byte[]]) {
            $Data
        } elseif ($Data -is [string]) {
            [System.Text.Encoding]::UTF8.GetBytes($Data)
        } else {
            throw "Data must be either a string or byte array"
        }
        
        # Handle empty input - create empty byte array
        if ($dataBytes.Length -eq 0) {
            $dataBytes = New-Object byte[] 0
        }
        
        # Get encryption key and salt
        $keyInfo = Get-WmrEncryptionKey -Passphrase $Passphrase
        $key = $keyInfo.Key
        $salt = $keyInfo.Salt

        # Create AES provider
        $aes = [System.Security.Cryptography.AesCryptoServiceProvider]::new()
        $aes.KeySize = 256
        $aes.BlockSize = 128
        $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
        $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
        $aes.Key = $key
        $aes.GenerateIV()  # Generate random IV for this encryption
        
        $iv = $aes.IV

        # Encrypt the data
        $encryptor = $aes.CreateEncryptor()
        $encryptedBytes = $encryptor.TransformFinalBlock($dataBytes, 0, $dataBytes.Length)
        
        # Combine salt (32 bytes) + IV (16 bytes) + encrypted data
        $combinedData = New-Object byte[] ($salt.Length + $iv.Length + $encryptedBytes.Length)
        [Array]::Copy($salt, 0, $combinedData, 0, $salt.Length)
        [Array]::Copy($iv, 0, $combinedData, $salt.Length, $iv.Length)
        [Array]::Copy($encryptedBytes, 0, $combinedData, $salt.Length + $iv.Length, $encryptedBytes.Length)
        
        # Return as Base64 string
        $encryptedData = [System.Convert]::ToBase64String($combinedData)
        
        # Clean up
        $encryptor.Dispose()
        $aes.Dispose()
        
        Write-Verbose "Data successfully encrypted ($(($dataBytes.Length)) bytes -> $(($combinedData.Length)) bytes)"
        return $encryptedData
    }
    catch {
        Write-Error "Failed to encrypt data: $($_.Exception.Message)"
        throw
    }
}

function Unprotect-WmrData {
    <#
    .SYNOPSIS
    Decrypts data that was encrypted with Protect-WmrData.
    
    .DESCRIPTION
    Decrypts AES-256-CBC encrypted data using a passphrase-derived key.
    Expects input that contains salt, IV, and encrypted data.
    
    .PARAMETER EncodedData
    Base64-encoded string containing salt, IV, and encrypted data.
    
    .PARAMETER Passphrase
    Optional passphrase for decryption. If not provided, prompts the user.
    
    .PARAMETER ReturnBytes
    If true, returns the decrypted data as a byte array. If false (default),
    attempts to convert the decrypted data to a UTF-8 string.
    
    .OUTPUTS
    Decrypted data as a string (default) or byte array (if ReturnBytes is true)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$EncodedData,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        [SecureString]$Passphrase,
        
        [Parameter(Mandatory=$false)]
        [switch]$ReturnBytes
    )

    Write-Verbose "Decrypting data using AES-256-CBC decryption"
    
    try {
        # Decode the Base64 data
        try {
            $combinedData = [System.Convert]::FromBase64String($EncodedData)
        }
        catch {
            throw "Decryption failed: Invalid Base64 data"
        }
        
        # Extract salt (first 32 bytes), IV (next 16 bytes), and encrypted data (remainder)
        if ($combinedData.Length -lt 48) {  # 32 + 16 = minimum size
            throw "Decryption failed: Data too short"
        }
        
        $salt = New-Object byte[] 32
        $iv = New-Object byte[] 16
        $encryptedBytes = New-Object byte[] ($combinedData.Length - 48)
        
        [Array]::Copy($combinedData, 0, $salt, 0, 32)
        [Array]::Copy($combinedData, 32, $iv, 0, 16)
        [Array]::Copy($combinedData, 48, $encryptedBytes, 0, $encryptedBytes.Length)

        # Derive the key using the extracted salt
        $keyInfo = Get-WmrEncryptionKey -Passphrase $Passphrase -Salt $salt
        $key = $keyInfo.Key

        # Create AES provider
        $aes = [System.Security.Cryptography.AesCryptoServiceProvider]::new()
        $aes.KeySize = 256
        $aes.BlockSize = 128
        $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
        $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
        $aes.Key = $key
        $aes.IV = $iv

        # Decrypt the data
        try {
            $decryptor = $aes.CreateDecryptor()
            $decryptedBytes = $decryptor.TransformFinalBlock($encryptedBytes, 0, $encryptedBytes.Length)
        }
        catch {
            throw "Decryption failed: Invalid key or corrupted data"
        }
        finally {
            if ($decryptor) { $decryptor.Dispose() }
            $aes.Dispose()
        }
        
        Write-Verbose "Data successfully decrypted ($(($encryptedBytes.Length)) bytes -> $(($decryptedBytes.Length)) bytes)"
        
        # Return as bytes or string based on ReturnBytes parameter
        if ($ReturnBytes) {
            return $decryptedBytes
        } else {
            try {
                return [System.Text.Encoding]::UTF8.GetString($decryptedBytes)
            }
            catch {
                throw "Decryption failed: Invalid UTF-8 data"
            }
        }
    }
    catch {
        Write-Error "Failed to decrypt data: $($_.Exception.Message)"
        throw
    }
}

function Test-WmrEncryption {
    <#
    .SYNOPSIS
    Tests the encryption/decryption functionality.
    
    .DESCRIPTION
    Performs a round-trip test of the encryption and decryption functions.
    
    .PARAMETER TestData
    Optional test data. If not provided, uses default test string.
    
    .OUTPUTS
    Boolean indicating success or failure
    #>
    param(
        [Parameter(Mandatory=$false)]
        [string]$TestData = "Windows Melody Recovery Encryption Test - $(Get-Date)"
    )
    
    try {
        Write-Host "Testing AES-256 encryption/decryption..."
        
        # Convert test data to bytes
        $originalBytes = [System.Text.Encoding]::UTF8.GetBytes($TestData)
        Write-Host "  Original data: $($originalBytes.Length) bytes"
        
        # Create a test passphrase
        $testPassphrase = ConvertTo-SecureString "TestPassphrase123!" -AsPlainText -Force
        
        # Encrypt
        $encrypted = Protect-WmrData -Data $originalBytes -Passphrase $testPassphrase
        Write-Host "  Encrypted data: $($encrypted.Length) characters (Base64)"
        
        # Clear cache to force re-derivation (simulates new session)
        Clear-WmrEncryptionCache
        
        # Decrypt
        $decryptedBytes = Unprotect-WmrData -EncodedData $encrypted -Passphrase $testPassphrase
        $decryptedText = [System.Text.Encoding]::UTF8.GetString($decryptedBytes)
        Write-Host "  Decrypted data: $($decryptedBytes.Length) bytes"
        
        # Verify
        $success = $decryptedText -eq $TestData
        if ($success) {
            Write-Host "  ✅ Encryption test PASSED - data integrity verified" -ForegroundColor Green
        } else {
            Write-Host "  ❌ Encryption test FAILED - data mismatch" -ForegroundColor Red
            Write-Host "    Original: $TestData"
            Write-Host "    Decrypted: $decryptedText"
        }
        
        # Clean up
        Clear-WmrEncryptionCache
        
        return $success
    }
    catch {
        Write-Host "  ❌ Encryption test FAILED with exception: $($_.Exception.Message)" -ForegroundColor Red
        Clear-WmrEncryptionCache
        return $false
    }
}

# Functions are available via dot-sourcing - no Export-ModuleMember needed
# Available functions: Protect-WmrData, Unprotect-WmrData, Get-WmrEncryptionKey, Clear-WmrEncryptionCache, Test-WmrEncryption 