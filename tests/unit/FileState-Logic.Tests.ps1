#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Pure Unit Tests for FileState Logic

.DESCRIPTION
    Tests the FileState functions' logic without any actual file operations.
    Uses mock data and tests the decision-making logic only.

.NOTES
    These are pure unit tests - no file system operations!
    File operation tests are in tests/file-operations/
#>

Describe "FileState Logic Tests" -Tag "Unit", "Logic" {
    
    BeforeAll {
        # Import test environment utilities
        . (Join-Path $PSScriptRoot "..\utilities\Test-Environment.ps1")
        
        # Get standardized test paths
        $script:TestPaths = Get-TestPaths
        
        # Import core functions for testing
        . (Join-Path $script:TestPaths.ModuleRoot "Private\Core\FileState.ps1")
        . (Join-Path $script:TestPaths.ModuleRoot "Private\Core\PathUtilities.ps1")
        . (Join-Path $script:TestPaths.ModuleRoot "Private\Core\EncryptionUtilities.ps1")
        
        # Mock all file system operations
        Mock Test-Path { return $true } -ParameterFilter { $Path -like "*exists*" }
        Mock Test-Path { return $false } -ParameterFilter { $Path -like "*missing*" }
        Mock Get-Content { return "mock file content" }
        Mock Set-Content { }
        Mock New-Item { }
        Mock Get-ChildItem { return @() }
        Mock Get-FileHash { return @{ Hash = "MOCKHASH123" } }
        
        # Mock encryption functions
        Mock Protect-WmrData { 
            param($Data, $Passphrase)
            return "ENCRYPTED:$([Convert]::ToBase64String($Data))"
        }
        Mock Unprotect-WmrData { 
            param($EncodedData, $Passphrase)
            $base64 = $EncodedData -replace '^ENCRYPTED:', ''
            return [Convert]::FromBase64String($base64)
        }
    }
    
    Context "File Configuration Validation Logic" {
        
        It "Should validate required file configuration properties" {
            $validConfig = [PSCustomObject]@{
                name = "Test File"
                path = "C:\test\file.txt"
                type = "file"
                action = "backup"
                dynamic_state_path = "files/test.txt"
            }
            
            # Test that valid config doesn't throw
            { Get-WmrFileState -FileConfig $validConfig -StateFilesDirectory "C:\test" } | Should -Not -Throw
        }
        
        It "Should handle missing path gracefully" {
            $configWithMissingPath = [PSCustomObject]@{
                name = "Missing File"
                path = "C:\test\missing_file.txt"
                type = "file"
                action = "backup"
                dynamic_state_path = "files/missing.txt"
            }
            
            $result = Get-WmrFileState -FileConfig $configWithMissingPath -StateFilesDirectory "C:\test"
            $result | Should -BeNull
        }
        
        It "Should determine encryption requirement correctly" {
            $encryptedConfig = [PSCustomObject]@{
                name = "Encrypted File"
                path = "C:\test\exists_file.txt"
                type = "file"
                action = "backup"
                dynamic_state_path = "files/encrypted.txt"
                encrypt = $true
            }
            
            $result = Get-WmrFileState -FileConfig $encryptedConfig -StateFilesDirectory "C:\test"
            $result.Encrypted | Should -Be $true
        }
    }
    
    Context "File Type Detection Logic" {
        
        It "Should correctly identify file type" {
            $fileConfig = [PSCustomObject]@{
                name = "Test File"
                path = "C:\test\exists_file.txt"
                type = "file"
                action = "backup"
                dynamic_state_path = "files/test.txt"
            }
            
            $result = Get-WmrFileState -FileConfig $fileConfig -StateFilesDirectory "C:\test"
            $result.Type | Should -Be "file"
        }
        
        It "Should correctly identify directory type" {
            $dirConfig = [PSCustomObject]@{
                name = "Test Directory"
                path = "C:\test\exists_dir"
                type = "directory"
                action = "backup"
                dynamic_state_path = "dirs/test.json"
            }
            
            $result = Get-WmrFileState -FileConfig $dirConfig -StateFilesDirectory "C:\test"
            $result.Type | Should -Be "directory"
        }
    }
    
    Context "State Path Generation Logic" {
        
        It "Should generate correct state file path" {
            $config = [PSCustomObject]@{
                name = "Test File"
                path = "C:\test\exists_file.txt"
                type = "file"
                action = "backup"
                dynamic_state_path = "custom/path/file.txt"
            }
            
            # The function should use the dynamic_state_path correctly
            Get-WmrFileState -FileConfig $config -StateFilesDirectory "C:\StateDir"
            
            # Verify Set-Content was called with the correct path
            Should -Invoke Set-Content -ParameterFilter { 
                $Path -eq "C:\StateDir\custom\path\file.txt" 
            }
        }
        
        It "Should handle nested directory paths in dynamic_state_path" {
            $config = [PSCustomObject]@{
                name = "Nested File"
                path = "C:\test\exists_file.txt"
                type = "file"
                action = "backup"
                dynamic_state_path = "level1/level2/level3/nested.txt"
            }
            
            Get-WmrFileState -FileConfig $config -StateFilesDirectory "C:\StateDir"
            
            # Should create parent directories
            Should -Invoke New-Item -ParameterFilter { 
                $ItemType -eq "Directory" -and $Path -like "*level1*level2*level3*"
            }
        }
    }
    
    Context "Restore Logic Decision Making" {
        
        It "Should use destination path when provided" {
            $config = [PSCustomObject]@{
                name = "Restore File"
                path = "C:\original\path.txt"
                type = "file"
                action = "restore"
                dynamic_state_path = "files/restore.txt"
                destination = "C:\custom\destination.txt"
            }
            
            Set-WmrFileState -FileConfig $config -StateFilesDirectory "C:\StateDir"
            
            # Should restore to destination, not original path
            Should -Invoke Set-Content -ParameterFilter { 
                $Path -eq "C:\custom\destination.txt"
            }
        }
        
        It "Should fall back to original path when no destination provided" {
            $config = [PSCustomObject]@{
                name = "Restore File"
                path = "C:\original\exists_path.txt"
                type = "file"
                action = "restore"
                dynamic_state_path = "files/restore.txt"
            }
            
            Set-WmrFileState -FileConfig $config -StateFilesDirectory "C:\StateDir"
            
            # Should restore to original path
            Should -Invoke Set-Content -ParameterFilter { 
                $Path -eq "C:\original\exists_path.txt"
            }
        }
    }
    
    Context "Encryption Logic" {
        
        It "Should apply encryption when encrypt flag is true" {
            $config = [PSCustomObject]@{
                name = "Encrypted File"
                path = "C:\test\exists_file.txt"
                type = "file"
                action = "backup"
                dynamic_state_path = "files/encrypted.txt"
                encrypt = $true
            }
            
            $result = Get-WmrFileState -FileConfig $config -StateFilesDirectory "C:\test" -Passphrase (ConvertTo-SecureString "test" -AsPlainText -Force)
            
            # Should call encryption function
            Should -Invoke Protect-WmrData
            $result.Encrypted | Should -Be $true
        }
        
        It "Should skip encryption when encrypt flag is false" {
            $config = [PSCustomObject]@{
                name = "Plain File"
                path = "C:\test\exists_file.txt"
                type = "file"
                action = "backup"
                dynamic_state_path = "files/plain.txt"
                encrypt = $false
            }
            
            $result = Get-WmrFileState -FileConfig $config -StateFilesDirectory "C:\test"
            
            # Should not call encryption function
            Should -Not -Invoke Protect-WmrData
            $result.Encrypted | Should -Be $false
        }
        
        It "Should apply decryption during restore when encrypt flag is true" {
            $config = [PSCustomObject]@{
                name = "Decrypt File"
                path = "C:\test\restore.txt"
                type = "file"
                action = "restore"
                dynamic_state_path = "files/encrypted.txt"
                encrypt = $true
            }
            
            # Mock encrypted content
            Mock Get-Content { return "ENCRYPTED:dGVzdCBjb250ZW50" }
            
            Set-WmrFileState -FileConfig $config -StateFilesDirectory "C:\test" -Passphrase (ConvertTo-SecureString "test" -AsPlainText -Force)
            
            # Should call decryption function
            Should -Invoke Unprotect-WmrData
        }
    }
    
    Context "Error Handling Logic" {
        
        It "Should handle missing state file gracefully" {
            $config = [PSCustomObject]@{
                name = "Missing State"
                path = "C:\test\restore.txt"
                type = "file"
                action = "restore"
                dynamic_state_path = "files/missing_state.txt"
            }
            
            Mock Test-Path { return $false }
            
            { Set-WmrFileState -FileConfig $config -StateFilesDirectory "C:\test" } | Should -Not -Throw
        }
        
        It "Should validate state directory exists" {
            $config = [PSCustomObject]@{
                name = "Test File"
                path = "C:\test\exists_file.txt"
                type = "file"
                action = "backup"
                dynamic_state_path = "files/test.txt"
            }
            
            # Should check if state directory exists and create if needed
            Get-WmrFileState -FileConfig $config -StateFilesDirectory "C:\NewStateDir"
            
            Should -Invoke New-Item -ParameterFilter { $ItemType -eq "Directory" }
        }
    }
} 