# tests/unit/FileState.Tests.ps1

# Disable confirmation prompts
$ConfirmPreference = 'None'

BeforeAll {
    # Import test environment utilities
    . (Join-Path $PSScriptRoot "..\utilities\Test-Environment.ps1")

    # Get standardized test paths
    $script:TestPaths = Get-TestPaths

    # Import core files directly for unit testing
    . (Join-Path $script:TestPaths.ModuleRoot "Private\Core\FileState.ps1")
    . (Join-Path $script:TestPaths.ModuleRoot "Private\Core\PathUtilities.ps1")
    . (Join-Path $script:TestPaths.ModuleRoot "Private\Core\EncryptionUtilities.ps1")

    # Import test utilities if they exist
    $testHelperPath = Join-Path $PSScriptRoot "..\utilities\TestHelper.ps1"
    if (Test-Path $testHelperPath) {
        . $testHelperPath
    }

    $encryptionHelperPath = Join-Path $PSScriptRoot "..\utilities\EncryptionTestHelper.ps1"
    if (Test-Path $encryptionHelperPath) {
        . $encryptionHelperPath
    }

    # Use standardized test directories
    $script:testStateDir = Join-Path $script:TestPaths.TestRestore "state"
    $script:testDataDir = Join-Path $script:TestPaths.TestRestore "data"
    $script:SourceDir = Join-Path $script:TestPaths.TestRestore "source"
    $script:DestDir = Join-Path $script:TestPaths.TestRestore "dest"
    $script:TempStateDir = Join-Path $script:TestPaths.Temp "FileStateTests"
    $script:testPassphrase = ConvertTo-SecureString -String "TestPassphrase123!" -AsPlainText -Force

    # Function to safely remove items
    function Remove-TestItems {
        param([string]$Path)
        if ((Test-Path $Path) -and (Test-SafeTestPath $Path)) {
            Remove-Item -Path $Path -Force -Recurse -ErrorAction SilentlyContinue -Confirm:$false
        }
    }

    # Create fresh test directories
    New-Item -ItemType Directory -Path $script:testStateDir -Force | Out-Null
    New-Item -ItemType Directory -Path $script:testDataDir -Force | Out-Null
    New-Item -ItemType Directory -Path $script:SourceDir -Force | Out-Null
    New-Item -ItemType Directory -Path $script:DestDir -Force | Out-Null
    New-Item -ItemType Directory -Path $script:TempStateDir -Force | Out-Null

    # Mock encryption functions
    Mock Protect-WmrData {
        param($Data, $Passphrase)
        $base64 = [Convert]::ToBase64String($Data)
        return "ENCRYPTED:$base64"
    }

    Mock Unprotect-WmrData {
        param($EncodedData, $Passphrase)
        $base64 = $EncodedData -replace '^ENCRYPTED:', ''
        return [Convert]::FromBase64String($base64)
    }

    # Helper function to create test files
    function New-TestFile {
        param($Path, $Content)
        $parent = Split-Path -Path $Path -Parent
        if (-not (Test-Path $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        Set-Content -Path $Path -Value $Content -NoNewline -Encoding UTF8
    }
}

AfterAll {
    # Clean up temporary directories safely
    if ($script:TempStateDir -and (Test-SafeTestPath $script:TempStateDir)) {
        Remove-Item -Path $script:TempStateDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "Get-WmrFileState - File Type" {

    BeforeEach {
        # Clean up test files before each test
        Get-ChildItem -Path $script:SourceDir -Recurse | Remove-Item -Force -Recurse -Confirm:$false -ErrorAction SilentlyContinue
    }

    It "should capture file content and metadata and save to dynamic_state_path" {
        $testFilePath = Join-Path $script:SourceDir "testfile.txt"
        New-TestFile -Path $testFilePath -Content "Hello World"

        $fileConfig = [PSCustomObject]@{
            name = "Test File"
            path = $testFilePath
            type = "file"
            action = "backup"
            dynamic_state_path = "files/testfile.txt"
            checksum_type = "SHA256"
            encrypt = $false
        }

        $result = Get-WmrFileState -FileConfig $fileConfig -StateFilesDirectory $script:TempStateDir
        $result | Should -Not -BeNull
        $result.Name | Should -Be "Test File"
        # Normalize path separators for cross-platform compatibility
        $expectedPath = $testFilePath -replace '\\', '/'
        $actualPath = $result.Path -replace '\\', '/'
        $actualPath | Should -Be $expectedPath
        $result.Type | Should -Be "file"
        $result.Content | Should -Not -BeNullOrEmpty
        $result.Checksum | Should -Not -BeNullOrEmpty

        $stateFilePath = Join-Path $script:TempStateDir "files/testfile.txt"
        Test-Path $stateFilePath | Should -Be $true
        Get-Content -Path $stateFilePath -Encoding Utf8 -Raw | Should -Be "Hello World"
    }

    It "should simulate encryption for file content if encrypt is true" {
        $testFilePath = Join-Path $script:SourceDir "encrypted_file.txt"
        New-TestFile -Path $testFilePath -Content "Secret Data"

        $fileConfig = [PSCustomObject]@{
            name = "Encrypted File"
            path = $testFilePath
            type = "file"
            action = "backup"
            dynamic_state_path = "files/encrypted_file.txt"
            encrypt = $true
        }

        $result = Get-WmrFileState -FileConfig $fileConfig -StateFilesDirectory $script:TempStateDir -Passphrase $script:testPassphrase
        $result | Should -Not -BeNull
        $result.Content | Should -BeLike "ENCRYPTED:*" # Should be encrypted due to mock
        $result.Encrypted | Should -Be $true

        $stateFilePath = Join-Path $script:TempStateDir "files/encrypted_file.txt"
        Test-Path $stateFilePath | Should -Be $true
        Get-Content -Path $stateFilePath -Encoding Utf8 -Raw | Should -BeLike "ENCRYPTED:*"
    }

    It "should warn and return null if source path does not exist" {
        $fileConfig = [PSCustomObject]@{
            name = "Non Existent File"
            path = (Join-Path $script:SourceDir "nonexistent.txt")
            type = "file"
            action = "backup"
            dynamic_state_path = "files/nonexistent.txt"
            encrypt = $false
        }
        $result = Get-WmrFileState -FileConfig $fileConfig -StateFilesDirectory $script:TempStateDir
        $result | Should -BeNull
    }
}

Describe "Get-WmrFileState - Directory Type" {
    BeforeEach {
        # Clean up test directories before each test
        Get-ChildItem -Path $script:SourceDir -Recurse | Remove-Item -Force -Recurse -Confirm:$false -ErrorAction SilentlyContinue
    }

    It "should capture directory metadata and save to dynamic_state_path" {
        $testDirPath = Join-Path $script:SourceDir "test_dir"
        New-Item -ItemType Directory -Path $testDirPath -Force | Out-Null
        New-TestFile -Path (Join-Path $testDirPath "file1.txt") -Content "file1"
        New-Item -ItemType Directory -Path (Join-Path $testDirPath "subdir") -Force | Out-Null
        New-TestFile -Path (Join-Path $testDirPath "subdir/file2.txt") -Content "file2"

        $fileConfig = [PSCustomObject]@{
            name = "Test Directory"
            path = $testDirPath
            type = "directory"
            action = "backup"
            dynamic_state_path = "dirs/test_dir_meta.json"
        }

        $result = Get-WmrFileState -FileConfig $fileConfig -StateFilesDirectory $script:TempStateDir
        $result | Should -Not -BeNull
        $result.Name | Should -Be "Test Directory"
        $result.Type | Should -Be "directory"
        $result.Contents | Should -Not -BeNullOrEmpty

        $stateFilePath = Join-Path $script:TempStateDir "dirs/test_dir_meta.json"
        Test-Path $stateFilePath | Should -Be $true
        $content = Get-Content -Path $stateFilePath -Encoding Utf8 -Raw | ConvertFrom-Json
        $content.Count | Should -BeGreaterThan 2 # Should include test_dir, file1.txt, subdir, file2.txt
        ($content | Where-Object { $_.FullName -like "*file1.txt" }).FullName | Should -Not -BeNullOrEmpty
        ($content | Where-Object { $_.FullName -like "*file2.txt" }).FullName | Should -Not -BeNullOrEmpty
    }
}

Describe "Set-WmrFileState - File Type" {
    BeforeEach {
        # Clean up test directories before each test
        Remove-TestItems -Path $script:DestDir
        Remove-TestItems -Path $script:TempStateDir

        # Recreate test directories
        New-Item -ItemType Directory -Path $script:DestDir -Force | Out-Null
        New-Item -ItemType Directory -Path $script:TempStateDir -Force | Out-Null
    }

    It "should restore file content from dynamic_state_path" {
        $stateFilePath = Join-Path $script:TempStateDir "files/restore_test.txt"
        New-TestFile -Path $stateFilePath -Content "Content to restore"

        $fileConfig = [PSCustomObject]@{
            name = "Restore Test File"
            path = (Join-Path $script:SourceDir "dummy.txt") # Path here doesn't matter if destination is provided
            type = "file"
            action = "restore"
            dynamic_state_path = "files/restore_test.txt"
            destination = (Join-Path $script:DestDir "restored_file.txt")
            encrypt = $false
        }

        Set-WmrFileState -FileConfig $fileConfig -StateFilesDirectory $script:TempStateDir

        $restoredFilePath = Join-Path $script:DestDir "restored_file.txt"
        Test-Path $restoredFilePath | Should -Be $true
        Get-Content -Path $restoredFilePath -Encoding Utf8 -Raw | Should -Be "Content to restore"
    }

    It "should simulate decryption for file content if encrypt is true" {
        $stateFilePath = Join-Path $script:TempStateDir "files/restore_encrypted.txt"
        $encryptedContent = "ENCRYPTED:$(([Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes('Encrypted Content Test'))))"
        New-TestFile -Path $stateFilePath -Content $encryptedContent

        $fileConfig = [PSCustomObject]@{
            name = "Restore Encrypted File"
            path = (Join-Path $script:SourceDir "dummy_encrypted.txt")
            type = "file"
            action = "restore"
            dynamic_state_path = "files/restore_encrypted.txt"
            destination = (Join-Path $script:DestDir "restored_encrypted_file.txt")
            encrypt = $true
        }

        Set-WmrFileState -FileConfig $fileConfig -StateFilesDirectory $script:TempStateDir -Passphrase $script:testPassphrase

        $restoredFilePath = Join-Path $script:DestDir "restored_encrypted_file.txt"
        Test-Path $restoredFilePath | Should -Be $true
        Get-Content -Path $restoredFilePath -Encoding Utf8 -Raw | Should -Be "Encrypted Content Test"
    }
}

Describe "Set-WmrFileState - Directory Type" {
    BeforeEach {
        # Clean up test directories before each test
        Remove-TestItems -Path $script:DestDir -Recurse -Force
        Remove-TestItems -Path $script:TempStateDir -Recurse -Force

        # Recreate test directories
        New-Item -ItemType Directory -Path $script:DestDir -Force | Out-Null
        New-Item -ItemType Directory -Path $script:TempStateDir -Force | Out-Null
    }

    It "should recreate directory structure from dynamic_state_path metadata" {
        # Create a simple test directory structure
        $testDirPath = Join-Path $script:SourceDir "test_dir"
        Write-Debug "Test directory path: $testDirPath"
        New-Item -ItemType Directory -Path $testDirPath -Force | Out-Null

        # Create test files
        $file1Path = Join-Path $testDirPath "file1.txt"
        $subdirPath = Join-Path $testDirPath "subdir"
        $file2Path = Join-Path $subdirPath "file2.txt"

        Write-Debug "Creating test files:"
        Write-Debug "  file1: $file1Path"
        Write-Debug "  subdir: $subdirPath"
        Write-Debug "  file2: $file2Path"

        New-Item -ItemType Directory -Path $subdirPath -Force | Out-Null
        Set-Content -Path $file1Path -Value "file1" -NoNewline
        Set-Content -Path $file2Path -Value "file2" -NoNewline

        # Create backup config
        $backupConfig = [PSCustomObject]@{
            name = "Test Directory"
            path = $testDirPath
            type = "directory"
            action = "backup"
            dynamic_state_path = "dirs/test_dir.json"
        }

        Write-Debug "Backup config:"
        Write-Debug ($backupConfig | ConvertTo-Json)

        # Backup the directory structure
        $result = Get-WmrFileState -FileConfig $backupConfig -StateFilesDirectory $script:TempStateDir
        $result | Should -Not -BeNull

        Write-Debug "Backup result:"
        Write-Debug ($result | ConvertTo-Json -Depth 10)

        # Create restore config
        $restoredDirPath = Join-Path $script:DestDir "restored_dir"
        Write-Debug "Restored directory path: $restoredDirPath"

        $restoreConfig = [PSCustomObject]@{
            name = "Test Directory"
            path = $testDirPath
            type = "directory"
            action = "restore"
            dynamic_state_path = "dirs/test_dir.json"
            destination = $restoredDirPath
        }

        Write-Debug "Restore config:"
        Write-Debug ($restoreConfig | ConvertTo-Json)

        # Restore the directory structure
        Set-WmrFileState -FileConfig $restoreConfig -StateFilesDirectory $script:TempStateDir

        # Verify paths exist (cross-platform compatible)
        $file1Path = Join-Path $restoredDirPath "file1.txt"
        $subdirPath = Join-Path $restoredDirPath "subdir"
        $file2Path = Join-Path $subdirPath "file2.txt"

        Write-Debug "Verifying paths:"
        Write-Debug "  $file1Path exists: $(Test-Path $file1Path)"
        Write-Debug "  $subdirPath exists: $(Test-Path $subdirPath)"
        Write-Debug "  $file2Path exists: $(Test-Path $file2Path)"

        # Verify the directory structure was recreated
        Test-Path $file1Path | Should -Be $true
        Test-Path $subdirPath | Should -Be $true
        Test-Path $file2Path | Should -Be $true
    }

    It "Should restore directory structure" {
        # Arrange
        $dirContent = @(
            @{
                FullName = "C:\testdir\file1.txt"
                Length = 10
                LastWriteTimeUtc = (Get-Date).ToUniversalTime()
                PSIsContainer = $false
                RelativePath = "file1.txt"
            },
            @{
                FullName = "C:\testdir\subdir"
                Length = 0
                LastWriteTimeUtc = (Get-Date).ToUniversalTime()
                PSIsContainer = $true
                RelativePath = "subdir"
            },
            @{
                FullName = "C:\testdir\subdir\file2.txt"
                Length = 10
                LastWriteTimeUtc = (Get-Date).ToUniversalTime()
                PSIsContainer = $false
                RelativePath = "subdir\file2.txt"
            }
        )

        $stateFilePath = Join-Path -Path $script:testStateDir -ChildPath "testdir.json"
        $dirContent | ConvertTo-Json -Compress | Set-Content -Path $stateFilePath -NoNewline

        $destinationPath = Join-Path -Path $script:testDataDir -ChildPath "restored_dir"
        $fileConfig = [PSCustomObject]@{
            name = "testdir"
            path = "C:\testdir"
            destination = $destinationPath
            type = "directory"
            dynamic_state_path = "testdir.json"
        }

        # Act
        Set-WmrFileState -FileConfig $fileConfig -StateFilesDirectory $script:testStateDir

        # Assert (cross-platform compatible)
        $file1Path = Join-Path $destinationPath "file1.txt"
        $subdirPath = Join-Path $destinationPath "subdir"
        $file2Path = Join-Path $subdirPath "file2.txt"

        Test-Path $file1Path | Should -Be $true
        Test-Path $subdirPath | Should -Be $true
        Test-Path $file2Path | Should -Be $true
    }
}

Describe "FileState" {
    BeforeEach {
        # Clean test directories before each test
        Remove-TestItems -Path $script:testStateDir
        Remove-TestItems -Path $script:testDataDir

        # Recreate test directories
        New-Item -ItemType Directory -Path $script:testStateDir -Force | Out-Null
        New-Item -ItemType Directory -Path $script:testDataDir -Force | Out-Null
    }

    Context "Get-WmrFileState" {
        It "Should backup plain text file without encryption" {
            # Arrange
            $testFile = Join-Path -Path $script:testDataDir -ChildPath "test.txt"
            $testContent = "Test content`nwith multiple lines"
            New-TestFile -Path $testFile -Content $testContent

            $fileConfig = [PSCustomObject]@{
                name = "test"
                path = $testFile
                type = "file"
                encrypt = $false
                dynamic_state_path = "test.txt"
            }

            # Act
            $result = Get-WmrFileState -FileConfig $fileConfig -StateFilesDirectory $script:testStateDir

            # Assert
            $result | Should -Not -BeNull
            $result.Name | Should -Be "test"
            $result.Type | Should -Be "file"
            $result.Encrypted | Should -Be $false

            # Verify state file
            $stateFilePath = Join-Path -Path $script:testStateDir -ChildPath "test.txt"
            $savedContent = Get-Content -Path $stateFilePath -Raw
            $savedContent | Should -Be $testContent
        }

        It "Should backup encrypted file with provided passphrase" {
            # Arrange
            $testFile = Join-Path -Path $script:testDataDir -ChildPath "secret.txt"
            $testContent = "Secret content`nto be encrypted"
            New-TestFile -Path $testFile -Content $testContent

            $fileConfig = [PSCustomObject]@{
                name = "secret"
                path = $testFile
                type = "file"
                encrypt = $true
                dynamic_state_path = "secret.txt"
            }

            # Act
            $result = Get-WmrFileState -FileConfig $fileConfig -StateFilesDirectory $script:testStateDir -Passphrase $script:testPassphrase

            # Assert
            $result | Should -Not -BeNull
            $result.Name | Should -Be "secret"
            $result.Type | Should -Be "file"
            $result.Encrypted | Should -Be $true

            # Verify state file
            $stateFilePath = Join-Path -Path $script:testStateDir -ChildPath "secret.txt"
            $savedContent = Get-Content -Path $stateFilePath -Raw
            $savedContent | Should -Match "^ENCRYPTED:"

            # Verify metadata
            $metadataPath = $stateFilePath -replace '\.[^.]+$', '.metadata.json'
            $metadata = Get-Content -Path $metadataPath -Raw | ConvertFrom-Json
            $metadata.Encrypted | Should -Be $true
            $metadata.Encoding | Should -Be "UTF8"
        }

        It "Should backup directory structure" {
            # Arrange
            $testDir = Join-Path -Path $script:testDataDir -ChildPath "testdir"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            New-Item -ItemType Directory -Path "$testDir/subdir" -Force | Out-Null
            New-TestFile -Path "$testDir/file1.txt" -Content "File 1"
            New-TestFile -Path "$testDir/subdir/file2.txt" -Content "File 2"

            $fileConfig = [PSCustomObject]@{
                name = "testdir"
                path = $testDir
                type = "directory"
                dynamic_state_path = "testdir.json"
            }

            # Act
            $result = Get-WmrFileState -FileConfig $fileConfig -StateFilesDirectory $script:testStateDir

            # Assert
            $result | Should -Not -BeNull
            $result.Name | Should -Be "testdir"
            $result.Type | Should -Be "directory"

            # Verify state file
            $stateFilePath = Join-Path -Path $script:testStateDir -ChildPath "testdir.json"
            $dirContent = Get-Content -Path $stateFilePath -Raw | ConvertFrom-Json
            $dirContent.Count | Should -BeGreaterThan 0
            $dirContent | Where-Object { $_.FullName -like "*file1.txt" } | Should -Not -BeNull
            $dirContent | Where-Object { $_.FullName -like "*file2.txt" } | Should -Not -BeNull
        }
    }

    Context "Set-WmrFileState" {
        It "Should restore plain text file without encryption" {
            # Arrange
            $testContent = "Test content`nto restore"
            $stateFilePath = Join-Path -Path $script:testStateDir -ChildPath "test.txt"
            New-TestFile -Path $stateFilePath -Content $testContent

            $destinationPath = Join-Path -Path $script:testDataDir -ChildPath "restored.txt"
            $fileConfig = [PSCustomObject]@{
                name = "test"
                path = $destinationPath
                type = "file"
                encrypt = $false
                dynamic_state_path = "test.txt"
            }

            # Act
            Set-WmrFileState -FileConfig $fileConfig -StateFilesDirectory $script:testStateDir

            # Assert
            Test-Path $destinationPath | Should -Be $true
            $restoredContent = Get-Content -Path $destinationPath -Raw
            $restoredContent | Should -Be $testContent
        }

        It "Should restore encrypted file with provided passphrase" {
            # Arrange
            $testContent = "Secret content`nto restore"
            $contentBytes = [System.Text.Encoding]::UTF8.GetBytes($testContent)
            $encryptedContent = "ENCRYPTED:" + [Convert]::ToBase64String($contentBytes)

            $stateFilePath = Join-Path -Path $script:testStateDir -ChildPath "secret.txt"
            New-TestFile -Path $stateFilePath -Content $encryptedContent

            # Create metadata file
            $metadataPath = $stateFilePath -replace '\.[^.]+$', '.metadata.json'
            $metadata = @{
                Encrypted = $true
                Encoding = "UTF8"
                OriginalSize = $contentBytes.Length
            }
            $metadata | ConvertTo-Json | Set-Content -Path $metadataPath -NoNewline

            $destinationPath = Join-Path -Path $script:testDataDir -ChildPath "restored_secret.txt"
            $fileConfig = [PSCustomObject]@{
                name = "secret"
                path = $destinationPath
                type = "file"
                encrypt = $true
                dynamic_state_path = "secret.txt"
            }

            # Act
            Set-WmrFileState -FileConfig $fileConfig -StateFilesDirectory $script:testStateDir -Passphrase $script:testPassphrase

            # Assert
            Test-Path $destinationPath | Should -Be $true
            $restoredContent = Get-Content -Path $destinationPath -Raw
            $restoredContent | Should -Be $testContent
        }

        It "Should restore directory structure" {
            # Arrange
            $dirContent = @(
                @{
                    FullName = "C:\testdir\file1.txt"
                    Length = 10
                    LastWriteTimeUtc = (Get-Date).ToUniversalTime()
                    PSIsContainer = $false
                    RelativePath = "file1.txt"
                },
                @{
                    FullName = "C:\testdir\subdir"
                    Length = 0
                    LastWriteTimeUtc = (Get-Date).ToUniversalTime()
                    PSIsContainer = $true
                    RelativePath = "subdir"
                },
                @{
                    FullName = "C:\testdir\subdir\file2.txt"
                    Length = 10
                    LastWriteTimeUtc = (Get-Date).ToUniversalTime()
                    PSIsContainer = $false
                    RelativePath = "subdir\file2.txt"
                }
            )

            $stateFilePath = Join-Path -Path $script:testStateDir -ChildPath "testdir.json"
            $dirContent | ConvertTo-Json -Compress | Set-Content -Path $stateFilePath -NoNewline

            $destinationPath = Join-Path -Path $script:testDataDir -ChildPath "restored_dir"
            $fileConfig = [PSCustomObject]@{
                name = "testdir"
                path = "C:\testdir"
                destination = $destinationPath
                type = "directory"
                dynamic_state_path = "testdir.json"
            }

            # Act
            Set-WmrFileState -FileConfig $fileConfig -StateFilesDirectory $script:testStateDir

            # Assert (cross-platform compatible)
            $file1Path = Join-Path $destinationPath "file1.txt"
            $subdirPath = Join-Path $destinationPath "subdir"
            $file2Path = Join-Path $subdirPath "file2.txt"

            Test-Path $file1Path | Should -Be $true
            Test-Path $subdirPath | Should -Be $true
            Test-Path $file2Path | Should -Be $true
        }
    }
}





