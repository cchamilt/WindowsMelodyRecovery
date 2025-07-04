# tests/unit/TemplateModule.Tests.ps1

BeforeAll {
    # Create a dummy template file for testing
    $tempTemplateContent = @"
metadata:
  name: Test Template
  description: A test template for unit testing.
  version: "1.0"
prerequisites:
  - type: script
    name: Dummy Prereq
    inline_script: "Write-Output 'Hello'"
    expected_output: "Hello"
    on_missing: warn
"@
    $script:TempTemplatePath = Join-Path $PSScriptRoot "..\..\Temp\test_template.yaml"
    $script:TempTemplateDir = Split-Path -Path $script:TempTemplatePath
    if (-not (Test-Path $script:TempTemplateDir -PathType Container)) {
        New-Item -ItemType Directory -Path $script:TempTemplateDir -Force | Out-Null
    }
    $tempTemplateContent | Set-Content -Path $script:TempTemplatePath -Encoding Utf8

    # Import the WindowsMelodyRecovery module to make functions available
    $ModulePath = if (Test-Path "./WindowsMelodyRecovery.psm1") {
        "./WindowsMelodyRecovery.psm1"
    } elseif (Test-Path "/workspace/WindowsMelodyRecovery.psm1") {
        "/workspace/WindowsMelodyRecovery.psm1"
    } else {
        throw "Cannot find WindowsMelodyRecovery.psm1 module"
    }
    Import-Module $ModulePath -Force
}

AfterAll {
    # Clean up the dummy template file
    Remove-Item -Path $script:TempTemplatePath -Force -ErrorAction SilentlyContinue
    # Optionally remove the Temp directory if empty or if it was created by the test
}

Describe "Read-WmrTemplateConfig" {

    It "should read and parse a valid YAML template file" {
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
        "metadata: name: [" | Set-Content -Path $invalidYamlPath -Encoding Utf8
        { Read-WmrTemplateConfig -TemplatePath $invalidYamlPath } | Should -Throw
        Remove-Item -Path $invalidYamlPath -ErrorAction SilentlyContinue
    }
}

Describe "Test-WmrTemplateSchema" {

    It "should pass for a valid template configuration (basic check)" {
        $config = Read-WmrTemplateConfig -TemplatePath $script:TempTemplatePath
        { Test-WmrTemplateSchema -TemplateConfig $config } | Should -Not -Throw
    }

    It "should throw an error if metadata.name is missing" {
        $invalidConfig = Read-WmrTemplateConfig -TemplatePath $script:TempTemplatePath
        $invalidConfig.metadata.PSObject.Properties.Remove("name") # Remove the 'name' property
        { Test-WmrTemplateSchema -TemplateConfig $invalidConfig } | Should -Throw "Template schema validation failed: 'metadata.name' is missing."
    }

    # Add more specific schema validation tests here as schema validation is implemented
} 