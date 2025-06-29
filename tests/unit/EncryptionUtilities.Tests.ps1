# tests/unit/EncryptionUtilities.Tests.ps1

BeforeAll {
    # Dot-source the module to make functions available
    . (Join-Path $PSScriptRoot "..\..\Private\Core\EncryptionUtilities.ps1")
}

Describe "Protect-WmrData and Unprotect-WmrData" {

    It "should correctly encode and decode string data" {
        $originalString = "This is a secret message."
        $originalBytes = [System.Text.Encoding]::UTF8.GetBytes($originalString)

        $encodedString = Protect-WmrData -DataBytes $originalBytes
        $encodedString | Should Not BeNullOrEmpty
        $encodedString | Should Not Be $originalString

        $decodedBytes = Unprotect-WmrData -EncodedData $encodedString
        $decodedBytes | Should Not BeNullOrEmpty

        $decodedString = [System.Text.Encoding]::UTF8.GetString($decodedBytes)
        $decodedString | Should Be $originalString
    }

    It "should handle empty string data" {
        $originalString = ""
        $originalBytes = [System.Text.Encoding]::UTF8.GetBytes($originalString)

        $encodedString = Protect-WmrData -DataBytes $originalBytes
        $encodedString | Should Be ""

        $decodedBytes = Unprotect-WmrData -EncodedData $encodedString
        $decodedBytes | Should Be ([byte[]]::new(0))

        $decodedString = [System.Text.Encoding]::UTF8.GetString($decodedBytes)
        $decodedString | Should Be $originalString
    }

    It "should handle string with special characters" {
        $originalString = "!@#$%^&*()_+`-={}[]|\:;'"<>,.?/"
        $originalBytes = [System.Text.Encoding]::UTF8.GetBytes($originalString)

        $encodedString = Protect-WmrData -DataBytes $originalBytes
        $decodedBytes = Unprotect-WmrData -EncodedData $encodedString
        $decodedString = [System.Text.Encoding]::UTF8.GetString($decodedBytes)

        $decodedString | Should Be $originalString
    }
} 