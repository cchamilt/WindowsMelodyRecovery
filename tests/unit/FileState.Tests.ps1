# tests/unit/FileState.Tests.ps1

BeforeAll {
    # Import the WindowsMelodyRecovery module to make functions available
    Import-Module WindowsMelodyRecovery -Force # For mocked encryption

    # Setup a temporary directory for state files and dummy files
    $script:TempStateDir = Join-Path $PSScriptRoot "..\..\Temp\FileStateTests"
    $script:SourceDir = Join-Path $script:TempStateDir "Source"
    $script:DestDir = Join-Path $script:TempStateDir "Destination"

    if (-not (Test-Path $script:TempStateDir -PathType Container)) {
        New-Item -ItemType Directory -Path $script:TempStateDir -Force | Out-Null
    }
    if (-not (Test-Path $script:SourceDir -PathType Container)) {
        New-Item -ItemType Directory -Path $script:SourceDir -Force | Out-Null
    }
    if (-not (Test-Path $script:DestDir -PathType Container)) {
        New-Item -ItemType Directory -Path $script:DestDir -Force | Out-Null
    }

    # Mock encryption functions for testing purposes
    Mock Protect-WmrData {
        param([byte[]]$DataBytes)
        return [System.Convert]::ToBase64String($DataBytes) # Simply Base64 encode for mock
    }
    Mock Unprotect-WmrData {
        param([string]$EncodedData)
        return [System.Convert]::FromBase64String($EncodedData) # Simply Base64 decode for mock
    }
}

AfterAll {
    # Clean up temporary directories
    Remove-Item -Path $script:TempStateDir -Recurse -Force -ErrorAction SilentlyContinue
    # Unmock functions
    # Note: In Pester 5+, mocks are automatically cleaned up
}

Describe "Get-WmrFileState - File Type" {

    It "should capture file content and metadata and save to dynamic_state_path" {
        $testFilePath = Join-Path $script:SourceDir "testfile.txt"
        "Hello World" | Set-Content -Path $testFilePath -Encoding Utf8

        $fileConfig = @{
            name = "Test File"
            path = $testFilePath
            type = "file"
            action = "backup"
            dynamic_state_path = "files/testfile.txt"
            checksum_type = "SHA256"
            encrypt = $false
        }

        $result = Get-WmrFileState -FileConfig $fileConfig -StateFilesDirectory $script:TempStateDir
        $result | Should Not BeNull
        $result.Name | Should Be "Test File"
        $result.Path | Should Be $testFilePath
        $result.Type | Should Be "file"
        $result.Content | Should Not BeNullOrEmpty
        $result.Checksum | Should Not BeNullOrEmpty

        $stateFilePath = Join-Path $script:TempStateDir "files/testfile.txt"
        (Test-Path $stateFilePath) | Should Be $true
        (Get-Content -Path $stateFilePath -Encoding Utf8 -Raw) | Should Be "Hello World"
    }

    It "should simulate encryption for file content if encrypt is true" {
        $testFilePath = Join-Path $script:SourceDir "encrypted_file.txt"
        "Secret Data" | Set-Content -Path $testFilePath -Encoding Utf8

        $fileConfig = @{
            name = "Encrypted File"
            path = $testFilePath
            type = "file"
            action = "backup"
            dynamic_state_path = "files/encrypted_file.txt"
            encrypt = $true
        }

        $result = Get-WmrFileState -FileConfig $fileConfig -StateFilesDirectory $script:TempStateDir
        $result | Should Not BeNull
        $result.Content | Should Not Be "Secret Data" # Should be Base64 encoded due to mock

        $stateFilePath = Join-Path $script:TempStateDir "files/encrypted_file.txt"
        (Test-Path $stateFilePath) | Should Be $true
        # Content saved to file should be the original, encryption happens on the 'state' object
        (Get-Content -Path $stateFilePath -Encoding Utf8 -Raw) | Should Be "Secret Data"
    }

    It "should warn and return null if source path does not exist" {
        $fileConfig = @{
            name = "Non Existent File"
            path = "C:\NonExistent\file.txt"
            type = "file"
            action = "backup"
            dynamic_state_path = "files/nonexistent.txt"
            encrypt = $false
        }
        $result = Get-WmrFileState -FileConfig $fileConfig -StateFilesDirectory $script:TempStateDir
        $result | Should BeNull
    }
}

Describe "Get-WmrFileState - Directory Type" {
    It "should capture directory metadata and save to dynamic_state_path" {
        $testDirPath = Join-Path $script:SourceDir "test_dir"
        New-Item -ItemType Directory -Path $testDirPath -Force | Out-Null
        "file1" | Set-Content -Path (Join-Path $testDirPath "file1.txt")
        New-Item -ItemType Directory -Path (Join-Path $testDirPath "subdir") -Force | Out-Null
        "file2" | Set-Content -Path (Join-Path $testDirPath "subdir\file2.txt")

        $fileConfig = @{
            name = "Test Directory"
            path = $testDirPath
            type = "directory"
            action = "backup"
            dynamic_state_path = "dirs/test_dir_meta.json"
        }

        $result = Get-WmrFileState -FileConfig $fileConfig -StateFilesDirectory $script:TempStateDir
        $result | Should Not BeNull
        $result.Name | Should Be "Test Directory"
        $result.Type | Should Be "directory"
        $result.Contents | Should Not BeNullOrEmpty

        $stateFilePath = Join-Path $script:TempStateDir "dirs/test_dir_meta.json"
        (Test-Path $stateFilePath) | Should Be $true
        $content = (Get-Content -Path $stateFilePath -Encoding Utf8 -Raw) | ConvertFrom-Json
        $content.Count | Should Be 3 # test_dir, file1.txt, subdir, file2.txt
        ($content | Where-Object { $_.FullName -like "*file1.txt" }).FullName | Should Not BeNullOrEmpty
        ($content | Where-Object { $_.FullName -like "*file2.txt" }).FullName | Should Not BeNullOrEmpty

        Remove-Item -Path $testDirPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "Set-WmrFileState - File Type" {

    BeforeEach {
        # Ensure destination is clean
        Remove-Item -Path (Join-Path $script:DestDir "restored_file.txt") -ErrorAction SilentlyContinue
    }

    It "should restore file content from dynamic_state_path" {
        $originalContent = "Content to restore"
        $stateFilePath = Join-Path $script:TempStateDir "files/restore_test.txt"
        $originalContent | Set-Content -Path $stateFilePath -Encoding Utf8

        $fileConfig = @{
            name = "Restore Test File"
            path = "C:\temp\dummy.txt" # Path here doesn't matter for destination if destination is provided
            type = "file"
            action = "restore"
            dynamic_state_path = "files/restore_test.txt"
            destination = (Join-Path $script:DestDir "restored_file.txt")
            encrypt = $false
        }

        Set-WmrFileState -FileConfig $fileConfig -StateFilesDirectory $script:TempStateDir

        $restoredFilePath = Join-Path $script:DestDir "restored_file.txt"
        (Test-Path $restoredFilePath) | Should Be $true
        (Get-Content -Path $restoredFilePath -Encoding Utf8 -Raw) | Should Be $originalContent
    }

    It "should simulate decryption for file content if encrypt is true" {
        $originalContent = "Encrypted Content Test"
        $stateFilePath = Join-Path $script:TempStateDir "files/restore_encrypted.txt"
        $originalContent | Set-Content -Path $stateFilePath -Encoding Utf8 # Content in state file is unencrypted

        $fileConfig = @{
            name = "Restore Encrypted File"
            path = "C:\temp\dummy_encrypted.txt"
            type = "file"
            action = "restore"
            dynamic_state_path = "files/restore_encrypted.txt"
            destination = (Join-Path $script:DestDir "restored_encrypted_file.txt")
            encrypt = $true
        }

        Set-WmrFileState -FileConfig $fileConfig -StateFilesDirectory $script:TempStateDir

        $restoredFilePath = Join-Path $script:DestDir "restored_encrypted_file.txt"
        (Test-Path $restoredFilePath) | Should Be $true
        # Decryption mock means content should be identical to original saved in state file
        (Get-Content -Path $restoredFilePath -Encoding Utf8 -Raw) | Should Be $originalContent
    }

    It "should warn if state file does not exist" {
        $fileConfig = @{
            name = "Missing State File"
            path = "C:\temp\dummy_missing.txt"
            type = "file"
            action = "restore"
            dynamic_state_path = "files/non_existent_state.txt"
            destination = (Join-Path $script:DestDir "should_not_exist.txt")
            encrypt = $false
        }
        Set-WmrFileState -FileConfig $fileConfig -StateFilesDirectory $script:TempStateDir
        (Test-Path (Join-Path $script:DestDir "should_not_exist.txt")) | Should Be $false
    }
}

Describe "Set-WmrFileState - Directory Type" {
    BeforeEach {
        # Ensure destination is clean
        Remove-Item -Path (Join-Path $script:DestDir "restored_dir") -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "should recreate directory structure from dynamic_state_path metadata" {
        $originalContent = @(
            @{ FullName = (Join-Path $script:SourceDir "source_dir\fileA.txt"); Length = 10; LastWriteTimeUtc = (Get-Date).ToUniversalTime() },
            @{ FullName = (Join-Path $script:SourceDir "source_dir\subdirB"); PSIsContainer = $true; Length = 0; LastWriteTimeUtc = (Get-Date).ToUniversalTime() },
            @{ FullName = (Join-Path $script:SourceDir "source_dir\subdirB\fileC.txt"); Length = 20; LastWriteTimeUtc = (Get-Date).ToUniversalTime() }
        )
        $stateFilePath = Join-Path $script:TempStateDir "dirs/restore_dir_meta.json"
        $originalContent | ConvertTo-Json -Compress | Set-Content -Path $stateFilePath -Encoding Utf8

        $fileConfig = @{
            name = "Restore Test Directory"
            path = "C:\temp\dummy_dir"
            type = "directory"
            action = "restore"
            dynamic_state_path = "dirs/restore_dir_meta.json"
            destination = (Join-Path $script:DestDir "restored_dir")
        }

        Set-WmrFileState -FileConfig $fileConfig -StateFilesDirectory $script:TempStateDir

        $restoredDirPath = Join-Path $script:DestDir "restored_dir"
        (Test-Path $restoredDirPath -PathType Container) | Should Be $true
        (Test-Path (Join-Path $restoredDirPath "fileA.txt")) | Should Be $true # File itself is not restored, but path created
        (Test-Path (Join-Path $restoredDirPath "subdirB") -PathType Container) | Should Be $true
        (Test-Path (Join-Path $restoredDirPath "subdirB\fileC.txt")) | Should Be $true # File itself is not restored, but path created
    }
} 