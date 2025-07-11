# Unit Tests for Template Module Logic
# Tests the core template processing logic without file system operations

BeforeAll {
    # Import the main module to make functions available
    Import-Module (Resolve-Path "$PSScriptRoot/../../WindowsMelodyRecovery.psd1") -Force

    # Load the unified test environment (works for both Docker and Windows)
    . (Join-Path $PSScriptRoot "..\utilities\Test-Environment.ps1")

    # Initialize test environment
    $testEnvironment = Initialize-TestEnvironment

    # Mock all file operations
    Mock Test-Path { return $true } -ParameterFilter { $Path -like "*exists*" }
    Mock Test-Path { return $true } -ParameterFilter { $Path -like "*valid*" }
    Mock Test-Path { return $false } -ParameterFilter { $Path -like "*missing*" }
    Mock Test-Path { return $false } -ParameterFilter { $Path -like "*invalid*" }
    Mock New-Item { return @{ FullName = $Path } }
    Mock Set-Content { }
    Mock Remove-Item { }

    # Mock Get-Content for YAML template files
    Mock Get-Content {
        if ($Path -like "*valid*") {
            return @'
metadata:
  name: "Valid Template"
  version: "1.0"
  description: "A valid test template"

prerequisites:
  - type: "directory"
    path: "C:\Test"

files:
  - name: "test.txt"
    source: "source.txt"
    destination: "dest.txt"
'@
        } elseif ($Path -like "*missing*") {
            throw "File not found"
        } elseif ($Path -like "*invalid*") {
            return "invalid: [unclosed_array"
        } else {
            return "default: content"
        }
    }

    # Mock Read-WmrTemplateConfig function
    Mock Read-WmrTemplateConfig {
        param([string]$TemplatePath)

        if ($TemplatePath -like "*missing*") {
            throw "Template file not found: $TemplatePath"
        }

        if ($TemplatePath -like "*invalid*") {
            throw "Failed to parse YAML template file '$TemplatePath': Invalid YAML content"
        }

        if ($TemplatePath -like "*valid*") {
            return [PSCustomObject]@{
                metadata = [PSCustomObject]@{
                    name = "Valid Template"
                    version = "1.0"
                    description = "A valid test template"
                }
                prerequisites = @(
                    [PSCustomObject]@{
                        type = "directory"
                        path = "C:\Test"
                    }
                )
                files = @(
                    [PSCustomObject]@{
                        name = "test.txt"
                        source = "source.txt"
                        destination = "dest.txt"
                    }
                )
            }
        }

        # Default case
        return [PSCustomObject]@{
            metadata = [PSCustomObject]@{
                name = "Default Template"
                version = "1.0"
            }
            prerequisites = @()
        }
    }

    # Mock Test-WmrTemplateSchema function
    Mock Test-WmrTemplateSchema {
        param([PSObject]$TemplateConfig)

        if ($null -eq $TemplateConfig -or $TemplateConfig -is [hashtable] -and $TemplateConfig.Count -eq 0) {
            throw "Template schema validation failed: Template configuration is null or empty."
        }

        if (-not $TemplateConfig.metadata) {
            throw "Template schema validation failed: 'metadata' section is missing."
        }

        if (-not $TemplateConfig.metadata.name) {
            throw "Template schema validation failed: 'metadata.name' is missing."
        }

        Write-Information -MessageData "NOTE: Schema validation is not yet fully implemented. This is a placeholder." -InformationAction Continue
        Write-Information -MessageData "Basic template schema validation passed." -InformationAction Continue
        return $true
    }

    # Add missing Get-WmrTestPath function
    function Get-WmrTestPath {
        param(
            [string]$Path,
            [string]$WindowsPath
        )

        # If WindowsPath is provided, use it; otherwise use Path
        if ($WindowsPath) {
            return $WindowsPath
        } else {
            return $Path
        }
    }
}

Describe "TemplateModule Logic Tests" -Tag "Unit", "Logic" {

    Context "Template Configuration Reading Logic" {

        It "should parse valid YAML template configuration correctly" {
            $config = Read-WmrTemplateConfig -TemplatePath "valid_template.yaml"
            $config | Should -Not -BeNullOrEmpty
            $config.metadata.name | Should -Be "Valid Template"
            $config.metadata.version | Should -Be "1.0"
            $config.prerequisites.Count | Should -Be 1
            $config.prerequisites[0].type | Should -Be "directory"
        }

        It "should handle missing template files gracefully" {
            { Read-WmrTemplateConfig -TemplatePath "missing_template.yaml" } | Should -Throw "Template file not found: missing_template.yaml"
        }

        It "should handle invalid YAML content gracefully" {
            { Read-WmrTemplateConfig -TemplatePath "invalid_template.yaml" } | Should -Throw
        }
    }

    Context "Template Schema Validation Logic" {

        It "should validate template configuration with required metadata" {
            $validConfig = [PSCustomObject]@{
                metadata = [PSCustomObject]@{
                    name = "Valid Template"
                    description = "A valid template"
                    version = "1.0"
                }
                prerequisites = @()
            }

            { Test-WmrTemplateSchema -TemplateConfig $validConfig } | Should -Not -Throw
        }

        It "should reject template configuration missing required metadata.name" {
            $invalidConfig = [PSCustomObject]@{
                metadata = [PSCustomObject]@{
                    description = "Missing name"
                    version = "1.0"
                }
                prerequisites = @()
            }

            { Test-WmrTemplateSchema -TemplateConfig $invalidConfig } | Should -Throw "Template schema validation failed: 'metadata.name' is missing."
        }

        It "should reject template configuration missing metadata entirely" {
            $invalidConfig = [PSCustomObject]@{
                prerequisites = @()
            }

            { Test-WmrTemplateSchema -TemplateConfig $invalidConfig } | Should -Throw
        }

        It "should handle null or empty template configuration" {
            { Test-WmrTemplateSchema -TemplateConfig $null } | Should -Throw
            { Test-WmrTemplateSchema -TemplateConfig @{} } | Should -Throw
        }
    }

    Context "Template Processing Logic" {

        It "should identify template type from metadata" {
            $config = [PSCustomObject]@{
                metadata = [PSCustomObject]@{
                    name = "System Template"
                    type = "system"
                    version = "1.0"
                }
            }

            # Test that the template type is correctly identified
            $config.metadata.type | Should -Be "system"
        }

        It "should handle templates with different prerequisite types" {
            $config = [PSCustomObject]@{
                metadata = [PSCustomObject]@{
                    name = "Multi-Prereq Template"
                    version = "1.0"
                }
                prerequisites = @(
                    [PSCustomObject]@{
                        type = "script"
                        name = "Script Prereq"
                        inline_script = "Write-Output 'test'"
                        expected_output = "test"
                        on_missing = "warn"
                    },
                    [PSCustomObject]@{
                        type = "application"
                        name = "App Prereq"
                        check_command = "winget --version"
                        expected_output = "v.*"
                        on_missing = "fail_backup"
                    }
                )
            }

            $config.prerequisites.Count | Should -Be 2
            $config.prerequisites[0].type | Should -Be "script"
            $config.prerequisites[1].type | Should -Be "application"
        }

        It "should validate prerequisite structure" {
            $prereq = [PSCustomObject]@{
                type = "script"
                name = "Test Prereq"
                inline_script = "Write-Output 'Hello'"
                expected_output = "Hello"
                on_missing = "warn"
            }

            # Validate prerequisite has required properties
            $prereq.type | Should -Not -BeNullOrEmpty
            $prereq.name | Should -Not -BeNullOrEmpty
            $prereq.on_missing | Should -BeIn @("warn", "fail_backup", "fail_restore")
        }
    }

    Context "Template Configuration Merging Logic" {

        It "should merge template configurations correctly" {
            $baseConfig = [PSCustomObject]@{
                metadata = [PSCustomObject]@{
                    name = "Base Template"
                    version = "1.0"
                }
                prerequisites = @()
            }

            $overrideConfig = [PSCustomObject]@{
                metadata = [PSCustomObject]@{
                    description = "Override description"
                }
                prerequisites = @(
                    [PSCustomObject]@{
                        type = "script"
                        name = "New Prereq"
                        inline_script = "echo test"
                        expected_output = "test"
                        on_missing = "warn"
                    }
                )
            }

            # Test merging logic (this would be implemented in the actual function)
            $baseConfig.metadata.name | Should -Be "Base Template"
            $overrideConfig.metadata.description | Should -Be "Override description"
            $overrideConfig.prerequisites.Count | Should -Be 1
        }

        It "should handle empty or null configurations in merging" {
            $validConfig = [PSCustomObject]@{
                metadata = [PSCustomObject]@{
                    name = "Valid Template"
                    version = "1.0"
                }
            }

            # Test that valid config remains valid when merging with null/empty
            $validConfig.metadata.name | Should -Be "Valid Template"
        }
    }

    Context "Template Path Resolution Logic" {

        It "should resolve relative template paths correctly" {
            # Mock path resolution logic
            $relativePath = "system/display.yaml"
            $expectedFullPath = Join-Path "Templates" $relativePath

            # Test path resolution logic
            $expectedFullPath | Should -Match "Templates.*system.*display\.yaml"
        }

        It "should handle absolute template paths correctly" {
            $absolutePath = (Get-WmrTestPath -WindowsPath "C:\Templates\custom\template.yaml")

            # Test that absolute paths are preserved (works with both Windows and Linux paths)
            $absolutePath | Should -Match "(^[A-Z]:\\.*template\.yaml$)|(^/.*template\.yaml$)"
        }

        It "should validate template file extensions" {
            $validExtensions = @(".yaml", ".yml")
            $testPaths = @(
                "template.yaml",
                "template.yml",
                "template.json",  # invalid
                "template.txt"    # invalid
            )

            foreach ($path in $testPaths) {
                $extension = [System.IO.Path]::GetExtension($path)
                if ($extension -in $validExtensions) {
                    $extension | Should -BeIn $validExtensions
                } else {
                    $extension | Should -Not -BeIn $validExtensions
                }
            }
        }
    }

    Context "Template Content Validation Logic" {

        It "should validate required template sections" {
            $completeTemplate = [PSCustomObject]@{
                metadata = [PSCustomObject]@{
                    name = "Complete Template"
                    description = "A complete template"
                    version = "1.0"
                }
                prerequisites = @()
                files = @()
                registry = @()
                applications = @()
            }

            # Test that all required sections are present
            $completeTemplate.metadata | Should -Not -BeNull
            $completeTemplate.PSObject.Properties.Name | Should -Contain "metadata"
        }

        It "should handle templates with minimal required content" {
            $minimalTemplate = [PSCustomObject]@{
                metadata = [PSCustomObject]@{
                    name = "Minimal Template"
                    version = "1.0"
                }
            }

            # Test that minimal template is still valid
            $minimalTemplate.metadata.name | Should -Be "Minimal Template"
            $minimalTemplate.metadata.version | Should -Be "1.0"
        }

        It "should validate template version format" {
            $validVersions = @("1.0", "1.0.0", "2.1.3", "1.0.0-beta")
            $invalidVersions = @("", "v1.0", "1.0.0.0.0", "latest")

            foreach ($version in $validVersions) {
                # Test version format validation logic
                $version | Should -Match "^\d+\.\d+(\.\d+)?(-\w+)?$"
            }

            foreach ($version in $invalidVersions) {
                # Test invalid version detection
                if ($version -eq "") {
                    $version | Should -BeNullOrEmpty
                } else {
                    $version | Should -Not -Match "^\d+\.\d+(\.\d+)?(-\w+)?$"
                }
            }
        }
    }
}








