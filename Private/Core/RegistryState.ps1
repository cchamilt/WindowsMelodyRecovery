# Private/Core/RegistryState.ps1

# Requires Convert-WmrPath from PathUtilities.ps1
# Requires EncryptionUtilities.ps1 for encryption/decryption (will be created in Task 2.5)

function Get-WmrRegistryState {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$true)]
        [PSObject]$RegistryConfig,

        [Parameter(Mandatory=$true)]
        [string]$StateFilesDirectory # Base directory where dynamic state files are stored
    )

    Write-Host "  Getting registry state for: $($RegistryConfig.name)"

    if ($WhatIfPreference) {
        Write-Host "    WhatIf: Would backup registry state from $($RegistryConfig.path)" -ForegroundColor Yellow
        $stateFilePath = Join-Path -Path $StateFilesDirectory -ChildPath $RegistryConfig.dynamic_state_path
        Write-Host "    WhatIf: Would save registry data to $stateFilePath" -ForegroundColor Yellow
        
        if (-not (Test-Path $RegistryConfig.path)) {
            Write-Warning "    WhatIf: Registry path not found: $($RegistryConfig.path). Would skip backup for this item."
        } else {
            Write-Host "    WhatIf: Would capture registry $($RegistryConfig.type) values" -ForegroundColor Yellow
        }
        return $null
    }

    $resolvedPathObj = Convert-WmrPath -Path $RegistryConfig.path
    if ($resolvedPathObj.PathType -ne "Registry") {
        Write-Warning "    Provided path is not a registry path: $($RegistryConfig.path). Skipping."
        return $null
    }
    $resolvedPath = $resolvedPathObj.Path

    $stateFilePath = Join-Path -Path $StateFilesDirectory -ChildPath $RegistryConfig.dynamic_state_path
    $stateFileDirectory = Split-Path -Path $stateFilePath

    # Ensure the target directory for state file exists
    if (-not (Test-Path $stateFileDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $stateFileDirectory -Force | Out-Null
    }

    $registryState = @{
        Name = $RegistryConfig.name
        Path = $resolvedPath
        Type = $RegistryConfig.type
    }

    try {
        if ($RegistryConfig.type -eq "value") {
            if (-not $RegistryConfig.key_name) {
                throw "Registry item type is 'value' but 'key_name' is not specified for $($RegistryConfig.name)"
            }
            # Get a specific registry value
            $value = (Get-ItemProperty -Path $resolvedPath -Name $RegistryConfig.key_name -ErrorAction Stop).($RegistryConfig.key_name)
            $registryState.KeyName = $RegistryConfig.key_name
            $registryState.Value = $value

            if ($RegistryConfig.encrypt) {
                Write-Host "    Encrypting registry value with AES-256"
                $valueBytes = [System.Text.Encoding]::UTF8.GetBytes($value.ToString())
                $encryptedValue = Protect-WmrData -DataBytes $valueBytes
                $registryState.EncryptedValue = $encryptedValue
                $registryState.Encrypted = $true
                # Remove unencrypted value
                $registryState.Remove('Value')
            } else {
                $registryState.Encrypted = $false
            }
            ($registryState | ConvertTo-Json -Compress) | Set-Content -Path $stateFilePath -Encoding Utf8

        } elseif ($RegistryConfig.type -eq "key") {
            # Get all values under a registry key
            $keyValues = Get-ItemProperty -Path $resolvedPath -ErrorAction Stop | Select-Object -ExcludeProperty PSPath, PSParentPath, PSChildName, PSDrive, PSProvider
            $registryState.Values = $keyValues

            # Convert to JSON and save to dynamic_state_path
            ($registryState | ConvertTo-Json -Compress) | Set-Content -Path $stateFilePath -Encoding Utf8
        }
        Write-Host "  Registry state for $($RegistryConfig.name) captured and saved to $stateFilePath."
        return $registryState

    } catch {
        $errorMessage = $_.Exception.Message
        Write-Warning ("    Failed to get registry state for " + $RegistryConfig.name + ": " + $errorMessage + ". Skipping.")
        return $null
    }
}

function Set-WmrRegistryState {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$true)]
        [PSObject]$RegistryConfig,

        [Parameter(Mandatory=$true)]
        [string]$StateFilesDirectory # Base directory where dynamic state files are stored
    )

    Write-Host "  Setting registry state for: $($RegistryConfig.name)"

    $resolvedPathObj = Convert-WmrPath -Path $RegistryConfig.path
    if ($resolvedPathObj.PathType -ne "Registry") {
        Write-Warning "    Provided path is not a registry path: $($RegistryConfig.path). Skipping."
        return
    }
    $resolvedPath = $resolvedPathObj.Path

    $stateFilePath = Join-Path -Path $StateFilesDirectory -ChildPath $RegistryConfig.dynamic_state_path

    if ($WhatIfPreference) {
        Write-Host "    WhatIf: Would restore registry state from $stateFilePath to $resolvedPath" -ForegroundColor Yellow
        
        if (Test-Path $stateFilePath) {
            try {
                $stateData = (Get-Content -Path $stateFilePath -Raw -Encoding Utf8) | ConvertFrom-Json
                
                if ($RegistryConfig.type -eq "value") {
                    $valueToShow = "?"
                    if ($stateData.Encrypted -eq $true -and $stateData.EncryptedValue) {
                        Write-Host "    WhatIf: Would decrypt registry value with AES-256" -ForegroundColor Yellow
                        $valueToShow = "<encrypted>"
                    } elseif ($stateData.Value) {
                        $valueToShow = $stateData.Value
                    } elseif ($RegistryConfig.value_data) {
                        $valueToShow = $RegistryConfig.value_data
                    }
                    Write-Host "    WhatIf: Would set registry value '$($RegistryConfig.key_name)' to '$valueToShow' at $resolvedPath" -ForegroundColor Yellow
                } elseif ($RegistryConfig.type -eq "key") {
                    if ($stateData.Values) {
                        $valueCount = ($stateData.Values.PSObject.Properties | Measure-Object).Count
                        Write-Host "    WhatIf: Would restore $valueCount registry values under key $resolvedPath" -ForegroundColor Yellow
                    }
                }
            } catch {
                Write-Host "    WhatIf: Would attempt to restore registry from $stateFilePath (state file parse failed)" -ForegroundColor Yellow
            }
        } else {
            Write-Warning "    WhatIf: No state data found for registry $($RegistryConfig.name). Would skip."
        }
        return
    }

    $stateData = $null
    if (Test-Path $stateFilePath) {
        try {
            $stateData = (Get-Content -Path $stateFilePath -Raw -Encoding Utf8) | ConvertFrom-Json
        } catch {
            $errorMessage = $_.Exception.Message
            Write-Warning ("    Failed to read or parse state file for " + $RegistryConfig.name + " at " + $stateFilePath + ": " + $errorMessage + ". Trying default value if available.")
        }
    }

    try {
        if ($RegistryConfig.type -eq "value") {
            $valueToSet = $null
            if ($stateData) {
                if ($stateData.Encrypted -eq $true -and $stateData.EncryptedValue) {
                    Write-Host "    Decrypting registry value with AES-256"
                    $decryptedBytes = Unprotect-WmrData -EncodedData $stateData.EncryptedValue
                    $valueToSet = [System.Text.Encoding]::UTF8.GetString($decryptedBytes)
                } elseif ($stateData.Value) {
                    $valueToSet = $stateData.Value
                }
            } elseif ($RegistryConfig.value_data) {
                $valueToSet = $RegistryConfig.value_data
                Write-Host "    Using default value_data from template for $($RegistryConfig.name)."
            }

            if ($valueToSet -ne $null) {
                Set-ItemProperty -Path $resolvedPath -Name $RegistryConfig.key_name -Value $valueToSet -Force -ErrorAction Stop
                Write-Host "  Registry value $($RegistryConfig.name) set to $valueToSet at $resolvedPath/$($RegistryConfig.key_name)."
            } else {
                Write-Warning "    No state data or default value_data found for registry value $($RegistryConfig.name). Skipping."
            }

        } elseif ($RegistryConfig.type -eq "key") {
            if ($stateData -and $stateData.Values) {
                # Restore all values under the key from state data
                foreach ($prop in $stateData.Values.PSObject.Properties) {
                    Set-ItemProperty -Path $resolvedPath -Name $prop.Name -Value $prop.Value -Force -ErrorAction Stop
                    Write-Host "    Set value `'$($prop.Name)`' under `'$resolvedPath`'."
                }
                Write-Host "  Registry key $($RegistryConfig.name) values restored at $resolvedPath."
            } else {
                Write-Warning "    No state data found for registry key $($RegistryConfig.name). Skipping."
            }
        }
    } catch {
        $errorMessage = $_.Exception.Message
        Write-Warning ("    Failed to set registry state for " + $RegistryConfig.name + ": " + $errorMessage)
    }
}

# Functions are available via dot-sourcing - no Export-ModuleMember needed
# Available functions: Get-WmrRegistryState, Set-WmrRegistryState 