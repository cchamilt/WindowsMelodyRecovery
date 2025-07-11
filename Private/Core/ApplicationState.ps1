# Private/Core/ApplicationState.ps1

# Requires Convert-WmrPath from PathUtilities.ps1 (for any path parsing in custom scripts)
# Requires EncryptionUtilities.ps1 for encryption/decryption (will be created in Task 2.5)

function Get-WmrApplicationState {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$true)]
        [PSObject]$AppConfig,

        [Parameter(Mandatory=$true)]
        [string]$StateFilesDirectory # Base directory where dynamic state files are stored
    )

    Write-Host "  Getting application state for: $($AppConfig.name) (Type: $($AppConfig.type))"

    if ($WhatIfPreference) {
        Write-Host "    WhatIf: Would run discovery command: $($AppConfig.discovery_command)" -ForegroundColor Yellow
        Write-Host "    WhatIf: Would parse output with parse script" -ForegroundColor Yellow
        $stateFilePath = Join-Path -Path $StateFilesDirectory -ChildPath $AppConfig.dynamic_state_path
        Write-Host "    WhatIf: Would save application list to $stateFilePath" -ForegroundColor Yellow
        return
    }

    $stateFilePath = Join-Path -Path $StateFilesDirectory -ChildPath $AppConfig.dynamic_state_path
    $stateFileDirectory = Split-Path -Path $stateFilePath

    # Ensure the target directory for state file exists
    if (-not (Test-Path $stateFileDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $stateFileDirectory -Force | Out-Null
    }

    $installedAppsJson = "[]"
    try {
        Write-Host "    Running discovery command: $($AppConfig.discovery_command)"

        # Execute discovery command and capture raw output
        $discoveryOutput = Invoke-Expression $AppConfig.discovery_command

        Write-Host "    Parsing discovery output with parse_script..."
        # Pass output to the parse_script (inline or file)
        try {
            if (Test-Path $AppConfig.parse_script -PathType Leaf) {
                # Execute script from file path
                $parseResult = & $AppConfig.parse_script -DiscoveryOutput $discoveryOutput
            } else {
                # Execute inline script (from YAML template)
                $scriptBlock = [ScriptBlock]::Create($AppConfig.parse_script)
                $parseResult = & $scriptBlock $discoveryOutput
            }

            # Ensure we have a valid result - if parse_script failed, it might return null
            if ($parseResult -eq $null) {
                $parseResult = @()
            }

            # Handle different types of parse_script output
            if ($parseResult -is [string]) {
                # Parse script returned JSON string
                $installedAppsJson = $parseResult
            } elseif ($parseResult -is [array]) {
                # Parse script returned PowerShell array
                if ($parseResult.Count -eq 0) {
                    $installedAppsJson = "[]"
                } else {
                    $installedAppsJson = $parseResult | ConvertTo-Json -Depth 10 -AsArray
                }
            } elseif ($parseResult -is [PSCustomObject] -or $parseResult -is [Hashtable]) {
                # Parse script returned PowerShell objects, convert to JSON
                $installedAppsJson = $parseResult | ConvertTo-Json -Depth 10
            } else {
                # Convert other types to JSON
                try {
                    $installedAppsJson = $parseResult | ConvertTo-Json -Depth 10
                } catch {
                    # If conversion fails, treat as empty array
                    $installedAppsJson = "[]"
                }
            }
        } catch {
            # If parse script fails, log the error and return empty array
            Write-Warning "Parse script execution failed for $($AppConfig.name): $($_.Exception.Message)"
            $installedAppsJson = "[]"
        }

        # Validate the final JSON output
        try {
            if ($installedAppsJson.Trim() -eq "[]") {
                $parsedApps = @()
            } else {
                $parsedApps = $installedAppsJson | ConvertFrom-Json

                # Ensure consistent array format
                if ($parsedApps -isnot [array] -and $parsedApps -ne $null) {
                    $parsedApps = @($parsedApps)
                    $installedAppsJson = $parsedApps | ConvertTo-Json -Depth 10 -AsArray
                }
            }
        } catch {
            Write-Warning "JSON validation failed for $($AppConfig.name): $($_.Exception.Message). Using empty array."
            $installedAppsJson = "[]"
            $parsedApps = @()
        }

        # Implement encryption of the JSON string if needed for application lists
        if ($AppConfig.encrypt) {
            Write-Host "    Encrypting application data with AES-256"
            $appsBytes = [System.Text.Encoding]::UTF8.GetBytes($installedAppsJson)
            $encryptedAppsJson = Protect-WmrData -DataBytes $appsBytes
            Set-Content -Path $stateFilePath -Value $encryptedAppsJson -Encoding UTF8

            # Save metadata about encryption
            $metadata = @{ Encrypted = $true; OriginalSize = $appsBytes.Length }
            $metadataPath = $stateFilePath -replace '\.[^.]+$', '.metadata.json'
            $metadata | ConvertTo-Json | Set-Content -Path $metadataPath -Encoding UTF8
        } else {
            Set-Content -Path $stateFilePath -Value $installedAppsJson -Encoding Utf8

            # Save metadata about non-encryption
            $metadata = @{ Encrypted = $false; OriginalSize = $installedAppsJson.Length }
            $metadataPath = $stateFilePath -replace '\.[^.]+$', '.metadata.json'
            $metadata | ConvertTo-Json | Set-Content -Path $metadataPath -Encoding UTF8
        }
        Write-Host "  Application list for $($AppConfig.name) captured and saved to $stateFilePath."

    } catch {
        Write-Warning "    Failed to get application state for $($AppConfig.name): $($_.Exception.Message). Skipping."
    }
}

function Set-WmrApplicationState {
    [CmdletBinding(SupportsShouldProcess)]
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

    if ($WhatIfPreference) {
        Write-Host "    WhatIf: Would restore applications from $stateFilePath" -ForegroundColor Yellow
        try {
            # Check if the content was encrypted during backup
            $wasEncrypted = $false
            try {
                $stateMetadataPath = $stateFilePath -replace '\.[^.]+$', '.metadata.json'
                if (Test-Path $stateMetadataPath) {
                    $metadata = Get-Content -Path $stateMetadataPath -Raw | ConvertFrom-Json
                    $wasEncrypted = $metadata.Encrypted -eq $true
                }
            } catch {
                $wasEncrypted = $AppConfig.encrypt -eq $true
            }

            if ($wasEncrypted) {
                Write-Host "    WhatIf: Would decrypt application data with AES-256" -ForegroundColor Yellow
            }

            $installedAppsJson = Get-Content -Path $stateFilePath -Raw -Encoding Utf8
            if (-not $wasEncrypted) {
                $parsedApps = $installedAppsJson | ConvertFrom-Json
                $appCount = if ($parsedApps -is [array]) { $parsedApps.Count } else { 1 }
                Write-Host "    WhatIf: Would run install script for $appCount applications" -ForegroundColor Yellow
            } else {
                Write-Host "    WhatIf: Would run install script for encrypted application data" -ForegroundColor Yellow
            }
            Write-Host "    WhatIf: Install script: $($AppConfig.install_script)" -ForegroundColor Yellow
        } catch {
            Write-Host "    WhatIf: Would attempt to restore applications (state file parse failed)" -ForegroundColor Yellow
        }
        return
    }

    try {
        # Check if the content was encrypted during backup
        $wasEncrypted = $false
        try {
            # Try to read state metadata to check if content was encrypted
            $stateMetadataPath = $stateFilePath -replace '\.[^.]+$', '.metadata.json'
            if (Test-Path $stateMetadataPath) {
                $metadata = Get-Content -Path $stateMetadataPath -Raw | ConvertFrom-Json
                $wasEncrypted = $metadata.Encrypted -eq $true
            }
        } catch {
            # Fallback: assume encryption based on file config
            $wasEncrypted = $AppConfig.encrypt -eq $true
        }

        $installedAppsJson = Get-Content -Path $stateFilePath -Raw -Encoding Utf8

        # Implement decryption if the JSON string was encrypted during backup
        if ($wasEncrypted) {
            Write-Host "    Decrypting application data with AES-256"
            $decryptedBytes = Unprotect-WmrData -EncodedData $installedAppsJson
            $installedAppsJson = [System.Text.Encoding]::UTF8.GetString($decryptedBytes)
        }

        Write-Host "    Running installation script: $($AppConfig.install_script)"
        # Pass the JSON list to the install_script (inline or file)
        if (Test-Path $AppConfig.install_script -PathType Leaf) {
            # Execute script from file path
            & $AppConfig.install_script -StateJson $installedAppsJson
        } else {
            # Execute inline script (from YAML template)
            $scriptBlock = [ScriptBlock]::Create($AppConfig.install_script)
            & $scriptBlock $installedAppsJson
        }

        Write-Host "  Applications for $($AppConfig.name) restored."

    } catch {
        Write-Warning "    Failed to set application state for $($AppConfig.name): $($_.Exception.Message)"
    }
}

function Uninstall-WmrApplicationState {
    [CmdletBinding(SupportsShouldProcess)]
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

    if ($WhatIfPreference) {
        Write-Host "    WhatIf: Would uninstall applications from $stateFilePath" -ForegroundColor Yellow
        try {
            # Check if the content was encrypted during backup
            $wasEncrypted = $false
            try {
                $stateMetadataPath = $stateFilePath -replace '\.[^.]+$', '.metadata.json'
                if (Test-Path $stateMetadataPath) {
                    $metadata = Get-Content -Path $stateMetadataPath -Raw | ConvertFrom-Json
                    $wasEncrypted = $metadata.Encrypted -eq $true
                }
            } catch {
                $wasEncrypted = $AppConfig.encrypt -eq $true
            }

            if ($wasEncrypted) {
                Write-Host "    WhatIf: Would decrypt application data with AES-256" -ForegroundColor Yellow
            }

            $installedAppsJson = Get-Content -Path $stateFilePath -Raw -Encoding Utf8
            if (-not $wasEncrypted) {
                $parsedApps = $installedAppsJson | ConvertFrom-Json
                $appCount = if ($parsedApps -is [array]) { $parsedApps.Count } else { 1 }
                Write-Host "    WhatIf: Would run uninstall script for $appCount applications" -ForegroundColor Yellow
            } else {
                Write-Host "    WhatIf: Would run uninstall script for encrypted application data" -ForegroundColor Yellow
            }
            Write-Host "    WhatIf: Uninstall script: $($AppConfig.uninstall_script)" -ForegroundColor Yellow
        } catch {
            Write-Host "    WhatIf: Would attempt to uninstall applications (state file parse failed)" -ForegroundColor Yellow
        }
        return
    }

    try {
        # Check if the content was encrypted during backup
        $wasEncrypted = $false
        try {
            # Try to read state metadata to check if content was encrypted
            $stateMetadataPath = $stateFilePath -replace '\.[^.]+$', '.metadata.json'
            if (Test-Path $stateMetadataPath) {
                $metadata = Get-Content -Path $stateMetadataPath -Raw | ConvertFrom-Json
                $wasEncrypted = $metadata.Encrypted -eq $true
            }
        } catch {
            # Fallback: assume encryption based on file config
            $wasEncrypted = $AppConfig.encrypt -eq $true
        }

        $installedAppsJson = Get-Content -Path $stateFilePath -Raw -Encoding Utf8

        # Implement decryption if the JSON string was encrypted during backup
        if ($wasEncrypted) {
            Write-Host "    Decrypting application data with AES-256"
            $decryptedBytes = Unprotect-WmrData -EncodedData $installedAppsJson
            $installedAppsJson = [System.Text.Encoding]::UTF8.GetString($decryptedBytes)
        }

        Write-Host "    Running uninstallation script: $($AppConfig.uninstall_script)"
        # Pass the JSON list to the uninstall_script (inline or file)
        if (Test-Path $AppConfig.uninstall_script -PathType Leaf) {
            # Execute script from file path
            & $AppConfig.uninstall_script -StateJson $installedAppsJson
        } else {
            # Execute inline script (from YAML template)
            $scriptBlock = [ScriptBlock]::Create($AppConfig.uninstall_script)
            & $scriptBlock $installedAppsJson
        }

        Write-Host "  Applications for $($AppConfig.name) uninstalled."

    } catch {
        Write-Warning "    Failed to uninstall applications for $($AppConfig.name): $($_.Exception.Message)"
    }
}

# Functions are available via dot-sourcing - no Export-ModuleMember needed
# Available functions: Get-WmrApplicationState, Set-WmrApplicationState, Uninstall-WmrApplicationState