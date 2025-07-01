# Private/Core/ApplicationState.ps1

# Requires Convert-WmrPath from PathUtilities.ps1 (for any path parsing in custom scripts)
# Requires EncryptionUtilities.ps1 for encryption/decryption (will be created in Task 2.5)

function Get-WmrApplicationState {
    param(
        [Parameter(Mandatory=$true)]
        [PSObject]$AppConfig,

        [Parameter(Mandatory=$true)]
        [string]$StateFilesDirectory # Base directory where dynamic state files are stored
    )

    Write-Host "  Getting application state for: $($AppConfig.name) (Type: $($AppConfig.type))"

    $stateFilePath = Join-Path -Path $StateFilesDirectory -ChildPath $AppConfig.dynamic_state_path
    $stateFileDirectory = Split-Path -Path $stateFilePath

    # Ensure the target directory for state file exists
    if (-not (Test-Path $stateFileDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $stateFileDirectory -Force | Out-Null
    }

    $installedAppsJson = "[]"
    try {
        Write-Host "    Running discovery command: $($AppConfig.discovery_command)"
        $discoveryOutput = Invoke-Expression $AppConfig.discovery_command | Out-String

        Write-Host "    Parsing discovery output with parse_script..."
        # Pass output to the parse_script (inline or file)
        if ($AppConfig.parse_script.StartsWith("#")) { # Assuming inline script starts with # or some identifier
            # Execute inline script
            $scriptBlock = [ScriptBlock]::Create($AppConfig.parse_script)
            $installedAppsJson = & $scriptBlock -InputObject $discoveryOutput | Out-String
        } else {
            # Execute script from path
            $installedAppsJson = & $AppConfig.parse_script -InputObject $discoveryOutput | Out-String
        }

        # Basic validation: ensure it's valid JSON array
        try {
            $parsedApps = $installedAppsJson | ConvertFrom-Json
            if ($parsedApps -isnot [array]) {
                throw "Parse script did not return a JSON array."
            }
        } catch {
            throw "Invalid JSON output from parse_script: $($_.Exception.Message)"
        }

        # TODO: Implement encryption of the JSON string if needed for application lists
        # if ($AppConfig.encrypt) {
        #    $encryptedAppsJson = Protect-WmrData -Data $installedAppsJson
        #    $installedAppsJson = $encryptedAppsJson
        # }

        Set-Content -Path $stateFilePath -Value $installedAppsJson -Encoding Utf8
        Write-Host "  Application list for $($AppConfig.name) captured and saved to $stateFilePath."

    } catch {
        Write-Warning "    Failed to get application state for $($AppConfig.name): $($_.Exception.Message). Skipping."
    }
}

function Set-WmrApplicationState {
    param(
        [Parameter(Mandatory=$true)]
        [PSObject]$AppConfig,

        [Parameter(Mandatory=$true)]
        [string]$StateFilesDirectory # Base directory where dynamic state files are stored
    )

    Write-Host "  Setting application state for: $($AppConfig.name) (Type: $($AppConfig.type))"

    $stateFilePath = Join-Path -Path $StateFilesDirectory -ChildPath $AppConfig.dynamic_state_path

    if (-not (Test-Path $stateFilePath)) {
        Write-Warning "    State file not found for $($AppConfig.name) at $stateFilePath. Skipping restore for this item."
        return
    }

    try {
        $installedAppsJson = Get-Content -Path $stateFilePath -Raw -Encoding Utf8

        # TODO: Implement decryption if the JSON string was encrypted during backup
        # if ($AppConfig.encrypt) {
        #    $decryptedAppsJson = Unprotect-WmrData -Data $installedAppsJson
        #    $installedAppsJson = $decryptedAppsJson
        # }

        Write-Host "    Running installation script: $($AppConfig.install_script)"
        # Pass the JSON list to the install_script (inline or file)
        if ($AppConfig.install_script.StartsWith("#")) { # Assuming inline script starts with # or some identifier
            $scriptBlock = [ScriptBlock]::Create($AppConfig.install_script)
            & $scriptBlock -AppListJson $installedAppsJson
        } else {
            & $AppConfig.install_script -AppListJson $installedAppsJson
        }

        Write-Host "  Applications for $($AppConfig.name) restored."

    } catch {
        Write-Warning "    Failed to set application state for $($AppConfig.name): $($_.Exception.Message)"
    }
}

function Uninstall-WmrApplicationState {
    param(
        [Parameter(Mandatory=$true)]
        [PSObject]$AppConfig,

        [Parameter(Mandatory=$true)]
        [string]$StateFilesDirectory # Base directory where dynamic state files are stored
    )
    
    if (-not $AppConfig.uninstall_script) {
        Write-Warning "  No uninstall_script defined for $($AppConfig.name). Skipping uninstallation."
        return
    }

    Write-Host "  Uninstalling applications for: $($AppConfig.name) (Type: $($AppConfig.type))"

    $stateFilePath = Join-Path -Path $StateFilesDirectory -ChildPath $AppConfig.dynamic_state_path

    if (-not (Test-Path $stateFilePath)) {
        Write-Warning "    State file not found for $($AppConfig.name) at $stateFilePath. Skipping uninstallation for this item."
        return
    }

    try {
        $installedAppsJson = Get-Content -Path $stateFilePath -Raw -Encoding Utf8

        Write-Host "    Running uninstallation script: $($AppConfig.uninstall_script)"
        # Pass the JSON list to the uninstall_script (inline or file)
        if ($AppConfig.uninstall_script.StartsWith("#")) { 
            $scriptBlock = [ScriptBlock]::Create($AppConfig.uninstall_script)
            & $scriptBlock -AppListJson $installedAppsJson
        } else {
            & $AppConfig.uninstall_script -AppListJson $installedAppsJson
        }

        Write-Host "  Applications for $($AppConfig.name) uninstalled."

    } catch {
        Write-Warning "    Failed to uninstall applications for $($AppConfig.name): $($_.Exception.Message)"
    }
}

# Functions are available via dot-sourcing - no Export-ModuleMember needed
# Available functions: Get-WmrApplicationState, Set-WmrApplicationState, Uninstall-WmrApplicationState 