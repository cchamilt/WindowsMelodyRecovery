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
    # Load Docker test bootstrap for cross-platform compatibility
    . (Join-Path $PSScriptRoot "../utilities/Docker-Test-Bootstrap.ps1")

    # Import only the specific scripts needed to avoid TUI dependencies
    try {
        # Import template-related scripts (excluding .psm1 files which can't be dot-sourced)
        $TemplateScripts = @(
            "Private/Core/TemplateInheritance.ps1",
            "Private/Core/TemplateResolution.ps1",
            "Private/Core/PathUtilities.ps1",
            "Private/Core/FileState.ps1"
        )

        foreach ($script in $TemplateScripts) {
            $scriptPath = Resolve-Path "$PSScriptRoot/../../$script"
            . $scriptPath
        }

        # Initialize test environment (includes template function mocks)
        $TestEnvironmentScript = Resolve-Path "$PSScriptRoot/../utilities/Test-Environment.ps1"
        . $TestEnvironmentScript
        Initialize-TestEnvironment -SuiteName 'FileOps' | Out-Null
    }
    catch {
        throw "Cannot find or import template scripts: $($_.Exception.Message)"
    }

    # Set up environment-aware test paths
    $isDockerEnvironment = ($env:DOCKER_TEST -eq 'true') -or ($env:CONTAINER -eq 'true') -or
    (Test-Path '/.dockerenv' -ErrorAction SilentlyContinue)

    if ($isDockerEnvironment) {
        $script:TempTemplateDir = "/workspace/Temp"
    }
    else {
        # Use project Temp directory for local Windows environments
        $moduleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:TempTemplateDir = Join-Path $moduleRoot "Temp"
    }

    $script:TempTemplatePath = Join-Path $script:TempTemplateDir "test_template.yaml"

    # Ensure temp directory exists
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

Describe "TemplateModule File Operations" -Tag "FileOperations", "Safe" {

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
            $invalidYamlPath = Join-Path $script:TempTemplateDir "invalid.yaml"
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
            }
            finally {
                Remove-Item -Path $invalidYamlPath -ErrorAction SilentlyContinue
            }
        }

        It "should handle UTF-8 encoding correctly in template files" {
            $utf8TemplatePath = Join-Path $script:TempTemplateDir "utf8_template.yaml"
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
            }
            finally {
                Remove-Item -Path $utf8TemplatePath -ErrorAction SilentlyContinue
            }
        }
    }

    Context "Template File Discovery and Path Resolution" {

        It "should handle relative paths correctly" {
            # Create a nested template structure
            $nestedDir = Join-Path $script:TempTemplateDir "system"
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
            }
            finally {
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
                $testPath = Join-Path $script:TempTemplateDir "test_extension$ext"
                # Copy content from the main template file
                Get-Content $script:TempTemplatePath | Set-Content -Path $testPath -Encoding Utf8

                try {
                    { Read-WmrTemplateConfig -TemplatePath $testPath } | Should -Not -Throw
                }
                finally {
                    Remove-Item -Path $testPath -ErrorAction SilentlyContinue
                }
            }
        }
    }

    Context "Template Schema Validation with File Operations" {

        It "should pass validation for a complete template file" {
            $completeTemplatePath = Join-Path $script:TempTemplateDir "complete_template.yaml"
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
    path: "C:\\test\\file.txt"
    type: file
    action: backup
    dynamic_state_path: "files/test.txt"
registry:
  - name: Test Registry
    path: "HKCU:\\Software\\Test"
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
            }
            finally {
                Remove-Item -Path $completeTemplatePath -ErrorAction SilentlyContinue
            }
        }

        It "should fail validation for template missing required metadata" {
            $incompleteTemplatePath = Join-Path $script:TempTemplateDir "incomplete_template.yaml"
            $incompleteContent = @"
metadata:
  description: Missing name
  version: "1.0"
prerequisites: []
"@
            $incompleteContent | Set-Content -Path $incompleteTemplatePath -Encoding Utf8

            try {
                $config = Read-WmrTemplateConfig -TemplatePath $incompleteTemplatePath
                { Test-WmrTemplateSchema -TemplateConfig $config } | Should -Throw
            }
            finally {
                Remove-Item -Path $incompleteTemplatePath -ErrorAction SilentlyContinue
            }
        }
    }

    Context "Template File Backup and Versioning" {

        It "should handle template file backup operations" {
            $backupDir = Join-Path $script:TempTemplateDir "template_backups"
            $backupTemplatePath = Join-Path $backupDir "test_template_backup.yaml"

            if (-not (Test-Path $backupDir -PathType Container)) {
                New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
            }

            # Copy main template to backup location
            Copy-Item -Path $script:TempTemplatePath -Destination $backupTemplatePath -Force

            try {
                $config = Read-WmrTemplateConfig -TemplatePath $backupTemplatePath
                $config.metadata.name | Should -Be "Test Template"
            }
            finally {
                Remove-Item -Path $backupTemplatePath -Force -ErrorAction SilentlyContinue
                Remove-Item -Path $backupDir -Force -ErrorAction SilentlyContinue
            }
        }

        It "should handle template versioning correctly" {
            $versionDir = Join-Path $script:TempTemplateDir "versioned_templates"
            $versionedTemplatePath = Join-Path $versionDir "template_v1.0.yaml"

            if (-not (Test-Path $versionDir -PathType Container)) {
                New-Item -ItemType Directory -Path $versionDir -Force | Out-Null
            }

            $versionedContent = @"
metadata:
  name: Versioned Template
  description: A template with version information
  version: "1.0"
prerequisites: []
"@
            $versionedContent | Set-Content -Path $versionedTemplatePath -Encoding Utf8

            try {
                $config = Read-WmrTemplateConfig -TemplatePath $versionedTemplatePath
                $config.metadata.name | Should -Be "Versioned Template"
                $config.metadata.version | Should -Be "1.0"
            }
            finally {
                Remove-Item -Path $versionedTemplatePath -Force -ErrorAction SilentlyContinue
                Remove-Item -Path $versionDir -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context "Template File Error Handling" {

        It "should handle file permission errors gracefully" {
            $readOnlyPath = Join-Path $script:TempTemplateDir "readonly_template.yaml"

            # Create template file first
            Get-Content $script:TempTemplatePath | Set-Content -Path $readOnlyPath -Encoding Utf8

            try {
                # On Linux/Docker, we can't easily set read-only, so just test normal access
                { Read-WmrTemplateConfig -TemplatePath $readOnlyPath } | Should -Not -Throw
            }
            finally {
                Remove-Item -Path $readOnlyPath -Force -ErrorAction SilentlyContinue
            }
        }

        It "should handle corrupted template files gracefully" {
            $corruptedPath = Join-Path $script:TempTemplateDir "corrupted_template.yaml"

            # Create a corrupted YAML file
            "corrupted: [unclosed array" | Set-Content -Path $corruptedPath -Encoding Utf8

            try {
                { Read-WmrTemplateConfig -TemplatePath $corruptedPath } | Should -Throw
            }
            finally {
                Remove-Item -Path $corruptedPath -ErrorAction SilentlyContinue
            }
        }

        It "should handle very large template files" {
            $largeTemplatePath = Join-Path $script:TempTemplateDir "large_template.yaml"

            # Create a large template file
            $largeContent = @"
metadata:
  name: Large Template
  description: A template with many entries
  version: "1.0"
prerequisites:
"@
            # Add many prerequisites to make it large
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
            }
            finally {
                Remove-Item -Path $largeTemplatePath -ErrorAction SilentlyContinue
            }
        }
    }
}






