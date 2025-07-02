# Private/Core/WindowsMelodyRecovery.Template.psm1

# Requires the PowerShellGet module for Install-Module, if not already installed.
# Requires the PowerShell YAML module for ConvertFrom-Yaml.

function Read-WmrTemplateConfig {
    param(
        [Parameter(Mandatory=$true)]
        [string]$TemplatePath
    )

    if (-not (Test-Path $TemplatePath)) {
        throw "Template file not found: $TemplatePath"
    }

    # Ensure the Yayaml module is available
    try {
        Import-Module Yayaml -ErrorAction Stop
    } catch {
        Write-Warning "Yayaml module not found. Attempting to install..."
        try {
            Install-Module Yayaml -Scope CurrentUser -Force -ErrorAction Stop
            Import-Module Yayaml -ErrorAction Stop
        } catch {
            throw "Failed to install and import Yayaml module. Please install it manually: Install-Module -Name Yayaml"
        }
    }

    try {
        $yamlContent = Get-Content $TemplatePath -Raw
        $templateConfig = $yamlContent | ConvertFrom-Yaml
        return $templateConfig
    } catch {
        throw "Failed to parse YAML template file '$TemplatePath': $($_.Exception.Message)"
    }
}

function Test-WmrTemplateSchema {
    param(
        [Parameter(Mandatory=$true)]
        [PSObject]$TemplateConfig
    )

    Write-Host "NOTE: Schema validation is not yet fully implemented. This is a placeholder."

    # TODO: Implement comprehensive schema validation based on docs/TEMPLATE_SCHEMA.md
    # This function will check if the $TemplateConfig object conforms to the defined schema,
    # ensuring all required fields are present and data types are correct.

    # Example placeholder validation: Check for 'metadata.name'
    if (-not $TemplateConfig.metadata.name) {
        throw "Template schema validation failed: 'metadata.name' is missing."
    }

    Write-Host "Basic template schema validation passed."
    return $true
}

Export-ModuleMember -Function @(
    "Read-WmrTemplateConfig",
    "Test-WmrTemplateSchema"
)