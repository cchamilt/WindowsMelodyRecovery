# Helper functions for encryption-related tests
using namespace System.Security.Cryptography
using namespace System.Text

function New-TestEncryptionKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [int]$KeySize = 256,
        
        [Parameter(Mandatory=$false)]
        [string]$Password = "TestP@ssw0rd!",
        
        [Parameter(Mandatory=$false)]
        [byte[]]$Salt
    )
    
    try {
        # Generate salt if not provided
        if (-not $Salt) {
            $Salt = New-Object byte[] 32
            for ($i = 0; $i -lt 32; $i++) {
                $Salt[$i] = $i
            }
        }
        
        # Derive key using PBKDF2 (100,000 iterations for security)
        $pbkdf2 = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($Password, $Salt, 100000)
        $key = $pbkdf2.GetBytes(32)  # 256-bit key
        $pbkdf2.Dispose()
        
        return $key
    }
    catch {
        Write-Error "Failed to generate test encryption key: $_"
        throw
    }
}

function New-TestInitializationVector {
    [CmdletBinding()]
    param()
    
    try {
        $aes = [AesManaged]::new()
        $aes.GenerateIV()
        return $aes.IV
    }
    catch {
        Write-Error "Failed to generate test initialization vector: $_"
        throw
    }
    finally {
        if ($aes) { $aes.Dispose() }
    }
}

function New-TestSecureString {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$PlainText
    )
    
    try {
        $secureString = [SecureString]::new()
        $PlainText.ToCharArray() | ForEach-Object { $secureString.AppendChar($_) }
        $secureString.MakeReadOnly()
        return $secureString
    }
    catch {
        Write-Error "Failed to create test secure string: $_"
        throw
    }
}

function New-TestEncryptedData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [byte[]]$Key,
        
        [Parameter(Mandatory=$true)]
        [byte[]]$InitializationVector,
        
        [Parameter(Mandatory=$true)]
        [AllowEmptyString()]
        [string]$PlainText
    )
    
    try {
        # Create a fixed salt for testing
        $salt = New-Object byte[] 32
        for ($i = 0; $i -lt 32; $i++) {
            $salt[$i] = $i
        }
        
        # Convert plain text to bytes
        $plainBytes = [Encoding]::UTF8.GetBytes($PlainText)
        
        # Handle empty input - create empty byte array
        if ($plainBytes.Length -eq 0) {
            $plainBytes = New-Object byte[] 0
        }
        
        # Create AES provider
        $aes = [AesManaged]::new()
        $aes.Key = $Key
        $aes.IV = $InitializationVector
        $aes.Mode = [CipherMode]::CBC
        $aes.Padding = [PaddingMode]::PKCS7
        
        # Encrypt the data
        $encryptor = $aes.CreateEncryptor()
        $encryptedBytes = $encryptor.TransformFinalBlock($plainBytes, 0, $plainBytes.Length)
        
        # Combine salt + IV + encrypted data
        $combinedData = New-Object byte[] ($salt.Length + $InitializationVector.Length + $encryptedBytes.Length)
        [Array]::Copy($salt, 0, $combinedData, 0, $salt.Length)
        [Array]::Copy($InitializationVector, 0, $combinedData, $salt.Length, $InitializationVector.Length)
        [Array]::Copy($encryptedBytes, 0, $combinedData, $salt.Length + $InitializationVector.Length, $encryptedBytes.Length)
        
        return $combinedData
    }
    catch {
        Write-Error "Failed to create test encrypted data: $_"
        throw
    }
    finally {
        if ($encryptor) { $encryptor.Dispose() }
        if ($aes) { $aes.Dispose() }
    }
}

function Test-DecryptedDataEquals {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [byte[]]$DecryptedData,
        
        [Parameter(Mandatory=$true)]
        [string]$ExpectedPlainText
    )
    
    $decryptedText = [Encoding]::UTF8.GetString($DecryptedData)
    return $decryptedText -eq $ExpectedPlainText
}

function New-TestTempDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$Prefix = "WMR_Test_"
    )
    
    $tempPath = Join-Path $TestDrive ($Prefix + [Guid]::NewGuid().ToString())
    New-Item -Path $tempPath -ItemType Directory -Force
    return $tempPath
}

function Remove-TestTempDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )
    
    if (Test-Path $Path) {
        Remove-Item -Path $Path -Recurse -Force
    }
}

# Create a module from this script
$scriptModule = New-Module -Name EncryptionTestHelper -ScriptBlock {
    # Export all functions defined above
    Export-ModuleMember -Function @(
        'New-TestEncryptionKey',
        'New-TestInitializationVector',
        'New-TestSecureString',
        'New-TestEncryptedData',
        'Test-DecryptedDataEquals',
        'New-TestTempDirectory',
        'Remove-TestTempDirectory'
    )
}

# Import the module into the current session
$scriptModule | Import-Module -Force 