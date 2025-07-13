# Private/Core/RegistryState.ps1

# Requires Convert-WmrPath from PathUtilities.ps1
# Requires EncryptionUtilities.ps1 for encryption/decryption (will be created in Task 2.5)

function Get-WmrRegistryMockData {
    <#
    .SYNOPSIS
        Retrieves mock registry data for testing when actual Windows registry is not available.
    .DESCRIPTION
        Maps registry paths to mock JSON files in test environments to simulate registry reads.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RegistryPath
    )

    # Only use mock data in test environments
    if (-not ($env:WMR_TEST_MODE -eq 'true' -or $env:DOCKER_TEST -eq 'true' -or $env:PESTER_OUTPUT_PATH -or $env:DOCKER_ENVIRONMENT -eq 'true')) {
        return $null
    }

    Write-Verbose "Mock registry activated for path: $RegistryPath"
    Write-Information -MessageData "    Mock registry debug: mockDataRoot=$mockDataRoot, registryMockPath would be: $(if ($mockDataRoot) { Join-Path $mockDataRoot "Registry" } else { "null" })" -InformationAction Continue

            # Get the source system path where we placed our mock data
    $mockDataRoot = $env:WMR_STATE_PATH
    Write-Information -MessageData "    WMR_STATE_PATH environment variable: '$env:WMR_STATE_PATH'" -InformationAction Continue

    # If WMR_STATE_PATH is set and valid, use it directly
    if ($mockDataRoot -and (Test-Path $mockDataRoot)) {
        Write-Information -MessageData "    Using WMR_STATE_PATH: $mockDataRoot" -InformationAction Continue
    } else {
        # Try to find the actual directory in both Windows and Linux paths
        $actualMockDirs = @()

        # Check Linux/Docker paths
        if (Test-Path "/tmp") {
            $actualMockDirs += Get-ChildItem -Path "/tmp" -Directory -Filter "WMR-EndToEnd-*" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
        }

        # Check Windows paths
        if ($env:TEMP -and (Test-Path $env:TEMP)) {
            $actualMockDirs += Get-ChildItem -Path $env:TEMP -Directory -Filter "WMR-EndToEnd-*" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
        }

        if ($actualMockDirs) {
            # Use the most recent test directory
            $mockDataRoot = Join-Path $actualMockDirs[0].FullName "SourceSystem"
            Write-Information -MessageData "    Found mock data root: $mockDataRoot" -InformationAction Continue
        } else {
            Write-Information -MessageData "    No mock data directories found in /tmp or $env:TEMP" -InformationAction Continue
            $mockDataRoot = $null
        }
    }

    if (-not $mockDataRoot -or -not (Test-Path $mockDataRoot)) {
        Write-Verbose "Mock data root not found: $mockDataRoot"
        return $null
    }

    # Map registry paths to mock data files
    $registryMockPath = Join-Path $mockDataRoot "Registry"
    Write-Information -MessageData "    Checking registry mock path: $registryMockPath" -InformationAction Continue
    if (-not (Test-Path $registryMockPath)) {
        Write-Information -MessageData "    Registry mock path not found: $registryMockPath" -InformationAction Continue
        Write-Information -MessageData "    Available directories in mockDataRoot: $(if (Test-Path $mockDataRoot) { (Get-ChildItem $mockDataRoot -Directory).Name -join ', ' } else { 'mockDataRoot does not exist' })" -InformationAction Continue
        return $null
    }

    # Define mappings from registry paths to mock files
    $mockFileMappings = @{
        'HKLM:\SYSTEM\CurrentControlSet\Control' = 'system_control.json'
        'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' = 'windows_setup.json'
        'HKCU:\Control Panel\Desktop\WindowMetrics' = 'visual_effects.json'
        'HKCU:\Control Panel\International' = 'international.json'
        'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' = 'memory_management.json'
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer' = 'explorer_base.json'
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' = 'explorer_advanced.json'
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FileExts' = 'file_exts.json'
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StreamMRU' = 'stream_mru.json'
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\TypedPaths' = 'typed_paths.json'
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\UserAssist' = 'user_assist.json'
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies' = 'system_policies.json'
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies' = 'user_policies.json'
        'HKLM:\SYSTEM\CurrentControlSet\Services' = 'services.json'
        'HKLM:\SYSTEM\CurrentControlSet\Control\Power' = 'power_control.json'
        'HKCU:\Control Panel\PowerCfg' = 'power_options.json'
        'HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation' = 'timezone.json'
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings' = 'internet_settings.json'
    }

    # Find the best matching mock file
    $bestMatch = $null
    $longestMatch = 0

    foreach ($mockPath in $mockFileMappings.Keys) {
        if ($RegistryPath.StartsWith($mockPath, [System.StringComparison]::OrdinalIgnoreCase) -and $mockPath.Length -gt $longestMatch) {
            $bestMatch = $mockFileMappings[$mockPath]
            $longestMatch = $mockPath.Length
        }
    }

    if (-not $bestMatch) {
        # Create a generic mock response for unmapped paths
        Write-Verbose "No specific mock data for registry path: $RegistryPath - creating generic mock"

        # Generate more realistic mock data based on the registry path
        $mockData = @{
            Path = $RegistryPath
            IsMock = $true
            Timestamp = Get-Date
        }

        # Add path-specific mock values
        if ($RegistryPath -match "Software\\Microsoft\\Windows") {
            $mockData.MockValue = "Windows mock setting"
            $mockData.Version = "10.0.19045"
        }
        elseif ($RegistryPath -match "Control Panel") {
            $mockData.MockValue = "Control panel mock setting"
            $mockData.ControlValue = 1
        }
        elseif ($RegistryPath -match "Office") {
            $mockData.MockValue = "Office mock setting"
            $mockData.OfficeVersion = "16.0"
        }
        else {
            $mockData.MockValue = "Generic mock registry value for testing"
            $mockData.DefaultValue = "test-value"
        }

        return @{
            MockData = $mockData
        }
    }

    # Load the mock data file
    $mockFilePath = Join-Path $registryMockPath $bestMatch
    if (Test-Path $mockFilePath) {
        try {
            $mockContent = Get-Content $mockFilePath -Raw -Encoding UTF8 | ConvertFrom-Json
            Write-Verbose "Loaded mock registry data from: $mockFilePath"
            return @{
                MockData = $mockContent
                SourceFile = $mockFilePath
                IsMock = $true
            }
        }
        catch {
            Write-Warning "Failed to parse mock registry file $mockFilePath : $($_.Exception.Message)"
            return $null
        }
    }

    return $null
}

function Get-WmrRegistryState {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [PSObject]$RegistryConfig,

        [Parameter(Mandatory = $true)]
        [string]$StateFilesDirectory # Base directory where dynamic state files are stored
    )

    Write-Information -MessageData "  Getting registry state for: $($RegistryConfig.name)" -InformationAction Continue

    if ($WhatIfPreference) {
        Write-Warning -Message "    WhatIf: Would backup registry state from $($RegistryConfig.path)"
        $stateFilePath = Join-Path -Path $StateFilesDirectory -ChildPath $RegistryConfig.dynamic_state_path
        Write-Warning -Message "    WhatIf: Would save registry data to $stateFilePath"

        if (-not (Test-Path $RegistryConfig.path)) {
            Write-Warning "    WhatIf: Registry path not found: $($RegistryConfig.path). Would skip backup for this item."
        }
        else {
            Write-Warning -Message "    WhatIf: Would capture registry $($RegistryConfig.type) values"
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

    # Check if we're in a test environment and should use mock data
    $mockData = Get-WmrRegistryMockData -RegistryPath $resolvedPath
    Write-Information -MessageData "    Mock data result: $($mockData -ne $null)" -InformationAction Continue
    if ($mockData) {
        Write-Information -MessageData "    Using mock registry data for testing" -InformationAction Continue

        try {
            if ($RegistryConfig.type -eq "value") {
                if (-not $RegistryConfig.key_name) {
                    throw "Registry item type is 'value' but 'key_name' is not specified for $($RegistryConfig.name)"
                }

                # Get specific value from mock data
                $mockValue = $null
                if ($mockData.MockData.$($RegistryConfig.key_name)) {
                    $mockValue = $mockData.MockData.$($RegistryConfig.key_name)
                } elseif ($mockData.MockData.MockValue) {
                    $mockValue = $mockData.MockData.MockValue
                } else {
                    $mockValue = "Mock value for $($RegistryConfig.key_name)"
                }

                $registryState.KeyName = $RegistryConfig.key_name
                $registryState.Value = $mockValue

                if ($RegistryConfig.encrypt) {
                    Write-Information -MessageData "    Encrypting mock registry value with AES-256" -InformationAction Continue
                    $valueBytes = [System.Text.Encoding]::UTF8.GetBytes($mockValue.ToString())
                    $encryptedValue = Protect-WmrData -DataBytes $valueBytes
                    $registryState.EncryptedValue = $encryptedValue
                    $registryState.Encrypted = $true
                    # Remove unencrypted value
                    $registryState.Remove('Value')
                }
                else {
                    $registryState.Encrypted = $false
                }
            }
            elseif ($RegistryConfig.type -eq "key") {
                # Use all mock data as key values
                $registryState.Values = $mockData.MockData
            }

            # Save mock data to state file
            ($registryState | ConvertTo-Json -Compress) | Set-Content -Path $stateFilePath -Encoding Utf8
            Write-Information -MessageData "  Mock registry state for $($RegistryConfig.name) captured and saved to $stateFilePath." -InformationAction Continue
            return $registryState

        }
        catch {
            $errorMessage = $_.Exception.Message
            Write-Warning ("    Failed to process mock registry data for " + $RegistryConfig.name + ": " + $errorMessage + ". Skipping.")
            return $null
        }
    }

    # Original registry access code for non-test environments
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
                Write-Information -MessageData "    Encrypting registry value with AES-256" -InformationAction Continue
                $valueBytes = [System.Text.Encoding]::UTF8.GetBytes($value.ToString())
                $encryptedValue = Protect-WmrData -DataBytes $valueBytes
                $registryState.EncryptedValue = $encryptedValue
                $registryState.Encrypted = $true
                # Remove unencrypted value
                $registryState.Remove('Value')
            }
            else {
                $registryState.Encrypted = $false
            }
            ($registryState | ConvertTo-Json -Compress) | Set-Content -Path $stateFilePath -Encoding Utf8

        }
        elseif ($RegistryConfig.type -eq "key") {
            # Get all values under a registry key
            $keyValues = Get-ItemProperty -Path $resolvedPath -ErrorAction Stop | Select-Object -ExcludeProperty PSPath, PSParentPath, PSChildName, PSDrive, PSProvider
            $registryState.Values = $keyValues

            # Convert to JSON and save to dynamic_state_path
            ($registryState | ConvertTo-Json -Compress) | Set-Content -Path $stateFilePath -Encoding Utf8
        }

        Write-Information -MessageData "  Registry state for $($RegistryConfig.name) captured and saved to $stateFilePath." -InformationAction Continue
        return $registryState

    }
    catch {
        $errorMessage = $_.Exception.Message
        Write-Warning ("    Failed to get registry state for " + $RegistryConfig.name + ": " + $errorMessage + ". Skipping.")
        return $null
    }
}

function Set-WmrRegistryState {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [PSObject]$RegistryConfig,

        [Parameter(Mandatory = $true)]
        [string]$StateFilesDirectory # Base directory where dynamic state files are stored
    )

    Write-Information -MessageData "  Setting registry state for: $($RegistryConfig.name)" -InformationAction Continue

    $resolvedPathObj = Convert-WmrPath -Path $RegistryConfig.path
    if ($resolvedPathObj.PathType -ne "Registry") {
        Write-Warning "    Provided path is not a registry path: $($RegistryConfig.path). Skipping."
        return
    }
    $resolvedPath = $resolvedPathObj.Path

    $stateFilePath = Join-Path -Path $StateFilesDirectory -ChildPath $RegistryConfig.dynamic_state_path

    if ($WhatIfPreference) {
        Write-Warning -Message "    WhatIf: Would restore registry state from $stateFilePath to $resolvedPath"

        if (Test-Path $stateFilePath) {
            try {
                $stateData = (Get-Content -Path $stateFilePath -Raw -Encoding Utf8) | ConvertFrom-Json

                if ($RegistryConfig.type -eq "value") {
                    $valueToShow = "?"
                    if ($stateData.Encrypted -eq $true -and $stateData.EncryptedValue) {
                        Write-Warning -Message "    WhatIf: Would decrypt registry value with AES-256"
                        $valueToShow = "<encrypted>"
                    }
                    elseif ($stateData.Value) {
                        $valueToShow = $stateData.Value
                    }
                    elseif ($RegistryConfig.value_data) {
                        $valueToShow = $RegistryConfig.value_data
                    }
                    Write-Warning -Message "    WhatIf: Would set registry value '$($RegistryConfig.key_name)' to '$valueToShow' at $resolvedPath"
                }
                elseif ($RegistryConfig.type -eq "key") {
                    if ($stateData.Values) {
                        $valueCount = ($stateData.Values.PSObject.Properties | Measure-Object).Count
                        Write-Warning -Message "    WhatIf: Would restore $valueCount registry values under key $resolvedPath"
                    }
                }
            }
            catch {
                Write-Warning -Message "    WhatIf: Would attempt to restore registry from $stateFilePath (state file parse failed)"
            }
        }
        else {
            Write-Warning "    WhatIf: No state data found for registry $($RegistryConfig.name). Would skip."
        }
        return
    }

    $stateData = $null
    if (Test-Path $stateFilePath) {
        try {
            $stateData = (Get-Content -Path $stateFilePath -Raw -Encoding Utf8) | ConvertFrom-Json
        }
        catch {
            $errorMessage = $_.Exception.Message
            Write-Warning ("    Failed to read or parse state file for " + $RegistryConfig.name + " at " + $stateFilePath + ": " + $errorMessage + ". Trying default value if available.")
        }
    }

    try {
        if ($RegistryConfig.type -eq "value") {
            $valueToSet = $null
            if ($stateData) {
                if ($stateData.Encrypted -eq $true -and $stateData.EncryptedValue) {
                    Write-Information -MessageData "    Decrypting registry value with AES-256" -InformationAction Continue
                    $decryptedBytes = Unprotect-WmrData -EncodedData $stateData.EncryptedValue
                    $valueToSet = [System.Text.Encoding]::UTF8.GetString($decryptedBytes)
                }
                elseif ($stateData.Value) {
                    $valueToSet = $stateData.Value
                }
            }
            elseif ($RegistryConfig.value_data) {
                $valueToSet = $RegistryConfig.value_data
                Write-Information -MessageData "    Using default value_data from template for $($RegistryConfig.name)." -InformationAction Continue
            }

            if ($null -ne $valueToSet) {
                Set-ItemProperty -Path $resolvedPath -Name $RegistryConfig.key_name -Value $valueToSet -Force -ErrorAction Stop
                Write-Information -MessageData "  Registry value $($RegistryConfig.name) set to $valueToSet at $resolvedPath/$($RegistryConfig.key_name)." -InformationAction Continue
            }
            else {
                Write-Warning "    No state data or default value_data found for registry value $($RegistryConfig.name). Skipping."
            }

        }
        elseif ($RegistryConfig.type -eq "key") {
            if ($stateData -and $stateData.Values) {
                # Restore all values under the key from state data
                foreach ($prop in $stateData.Values.PSObject.Properties) {
                    Set-ItemProperty -Path $resolvedPath -Name $prop.Name -Value $prop.Value -Force -ErrorAction Stop
                    Write-Information -MessageData "    Set value `'$($prop.Name)`' under `'$resolvedPath`'." -InformationAction Continue
                }
                Write-Information -MessageData "  Registry key $($RegistryConfig.name) values restored at $resolvedPath." -InformationAction Continue
            }
            else {
                Write-Warning "    No state data found for registry key $($RegistryConfig.name). Skipping."
            }
        }
    }
    catch {
        $errorMessage = $_.Exception.Message
        Write-Warning ("    Failed to set registry state for " + $RegistryConfig.name + ": " + $errorMessage)
    }
}

# Functions are available via dot-sourcing - no Export-ModuleMember needed
# Available functions: Get-WmrRegistryState, Set-WmrRegistryState







