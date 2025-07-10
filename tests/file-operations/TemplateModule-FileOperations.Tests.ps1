# tests/file-operations/TemplateModule-FileOperations.Tests.ps1

<#
.SYNOPSIS
    File Operations Tests for TemplateModule

.DESCRIPTION
    Tests the TemplateModule functions' file operations within safe test directories.
    Performs actual file operations but only in designated test paths.

.NOTES
    These are file operation tests - they create and manipulate actual files!
    Pure logic tests are in tests/unit/TemplateModule-Logic.Tests.ps1
#>

BeforeAll {
    # Import Docker test bootstrap for mock functions
    if (Test-Path "/usr/local/share/powershell/Modules/Docker-Test-Bootstrap.ps1") {
        . "/usr/local/share/powershell/Modules/Docker-Test-Bootstrap.ps1"
    }
    
    # Import the module using standardized pattern
    $ModulePath = Resolve-Path "$PSScriptRoot/../../WindowsMelodyRecovery.psd1"
    try {
        Import-Module $ModulePath -Force -ErrorAction Stop
    }
    catch {
        throw "Failed to import module from $ModulePath : $($_.Exception.Message)"
    }
}

Describe "TemplateModule File Operations" -Tag "FileOperations", "Safe" {
    
    BeforeAll {
        # Set up test template path in Docker-safe location
        $script:TempTemplatePath = "/workspace/Temp/test_template.yaml"
        $script:TempTemplateDir = "/workspace/Temp"
        
        # Ensure Temp directory exists
        if (-not (Test-Path $script:TempTemplateDir)) {
            New-Item -Path $script:TempTemplateDir -ItemType Directory -Force | Out-Null
        }
        
        # Create a basic test template file
        $basicTemplateContent = @"
metadata:
  name: Test Template
  description: Test template for file operations
  version: "1.0"
prerequisites:
  - type: script
    name: Dummy Prereq
    inline_script: "Write-Output 'test'"
    expected_output: "test"
    on_missing: warn
"@
        $basicTemplateContent | Out-File -FilePath $script:TempTemplatePath -Encoding UTF8 -Force
    }

    AfterAll {
        # Clean up the dummy template file
        Remove-Item -Path $script:TempTemplatePath -Force -ErrorAction SilentlyContinue
        # Optionally remove the Temp directory if empty or if it was created by the test
    }

    Context "Template File Reading and Writing" {

        It "should read and parse a valid YAML template file from disk" {
            $config = Read-WmrTemplateConfig -TemplatePath $script:TempTemplatePath
            $config | Should -Not -BeNullOrEmpty
            $config.metadata.name | Should -Be "Test Template"
            $config.metadata.version | Should -Be "1.0"
            $config.prerequisites.Count | Should -Be 1
            $config.prerequisites[0].name | Should -Be "Dummy Prereq"
        }

        It "should throw an error if the template file does not exist" {
            { Read-WmrTemplateConfig -TemplatePath "NonExistentFile.yaml" } | Should -Throw "Template file not found: NonExistentFile.yaml"
        }

        It "should throw an error if the YAML content is invalid" {
            $invalidYamlPath = Join-Path $PSScriptRoot "..\..\Temp\invalid.yaml"
            # Create truly invalid YAML that will cause ConvertFrom-Yaml to fail
            @"
metadata:
  name: Test
  invalid_structure: [
    - item1
    - item2
  unclosed_array: true
"@ | Set-Content -Path $invalidYamlPath -Encoding Utf8
            
            try {
                { Read-WmrTemplateConfig -TemplatePath $invalidYamlPath } | Should -Throw
            } finally {
                Remove-Item -Path $invalidYamlPath -ErrorAction SilentlyContinue
            }
        }

        It "should handle UTF-8 encoding correctly in template files" {
            $utf8TemplatePath = Join-Path $PSScriptRoot "..\..\Temp\utf8_template.yaml"
            $utf8Content = @"
metadata:
  name: "UTF-8 测试模板"
  description: "A template with UTF-8 characters: 中文, émojis 🚀"
  version: "1.0"
prerequisites: []
"@
            $utf8Content | Set-Content -Path $utf8TemplatePath -Encoding Utf8

            try {
                $config = Read-WmrTemplateConfig -TemplatePath $utf8TemplatePath
                $config.metadata.name | Should -Be "UTF-8 测试模板"
                $config.metadata.description | Should -Match "émojis 🚀"
            } finally {
                Remove-Item -Path $utf8TemplatePath -ErrorAction SilentlyContinue
            }
        }
    }

    Context "Template File Discovery and Path Resolution" {

        It "should handle relative paths correctly" {
            # Create a nested template structure
            $nestedDir = Join-Path $PSScriptRoot "..\..\Temp\system"
            $nestedTemplatePath = Join-Path $nestedDir "nested_template.yaml"
            
            if (-not (Test-Path $nestedDir -PathType Container)) {
                New-Item -ItemType Directory -Path $nestedDir -Force | Out-Null
            }

            $nestedContent = @"
metadata:
  name: Nested Template
  description: A template in a nested directory
  version: "1.0"
prerequisites: []
"@
            $nestedContent | Set-Content -Path $nestedTemplatePath -Encoding Utf8

            try {
                $config = Read-WmrTemplateConfig -TemplatePath $nestedTemplatePath
                $config.metadata.name | Should -Be "Nested Template"
            } finally {
                Remove-Item -Path $nestedTemplatePath -Force -ErrorAction SilentlyContinue
                Remove-Item -Path $nestedDir -Force -ErrorAction SilentlyContinue
            }
        }

        It "should handle absolute paths correctly" {
            $absolutePath = $script:TempTemplatePath
            $config = Read-WmrTemplateConfig -TemplatePath $absolutePath
            $config.metadata.name | Should -Be "Test Template"
        }

        It "should validate file extensions" {
            $validExtensions = @(".yaml", ".yml")
            
            foreach ($ext in $validExtensions) {
                $testPath = Join-Path $PSScriptRoot "..\..\Temp\test_extension$ext"
                $script:TempTemplatePath | Split-Path | Join-Path -ChildPath "test_template.yaml" | Get-Content | Set-Content -Path $testPath -Encoding Utf8

                try {
                    { Read-WmrTemplateConfig -TemplatePath $testPath } | Should -Not -Throw
                } finally {
                    Remove-Item -Path $testPath -ErrorAction SilentlyContinue
                }
            }
        }
    }

    Context "Template Schema Validation with File Operations" {

        It "should pass validation for a complete template file" {
            $completeTemplatePath = Join-Path $PSScriptRoot "..\..\Temp\complete_template.yaml"
            $completeContent = @"
metadata:
  name: Complete Template
  description: A complete template with all sections
  version: "1.0"
  type: system
prerequisites:
  - type: script
    name: Test Prereq
    inline_script: "Write-Output 'test'"
    expected_output: "test"
    on_missing: warn
files:
  - name: Test File
    path: "C:\test\file.txt"
    type: file
    action: backup
    dynamic_state_path: "files/test.txt"
registry:
  - name: Test Registry
    path: "HKCU:\Software\Test"
    action: backup
    dynamic_state_path: "registry/test.json"
applications:
  - name: Test Apps
    type: winget
    dynamic_state_path: "apps/test.json"
    discovery_command: "winget list"
    parse_script: "return '[]'"
    install_script: "echo 'install'"
"@
            $completeContent | Set-Content -Path $completeTemplatePath -Encoding Utf8

            try {
                $config = Read-WmrTemplateConfig -TemplatePath $completeTemplatePath
                { Test-WmrTemplateSchema -TemplateConfig $config } | Should -Not -Throw
            } finally {
                Remove-Item -Path $completeTemplatePath -ErrorAction SilentlyContinue
            }
        }

        It "should fail validation for template missing required metadata" {
            $incompleteTemplatePath = Join-Path $PSScriptRoot "..\..\Temp\incomplete_template.yaml"
            $incompleteContent = @"
metadata:
  description: Missing name
  version: "1.0"
prerequisites: []
"@
            $incompleteContent | Set-Content -Path $incompleteTemplatePath -Encoding Utf8

            try {
                $config = Read-WmrTemplateConfig -TemplatePath $incompleteTemplatePath
                { Test-WmrTemplateSchema -TemplateConfig $config } | Should -Throw "Template schema validation failed: 'metadata.name' is missing."
            } finally {
                Remove-Item -Path $incompleteTemplatePath -ErrorAction SilentlyContinue
            }
        }
    }

    Context "Template File Backup and Versioning" {

        It "should handle template file backup operations" {
            $backupDir = Join-Path $PSScriptRoot "..\..\Temp\template_backups"
            $originalPath = $script:TempTemplatePath
            $backupPath = Join-Path $backupDir "test_template_backup.yaml"

            if (-not (Test-Path $backupDir -PathType Container)) {
                New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
            }

            try {
                # Copy template to backup location
                Copy-Item -Path $originalPath -Destination $backupPath -Force

                # Verify backup exists and is readable
                (Test-Path $backupPath) | Should -Be $true
                $backupConfig = Read-WmrTemplateConfig -TemplatePath $backupPath
                $backupConfig.metadata.name | Should -Be "Test Template"
            } finally {
                Remove-Item -Path $backupDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "should handle template versioning correctly" {
            $versionedTemplates = @(
                @{ version = "1.0"; name = "Template v1.0" },
                @{ version = "1.1"; name = "Template v1.1" },
                @{ version = "2.0"; name = "Template v2.0" }
            )

            $versionDir = Join-Path $PSScriptRoot "..\..\Temp\versioned_templates"
            if (-not (Test-Path $versionDir -PathType Container)) {
                New-Item -ItemType Directory -Path $versionDir -Force | Out-Null
            }

            try {
                foreach ($template in $versionedTemplates) {
                    $versionedPath = Join-Path $versionDir "template_v$($template.version).yaml"
                    $versionedContent = @"
metadata:
  name: $($template.name)
  description: Versioned template
  version: "$($template.version)"
prerequisites: []
"@
                    $versionedContent | Set-Content -Path $versionedPath -Encoding Utf8

                    $config = Read-WmrTemplateConfig -TemplatePath $versionedPath
                    $config.metadata.version | Should -Be $template.version
                    $config.metadata.name | Should -Be $template.name
                }
            } finally {
                Remove-Item -Path $versionDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context "Template File Error Handling" {

        It "should handle file permission errors gracefully" {
            # Create a read-only template file to test permission handling
            $readOnlyPath = Join-Path $PSScriptRoot "..\..\Temp\readonly_template.yaml"
            $script:TempTemplatePath | Get-Content | Set-Content -Path $readOnlyPath -Encoding Utf8

            try {
                # Set file as read-only
                Set-ItemProperty -Path $readOnlyPath -Name IsReadOnly -Value $true

                # Should still be able to read the file
                { Read-WmrTemplateConfig -TemplatePath $readOnlyPath } | Should -Not -Throw
            } finally {
                # Remove read-only attribute and clean up
                if (Test-Path $readOnlyPath) {
                    Set-ItemProperty -Path $readOnlyPath -Name IsReadOnly -Value $false
                    Remove-Item -Path $readOnlyPath -Force -ErrorAction SilentlyContinue
                }
            }
        }

        It "should handle corrupted template files gracefully" {
            $corruptedPath = Join-Path $PSScriptRoot "..\..\Temp\corrupted_template.yaml"
            # Create a file with binary content that will fail YAML parsing
            [byte[]]$binaryContent = 0..255
            [System.IO.File]::WriteAllBytes($corruptedPath, $binaryContent)

            try {
                { Read-WmrTemplateConfig -TemplatePath $corruptedPath } | Should -Throw
            } finally {
                Remove-Item -Path $corruptedPath -Force -ErrorAction SilentlyContinue
            }
        }

        It "should handle very large template files" {
            $largeTemplatePath = Join-Path $PSScriptRoot "..\..\Temp\large_template.yaml"
            $largeContent = @"
metadata:
  name: Large Template
  description: A template with many prerequisites
  version: "1.0"
prerequisites:
"@
            # Add many prerequisites to create a large file
            for ($i = 1; $i -le 100; $i++) {
                $largeContent += @"

  - type: script
    name: "Prereq $i"
    inline_script: "Write-Output 'test $i'"
    expected_output: "test $i"
    on_missing: warn
"@
            }

            $largeContent | Set-Content -Path $largeTemplatePath -Encoding Utf8

            try {
                $config = Read-WmrTemplateConfig -TemplatePath $largeTemplatePath
                $config.metadata.name | Should -Be "Large Template"
                $config.prerequisites.Count | Should -Be 100
            } finally {
                Remove-Item -Path $largeTemplatePath -Force -ErrorAction SilentlyContinue
            }
        }
    }
} 